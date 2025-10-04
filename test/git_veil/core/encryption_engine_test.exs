defmodule GitVeil.Core.EncryptionEngineTest do
  use ExUnit.Case, async: true

  alias GitVeil.Core.{EncryptionEngine, Types}
  alias GitVeil.Core.Types.EncryptionKey
  alias GitVeil.Adapters.OpenSSLCrypto

  describe "full encryption pipeline" do
    setup do
      # Generate master key (32 bytes for HKDF)
      master_key = EncryptionKey.new(:crypto.strong_rand_bytes(32))

      {:ok, master_key: master_key}
    end

    test "encrypts and decrypts using full pipeline", %{master_key: master_key} do
      plaintext = "Full pipeline encryption test with OpenSSL triple layers"
      file_path = "/path/to/repository/secret.txt"

      # Encrypt: derives keys, encrypts through 3 layers, serializes
      {:ok, blob} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          OpenSSLCrypto,
          OpenSSLCrypto,
          file_path
        )

      # Verify blob structure
      assert blob.version == 1
      assert byte_size(blob.tag1) == 16
      assert byte_size(blob.tag2) == 16
      assert byte_size(blob.tag3) == 16
      assert is_binary(blob.ciphertext)

      # Decrypt: derives keys, decrypts through 3 layers
      {:ok, decrypted} =
        EncryptionEngine.decrypt(
          blob,
          master_key,
          OpenSSLCrypto,
          OpenSSLCrypto,
          OpenSSLCrypto,
          file_path
        )

      assert decrypted == plaintext
    end

    test "serialization round-trip preserves data", %{master_key: master_key} do
      plaintext = "Serialization test"
      file_path = "/path/to/file.txt"

      {:ok, blob} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          OpenSSLCrypto,
          OpenSSLCrypto,
          file_path
        )

      # Serialize to binary
      serialized = EncryptionEngine.serialize(blob)
      assert is_binary(serialized)

      # Deserialize back to blob
      {:ok, deserialized_blob} = EncryptionEngine.deserialize(serialized)

      assert deserialized_blob.version == blob.version
      assert deserialized_blob.tag1 == blob.tag1
      assert deserialized_blob.tag2 == blob.tag2
      assert deserialized_blob.tag3 == blob.tag3
      assert deserialized_blob.ciphertext == blob.ciphertext

      # Decrypt deserialized blob
      {:ok, decrypted} =
        EncryptionEngine.decrypt(
          deserialized_blob,
          master_key,
          OpenSSLCrypto,
          OpenSSLCrypto,
          OpenSSLCrypto,
          file_path
        )

      assert decrypted == plaintext
    end

    test "different file paths produce different ciphertexts", %{master_key: master_key} do
      plaintext = "Same content, different files"

      {:ok, blob1} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          OpenSSLCrypto,
          OpenSSLCrypto,
          "/path/to/file1.txt"
        )

      {:ok, blob2} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          OpenSSLCrypto,
          OpenSSLCrypto,
          "/path/to/file2.txt"
        )

      # Different file paths → different derived keys → different ciphertext
      assert blob1.ciphertext != blob2.ciphertext
    end

    test "rejects invalid version during deserialization", %{master_key: master_key} do
      # Create a blob with unsupported version (version 99)
      tag1 = <<0::128>>
      tag2 = <<0::128>>
      tag3 = <<0::128>>
      invalid_serialized = <<99>> <> tag1 <> tag2 <> tag3 <> "data"

      {:ok, blob} = EncryptionEngine.deserialize(invalid_serialized)

      # Should fail during decryption due to version check
      result =
        EncryptionEngine.decrypt(
          blob,
          master_key,
          OpenSSLCrypto,
          OpenSSLCrypto,
          OpenSSLCrypto,
          "/path/to/file.txt"
        )

      assert {:error, {:unsupported_version, 99}} = result
    end

    test "handles empty plaintext", %{master_key: master_key} do
      plaintext = ""
      file_path = "/path/to/empty.txt"

      {:ok, blob} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          OpenSSLCrypto,
          OpenSSLCrypto,
          file_path
        )

      {:ok, decrypted} =
        EncryptionEngine.decrypt(
          blob,
          master_key,
          OpenSSLCrypto,
          OpenSSLCrypto,
          OpenSSLCrypto,
          file_path
        )

      assert decrypted == ""
    end

    test "deterministic encryption for Git compatibility", %{master_key: master_key} do
      plaintext = "Git requires deterministic encryption"
      file_path = "/path/to/tracked.txt"

      # Encrypt same data twice
      {:ok, blob1} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          OpenSSLCrypto,
          OpenSSLCrypto,
          file_path
        )

      {:ok, blob2} =
        EncryptionEngine.encrypt(
          plaintext,
          master_key,
          OpenSSLCrypto,
          OpenSSLCrypto,
          OpenSSLCrypto,
          file_path
        )

      # Must produce identical output (critical for Git)
      assert EncryptionEngine.serialize(blob1) == EncryptionEngine.serialize(blob2)
    end
  end
end
