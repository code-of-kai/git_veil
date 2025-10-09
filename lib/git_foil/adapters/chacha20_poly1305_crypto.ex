defmodule GitFoil.Adapters.ChaCha20Poly1305Crypto do
  @moduledoc """
  ChaCha20-Poly1305 authenticated encryption adapter.

  ChaCha20-Poly1305 is an IETF standard AEAD cipher (RFC 8439) widely used
  in modern protocols like TLS 1.3, WireGuard, and Signal.

  **Architecture:**
  - Port: CryptoProvider
  - Implementation: Rust NIF (chacha20poly1305_nif)
  - Algorithm: ChaCha20-Poly1305 AEAD

  **Specifications:**
  - Key: 32 bytes (256 bits)
  - Nonce: 12 bytes (96 bits) - IETF variant
  - Tag: 16 bytes (128 bits)

  **Security:**
  - IETF standard (RFC 8439)
  - ~128-bit post-quantum security
  - Software-friendly (no hardware requirements)
  - Constant-time implementation
  """

  @behaviour GitFoil.Ports.CryptoProvider

  alias GitFoil.Native.ChaCha20Poly1305Nif

  @impl true
  def chacha20_poly1305_encrypt(key, iv, plaintext, aad)
      when byte_size(key) == 32 and byte_size(iv) == 12 and is_binary(plaintext) and
             is_binary(aad) do
    case ChaCha20Poly1305Nif.encrypt(key, iv, plaintext, aad) do
      {ciphertext, tag} -> {:ok, ciphertext, tag}
      {:error, _} = error -> error
    end
  end

  def chacha20_poly1305_encrypt(_key, _iv, _plaintext, _aad) do
    {:error, :invalid_parameters}
  end

  @impl true
  def chacha20_poly1305_decrypt(key, iv, ciphertext, tag, aad)
      when byte_size(key) == 32 and byte_size(iv) == 12 and byte_size(tag) == 16 and
             is_binary(ciphertext) and is_binary(aad) do
    case ChaCha20Poly1305Nif.decrypt(key, iv, ciphertext, tag, aad) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      {:error, _} = error -> error
    end
  end

  def chacha20_poly1305_decrypt(_key, _iv, _ciphertext, _tag, _aad) do
    {:error, :invalid_parameters}
  end

  # Stub unused callbacks (this adapter only implements ChaCha20-Poly1305)
  @impl true
  def aes_256_gcm_encrypt(_key, _iv, _plaintext, _aad), do: {:error, :not_implemented}

  @impl true
  def aes_256_gcm_decrypt(_key, _iv, _ciphertext, _tag, _aad), do: {:error, :not_implemented}

  @impl true
  def ascon_128a_encrypt(_key, _nonce, _plaintext, _aad), do: {:error, :not_implemented}

  @impl true
  def ascon_128a_decrypt(_key, _nonce, _ciphertext, _tag, _aad), do: {:error, :not_implemented}

  @impl true
  def aegis_256_encrypt(_key, _nonce, _plaintext, _aad), do: {:error, :not_implemented}

  @impl true
  def aegis_256_decrypt(_key, _nonce, _ciphertext, _tag, _aad),
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
