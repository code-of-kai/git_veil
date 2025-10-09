defmodule GitFoil.Native.ChaCha20Poly1305Nif do
  @moduledoc """
  Rust NIF for ChaCha20-Poly1305 authenticated encryption.

  ChaCha20-Poly1305 is an IETF standard AEAD cipher (RFC 8439) combining
  the ChaCha20 stream cipher with the Poly1305 MAC.

  **Specifications:**
  - Key size: 32 bytes (256 bits)
  - Nonce size: 12 bytes (96 bits) - IETF variant
  - Tag size: 16 bytes (128 bits)
  - AEAD: Authenticated Encryption with Associated Data

  **Security:**
  - IETF standard (RFC 8439)
  - Used in TLS 1.3, WireGuard, Signal, etc.
  - Constant-time implementation
  - Software-friendly (no hardware requirements)
  - Quantum resistance: ~128 bits (via Grover's algorithm)
  """

  use Rustler, otp_app: :git_foil, crate: :chacha20poly1305_nif

  @doc """
  Encrypts plaintext using ChaCha20-Poly1305.

  ## Parameters
  - `key`: 32-byte encryption key
  - `nonce`: 12-byte nonce (must be unique per message)
  - `plaintext`: Data to encrypt
  - `aad`: Additional authenticated data (not encrypted, but authenticated)

  ## Returns
  - `{:ok, {ciphertext, tag}}` - Returns ciphertext and 16-byte authentication tag
  - `{:error, reason}` - Encryption failed

  ## Example
      iex> key = :crypto.strong_rand_bytes(32)
      iex> nonce = :crypto.strong_rand_bytes(12)
      iex> {:ok, {ct, tag}} = GitFoil.Native.ChaCha20Poly1305Nif.encrypt(key, nonce, "secret", "metadata")
      iex> byte_size(tag)
      16
  """
  @spec encrypt(binary(), binary(), binary(), binary()) ::
          {:ok, {binary(), binary()}} | {:error, term()}
  def encrypt(_key, _nonce, _plaintext, _aad), do: {:error, :not_implemented}

  @doc """
  Decrypts ciphertext using ChaCha20-Poly1305.

  ## Parameters
  - `key`: 32-byte encryption key (same as used for encryption)
  - `nonce`: 12-byte nonce (same as used for encryption)
  - `ciphertext`: Encrypted data
  - `tag`: 16-byte authentication tag from encryption
  - `aad`: Additional authenticated data (same as used for encryption)

  ## Returns
  - `{:ok, plaintext}` - Successfully decrypted and verified
  - `{:error, :authentication_failed}` - Tag verification failed (tampered data)
  - `{:error, reason}` - Decryption failed

  ## Example
      iex> key = :crypto.strong_rand_bytes(32)
      iex> nonce = :crypto.strong_rand_bytes(12)
      iex> {:ok, {ct, tag}} = GitFoil.Native.ChaCha20Poly1305Nif.encrypt(key, nonce, "secret", "metadata")
      iex> {:ok, plaintext} = GitFoil.Native.ChaCha20Poly1305Nif.decrypt(key, nonce, ct, tag, "metadata")
      iex> plaintext
      "secret"
  """
  @spec decrypt(binary(), binary(), binary(), binary(), binary()) ::
          {:ok, binary()} | {:error, term()}
  def decrypt(_key, _nonce, _ciphertext, _tag, _aad), do: {:error, :not_implemented}
end
