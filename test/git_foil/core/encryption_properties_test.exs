defmodule GitFoil.Core.EncryptionPropertiesTest do
  @moduledoc """
  Property-based tests for encryption using StreamData.

  These tests generate thousands of random inputs to ensure encryption
  works correctly for ALL possible inputs, not just hand-picked examples.

  Properties tested:
  1. Round-trip: decrypt(encrypt(data)) == data
  2. Deterministic: encrypt(data, key) always produces same output
  3. Different keys produce different outputs
  4. Authentication: tampering with ciphertext is detected
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GitFoil.Core.EncryptionEngine
  alias GitFoil.Adapters.FileKeyStorage

  @moduletag :property
  @moduletag timeout: 300_000

  setup do
    # Generate a random master key for each test
    master_key = :crypto.strong_rand_bytes(64)
    {:ok, master_key: master_key}
  end

  describe "round-trip property" do
    property "decrypt(encrypt(plaintext)) == plaintext for any plaintext", %{master_key: key} do
      check all(
              plaintext <- binary(),
              max_runs: 100
            ) do
        file_path = "/test/file.txt"

        # Encrypt
        {:ok, encrypted_blob} = EncryptionEngine.encrypt(plaintext, key, file_path)

        # Decrypt
        {:ok, decrypted} = EncryptionEngine.decrypt(encrypted_blob, key, file_path)

        # Property: decryption recovers original plaintext
        assert decrypted == plaintext
      end
    end

    property "works for various data types", %{master_key: key} do
      check all(
              data <-
                one_of([
                  binary(),
                  string(:printable),
                  string(:alphanumeric),
                  string(:ascii),
                  binary(min_length: 0, max_length: 1000)
                ]),
              max_runs: 50
            ) do
        file_path = "/test/file.txt"

        {:ok, encrypted} = EncryptionEngine.encrypt(data, key, file_path)
        {:ok, decrypted} = EncryptionEngine.decrypt(encrypted, key, file_path)

        assert decrypted == data
      end
    end

    property "works for edge case sizes", %{master_key: key} do
      check all(
              size <- one_of([constant(0), constant(1), constant(255), constant(256), constant(1024)]),
              max_runs: 25
            ) do
        plaintext = :crypto.strong_rand_bytes(size)
        file_path = "/test/file.txt"

        {:ok, encrypted} = EncryptionEngine.encrypt(plaintext, key, file_path)
        {:ok, decrypted} = EncryptionEngine.decrypt(encrypted, key, file_path)

        assert decrypted == plaintext
      end
    end
  end

  describe "deterministic property" do
    property "same plaintext + key produces same ciphertext", %{master_key: key} do
      check all(
              plaintext <- binary(min_length: 1, max_length: 100),
              max_runs: 50
            ) do
        file_path = "/test/file.txt"

        {:ok, encrypted1} = EncryptionEngine.encrypt(plaintext, key, file_path)
        {:ok, encrypted2} = EncryptionEngine.encrypt(plaintext, key, file_path)

        # Property: deterministic encryption
        assert encrypted1 == encrypted2
      end
    end

    property "same plaintext with same file path is deterministic", %{master_key: key} do
      check all(
              plaintext <- binary(min_length: 1, max_length: 100),
              file_path <- string(:alphanumeric, min_length: 1, max_length: 50),
              max_runs: 50
            ) do
        path = "/" <> file_path <> ".txt"

        {:ok, encrypted1} = EncryptionEngine.encrypt(plaintext, key, path)
        {:ok, encrypted2} = EncryptionEngine.encrypt(plaintext, key, path)

        assert encrypted1 == encrypted2
      end
    end
  end

  describe "key sensitivity property" do
    property "different keys produce different ciphertexts" do
      check all(
              plaintext <- binary(min_length: 1, max_length: 100),
              max_runs: 50
            ) do
        key1 = :crypto.strong_rand_bytes(64)
        key2 = :crypto.strong_rand_bytes(64)
        file_path = "/test/file.txt"

        {:ok, encrypted1} = EncryptionEngine.encrypt(plaintext, key1, file_path)
        {:ok, encrypted2} = EncryptionEngine.encrypt(plaintext, key2, file_path)

        # Property: different keys produce different outputs
        assert encrypted1 != encrypted2
      end
    end

    property "wrong key fails to decrypt" do
      check all(
              plaintext <- binary(min_length: 1, max_length: 100),
              max_runs: 50
            ) do
        key1 = :crypto.strong_rand_bytes(64)
        key2 = :crypto.strong_rand_bytes(64)
        file_path = "/test/file.txt"

        {:ok, encrypted} = EncryptionEngine.encrypt(plaintext, key1, file_path)

        # Property: wrong key causes authentication failure
        assert {:error, :authentication_failed} = EncryptionEngine.decrypt(encrypted, key2, file_path)
      end
    end
  end

  describe "authentication property" do
    property "tampering with ciphertext is detected" do
      check all(
              plaintext <- binary(min_length: 10, max_length: 100),
              max_runs: 50
            ) do
        key = :crypto.strong_rand_bytes(64)
        file_path = "/test/file.txt"

        {:ok, encrypted} = EncryptionEngine.encrypt(plaintext, key, file_path)

        # Tamper with the ciphertext (flip one bit)
        tampered = tamper_with_blob(encrypted)

        # Property: tampering is detected
        assert {:error, :authentication_failed} = EncryptionEngine.decrypt(tampered, key, file_path)
      end
    end
  end

  describe "file path binding property" do
    property "ciphertext is bound to file path", %{master_key: key} do
      check all(
              plaintext <- binary(min_length: 1, max_length: 100),
              path1 <- string(:alphanumeric, min_length: 1, max_length: 30),
              path2 <- string(:alphanumeric, min_length: 1, max_length: 30),
              path1 != path2,
              max_runs: 50
            ) do
        file_path1 = "/" <> path1 <> ".txt"
        file_path2 = "/" <> path2 <> ".txt"

        {:ok, encrypted} = EncryptionEngine.encrypt(plaintext, key, file_path1)

        # Property: decrypting with wrong file path fails
        assert {:error, :authentication_failed} = EncryptionEngine.decrypt(encrypted, key, file_path2)
      end
    end
  end

  describe "special characters in plaintext" do
    property "handles null bytes" do
      check all(
              prefix <- binary(max_length: 50),
              suffix <- binary(max_length: 50),
              max_runs: 50
            ) do
        key = :crypto.strong_rand_bytes(64)
        plaintext = prefix <> <<0>> <> suffix
        file_path = "/test/file.txt"

        {:ok, encrypted} = EncryptionEngine.encrypt(plaintext, key, file_path)
        {:ok, decrypted} = EncryptionEngine.decrypt(encrypted, key, file_path)

        assert decrypted == plaintext
      end
    end

    property "handles all byte values" do
      check all(
              bytes <- list_of(integer(0..255), min_length: 10, max_length: 100),
              max_runs: 50
            ) do
        key = :crypto.strong_rand_bytes(64)
        plaintext = :binary.list_to_bin(bytes)
        file_path = "/test/file.txt"

        {:ok, encrypted} = EncryptionEngine.encrypt(plaintext, key, file_path)
        {:ok, decrypted} = EncryptionEngine.decrypt(encrypted, key, file_path)

        assert decrypted == plaintext
      end
    end
  end

  describe "empty and minimal inputs" do
    test "empty plaintext round-trips correctly", %{master_key: key} do
      plaintext = ""
      file_path = "/test/empty.txt"

      {:ok, encrypted} = EncryptionEngine.encrypt(plaintext, key, file_path)
      {:ok, decrypted} = EncryptionEngine.decrypt(encrypted, key, file_path)

      assert decrypted == plaintext
    end

    test "single byte round-trips correctly", %{master_key: key} do
      plaintext = "A"
      file_path = "/test/single.txt"

      {:ok, encrypted} = EncryptionEngine.encrypt(plaintext, key, file_path)
      {:ok, decrypted} = EncryptionEngine.decrypt(encrypted, key, file_path)

      assert decrypted == plaintext
    end
  end

  # Helper functions

  defp tamper_with_blob(blob) when byte_size(blob) > 150 do
    # Tamper with a byte in the ciphertext portion (after version + tags)
    # Version is 1 byte, tags are 128 bytes total (16+32+32+16+16+16)
    tamper_position = 150

    <<prefix::binary-size(tamper_position), byte::8, rest::binary>> = blob
    tampered_byte = Bitwise.bxor(byte, 0xFF)
    prefix <> <<tampered_byte>> <> rest
  end

  defp tamper_with_blob(blob) do
    # For very small blobs, just flip a bit somewhere
    size = byte_size(blob)
    position = div(size, 2)
    <<prefix::binary-size(position), byte::8, rest::binary>> = blob
    tampered_byte = Bitwise.bxor(byte, 0xFF)
    prefix <> <<tampered_byte>> <> rest
  end
end
