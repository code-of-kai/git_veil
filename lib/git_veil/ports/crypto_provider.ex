defmodule GitVeil.Ports.CryptoProvider do
  @moduledoc """
  Port for cryptographic operations.

  **AEAD Algorithms:**
  - AES-256-GCM: 256-bit key, 96-bit IV, 128-bit auth tag
  - ChaCha20-Poly1305: 256-bit key, 96-bit nonce, 128-bit auth tag

  All operations use authenticated encryption with associated data (AEAD).
  """

  @callback aes_256_gcm_encrypt(
              key :: binary(),
              iv :: binary(),
              plaintext :: binary(),
              aad :: binary()
            ) ::
              {:ok, ciphertext :: binary(), tag :: binary()}
              | {:error, term()}

  @callback aes_256_gcm_decrypt(
              key :: binary(),
              iv :: binary(),
              ciphertext :: binary(),
              tag :: binary(),
              aad :: binary()
            ) ::
              {:ok, plaintext :: binary()}
              | {:error, term()}

  @callback chacha20_poly1305_encrypt(
              key :: binary(),
              iv :: binary(),
              plaintext :: binary(),
              aad :: binary()
            ) ::
              {:ok, ciphertext :: binary(), tag :: binary()}
              | {:error, term()}

  @callback chacha20_poly1305_decrypt(
              key :: binary(),
              iv :: binary(),
              ciphertext :: binary(),
              tag :: binary(),
              aad :: binary()
            ) ::
              {:ok, plaintext :: binary()}
              | {:error, term()}
end
