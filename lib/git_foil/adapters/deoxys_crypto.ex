defmodule GitFoil.Adapters.DeoxysCrypto do
  @moduledoc """
  Deoxys-II-256 authenticated encryption adapter.

  Deoxys-II-256 is a CAESAR competition winner for defense-in-depth category.
  Nonce-misuse resistant with 256-bit security.

  **Architecture:**
  - Port: CryptoProvider
  - Implementation: Rust NIF (deoxys_nif)
  - Algorithm: Deoxys-II-256 AEAD (TWEAKEY framework)

  **Specifications:**
  - Key: 32 bytes (256 bits)
  - Nonce: 15 bytes (120 bits)
  - Tag: 16 bytes (128 bits)

  **Security:**
  - CAESAR winner (2019) - Defense-in-depth category
  - Nonce-misuse resistant
  - ~128-bit post-quantum security
  - Tweakable block cipher
  """

  @behaviour GitFoil.Ports.CryptoProvider

  alias GitFoil.Native.DeoxysNif

  @impl true
  def deoxys_ii_256_encrypt(key, nonce, plaintext, aad)
      when byte_size(key) == 32 and byte_size(nonce) == 15 and is_binary(plaintext) and
             is_binary(aad) do
    case DeoxysNif.encrypt(key, nonce, plaintext, aad) do
      {ciphertext, tag} -> {:ok, ciphertext, tag}
      {:error, _} = error -> error
    end
  end

  def deoxys_ii_256_encrypt(_key, _nonce, _plaintext, _aad) do
    {:error, :invalid_parameters}
  end

  @impl true
  def deoxys_ii_256_decrypt(key, nonce, ciphertext, tag, aad)
      when byte_size(key) == 32 and byte_size(nonce) == 15 and byte_size(tag) == 16 and
             is_binary(ciphertext) and is_binary(aad) do
    case DeoxysNif.decrypt(key, nonce, ciphertext, tag, aad) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      {:error, _} = error -> error
    end
  end

  def deoxys_ii_256_decrypt(_key, _nonce, _ciphertext, _tag, _aad) do
    {:error, :invalid_parameters}
  end

  # Stub unused callbacks (this adapter only implements Deoxys-II-256)
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
  def schwaemm256_256_encrypt(_key, _nonce, _plaintext, _aad), do: {:error, :not_implemented}

  @impl true
  def schwaemm256_256_decrypt(_key, _nonce, _ciphertext, _tag, _aad),
    do: {:error, :not_implemented}
end
