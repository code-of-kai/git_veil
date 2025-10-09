#!/usr/bin/env elixir

# Demo: Triple-Layer Quantum-Resistant Encryption with Ascon-128a

IO.puts("\n🔐 GitFoil Triple-Layer Quantum-Resistant Encryption Demo\n")
IO.puts("=" |> String.duplicate(60))

alias GitFoil.Core.{EncryptionEngine, KeyDerivation}
alias GitFoil.Core.Types.EncryptionKey
alias GitFoil.Adapters.{OpenSSLCrypto, AsconCrypto}

# Test data
plaintext = "Top Secret: Launch codes are 1-2-3-4-5"
file_path = "secrets/launch_codes.txt"

IO.puts("\n📄 Original Data:")
IO.puts("   #{plaintext}")
IO.puts("   File: #{file_path}")

# Generate master key
IO.puts("\n🔑 Generating Master Key...")
master_key = EncryptionKey.new(:crypto.strong_rand_bytes(32))
IO.puts("   ✓ 32-byte master key generated")

# Derive layer-specific keys
IO.puts("\n🔐 Deriving Layer-Specific Keys...")
{:ok, derived_keys} = KeyDerivation.derive_keys(master_key, file_path)
IO.puts("   ✓ Layer 1 (AES-256-GCM):      #{byte_size(derived_keys.layer1_key)} bytes")
IO.puts("   ✓ Layer 2 (Ascon-128a):       #{byte_size(derived_keys.layer2_key)} bytes")
IO.puts("   ✓ Layer 3 (ChaCha20-Poly1305): #{byte_size(derived_keys.layer3_key)} bytes")

# Encrypt through all three layers
IO.puts("\n🔒 Encrypting through Triple Layers...")
IO.puts("   Layer 1: OpenSSL AES-256-GCM...")
IO.puts("   Layer 2: Rust Ascon-128a (NIST Lightweight Crypto)...")
IO.puts("   Layer 3: OpenSSL ChaCha20-Poly1305...")

{:ok, blob} =
  EncryptionEngine.encrypt(
    plaintext,
    master_key,
    OpenSSLCrypto,   # Layer 1: AES-256-GCM
    AsconCrypto,     # Layer 2: Ascon-128a (Rust NIF)
    OpenSSLCrypto,   # Layer 3: ChaCha20-Poly1305
    file_path
  )

IO.puts("   ✓ Encryption successful!")

# Show encrypted blob details
serialized = EncryptionEngine.serialize(blob)
IO.puts("\n📦 Encrypted Blob:")
IO.puts("   Version:    #{blob.version}")
IO.puts("   Tag 1 size: #{byte_size(blob.tag1)} bytes")
IO.puts("   Tag 2 size: #{byte_size(blob.tag2)} bytes")
IO.puts("   Tag 3 size: #{byte_size(blob.tag3)} bytes")
IO.puts("   Ciphertext: #{byte_size(blob.ciphertext)} bytes")
IO.puts("   Total size: #{byte_size(serialized)} bytes")
IO.puts("   Wire format: #{inspect(serialized |> binary_part(0, min(40, byte_size(serialized))), limit: :infinity)}...")

# Decrypt
IO.puts("\n🔓 Decrypting through Triple Layers (reverse order)...")
IO.puts("   Layer 3: ChaCha20-Poly1305 decrypt...")
IO.puts("   Layer 2: Ascon-128a decrypt...")
IO.puts("   Layer 1: AES-256-GCM decrypt...")

{:ok, decrypted} =
  EncryptionEngine.decrypt(
    blob,
    master_key,
    OpenSSLCrypto,   # Layer 1: AES-256-GCM
    AsconCrypto,     # Layer 2: Ascon-128a
    OpenSSLCrypto,   # Layer 3: ChaCha20-Poly1305
    file_path
  )

IO.puts("   ✓ Decryption successful!")

# Verify
IO.puts("\n✅ Verification:")
IO.puts("   Decrypted: #{decrypted}")
IO.puts("   Match: #{if decrypted == plaintext, do: "✓ SUCCESS", else: "✗ FAILED"}")

# Test determinism
IO.puts("\n🔁 Testing Deterministic Encryption (Git Compatibility)...")
{:ok, blob2} =
  EncryptionEngine.encrypt(
    plaintext,
    master_key,
    OpenSSLCrypto,
    AsconCrypto,
    OpenSSLCrypto,
    file_path
  )

serialized2 = EncryptionEngine.serialize(blob2)
deterministic = serialized == serialized2
IO.puts("   Same input → Same output: #{if deterministic, do: "✓ YES", else: "✗ NO"}")

# Test authentication
IO.puts("\n🛡️  Testing Authentication (Tamper Detection)...")
# Tamper with ciphertext
tampered_blob = %{blob | ciphertext: <<0>> <> binary_part(blob.ciphertext, 1, byte_size(blob.ciphertext) - 1)}

case EncryptionEngine.decrypt(tampered_blob, master_key, OpenSSLCrypto, AsconCrypto, OpenSSLCrypto, file_path) do
  {:error, :authentication_failed} ->
    IO.puts("   Tampered ciphertext: ✓ REJECTED (authentication failed)")
  {:ok, _} ->
    IO.puts("   Tampered ciphertext: ✗ ACCEPTED (security breach!)")
  other ->
    IO.puts("   Tampered ciphertext: ✓ REJECTED (#{inspect(other)})")
end

IO.puts("\n" <> ("=" |> String.duplicate(60)))
IO.puts("🎉 Triple-Layer Quantum-Resistant Encryption Demo Complete!")
IO.puts("\n")
