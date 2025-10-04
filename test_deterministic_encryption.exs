#!/usr/bin/env elixir
#
# Smoke test: Verify deterministic encryption produces identical output
# This validates that GitVeil will work with Git's content-addressable storage
#

Mix.install([])

# Add git_veil to load path
Code.prepend_path("_build/dev/lib/git_veil/ebin")
Code.prepend_path("_build/dev/lib/pqclean/ebin")

alias GitVeil.Core.{EncryptionEngine, Types.EncryptionKey}
alias GitVeil.Adapters.{OpenSSLCrypto, InMemoryKeyStorage}

IO.puts("=" |> String.duplicate(70))
IO.puts("GitVeil Deterministic Encryption Smoke Test")
IO.puts("=" |> String.duplicate(70))
IO.puts("")

# Test 1: Generate master key (using direct crypto, not GenServer)
IO.puts("Test 1: Generating master key...")

# Generate Kyber1024 keypair using pqclean directly
{pq_public, pq_secret} = :pqclean_nif.kyber1024_keypair()
IO.puts("✓ Kyber1024 keypair generated")
IO.puts("  Public key: #{byte_size(pq_public)} bytes")
IO.puts("  Secret key: #{byte_size(pq_secret)} bytes")

# For this test, derive a simple master key from the Kyber secret
# In production, this would use proper KEM + KDF
master_key_bytes = :crypto.hash(:sha256, pq_secret)
master_key = EncryptionKey.new(master_key_bytes)
IO.puts("✓ Master key derived: #{byte_size(master_key.key)} bytes")
IO.puts("")

# Test 2: Encrypt same plaintext twice
plaintext = """
This is a secret document that will be stored in Git.
It contains sensitive information that must be encrypted.

Lines:
1. First secret
2. Second secret
3. Third secret
"""

file_path = "test/secrets.txt"

IO.puts("Test 2: Encrypting same plaintext twice...")
IO.puts("Plaintext size: #{byte_size(plaintext)} bytes")
IO.puts("File path: #{file_path}")
IO.puts("")

{:ok, blob1} = EncryptionEngine.encrypt(
  plaintext,
  master_key,
  OpenSSLCrypto,
  OpenSSLCrypto,
  OpenSSLCrypto,
  file_path
)

{:ok, blob2} = EncryptionEngine.encrypt(
  plaintext,
  master_key,
  OpenSSLCrypto,
  OpenSSLCrypto,
  OpenSSLCrypto,
  file_path
)

IO.puts("Blob 1 created:")
IO.puts("  Version: #{blob1.version}")
IO.puts("  Tag1: #{Base.encode16(blob1.tag1) |> String.slice(0, 16)}...")
IO.puts("  Tag2: #{Base.encode16(blob1.tag2) |> String.slice(0, 16)}...")
IO.puts("  Tag3: #{Base.encode16(blob1.tag3) |> String.slice(0, 16)}...")
IO.puts("  Ciphertext: #{byte_size(blob1.ciphertext)} bytes")
IO.puts("")

IO.puts("Blob 2 created:")
IO.puts("  Version: #{blob2.version}")
IO.puts("  Tag1: #{Base.encode16(blob2.tag1) |> String.slice(0, 16)}...")
IO.puts("  Tag2: #{Base.encode16(blob2.tag2) |> String.slice(0, 16)}...")
IO.puts("  Tag3: #{Base.encode16(blob2.tag3) |> String.slice(0, 16)}...")
IO.puts("  Ciphertext: #{byte_size(blob2.ciphertext)} bytes")
IO.puts("")

# Test 3: Compare blobs
IO.puts("Test 3: Comparing encrypted blobs...")

version_match = blob1.version == blob2.version
tag1_match = blob1.tag1 == blob2.tag1
tag2_match = blob1.tag2 == blob2.tag2
tag3_match = blob1.tag3 == blob2.tag3
ciphertext_match = blob1.ciphertext == blob2.ciphertext

IO.puts("  Version match:    #{if version_match, do: "✓", else: "✗"}")
IO.puts("  Tag1 match:       #{if tag1_match, do: "✓", else: "✗"}")
IO.puts("  Tag2 match:       #{if tag2_match, do: "✓", else: "✗"}")
IO.puts("  Tag3 match:       #{if tag3_match, do: "✓", else: "✗"}")
IO.puts("  Ciphertext match: #{if ciphertext_match, do: "✓", else: "✗"}")
IO.puts("")

all_match = version_match && tag1_match && tag2_match && tag3_match && ciphertext_match

if all_match do
  IO.puts("✓ PASS: Encryption is deterministic - identical blobs produced")
else
  IO.puts("✗ FAIL: Encryption is NOT deterministic - blobs differ!")
  IO.puts("This is a CRITICAL issue - GitVeil will not work with Git.")
  System.halt(1)
end

IO.puts("")

# Test 4: Serialize and compare Git object hashes
IO.puts("Test 4: Simulating Git hash-object...")

serialized1 = EncryptionEngine.serialize(blob1)
serialized2 = EncryptionEngine.serialize(blob2)

IO.puts("  Serialized blob 1: #{byte_size(serialized1)} bytes")
IO.puts("  Serialized blob 2: #{byte_size(serialized2)} bytes")

binary_match = serialized1 == serialized2
IO.puts("  Binary match: #{if binary_match, do: "✓", else: "✗"}")
IO.puts("")

# Compute SHA-1 hash like Git does
# Git uses: "blob <size>\0<content>"
git_blob_1 = "blob #{byte_size(serialized1)}\0#{serialized1}"
git_blob_2 = "blob #{byte_size(serialized2)}\0#{serialized2}"

hash1 = :crypto.hash(:sha, git_blob_1) |> Base.encode16(case: :lower)
hash2 = :crypto.hash(:sha, git_blob_2) |> Base.encode16(case: :lower)

IO.puts("  Git SHA-1 hash (blob 1): #{hash1}")
IO.puts("  Git SHA-1 hash (blob 2): #{hash2}")
IO.puts("  Hash match: #{if hash1 == hash2, do: "✓", else: "✗"}")
IO.puts("")

if hash1 == hash2 do
  IO.puts("✓ PASS: Git would see both encrypted files as identical")
else
  IO.puts("✗ FAIL: Git would see different hashes - determinism broken!")
  System.halt(1)
end

IO.puts("")

# Test 5: Verify decryption works
IO.puts("Test 5: Verifying decryption...")

{:ok, decrypted1} = EncryptionEngine.decrypt(
  blob1,
  master_key,
  OpenSSLCrypto,
  OpenSSLCrypto,
  OpenSSLCrypto,
  file_path
)

{:ok, decrypted2} = EncryptionEngine.decrypt(
  blob2,
  master_key,
  OpenSSLCrypto,
  OpenSSLCrypto,
  OpenSSLCrypto,
  file_path
)

decrypt_match = decrypted1 == plaintext && decrypted2 == plaintext

IO.puts("  Decrypted blob 1 matches plaintext: #{if decrypted1 == plaintext, do: "✓", else: "✗"}")
IO.puts("  Decrypted blob 2 matches plaintext: #{if decrypted2 == plaintext, do: "✓", else: "✗"}")
IO.puts("")

if decrypt_match do
  IO.puts("✓ PASS: Both blobs decrypt to original plaintext")
else
  IO.puts("✗ FAIL: Decryption failed!")
  System.halt(1)
end

IO.puts("")

# Test 6: Different file paths produce different ciphertexts
IO.puts("Test 6: Verifying file path affects encryption (context separation)...")

{:ok, blob_file1} = EncryptionEngine.encrypt(
  plaintext,
  master_key,
  OpenSSLCrypto,
  OpenSSLCrypto,
  OpenSSLCrypto,
  "path/to/file1.txt"
)

{:ok, blob_file2} = EncryptionEngine.encrypt(
  plaintext,
  master_key,
  OpenSSLCrypto,
  OpenSSLCrypto,
  OpenSSLCrypto,
  "path/to/file2.txt"
)

different_ciphertext = blob_file1.ciphertext != blob_file2.ciphertext

IO.puts("  Same plaintext, different file paths")
IO.puts("  Ciphertexts differ: #{if different_ciphertext, do: "✓", else: "✗"}")
IO.puts("")

if different_ciphertext do
  IO.puts("✓ PASS: Different file paths produce different ciphertexts")
else
  IO.puts("✗ FAIL: File path not affecting encryption - HKDF issue!")
  System.halt(1)
end

IO.puts("")

# Summary
IO.puts("=" |> String.duplicate(70))
IO.puts("SUMMARY: All Tests Passed ✓")
IO.puts("=" |> String.duplicate(70))
IO.puts("")
IO.puts("Deterministic Encryption: ✓ VERIFIED")
IO.puts("  • Same file + same content → same encrypted blob")
IO.puts("  • Git will not see spurious changes")
IO.puts("  • Round-trip encryption/decryption works")
IO.puts("  • File path context separation works")
IO.puts("")
IO.puts("Git SHA-1 Hash: #{hash1}")
IO.puts("")
IO.puts("GitVeil is ready for Git filter integration!")
IO.puts("")

# Write test files for manual git hash-object verification
IO.puts("Writing test files for manual verification...")
File.write!("/tmp/gitveil_encrypted_v1.bin", serialized1)
File.write!("/tmp/gitveil_encrypted_v2.bin", serialized2)
IO.puts("  /tmp/gitveil_encrypted_v1.bin")
IO.puts("  /tmp/gitveil_encrypted_v2.bin")
IO.puts("")
IO.puts("You can verify with Git:")
IO.puts("  git hash-object /tmp/gitveil_encrypted_v1.bin")
IO.puts("  git hash-object /tmp/gitveil_encrypted_v2.bin")
IO.puts("  (Both should output: #{hash1})")
IO.puts("")
