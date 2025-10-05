defmodule GitVeil.Core.TripleCipherTest do
  use ExUnit.Case, async: true

  alias GitVeil.Core.{TripleCipher, Types}
  alias GitVeil.Core.Types.DerivedKeys
  alias GitVeil.Adapters.{OpenSSLCrypto, AsconCrypto}

  describe "triple-layer quantum-resistant encryption" do
    setup do
      # Generate three independent keys (variable lengths for different algorithms)
      derived_keys = %DerivedKeys{
        layer1_key: :crypto.strong_rand_bytes(32),  # AES-256-GCM
        layer2_key: :crypto.strong_rand_bytes(16),  # Ascon-128a
        layer3_key: :crypto.strong_rand_bytes(32)   # ChaCha20-Poly1305
      }

      {:ok, derived_keys: derived_keys}
    end

    test "encrypts and decrypts plaintext successfully", %{derived_keys: keys} do
      plaintext = "Secret data that needs triple-layer encryption"
      file_path = "/path/to/secret.txt"

      # Encrypt using triple-layer: AES-256-GCM, Ascon-128a, ChaCha20-Poly1305
      {:ok, ciphertext, tag1, tag2, tag3} =
        TripleCipher.encrypt(
          plaintext,
          keys,
          OpenSSLCrypto,  # Layer 1: AES-256-GCM
          AsconCrypto,     # Layer 2: Ascon-128a
          OpenSSLCrypto,  # Layer 3: ChaCha20-Poly1305
          file_path
        )

      # Verify ciphertext is different from plaintext
      assert ciphertext != plaintext
      assert is_binary(ciphertext)

      # Verify we got three auth tags
      assert byte_size(tag1) == 16
      assert byte_size(tag2) == 16
      assert byte_size(tag3) == 16

      # Decrypt (layers in reverse order: ChaCha20 -> Ascon -> AES)
      {:ok, decrypted} =
        TripleCipher.decrypt(
          ciphertext,
          {tag1, tag2, tag3},
          keys,
          OpenSSLCrypto,  # Layer 1: AES-256-GCM
          AsconCrypto,     # Layer 2: Ascon-128a
          OpenSSLCrypto,  # Layer 3: ChaCha20-Poly1305
          file_path
        )

      # Verify we got our original plaintext back
      assert decrypted == plaintext
    end

    test "encryption is deterministic (same input → same output)", %{derived_keys: keys} do
      plaintext = "Deterministic encryption test"
      file_path = "/path/to/file.txt"

      # Encrypt the same data twice
      {:ok, ciphertext1, tag1_a, tag2_a, tag3_a} =
        TripleCipher.encrypt(
          plaintext,
          keys,
          OpenSSLCrypto,  # Layer 1: AES-256-GCM
          AsconCrypto,     # Layer 2: Ascon-128a
          OpenSSLCrypto,  # Layer 3: ChaCha20-Poly1305
          file_path
        )

      {:ok, ciphertext2, tag1_b, tag2_b, tag3_b} =
        TripleCipher.encrypt(
          plaintext,
          keys,
          OpenSSLCrypto,  # Layer 1: AES-256-GCM
          AsconCrypto,     # Layer 2: Ascon-128a
          OpenSSLCrypto,  # Layer 3: ChaCha20-Poly1305
          file_path
        )

      # Verify deterministic: same input produces same output
      assert ciphertext1 == ciphertext2
      assert tag1_a == tag1_b
      assert tag2_a == tag2_b
      assert tag3_a == tag3_b
    end

    test "different plaintexts produce different ciphertexts", %{derived_keys: keys} do
      plaintext1 = "First message"
      plaintext2 = "Second message"
      file_path = "/path/to/file.txt"

      {:ok, ciphertext1, _, _, _} =
        TripleCipher.encrypt(
          plaintext1,
          keys,
          OpenSSLCrypto,  # Layer 1: AES-256-GCM
          AsconCrypto,     # Layer 2: Ascon-128a
          OpenSSLCrypto,  # Layer 3: ChaCha20-Poly1305
          file_path
        )

      {:ok, ciphertext2, _, _, _} =
        TripleCipher.encrypt(
          plaintext2,
          keys,
          OpenSSLCrypto,  # Layer 1: AES-256-GCM
          AsconCrypto,     # Layer 2: Ascon-128a
          OpenSSLCrypto,  # Layer 3: ChaCha20-Poly1305
          file_path
        )

      assert ciphertext1 != ciphertext2
    end

    test "tampering with ciphertext causes authentication failure", %{derived_keys: keys} do
      plaintext = "Original message"
      file_path = "/path/to/file.txt"

      {:ok, ciphertext, tag1, tag2, tag3} =
        TripleCipher.encrypt(
          plaintext,
          keys,
          OpenSSLCrypto,  # Layer 1: AES-256-GCM
          AsconCrypto,     # Layer 2: Ascon-128a
          OpenSSLCrypto,  # Layer 3: ChaCha20-Poly1305
          file_path
        )

      # Tamper with one byte in the ciphertext
      <<first::binary-1, _::binary-1, rest::binary>> = ciphertext
      tampered_ciphertext = first <> <<255>> <> rest

      # Decryption should fail due to authentication
      result =
        TripleCipher.decrypt(
          tampered_ciphertext,
          {tag1, tag2, tag3},
          keys,
          OpenSSLCrypto,  # Layer 1: AES-256-GCM
          AsconCrypto,     # Layer 2: Ascon-128a
          OpenSSLCrypto,  # Layer 3: ChaCha20-Poly1305
          file_path
        )

      assert {:error, :authentication_failed} = result
    end

    test "wrong key causes authentication failure", %{derived_keys: keys} do
      plaintext = "Secret message"
      file_path = "/path/to/file.txt"

      {:ok, ciphertext, tag1, tag2, tag3} =
        TripleCipher.encrypt(
          plaintext,
          keys,
          OpenSSLCrypto,  # Layer 1: AES-256-GCM
          AsconCrypto,     # Layer 2: Ascon-128a
          OpenSSLCrypto,  # Layer 3: ChaCha20-Poly1305
          file_path
        )

      # Try to decrypt with wrong keys
      wrong_keys = %DerivedKeys{
        layer1_key: :crypto.strong_rand_bytes(32),  # Wrong AES key
        layer2_key: :crypto.strong_rand_bytes(16),  # Wrong Ascon key
        layer3_key: :crypto.strong_rand_bytes(32)   # Wrong ChaCha20 key
      }

      result =
        TripleCipher.decrypt(
          ciphertext,
          {tag1, tag2, tag3},
          wrong_keys,
          OpenSSLCrypto,  # Layer 1: AES-256-GCM
          AsconCrypto,     # Layer 2: Ascon-128a
          OpenSSLCrypto,  # Layer 3: ChaCha20-Poly1305
          file_path
        )

      assert {:error, :authentication_failed} = result
    end

    test "handles large plaintexts (1MB)", %{derived_keys: keys} do
      # Generate 1MB of random data
      plaintext = :crypto.strong_rand_bytes(1_024 * 1_024)
      file_path = "/path/to/large_file.bin"

      {:ok, ciphertext, tag1, tag2, tag3} =
        TripleCipher.encrypt(
          plaintext,
          keys,
          OpenSSLCrypto,  # Layer 1: AES-256-GCM
          AsconCrypto,     # Layer 2: Ascon-128a
          OpenSSLCrypto,  # Layer 3: ChaCha20-Poly1305
          file_path
        )

      {:ok, decrypted} =
        TripleCipher.decrypt(
          ciphertext,
          {tag1, tag2, tag3},
          keys,
          OpenSSLCrypto,  # Layer 1: AES-256-GCM
          AsconCrypto,     # Layer 2: Ascon-128a
          OpenSSLCrypto,  # Layer 3: ChaCha20-Poly1305
          file_path
        )

      assert decrypted == plaintext
    end
  end
end
