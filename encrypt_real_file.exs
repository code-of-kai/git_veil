#!/usr/bin/env elixir

alias GitVeil.Core.{EncryptionEngine, KeyDerivation}
alias GitVeil.Core.Types.EncryptionKey
alias GitVeil.Adapters.{OpenSSLCrypto, AsconCrypto}

IO.puts("\n🔐 Encrypting Real File with Triple-Layer Encryption\n")
IO.puts("=" |> String.duplicate(60))

# Read the actual test file
file_path = "test_secret.env"
plaintext = File.read!(file_path)

IO.puts("\n📄 Original File Contents (#{file_path}):")
IO.puts(plaintext)

# Generate master key
master_key = EncryptionKey.new(:crypto.strong_rand_bytes(32))

# Encrypt
IO.puts("\n🔒 Encrypting with:")
IO.puts("   Layer 1: AES-256-GCM")
IO.puts("   Layer 2: Ascon-128a (Quantum-Resistant)")
IO.puts("   Layer 3: ChaCha20-Poly1305")

{:ok, blob} =
  EncryptionEngine.encrypt(
    plaintext,
    master_key,
    OpenSSLCrypto,
    AsconCrypto,
    OpenSSLCrypto,
    file_path
  )

serialized = EncryptionEngine.serialize(blob)

IO.puts("\n📦 Encrypted Result:")
IO.puts("   Size: #{byte_size(serialized)} bytes (from #{byte_size(plaintext)} bytes plaintext)")
IO.puts("   Hex: #{Base.encode16(serialized) |> String.slice(0, 80)}...")

# Decrypt
IO.puts("\n🔓 Decrypting...")

{:ok, decrypted} =
  EncryptionEngine.decrypt(
    blob,
    master_key,
    OpenSSLCrypto,
    AsconCrypto,
    OpenSSLCrypto,
    file_path
  )

IO.puts("\n✅ Decrypted Contents:")
IO.puts(decrypted)

IO.puts("\n🎯 Verification: #{if decrypted == plaintext, do: "✓ PERFECT MATCH", else: "✗ MISMATCH"}")
IO.puts("")
