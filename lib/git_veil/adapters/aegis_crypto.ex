defmodule GitVeil.Adapters.AegisCrypto do
  @moduledoc """
  AEGIS-256 authenticated encryption adapter.

  AEGIS-256 is a CAESAR competition winner optimized for high performance
  using AES round functions. Provides 256-bit security with hardware acceleration.

  **Architecture:**
  - Port: CryptoProvider
  - Implementation: Rust NIF (aegis_nif)
  - Algorithm: AEGIS-256 AEAD

  **Specifications:**
  - Key: 32 bytes (256 bits)
  - Nonce: 32 bytes (256 bits)
  - Tag: 32 bytes (256 bits)

  **Security:**
  - CAESAR winner (2019)
  - ~128-bit post-quantum security
  - Hardware-accelerated (AES-NI)
  """

  @behaviour GitVeil.Ports.CryptoProvider

  alias GitVeil.Native.AegisNif

  @impl true
  def aegis_256_encrypt(key, nonce, plaintext, aad)
      when byte_size(key) == 32 and byte_size(nonce) == 32 and is_binary(plaintext) and
             is_binary(aad) do
    case AegisNif.encrypt(key, nonce, plaintext, aad) do
      {ciphertext, tag} -> {:ok, ciphertext, tag}
      {:error, _} = error -> error
    end
  end

  def aegis_256_encrypt(_key, _nonce, _plaintext, _aad) do
    {:error, :invalid_parameters}
  end

  @impl true
  def aegis_256_decrypt(key, nonce, ciphertext, tag, aad)
      when byte_size(key) == 32 and byte_size(nonce) == 32 and byte_size(tag) == 32 and
             is_binary(ciphertext) and is_binary(aad) do
    case AegisNif.decrypt(key, nonce, ciphertext, tag, aad) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      {:error, _} = error -> error
    end
  end

  def aegis_256_decrypt(_key, _nonce, _ciphertext, _tag, _aad) do
    {:error, :invalid_parameters}
  end

  # Stub unused callbacks (this adapter only implements AEGIS-256)
  @impl true
  def aes_256_gcm_encrypt(_key, _iv, _plaintext, _aad), do: {:error, :not_implemented}

  @impl true
  def aes_256_gcm_decrypt(_key, _iv, _ciphertext, _tag, _aad), do: {:error, :not_implemented}

  @impl true
  def ascon_128a_encrypt(_key, _nonce, _plaintext, _aad), do: {:error, :not_implemented}

  @impl true
  def ascon_128a_decrypt(_key, _nonce, _ciphertext, _tag, _aad), do: {:error, :not_implemented}

  @impl true
  def chacha20_poly1305_encrypt(_key, _nonce, _plaintext, _aad), do: {:error, :not_implemented}

  @impl true
  def chacha20_poly1305_decrypt(_key, _nonce, _ciphertext, _tag, _aad),
    do: {:error, :not_implemented}

  @impl true
  def schwaemm256_256_encrypt(_key, _nonce, _plaintext, _aad), do: {:error, :not_implemented}

  @impl true
  def schwaemm256_256_decrypt(_key, _nonce, _ciphertext, _tag, _aad),
    do: {:error, :not_implemented}

  @impl true
  def deoxys_ii_256_encrypt(_key, _nonce, _plaintext, _aad), do: {:error, :not_implemented}

  @impl true
  def deoxys_ii_256_decrypt(_key, _nonce, _ciphertext, _tag, _aad),
    do: {:error, :not_implemented}
end
