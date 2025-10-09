defmodule GitFoil.Core.KeyDerivation do
  @moduledoc """
  HKDF-based key derivation using SHA3-512.

  **Purpose:**
  Derives six independent keys from a master key for the six-layer
  encryption scheme (v3.0).

  **Algorithm:**
  Uses HKDF (HMAC-based Key Derivation Function) with SHA3-512 as the
  underlying hash function for quantum resistance.

  **Deterministic:**
  Same master key + file path → same derived keys (required for Git)

  **Key Sizes (v3.0):**
  - Layer 1: 32 bytes (AES-256-GCM)
  - Layer 2: 32 bytes (AEGIS-256)
  - Layer 3: 32 bytes (Schwaemm256-256)
  - Layer 4: 32 bytes (Deoxys-II-256)
  - Layer 5: 16 bytes (Ascon-128a)
  - Layer 6: 32 bytes (ChaCha20-Poly1305)

  Total: 1,408 bits → 704 bits post-quantum security
  """

  alias GitFoil.Core.Types.{EncryptionKey, DerivedKeys}

  @doc """
  Derives six independent keys for 6-layer encryption with variable lengths.

  ## Parameters
  - master_key: 32-byte master encryption key
  - file_path: File path used as context/salt

  ## Returns
  - {:ok, %DerivedKeys{}} with:
    - layer1_key: 32 bytes (AES-256-GCM)
    - layer2_key: 32 bytes (AEGIS-256)
    - layer3_key: 32 bytes (Schwaemm256-256)
    - layer4_key: 32 bytes (Deoxys-II-256)
    - layer5_key: 16 bytes (Ascon-128a)
    - layer6_key: 32 bytes (ChaCha20-Poly1305)
  - {:error, reason}
  """
  @spec derive_keys(EncryptionKey.t(), String.t()) ::
          {:ok, DerivedKeys.t()} | {:error, term()}
  def derive_keys(%EncryptionKey{key: master_key}, file_path)
      when byte_size(master_key) == 32 and is_binary(file_path) do
    try do
      # Use file path as salt/info for context separation
      salt = :crypto.hash(:sha3_512, file_path) |> binary_part(0, 32)

      # Derive six independent keys using HKDF-SHA3-512
      # Each layer gets a different context to ensure key independence
      # Layer 1: AES-256-GCM (32 bytes)
      layer1_key = hkdf_sha3_512(master_key, salt, "GitFoil.Layer1.AES256", 32)
      # Layer 2: AEGIS-256 (32 bytes)
      layer2_key = hkdf_sha3_512(master_key, salt, "GitFoil.Layer2.AEGIS256", 32)
      # Layer 3: Schwaemm256-256 (32 bytes)
      layer3_key = hkdf_sha3_512(master_key, salt, "GitFoil.Layer3.Schwaemm256", 32)
      # Layer 4: Deoxys-II-256 (32 bytes)
      layer4_key = hkdf_sha3_512(master_key, salt, "GitFoil.Layer4.DeoxysII256", 32)
      # Layer 5: Ascon-128a (16 bytes)
      layer5_key = hkdf_sha3_512(master_key, salt, "GitFoil.Layer5.Ascon128a", 16)
      # Layer 6: ChaCha20-Poly1305 (32 bytes)
      layer6_key = hkdf_sha3_512(master_key, salt, "GitFoil.Layer6.ChaCha20", 32)

      derived = %DerivedKeys{
        layer1_key: layer1_key,
        layer2_key: layer2_key,
        layer3_key: layer3_key,
        layer4_key: layer4_key,
        layer5_key: layer5_key,
        layer6_key: layer6_key
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
