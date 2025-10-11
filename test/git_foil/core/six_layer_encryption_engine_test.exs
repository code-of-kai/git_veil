defmodule GitFoil.Core.SixLayerEncryptionEngineTest do
  @moduledoc """
  Comprehensive tests for v3.0 six-layer encryption engine.

  Tests the complete encryption pipeline:
  1. AES-256-GCM (OpenSSL)
  2. AEGIS-256 (Rust NIF)
  3. Schwaemm256-256 (Rust NIF)
  4. Deoxys-II-256 (Rust NIF)
  5. Ascon-128a (Rust NIF)
  6. ChaCha20-Poly1305 (OpenSSL)
  """

  use ExUnit.Case, async: true
  use Bitwise

  alias GitFoil.Core.EncryptionEngine
  alias GitFoil.Core.Types.EncryptionKey
  alias GitFoil.Adapters.{
    OpenSSLCrypto,
    AegisCrypto,
    SchwaemmCrypto,
    DeoxysCrypto,
    AsconCrypto
  }

  @moduletag :six_layer

  describe "six-layer encryption pipeline (v3.0)" do
    setup do
      # Generate random master key (32 bytes for AES-256 level security)
      master_key = EncryptionKey.new(:crypto.strong_rand_bytes(32))
      {:ok, master_key: master_key}
    end

    test "encrypts and decrypts through all 6 layers", %{master_key: master_key} do
      plaintext = "Six-layer quantum-resistant encryption test"
      file_path = "test/secret.txt"

      # Encrypt through all 6 layers
      {:ok, blob} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,    # Layer 1: AES-256-GCM
          AegisCrypto,      # Layer 2: AEGIS-256
          SchwaemmCrypto,   # Layer 3: Schwaemm256-256
          DeoxysCrypto,     # Layer 4: Deoxys-II-256
          AsconCrypto,      # Layer 5: Ascon-128a
          OpenSSLCrypto,    # Layer 6: ChaCha20-Poly1305
          file_path
        )

      # Verify blob structure (v3.0 format)
      assert blob.version == 3
      assert byte_size(blob.tag1) == 16   # AES-256-GCM tag
      assert byte_size(blob.tag2) == 32   # AEGIS-256 tag
      assert byte_size(blob.tag3) == 32   # Schwaemm256-256 tag
      assert byte_size(blob.tag4) == 16   # Deoxys-II-256 tag
      assert byte_size(blob.tag5) == 16   # Ascon-128a tag
      assert byte_size(blob.tag6) == 16   # ChaCha20-Poly1305 tag
      assert is_binary(blob.ciphertext)

      # Decrypt through all 6 layers (reverse order)
      {:ok, decrypted} =
        EncryptionEngine.decrypt(
          blob,
          master_key,
          OpenSSLCrypto,    # Layer 1: AES-256-GCM
          AegisCrypto,      # Layer 2: AEGIS-256
          SchwaemmCrypto,   # Layer 3: Schwaemm256-256
          DeoxysCrypto,     # Layer 4: Deoxys-II-256
          AsconCrypto,      # Layer 5: Ascon-128a
          OpenSSLCrypto,    # Layer 6: ChaCha20-Poly1305
          file_path
        )

      assert decrypted == plaintext
    end

    test "serialization produces correct wire format", %{master_key: master_key} do
      plaintext = "Wire format test"
      file_path = "test/data.bin"

      {:ok, blob} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          AegisCrypto,
          SchwaemmCrypto,
          DeoxysCrypto,
          AsconCrypto,
          OpenSSLCrypto,
          file_path
        )

      # Serialize to wire format
      serialized = EncryptionEngine.serialize(blob)

      # Wire format: [version:1][tag1:16][tag2:32][tag3:32][tag4:16][tag5:16][tag6:16][ciphertext]
      # Total overhead: 129 bytes (1 + 16 + 32 + 32 + 16 + 16 + 16)
      expected_overhead = 1 + 16 + 32 + 32 + 16 + 16 + 16
      assert byte_size(serialized) == expected_overhead + byte_size(blob.ciphertext)

      # Verify version byte is first
      <<version::8, _rest::binary>> = serialized
      assert version == 3

      # Deserialize and verify round-trip
      {:ok, deserialized_blob} = EncryptionEngine.deserialize(serialized)
      assert deserialized_blob.version == blob.version
      assert deserialized_blob.tag1 == blob.tag1
      assert deserialized_blob.tag2 == blob.tag2
      assert deserialized_blob.tag3 == blob.tag3
      assert deserialized_blob.tag4 == blob.tag4
      assert deserialized_blob.tag5 == blob.tag5
      assert deserialized_blob.tag6 == blob.tag6
      assert deserialized_blob.ciphertext == blob.ciphertext
    end

    test "encryption is deterministic (same inputs → same outputs)", %{master_key: master_key} do
      plaintext = "Deterministic test"
      file_path = "test/determinism.txt"

      # Encrypt same plaintext twice
      {:ok, blob1} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          AegisCrypto,
          SchwaemmCrypto,
          DeoxysCrypto,
          AsconCrypto,
          OpenSSLCrypto,
          file_path
        )

      {:ok, blob2} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          AegisCrypto,
          SchwaemmCrypto,
          DeoxysCrypto,
          AsconCrypto,
          OpenSSLCrypto,
          file_path
        )

      # Verify deterministic behavior (required for Git)
      assert blob1.ciphertext == blob2.ciphertext
      assert blob1.tag1 == blob2.tag1
      assert blob1.tag2 == blob2.tag2
      assert blob1.tag3 == blob2.tag3
      assert blob1.tag4 == blob2.tag4
      assert blob1.tag5 == blob2.tag5
      assert blob1.tag6 == blob2.tag6
    end

    test "different file paths produce different ciphertexts", %{master_key: master_key} do
      plaintext = "Same content, different files"

      {:ok, blob1} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          AegisCrypto,
          SchwaemmCrypto,
          DeoxysCrypto,
          AsconCrypto,
          OpenSSLCrypto,
          "file1.txt"
        )

      {:ok, blob2} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          AegisCrypto,
          SchwaemmCrypto,
          DeoxysCrypto,
          AsconCrypto,
          OpenSSLCrypto,
          "file2.txt"
        )

      # File path affects key derivation, so ciphertexts should differ
      assert blob1.ciphertext != blob2.ciphertext
    end

    test "tampering with ciphertext causes decryption to fail", %{master_key: master_key} do
      plaintext = "Tamper detection test"
      file_path = "test/tamper.txt"

      {:ok, blob} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          AegisCrypto,
          SchwaemmCrypto,
          DeoxysCrypto,
          AsconCrypto,
          OpenSSLCrypto,
          file_path
        )

      # Tamper with ciphertext (flip first byte)
      <<first_byte, rest::binary>> = blob.ciphertext
      tampered_ciphertext = <<bxor(first_byte, 0xFF), rest::binary>>
      tampered_blob = %{blob | ciphertext: tampered_ciphertext}

      # Decryption should fail due to authentication tag mismatch
      assert {:error, _} =
               EncryptionEngine.decrypt(
                 tampered_blob,
                 master_key,
                 OpenSSLCrypto,
                 AegisCrypto,
                 SchwaemmCrypto,
                 DeoxysCrypto,
                 AsconCrypto,
                 OpenSSLCrypto,
                 file_path
               )
    end

    test "tampering with any authentication tag causes decryption to fail", %{
      master_key: master_key
    } do
      plaintext = "Tag integrity test"
      file_path = "test/tag_check.txt"

      {:ok, blob} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          AegisCrypto,
          SchwaemmCrypto,
          DeoxysCrypto,
          AsconCrypto,
          OpenSSLCrypto,
          file_path
        )

      # Test tampering with each tag
      for tag_num <- 1..6 do
        tag_field = String.to_atom("tag#{tag_num}")
        original_tag = Map.get(blob, tag_field)

        # Flip first byte of tag
        <<first_byte, rest::binary>> = original_tag
        tampered_tag = <<bxor(first_byte, 0xFF), rest::binary>>
        tampered_blob = Map.put(blob, tag_field, tampered_tag)

        # Decryption should fail - either by raising ErlangError or returning {:error, _}
        result =
          try do
            EncryptionEngine.decrypt(
              tampered_blob,
              master_key,
              OpenSSLCrypto,
              AegisCrypto,
              SchwaemmCrypto,
              DeoxysCrypto,
              AsconCrypto,
              OpenSSLCrypto,
              file_path
            )
          rescue
            ErlangError -> {:error, :authentication_failed_via_exception}
          end

        assert match?({:error, _}, result),
               "Tag #{tag_num} tampering should be detected, got: #{inspect(result)}"
      end
    end

    test "wrong master key causes decryption to fail", %{master_key: master_key} do
      plaintext = "Key verification test"
      file_path = "test/key_check.txt"

      {:ok, blob} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          AegisCrypto,
          SchwaemmCrypto,
          DeoxysCrypto,
          AsconCrypto,
          OpenSSLCrypto,
          file_path
        )

      # Try to decrypt with different key
      wrong_key = EncryptionKey.new(:crypto.strong_rand_bytes(32))

      assert {:error, _} =
               EncryptionEngine.decrypt(
                 blob,
                 wrong_key,
                 OpenSSLCrypto,
                 AegisCrypto,
                 SchwaemmCrypto,
                 DeoxysCrypto,
                 AsconCrypto,
                 OpenSSLCrypto,
                 file_path
               )
    end

    test "rejects invalid version during decryption", %{master_key: master_key} do
      # Deserialization accepts any version byte, but decryption validates it
      # Create a valid blob structure with invalid version
      # Note: version is stored as unsigned 8-bit, so 999 wraps to 231
      invalid_version_large = 999
      expected_version = rem(invalid_version_large, 256)  # 231

      fake_serialized =
        <<invalid_version_large::8>> <>
        :crypto.strong_rand_bytes(16) <>  # tag1
        :crypto.strong_rand_bytes(32) <>  # tag2
        :crypto.strong_rand_bytes(32) <>  # tag3
        :crypto.strong_rand_bytes(16) <>  # tag4
        :crypto.strong_rand_bytes(16) <>  # tag5
        :crypto.strong_rand_bytes(16) <>  # tag6
        :crypto.strong_rand_bytes(10)     # ciphertext

      {:ok, invalid_blob} = EncryptionEngine.deserialize(fake_serialized)
      assert invalid_blob.version == expected_version

      # Decryption should reject the invalid version
      assert {:error, {:unsupported_version, ^expected_version}} =
               EncryptionEngine.decrypt(
                 invalid_blob,
                 master_key,
                 OpenSSLCrypto,
                 AegisCrypto,
                 SchwaemmCrypto,
                 DeoxysCrypto,
                 AsconCrypto,
                 OpenSSLCrypto,
                 "test.txt"
               )
    end

    test "handles large plaintexts (1MB)", %{master_key: master_key} do
      # 1MB of random data
      plaintext = :crypto.strong_rand_bytes(1_024 * 1_024)
      file_path = "test/large.bin"

      {:ok, blob} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          AegisCrypto,
          SchwaemmCrypto,
          DeoxysCrypto,
          AsconCrypto,
          OpenSSLCrypto,
          file_path
        )

      {:ok, decrypted} =
        EncryptionEngine.decrypt(
          blob,
          master_key,
          OpenSSLCrypto,
          AegisCrypto,
          SchwaemmCrypto,
          DeoxysCrypto,
          AsconCrypto,
          OpenSSLCrypto,
          file_path
        )

      assert decrypted == plaintext
      assert byte_size(decrypted) == 1_024 * 1_024
    end

    test "handles empty plaintext", %{master_key: master_key} do
      plaintext = ""
      file_path = "test/empty.txt"

      {:ok, blob} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          AegisCrypto,
          SchwaemmCrypto,
          DeoxysCrypto,
          AsconCrypto,
          OpenSSLCrypto,
          file_path
        )

      {:ok, decrypted} =
        EncryptionEngine.decrypt(
          blob,
          master_key,
          OpenSSLCrypto,
          AegisCrypto,
          SchwaemmCrypto,
          DeoxysCrypto,
          AsconCrypto,
          OpenSSLCrypto,
          file_path
        )

      assert decrypted == plaintext
      assert byte_size(decrypted) == 0
    end
  end
end
