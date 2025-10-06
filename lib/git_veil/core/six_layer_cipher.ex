defmodule GitVeil.Core.SixLayerCipher do
  @moduledoc """
  Six-layer authenticated encryption with maximum quantum resistance.

  **Architecture (v3.0 - Maximum Quantum Resistance):**
  - Layer 1: AES-256-GCM (32-byte key, 12-byte IV, 16-byte tag)
  - Layer 2: AEGIS-256 (32-byte key, 32-byte nonce, 32-byte tag)
  - Layer 3: Schwaemm256-256 (32-byte key, 32-byte nonce, 32-byte tag)
  - Layer 4: Deoxys-II-256 (32-byte key, 15-byte nonce, 16-byte tag)
  - Layer 5: Ascon-128a (16-byte key, 16-byte nonce, 16-byte tag)
  - Layer 6: ChaCha20-Poly1305 (32-byte key, 12-byte nonce, 16-byte tag)

  **Security:**
  - Combined key space: 1,408 bits
  - Post-quantum security: 704 bits (Grover's algorithm)
  - Algorithm diversity: 6 different mathematical primitives
  - Competition-vetted: All CAESAR winners or NIST finalists

  **Defense in Depth:**
  - No-feedback property: Breaking 1-5 layers gives zero useful information
  - Must break ALL 6 algorithms to decrypt
  - P(break) = P(break AES) × P(break AEGIS) × P(break Schwaemm) ×
                P(break Deoxys) × P(break Ascon) × P(break ChaCha20)

  **Deterministic:**
  Same keys + plaintext → same ciphertext (required for Git)
  Each layer uses deterministic IV/nonce derived from key + layer number.
  """

  alias GitVeil.Core.Types.DerivedKeys

  @doc """
  Encrypts data through six layers.

  ## Parameters
  - plaintext: Data to encrypt
  - derived_keys: Six independent keys (32, 32, 32, 32, 16, 32 bytes)
  - layer1_provider: CryptoProvider for AES-256-GCM
  - layer2_provider: CryptoProvider for AEGIS-256
  - layer3_provider: CryptoProvider for Schwaemm256-256
  - layer4_provider: CryptoProvider for Deoxys-II-256
  - layer5_provider: CryptoProvider for Ascon-128a
  - layer6_provider: CryptoProvider for ChaCha20-Poly1305
  - file_path: File path for AAD context

  ## Returns
  - {:ok, ciphertext, tag1, tag2, tag3, tag4, tag5, tag6}
  - {:error, reason}
  """
  @spec encrypt(
          binary(),
          DerivedKeys.t(),
          module(),
          module(),
          module(),
          module(),
          module(),
          module(),
          String.t()
        ) ::
          {:ok, binary(), binary(), binary(), binary(), binary(), binary(), binary()}
          | {:error, term()}
  def encrypt(
        plaintext,
        %DerivedKeys{
          layer1_key: k1,
          layer2_key: k2,
          layer3_key: k3,
          layer4_key: k4,
          layer5_key: k5,
          layer6_key: k6
        },
        layer1_provider,
        layer2_provider,
        layer3_provider,
        layer4_provider,
        layer5_provider,
        layer6_provider,
        file_path
      )
      when is_binary(plaintext) and is_binary(file_path) do
    aad = file_path

    # Layer 1: AES-256-GCM (12-byte IV)
    # Layer 2: AEGIS-256 (32-byte nonce)
    # Layer 3: Schwaemm256-256 (32-byte nonce)
    # Layer 4: Deoxys-II-256 (15-byte nonce)
    # Layer 5: Ascon-128a (16-byte nonce)
    # Layer 6: ChaCha20-Poly1305 (12-byte nonce)
    with {:ok, iv1} <- derive_deterministic_iv(k1, 1, 12),
         {:ok, ct1, tag1} <- layer1_provider.aes_256_gcm_encrypt(k1, iv1, plaintext, aad),
         {:ok, nonce2} <- derive_deterministic_iv(k2, 2, 32),
         {:ok, ct2, tag2} <- layer2_provider.aegis_256_encrypt(k2, nonce2, ct1, aad),
         {:ok, nonce3} <- derive_deterministic_iv(k3, 3, 32),
         {:ok, ct3, tag3} <- layer3_provider.schwaemm256_256_encrypt(k3, nonce3, ct2, aad),
         {:ok, nonce4} <- derive_deterministic_iv(k4, 4, 15),
         {:ok, ct4, tag4} <- layer4_provider.deoxys_ii_256_encrypt(k4, nonce4, ct3, aad),
         {:ok, nonce5} <- derive_deterministic_iv(k5, 5, 16),
         {:ok, ct5, tag5} <- layer5_provider.ascon_128a_encrypt(k5, nonce5, ct4, aad),
         {:ok, nonce6} <- derive_deterministic_iv(k6, 6, 12),
         {:ok, ct6, tag6} <- layer6_provider.chacha20_poly1305_encrypt(k6, nonce6, ct5, aad) do
      {:ok, ct6, tag1, tag2, tag3, tag4, tag5, tag6}
    end
  end

  @doc """
  Decrypts data through six layers (reverse order).

  ## Parameters
  - ciphertext: Encrypted data
  - tags: {tag1, tag2, tag3, tag4, tag5, tag6}
  - derived_keys: Six independent keys
  - layer1_provider through layer6_provider: CryptoProviders
  - file_path: File path for AAD context

  ## Returns
  - {:ok, plaintext}
  - {:error, reason} (including :authentication_failed if tags don't match)
  """
  @spec decrypt(
          binary(),
          {binary(), binary(), binary(), binary(), binary(), binary()},
          DerivedKeys.t(),
          module(),
          module(),
          module(),
          module(),
          module(),
          module(),
          String.t()
        ) ::
          {:ok, binary()} | {:error, term()}
  def decrypt(
        ciphertext,
        {tag1, tag2, tag3, tag4, tag5, tag6},
        %DerivedKeys{
          layer1_key: k1,
          layer2_key: k2,
          layer3_key: k3,
          layer4_key: k4,
          layer5_key: k5,
          layer6_key: k6
        },
        layer1_provider,
        layer2_provider,
        layer3_provider,
        layer4_provider,
        layer5_provider,
        layer6_provider,
        file_path
      )
      when is_binary(ciphertext) and is_binary(file_path) do
    aad = file_path

    # Decrypt in reverse order: Layer 6 → 5 → 4 → 3 → 2 → 1
    # Layer 6: ChaCha20-Poly1305 (12-byte nonce)
    # Layer 5: Ascon-128a (16-byte nonce)
    # Layer 4: Deoxys-II-256 (15-byte nonce)
    # Layer 3: Schwaemm256-256 (32-byte nonce)
    # Layer 2: AEGIS-256 (32-byte nonce)
    # Layer 1: AES-256-GCM (12-byte IV)
    with {:ok, nonce6} <- derive_deterministic_iv(k6, 6, 12),
         {:ok, ct5} <- layer6_provider.chacha20_poly1305_decrypt(k6, nonce6, ciphertext, tag6, aad),
         {:ok, nonce5} <- derive_deterministic_iv(k5, 5, 16),
         {:ok, ct4} <- layer5_provider.ascon_128a_decrypt(k5, nonce5, ct5, tag5, aad),
         {:ok, nonce4} <- derive_deterministic_iv(k4, 4, 15),
         {:ok, ct3} <- layer4_provider.deoxys_ii_256_decrypt(k4, nonce4, ct4, tag4, aad),
         {:ok, nonce3} <- derive_deterministic_iv(k3, 3, 32),
         {:ok, ct2} <- layer3_provider.schwaemm256_256_decrypt(k3, nonce3, ct3, tag3, aad),
         {:ok, nonce2} <- derive_deterministic_iv(k2, 2, 32),
         {:ok, ct1} <- layer2_provider.aegis_256_decrypt(k2, nonce2, ct2, tag2, aad),
         {:ok, iv1} <- derive_deterministic_iv(k1, 1, 12),
         {:ok, plaintext} <- layer1_provider.aes_256_gcm_decrypt(k1, iv1, ct1, tag1, aad) do
      {:ok, plaintext}
    end
  end

  # Derives deterministic IV/nonce from key + layer number
  # Supports variable-length output for different algorithms:
  # - 12 bytes for AES-256-GCM and ChaCha20-Poly1305
  # - 15 bytes for Deoxys-II-256
  # - 16 bytes for Ascon-128a
  # - 32 bytes for AEGIS-256 and Schwaemm256-256
  #
  # Cannot use content because during decryption we don't have the input content
  # (chicken-and-egg problem: need IV to decrypt, but IV depends on decrypted content)
  # This ensures same key + layer → same IV/nonce (required for Git determinism)
  defp derive_deterministic_iv(key, layer_num, size) do
    try do
      # Hash key + layer number to generate deterministic IV/nonce
      # Don't use content - it creates chicken-and-egg problem during decryption
      hash_input = key <> <<layer_num>>
      iv = :crypto.hash(:sha3_256, hash_input) |> binary_part(0, size)
      {:ok, iv}
    rescue
      error -> {:error, {:iv_derivation_failed, error}}
    end
  end
end
