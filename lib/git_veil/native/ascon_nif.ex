defmodule GitVeil.Native.AsconNif do
  @moduledoc """
  Ascon-128a NIF loader.

  This module loads the Rust-based Ascon-128a NIF and provides
  a fallback error message if the NIF fails to load.
  """

  use Rustler, otp_app: :git_veil, crate: "ascon_nif"

  @doc """
  Initializes the Ascon NIF (for testing).
  """
  def init, do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Encrypts plaintext using Ascon-128a AEAD.

  ## Parameters
  - key: 16-byte encryption key
  - nonce: 16-byte nonce
  - plaintext: Data to encrypt
  - aad: Additional authenticated data

  ## Returns
  - {:ok, ciphertext, tag}
  - Error if NIF not loaded
  """
  def encrypt(_key, _nonce, _plaintext, _aad), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Decrypts ciphertext using Ascon-128a AEAD.

  ## Parameters
  - key: 16-byte encryption key
  - nonce: 16-byte nonce
  - ciphertext: Encrypted data
  - tag: 16-byte authentication tag
  - aad: Additional authenticated data

  ## Returns
  - {:ok, plaintext}
  - Error if authentication fails or NIF not loaded
  """
  def decrypt(_key, _nonce, _ciphertext, _tag, _aad), do: :erlang.nif_error(:nif_not_loaded)
end
