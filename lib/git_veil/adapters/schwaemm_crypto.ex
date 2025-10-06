defmodule GitVeil.Adapters.SchwaemmCrypto do
  @moduledoc """
  Schwaemm256-256 authenticated encryption adapter.

  Schwaemm256-256 is a NIST Lightweight Cryptography finalist based on the Sparkle
  permutation family. Quantum-resistant design with 256-bit security.

  **Architecture:**
  - Port: CryptoProvider
  - Implementation: Rust NIF (schwaemm_nif)
  - Algorithm: Schwaemm256-256 AEAD (Sparkle permutation)

  **Specifications:**
  - Key: 32 bytes (256 bits)
  - Nonce: 32 bytes (256 bits)
  - Tag: 32 bytes (256 bits)

  **Security:**
  - NIST Lightweight Cryptography finalist (2021-2023)
  - Quantum-resistant design
  - ~128-bit post-quantum security
  - Sponge construction
  """

  @behaviour GitVeil.Ports.CryptoProvider

  alias GitVeil.Native.SchwaemmNif

  @impl true
  def schwaemm256_256_encrypt(key, nonce, plaintext, aad)
      when byte_size(key) == 32 and byte_size(nonce) == 32 and is_binary(plaintext) and
             is_binary(aad) do
    case SchwaemmNif.encrypt(key, nonce, plaintext, aad) do
      {ciphertext, tag} when is_binary(ciphertext) and is_binary(tag) -> {:ok, ciphertext, tag}
      {:error, _} = error -> error
      _ -> {:error, :encryption_failed}
    end
  end

  def schwaemm256_256_encrypt(_key, _nonce, _plaintext, _aad) do
    {:error, :invalid_parameters}
  end

  @impl true
  def schwaemm256_256_decrypt(key, nonce, ciphertext, tag, aad)
      when byte_size(key) == 32 and byte_size(nonce) == 32 and byte_size(tag) == 32 and
             is_binary(ciphertext) and is_binary(aad) do
    case SchwaemmNif.decrypt(key, nonce, ciphertext, tag, aad) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      {:error, _} = error -> error
      _ -> {:error, :decryption_failed}
    end
  end

  def schwaemm256_256_decrypt(_key, _nonce, _ciphertext, _tag, _aad) do
    {:error, :invalid_parameters}
  end

  # Stub unused callbacks (this adapter only implements Schwaemm256-256)
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
  def aegis_256_encrypt(_key, _nonce, _plaintext, _aad), do: {:error, :not_implemented}

  @impl true
  def aegis_256_decrypt(_key, _nonce, _ciphertext, _tag, _aad), do: {:error, :not_implemented}

  @impl true
  def deoxys_ii_256_encrypt(_key, _nonce, _plaintext, _aad), do: {:error, :not_implemented}

  @impl true
  def deoxys_ii_256_decrypt(_key, _nonce, _ciphertext, _tag, _aad),
    do: {:error, :not_implemented}
end
