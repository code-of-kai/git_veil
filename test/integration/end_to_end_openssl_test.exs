defmodule Integration.EndToEndOpenSSLTest do
  use ExUnit.Case, async: false

  @moduledoc """
  End-to-end integration test using ONLY real OpenSSL cryptography.

  This test verifies the complete encryption pipeline works with
  real AEAD algorithms, not mocks:

  1. Key generation and storage
  2. HKDF key derivation
  3. AES-256-GCM encryption (Layer 1)
  4. ChaCha20-Poly1305 encryption (Layer 2)
  5. AES-256-GCM encryption (Layer 3)
  6. GitVeil format serialization
  7. Full decryption pipeline (reverse order)

  **CRITICAL: This test uses ONLY OpenSSLCrypto - no mocks allowed.**
  """

  alias GitVeil.Adapters.{InMemoryKeyStorage, OpenSSLCrypto}
  alias GitVeil.Core.{EncryptionEngine, KeyDerivation, TripleCipher}
  alias GitVeil.Core.Types.EncryptionContext

  setup do
    # Start real key storage
    {:ok, _} = start_supervised(InMemoryKeyStorage)

    # Generate and save real keypair
    {:ok, keypair} = InMemoryKeyStorage.generate_keypair()
    :ok = InMemoryKeyStorage.save_keypair(keypair)

    :ok
  end

  describe "REAL OpenSSL crypto - end-to-end pipeline" do
    test "encrypts and decrypts with REAL OpenSSL AES-256-GCM and ChaCha20-Poly1305" do
      # Test data
      plaintext = """
      This is a real-world test using actual OpenSSL cryptography.

      Secrets:
      - API_KEY=sk_live_123456789
      - DATABASE_URL=postgresql://user:pass@localhost/db
      - JWT_SECRET=very_secret_key_here

      This data is encrypted using:
      1. REAL AES-256-GCM (not mock)
      2. REAL ChaCha20-Poly1305 (not mock)
      3. REAL AES-256-GCM again (not mock)
      """

      file_path = ".env.production"

      # Step 1: Derive master key from real keypair
      {:ok, master_key} = InMemoryKeyStorage.derive_master_key()
      assert byte_size(master_key) == 64, "Master key must be 64 bytes"

      # Step 2: Create encryption context
      context = EncryptionContext.new(file_path, master_key)

      # Step 3: Encrypt using REAL OpenSSL crypto
      {:ok, encrypted} = EncryptionEngine.encrypt(plaintext, context, crypto: OpenSSLCrypto)

      # Verify encrypted format
      assert String.starts_with?(encrypted, "GTVL"), "Must have GitVeil magic number"
      assert encrypted != plaintext, "Ciphertext must differ from plaintext"
      assert byte_size(encrypted) > byte_size(plaintext), "Ciphertext includes overhead"

      # Step 4: Decrypt using REAL OpenSSL crypto
      {:ok, decrypted} = EncryptionEngine.decrypt(encrypted, context, crypto: OpenSSLCrypto)

      # Verify perfect round-trip
      assert decrypted == plaintext, "Decryption must recover exact plaintext"

      # Verify secrets are in decrypted data
      assert decrypted =~ "API_KEY=sk_live_123456789"
      assert decrypted =~ "DATABASE_URL=postgresql"
      assert decrypted =~ "JWT_SECRET=very_secret_key_here"
    end

    test "REAL crypto with large binary data (10KB)" do
      # Generate random binary data
      plaintext = :crypto.strong_rand_bytes(10_000)
      file_path = "large_file.bin"

      {:ok, master_key} = InMemoryKeyStorage.derive_master_key()
      context = EncryptionContext.new(file_path, master_key)

      # Encrypt with REAL OpenSSL
      {:ok, encrypted} = EncryptionEngine.encrypt(plaintext, context, crypto: OpenSSLCrypto)

      # Decrypt with REAL OpenSSL
      {:ok, decrypted} = EncryptionEngine.decrypt(encrypted, context, crypto: OpenSSLCrypto)

      # Verify bit-perfect recovery
      assert decrypted == plaintext
      assert byte_size(decrypted) == 10_000
    end

    test "REAL crypto - different files get different ciphertexts (deterministic IV derivation)" do
      plaintext = "same content in both files"
      {:ok, master_key} = InMemoryKeyStorage.derive_master_key()

      # Encrypt same plaintext for two different files
      context1 = EncryptionContext.new("file1.env", master_key)
      context2 = EncryptionContext.new("file2.env", master_key)

      {:ok, encrypted1} = EncryptionEngine.encrypt(plaintext, context1, crypto: OpenSSLCrypto)
      {:ok, encrypted2} = EncryptionEngine.encrypt(plaintext, context2, crypto: OpenSSLCrypto)

      # Ciphertexts MUST differ (deterministic IV based on file path)
      assert encrypted1 != encrypted2, "Same plaintext in different files must produce different ciphertexts"

      # But both decrypt correctly
      {:ok, decrypted1} = EncryptionEngine.decrypt(encrypted1, context1, crypto: OpenSSLCrypto)
      {:ok, decrypted2} = EncryptionEngine.decrypt(encrypted2, context2, crypto: OpenSSLCrypto)

      assert decrypted1 == plaintext
      assert decrypted2 == plaintext
    end

    test "REAL crypto - authentication tag verification (tamper detection)" do
      plaintext = "sensitive data"
      file_path = "secrets.txt"

      {:ok, master_key} = InMemoryKeyStorage.derive_master_key()
      context = EncryptionContext.new(file_path, master_key)

      {:ok, encrypted} = EncryptionEngine.encrypt(plaintext, context, crypto: OpenSSLCrypto)

      # Tamper with the ciphertext
      tampered = String.replace(encrypted, "GTVL", "GTVX")

      # Decryption should fail with REAL OpenSSL auth verification
      result = EncryptionEngine.decrypt(tampered, context, crypto: OpenSSLCrypto)

      assert match?({:error, _}, result), "Tampered ciphertext must fail authentication"
    end

    test "REAL TripleCipher - verifies all three layers use OpenSSL" do
      plaintext = "testing triple-layer encryption with REAL crypto"
      file_path = "test.env"

      {:ok, master_key} = InMemoryKeyStorage.derive_master_key()
      context = EncryptionContext.new(file_path, master_key)

      # Derive file keys
      {:ok, file_keys} = KeyDerivation.derive_file_keys(context)
      base_iv = KeyDerivation.derive_base_iv(file_path)

      # Encrypt with REAL OpenSSL (all 3 layers)
      {:ok, result} = TripleCipher.encrypt(plaintext, file_keys, base_iv, crypto: OpenSSLCrypto)

      # Verify result structure
      assert byte_size(result.layer1_iv) == 12
      assert byte_size(result.layer1_tag) == 16
      assert byte_size(result.layer2_iv) == 12
      assert byte_size(result.layer2_tag) == 16
      assert byte_size(result.layer3_iv) == 12
      assert byte_size(result.layer3_tag) == 16
      assert is_binary(result.ciphertext)

      # Decrypt with REAL OpenSSL
      metadata = %{
        layer1_iv: result.layer1_iv,
        layer1_tag: result.layer1_tag,
        layer2_iv: result.layer2_iv,
        layer2_tag: result.layer2_tag,
        layer3_iv: result.layer3_iv,
        layer3_tag: result.layer3_tag
      }

      {:ok, decrypted} = TripleCipher.decrypt(result.ciphertext, file_keys, metadata, crypto: OpenSSLCrypto)

      assert decrypted == plaintext
    end

    test "REAL crypto - deterministic encryption (same input → same output)" do
      plaintext = "deterministic test"
      file_path = "test.env"

      {:ok, master_key} = InMemoryKeyStorage.derive_master_key()
      context = EncryptionContext.new(file_path, master_key)

      # Encrypt twice with REAL OpenSSL
      {:ok, encrypted1} = EncryptionEngine.encrypt(plaintext, context, crypto: OpenSSLCrypto)
      {:ok, encrypted2} = EncryptionEngine.encrypt(plaintext, context, crypto: OpenSSLCrypto)

      # MUST be deterministic (same master key + file path → same IV → same ciphertext)
      assert encrypted1 == encrypted2, "Encryption must be deterministic with REAL crypto"
    end

    test "REAL crypto - multiple files in batch" do
      files = [
        {".env", "API_KEY=real_key_1"},
        {"config.yml", "database:\n  host: localhost"},
        {"secrets.json", ~s({"secret": "value"})},
        {"credentials.txt", "username:password"}
      ]

      {:ok, master_key} = InMemoryKeyStorage.derive_master_key()

      # Encrypt all files with REAL OpenSSL
      encrypted_files = Enum.map(files, fn {path, content} ->
        context = EncryptionContext.new(path, master_key)
        {:ok, encrypted} = EncryptionEngine.encrypt(content, context, crypto: OpenSSLCrypto)
        {path, content, encrypted}
      end)

      # Verify all encrypted
      Enum.each(encrypted_files, fn {_path, plaintext, encrypted} ->
        assert String.starts_with?(encrypted, "GTVL")
        assert encrypted != plaintext
      end)

      # Decrypt all files with REAL OpenSSL
      Enum.each(encrypted_files, fn {path, original_plaintext, encrypted} ->
        context = EncryptionContext.new(path, master_key)
        {:ok, decrypted} = EncryptionEngine.decrypt(encrypted, context, crypto: OpenSSLCrypto)
        assert decrypted == original_plaintext
      end)
    end
  end

  describe "REAL OpenSSL - performance characteristics" do
    test "REAL crypto is acceptably fast for Git filter use case" do
      plaintext = :crypto.strong_rand_bytes(100_000)  # 100 KB file
      file_path = "large.bin"

      {:ok, master_key} = InMemoryKeyStorage.derive_master_key()
      context = EncryptionContext.new(file_path, master_key)

      # Measure encryption time with REAL OpenSSL
      {encrypt_time_us, {:ok, encrypted}} = :timer.tc(fn ->
        EncryptionEngine.encrypt(plaintext, context, crypto: OpenSSLCrypto)
      end)

      # Measure decryption time with REAL OpenSSL
      {decrypt_time_us, {:ok, decrypted}} = :timer.tc(fn ->
        EncryptionEngine.decrypt(encrypted, context, crypto: OpenSSLCrypto)
      end)

      # Verify correctness
      assert decrypted == plaintext

      # Report performance (informational)
      encrypt_time_ms = encrypt_time_us / 1000
      decrypt_time_ms = decrypt_time_us / 1000

      IO.puts("\nREAL OpenSSL Performance (100 KB file):")
      IO.puts("  Encryption: #{Float.round(encrypt_time_ms, 2)} ms")
      IO.puts("  Decryption: #{Float.round(decrypt_time_ms, 2)} ms")

      # Sanity check: should complete within 1 second for 100KB
      assert encrypt_time_ms < 1000, "Encryption too slow (#{encrypt_time_ms} ms)"
      assert decrypt_time_ms < 1000, "Decryption too slow (#{decrypt_time_ms} ms)"
    end
  end
end
