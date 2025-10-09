defmodule GitFoil.Native.SchwaemmNif do
  @moduledoc """
  Rust NIF for Schwaemm256-256 authenticated encryption.

  Schwaemm256-256 is a NIST Lightweight Cryptography finalist based on
  the Sparkle permutation family. Quantum-resistant design with 256-bit security.

  **Specifications:**
  - Key size: 32 bytes (256 bits)
  - Nonce size: 32 bytes (256 bits)
  - Tag size: 32 bytes (256 bits)
  - AEAD: Authenticated Encryption with Associated Data

  **Security:**
  - NIST Lightweight Cryptography finalist (2021-2023)
  - Sponge construction (Sparkle permutation)
  - Quantum-resistant design
  - ~128-bit post-quantum security (via Grover's algorithm)
  """

  # Schwaemm256-256 now implemented using custom Rust code
  use Rustler, otp_app: :git_foil, crate: :schwaemm_nif

  @doc """
  Encrypts plaintext using Schwaemm256-256.

  ## Parameters
  - `key`: 32-byte encryption key
  - `nonce`: 32-byte nonce (must be unique per message)
  - `plaintext`: Data to encrypt
  - `aad`: Additional authenticated data (not encrypted, but authenticated)

  ## Returns
  - `{:ok, {ciphertext, tag}}` - Returns ciphertext and 32-byte authentication tag
  - `{:error, reason}` - Encryption failed

  ## Example
      iex> key = :crypto.strong_rand_bytes(32)
      iex> nonce = :crypto.strong_rand_bytes(32)
      iex> {:ok, {ct, tag}} = GitFoil.Native.SchwaemmNif.encrypt(key, nonce, "secret", "metadata")
      iex> byte_size(tag)
      32
  """
  @spec encrypt(binary(), binary(), binary(), binary()) ::
          {:ok, {binary(), binary()}} | {:error, term()}
  def encrypt(_key, _nonce, _plaintext, _aad), do: {:error, :not_implemented}

  @doc """
  Decrypts ciphertext using Schwaemm256-256.

  ## Parameters
  - `key`: 32-byte encryption key (same as used for encryption)
  - `nonce`: 32-byte nonce (same as used for encryption)
  - `ciphertext`: Encrypted data
  - `tag`: 32-byte authentication tag from encryption
  - `aad`: Additional authenticated data (same as used for encryption)

  ## Returns
  - `{:ok, plaintext}` - Successfully decrypted and verified
  - `{:error, :authentication_failed}` - Tag verification failed (tampered data)
  - `{:error, reason}` - Decryption failed

  ## Example
      iex> key = :crypto.strong_rand_bytes(32)
      iex> nonce = :crypto.strong_rand_bytes(32)
      iex> {:ok, {ct, tag}} = GitFoil.Native.SchwaemmNif.encrypt(key, nonce, "secret", "metadata")
      iex> {:ok, plaintext} = GitFoil.Native.SchwaemmNif.decrypt(key, nonce, ct, tag, "metadata")
      iex> plaintext
      "secret"
  """
  @spec decrypt(binary(), binary(), binary(), binary(), binary()) ::
          {:ok, binary()} | {:error, term()}
  def decrypt(_key, _nonce, _ciphertext, _tag, _aad), do: {:error, :not_implemented}
end
