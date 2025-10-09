defmodule GitFoil.Ports.CryptoProvider do
  @moduledoc """
  Port for cryptographic operations.

  **AEAD Algorithms (v3.0 - 6-layer):**
  - AES-256-GCM: 256-bit key, 96-bit IV, 128-bit auth tag
  - AEGIS-256: 256-bit key, 256-bit nonce, 256-bit auth tag (CAESAR winner)
  - Schwaemm256-256: 256-bit key, 256-bit nonce, 256-bit auth tag (NIST finalist)
  - Deoxys-II-256: 256-bit key, 120-bit nonce, 128-bit auth tag (CAESAR winner)
  - Ascon-128a: 128-bit key, 128-bit nonce, 128-bit auth tag (NIST winner)
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

  @callback ascon_128a_encrypt(
              key :: binary(),
              nonce :: binary(),
              plaintext :: binary(),
              aad :: binary()
            ) ::
              {:ok, ciphertext :: binary(), tag :: binary()}
              | {:error, term()}

  @callback ascon_128a_decrypt(
              key :: binary(),
              nonce :: binary(),
              ciphertext :: binary(),
              tag :: binary(),
              aad :: binary()
            ) ::
              {:ok, plaintext :: binary()}
              | {:error, term()}

  @callback aegis_256_encrypt(
              key :: binary(),
              nonce :: binary(),
              plaintext :: binary(),
              aad :: binary()
            ) ::
              {:ok, ciphertext :: binary(), tag :: binary()}
              | {:error, term()}

  @callback aegis_256_decrypt(
              key :: binary(),
              nonce :: binary(),
              ciphertext :: binary(),
              tag :: binary(),
              aad :: binary()
            ) ::
              {:ok, plaintext :: binary()}
              | {:error, term()}

  @callback schwaemm256_256_encrypt(
              key :: binary(),
              nonce :: binary(),
              plaintext :: binary(),
              aad :: binary()
            ) ::
              {:ok, ciphertext :: binary(), tag :: binary()}
              | {:error, term()}

  @callback schwaemm256_256_decrypt(
              key :: binary(),
              nonce :: binary(),
              ciphertext :: binary(),
              tag :: binary(),
              aad :: binary()
            ) ::
              {:ok, plaintext :: binary()}
              | {:error, term()}

  @callback deoxys_ii_256_encrypt(
              key :: binary(),
              nonce :: binary(),
              plaintext :: binary(),
              aad :: binary()
            ) ::
              {:ok, ciphertext :: binary(), tag :: binary()}
              | {:error, term()}

  @callback deoxys_ii_256_decrypt(
              key :: binary(),
              nonce :: binary(),
              ciphertext :: binary(),
              tag :: binary(),
              aad :: binary()
            ) ::
              {:ok, plaintext :: binary()}
              | {:error, term()}
end
