defmodule GitVeil.Native.DeoxysNif do
  @moduledoc """
  Rust NIF for Deoxys-II-256 authenticated encryption.

  Deoxys-II-256 is a CAESAR competition winner for the defense-in-depth category.
  Nonce-misuse resistant with 256-bit security.

  **Specifications:**
  - Key size: 32 bytes (256 bits)
  - Nonce size: 15 bytes (120 bits)
  - Tag size: 16 bytes (128 bits)
  - AEAD: Authenticated Encryption with Associated Data
  - Nonce-misuse resistant

  **Security:**
  - CAESAR winner (2019) - Defense-in-depth category
  - Tweakable block cipher (TWEAKEY framework)
  - Nonce-misuse resistant design
  - ~128-bit post-quantum security (via Grover's algorithm)
  """

  use Rustler, otp_app: :git_veil, crate: :deoxys_nif

  @doc """
  Encrypts plaintext using Deoxys-II-256.

  ## Parameters
  - `key`: 32-byte encryption key
  - `nonce`: 15-byte nonce (120 bits, must be unique per message)
  - `plaintext`: Data to encrypt
  - `aad`: Additional authenticated data (not encrypted, but authenticated)

  ## Returns
  - `{:ok, {ciphertext, tag}}` - Returns ciphertext and 16-byte authentication tag
  - `{:error, reason}` - Encryption failed

  ## Example
      iex> key = :crypto.strong_rand_bytes(32)
      iex> nonce = :crypto.strong_rand_bytes(15)
      iex> {:ok, {ct, tag}} = GitVeil.Native.DeoxysNif.encrypt(key, nonce, "secret", "metadata")
      iex> byte_size(tag)
      16
  """
  @spec encrypt(binary(), binary(), binary(), binary()) ::
          {:ok, {binary(), binary()}} | {:error, term()}
  def encrypt(_key, _nonce, _plaintext, _aad), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Decrypts ciphertext using Deoxys-II-256.

  ## Parameters
  - `key`: 32-byte encryption key (same as used for encryption)
  - `nonce`: 15-byte nonce (same as used for encryption)
  - `ciphertext`: Encrypted data
  - `tag`: 16-byte authentication tag from encryption
  - `aad`: Additional authenticated data (same as used for encryption)

  ## Returns
  - `{:ok, plaintext}` - Successfully decrypted and verified
  - `{:error, :authentication_failed}` - Tag verification failed (tampered data)
  - `{:error, reason}` - Decryption failed

  ## Example
      iex> key = :crypto.strong_rand_bytes(32)
      iex> nonce = :crypto.strong_rand_bytes(15)
      iex> {:ok, {ct, tag}} = GitVeil.Native.DeoxysNif.encrypt(key, nonce, "secret", "metadata")
      iex> {:ok, plaintext} = GitVeil.Native.DeoxysNif.decrypt(key, nonce, ct, tag, "metadata")
      iex> plaintext
      "secret"
  """
  @spec decrypt(binary(), binary(), binary(), binary(), binary()) ::
          {:ok, binary()} | {:error, term()}
  def decrypt(_key, _nonce, _ciphertext, _tag, _aad), do: :erlang.nif_error(:nif_not_loaded)
end
