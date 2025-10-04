defmodule GitVeil.Core.KeyDerivation do
  @moduledoc """
  HKDF-based key derivation using SHA3-512.

  **Purpose:**
  Derives three independent 32-byte encryption keys from a master key
  for the three-layer encryption scheme.

  **Algorithm:**
  Uses HKDF (HMAC-based Key Derivation Function) with SHA3-512 as the
  underlying hash function for quantum resistance.

  **Deterministic:**
  Same master key + file path → same derived keys (required for Git)
  """

  alias GitVeil.Core.Types.{EncryptionKey, DerivedKeys}

  @doc """
  Derives three 32-byte keys for triple encryption.

  ## Parameters
  - master_key: 32-byte master encryption key
  - file_path: File path used as context/salt

  ## Returns
  - {:ok, %DerivedKeys{}} with layer1_key, layer2_key, layer3_key
  - {:error, reason}
  """
  @spec derive_keys(EncryptionKey.t(), String.t()) ::
          {:ok, DerivedKeys.t()} | {:error, term()}
  def derive_keys(%EncryptionKey{key: master_key}, file_path)
      when byte_size(master_key) == 32 and is_binary(file_path) do
    try do
      # Use file path as salt/info for context separation
      salt = :crypto.hash(:sha3_512, file_path) |> binary_part(0, 32)

      # Derive three independent keys using HKDF-SHA3-512
      # Each layer gets a different context to ensure key independence
      layer1_key = hkdf_sha3_512(master_key, salt, "GitVeil.Layer1", 32)
      layer2_key = hkdf_sha3_512(master_key, salt, "GitVeil.Layer2", 32)
      layer3_key = hkdf_sha3_512(master_key, salt, "GitVeil.Layer3", 32)

      derived = %DerivedKeys{
        layer1_key: layer1_key,
        layer2_key: layer2_key,
        layer3_key: layer3_key
      }

      {:ok, derived}
    rescue
      error -> {:error, {:key_derivation_failed, error}}
    end
  end

  def derive_keys(_master_key, _file_path) do
    {:error, :invalid_parameters}
  end

  # HKDF implementation using SHA3-512
  defp hkdf_sha3_512(key, salt, info, length) do
    # HKDF-Extract: PRK = HMAC-Hash(salt, IKM)
    prk = hmac_sha3_512(salt, key)

    # HKDF-Expand: OKM = HMAC-Hash(PRK, info || 0x01)
    hmac_sha3_512(prk, info <> <<0x01>>)
    |> binary_part(0, length)
  end

  # HMAC-SHA3-512 implementation
  defp hmac_sha3_512(key, data) do
    :crypto.mac(:hmac, :sha3_512, key, data)
  end
end
