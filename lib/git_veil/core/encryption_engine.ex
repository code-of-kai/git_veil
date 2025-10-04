defmodule GitVeil.Core.EncryptionEngine do
  @moduledoc """
  Orchestrates the complete encryption/decryption pipeline.

  **Pipeline:**
  1. Key Derivation: Master key → Three layer-specific keys
  2. Triple Cipher: Three-layer AEAD encryption
  3. Serialization: Pack ciphertext + tags into wire format

  **Wire Format:**
  ```
  [version:1][tag1:16][tag2:16][tag3:16][ciphertext:variable]
  ```

  Version byte allows for future algorithm changes.
  """

  alias GitVeil.Core.{KeyDerivation, TripleCipher, Types}
  alias GitVeil.Core.Types.{EncryptionKey, EncryptedBlob}

  @version 1

  @doc """
  Encrypts plaintext using three-layer encryption.

  ## Parameters
  - plaintext: Data to encrypt
  - master_key: 32-byte master encryption key
  - layer1_provider: CryptoProvider module for layer 1
  - layer2_provider: CryptoProvider module for layer 2
  - layer3_provider: CryptoProvider module for layer 3
  - file_path: File path for key derivation context

  ## Returns
  - {:ok, %EncryptedBlob{}} with serialized encrypted data
  - {:error, reason}
  """
  @spec encrypt(
          binary(),
          EncryptionKey.t(),
          module(),
          module(),
          module(),
          String.t()
        ) ::
          {:ok, EncryptedBlob.t()} | {:error, term()}
  def encrypt(
        plaintext,
        master_key,
        layer1_provider,
        layer2_provider,
        layer3_provider,
        file_path
      )
      when is_binary(plaintext) and is_binary(file_path) do
    with {:ok, derived_keys} <- KeyDerivation.derive_keys(master_key, file_path),
         {:ok, ciphertext, tag1, tag2, tag3} <-
           TripleCipher.encrypt(
             plaintext,
             derived_keys,
             layer1_provider,
             layer2_provider,
             layer3_provider,
             file_path
           ) do
      blob = %EncryptedBlob{
        version: @version,
        tag1: tag1,
        tag2: tag2,
        tag3: tag3,
        ciphertext: ciphertext
      }

      {:ok, blob}
    end
  end

  @doc """
  Decrypts an encrypted blob.

  ## Parameters
  - blob: %EncryptedBlob{} with version, tags, and ciphertext
  - master_key: 32-byte master encryption key
  - layer1_provider: CryptoProvider module for layer 1
  - layer2_provider: CryptoProvider module for layer 2
  - layer3_provider: CryptoProvider module for layer 3
  - file_path: File path for key derivation context

  ## Returns
  - {:ok, plaintext}
  - {:error, reason}
  """
  @spec decrypt(
          EncryptedBlob.t(),
          EncryptionKey.t(),
          module(),
          module(),
          module(),
          String.t()
        ) ::
          {:ok, binary()} | {:error, term()}
  def decrypt(
        %EncryptedBlob{
          version: version,
          tag1: tag1,
          tag2: tag2,
          tag3: tag3,
          ciphertext: ciphertext
        },
        master_key,
        layer1_provider,
        layer2_provider,
        layer3_provider,
        file_path
      )
      when is_binary(file_path) do
    with :ok <- validate_version(version),
         {:ok, derived_keys} <- KeyDerivation.derive_keys(master_key, file_path),
         {:ok, plaintext} <-
           TripleCipher.decrypt(
             ciphertext,
             {tag1, tag2, tag3},
             derived_keys,
             layer1_provider,
             layer2_provider,
             layer3_provider,
             file_path
           ) do
      {:ok, plaintext}
    end
  end

  @doc """
  Serializes an encrypted blob to binary wire format.

  Format: [version:1][tag1:16][tag2:16][tag3:16][ciphertext:variable]
  """
  @spec serialize(EncryptedBlob.t()) :: binary()
  def serialize(%EncryptedBlob{
        version: version,
        tag1: tag1,
        tag2: tag2,
        tag3: tag3,
        ciphertext: ciphertext
      }) do
    <<version::8, tag1::binary-16, tag2::binary-16, tag3::binary-16, ciphertext::binary>>
  end

  @doc """
  Deserializes binary wire format to encrypted blob.

  Format: [version:1][tag1:16][tag2:16][tag3:16][ciphertext:variable]
  """
  @spec deserialize(binary()) :: {:ok, EncryptedBlob.t()} | {:error, term()}
  def deserialize(
        <<version::8, tag1::binary-16, tag2::binary-16, tag3::binary-16, ciphertext::binary>>
      ) do
    blob = %EncryptedBlob{
      version: version,
      tag1: tag1,
      tag2: tag2,
      tag3: tag3,
      ciphertext: ciphertext
    }

    {:ok, blob}
  end

  def deserialize(_invalid) do
    {:error, :invalid_blob_format}
  end

  # Validates the version byte
  defp validate_version(@version), do: :ok
  defp validate_version(v), do: {:error, {:unsupported_version, v}}
end
