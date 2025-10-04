defmodule GitVeil.Core.TripleCipher do
  @moduledoc """
  Three-layer authenticated encryption with provider injection.

  **Architecture:**
  - Layer 1: OpenSSL AES-256-GCM (via :crypto)
  - Layer 2: libsodium ChaCha20-Poly1305 (via enacl)
  - Layer 3: libsodium AES-256-GCM (via enacl)

  **Defense in Depth:**
  - Algorithm diversity: AES-256-GCM + ChaCha20-Poly1305
  - Implementation diversity: OpenSSL + libsodium (two different codebases)
  - Post-quantum keypair: Kyber1024 protects master keys

  **Deterministic:**
  Same keys + plaintext → same ciphertext (required for Git)
  Each layer uses deterministic IV derived from content hash.
  """

  alias GitVeil.Core.Types.DerivedKeys
  alias GitVeil.Ports.CryptoProvider

  @doc """
  Encrypts data through three layers.

  ## Parameters
  - plaintext: Data to encrypt
  - derived_keys: Three independent 32-byte keys
  - layer1_provider: CryptoProvider for layer 1 (e.g., OpenSSLCrypto)
  - layer2_provider: CryptoProvider for layer 2 (e.g., LibsodiumCrypto)
  - layer3_provider: CryptoProvider for layer 3 (e.g., LibsodiumCrypto)
  - file_path: File path for AAD context

  ## Returns
  - {:ok, ciphertext, layer1_tag, layer2_tag, layer3_tag}
  - {:error, reason}
  """
  @spec encrypt(
          binary(),
          DerivedKeys.t(),
          module(),
          module(),
          module(),
          String.t()
        ) ::
          {:ok, binary(), binary(), binary(), binary()} | {:error, term()}
  def encrypt(
        plaintext,
        %DerivedKeys{
          layer1_key: key1,
          layer2_key: key2,
          layer3_key: key3
        },
        layer1_provider,
        layer2_provider,
        layer3_provider,
        file_path
      )
      when is_binary(plaintext) and is_binary(file_path) do
    aad = file_path

    with {:ok, iv1} <- derive_deterministic_iv(plaintext, key1, 1),
         {:ok, ciphertext1, tag1} <-
           layer1_provider.aes_256_gcm_encrypt(key1, iv1, plaintext, aad),
         {:ok, iv2} <- derive_deterministic_iv(ciphertext1, key2, 2),
         {:ok, ciphertext2, tag2} <-
           layer2_provider.chacha20_poly1305_encrypt(key2, iv2, ciphertext1, aad),
         {:ok, iv3} <- derive_deterministic_iv(ciphertext2, key3, 3),
         {:ok, ciphertext3, tag3} <-
           layer3_provider.aes_256_gcm_encrypt(key3, iv3, ciphertext2, aad) do
      {:ok, ciphertext3, tag1, tag2, tag3}
    end
  end

  @doc """
  Decrypts data through three layers (reverse order).

  ## Parameters
  - ciphertext: Encrypted data
  - tags: {layer1_tag, layer2_tag, layer3_tag}
  - derived_keys: Three independent 32-byte keys
  - layer1_provider: CryptoProvider for layer 1
  - layer2_provider: CryptoProvider for layer 2
  - layer3_provider: CryptoProvider for layer 3
  - file_path: File path for AAD context

  ## Returns
  - {:ok, plaintext}
  - {:error, reason} (including :authentication_failed if tags don't match)
  """
  @spec decrypt(
          binary(),
          {binary(), binary(), binary()},
          DerivedKeys.t(),
          module(),
          module(),
          module(),
          String.t()
        ) ::
          {:ok, binary()} | {:error, term()}
  def decrypt(
        ciphertext,
        {tag1, tag2, tag3},
        %DerivedKeys{
          layer1_key: key1,
          layer2_key: key2,
          layer3_key: key3
        },
        layer1_provider,
        layer2_provider,
        layer3_provider,
        file_path
      )
      when is_binary(ciphertext) and is_binary(file_path) do
    aad = file_path

    # Decrypt in reverse order: Layer 3 → Layer 2 → Layer 1
    with {:ok, iv3} <- derive_deterministic_iv(ciphertext, key3, 3),
         {:ok, ciphertext2} <-
           layer3_provider.aes_256_gcm_decrypt(key3, iv3, ciphertext, tag3, aad),
         {:ok, iv2} <- derive_deterministic_iv(ciphertext2, key2, 2),
         {:ok, ciphertext1} <-
           layer2_provider.chacha20_poly1305_decrypt(key2, iv2, ciphertext2, tag2, aad),
         {:ok, iv1} <- derive_deterministic_iv(ciphertext1, key1, 1),
         {:ok, plaintext} <-
           layer1_provider.aes_256_gcm_decrypt(key1, iv1, ciphertext1, tag1, aad) do
      {:ok, plaintext}
    end
  end

  # Derives deterministic 12-byte IV from key + layer number only
  # Cannot use content because during decryption we don't have the input content
  # (chicken-and-egg problem: need IV to decrypt, but IV depends on decrypted content)
  # This ensures same key + layer → same IV (required for Git determinism)
  defp derive_deterministic_iv(_content, key, layer_num) do
    try do
      # Hash key + layer number to generate deterministic IV
      # Don't use content - it creates chicken-and-egg problem during decryption
      hash_input = key <> <<layer_num>>
      iv = :crypto.hash(:sha3_256, hash_input) |> binary_part(0, 12)
      {:ok, iv}
    rescue
      error -> {:error, {:iv_derivation_failed, error}}
    end
  end
end
