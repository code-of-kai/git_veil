#!/usr/bin/env elixir

# Quick test for Schwaemm256-256 NIF

alias GitVeil.Adapters.SchwaemmCrypto

# Test 1: Basic roundtrip
IO.puts("\n=== Test 1: Basic Roundtrip ===")
key = :crypto.strong_rand_bytes(32)
nonce = :crypto.strong_rand_bytes(32)
plaintext = "Hello, Schwaemm256-256!"
aad = "Additional data"

case SchwaemmCrypto.schwaemm256_256_encrypt(key, nonce, plaintext, aad) do
  {:ok, ciphertext, tag} ->
    IO.puts("✓ Encryption successful")
    IO.puts("  CT length: #{byte_size(ciphertext)} bytes")
    IO.puts("  Tag length: #{byte_size(tag)} bytes")

    case SchwaemmCrypto.schwaemm256_256_decrypt(key, nonce, ciphertext, tag, aad) do
      {:ok, decrypted} ->
        if decrypted == plaintext do
          IO.puts("✓ Decryption successful - roundtrip OK!")
        else
          IO.puts("✗ Decryption failed - plaintext mismatch")
          IO.puts("  Expected: #{plaintext}")
          IO.puts("  Got: #{decrypted}")
          System.halt(1)
        end

      {:error, reason} ->
        IO.puts("✗ Decryption failed: #{inspect(reason)}")
        System.halt(1)
    end

  {:error, reason} ->
    IO.puts("✗ Encryption failed: #{inspect(reason)}")
    System.halt(1)
end

# Test 2: Authentication failure
IO.puts("\n=== Test 2: Authentication Failure ===")
{:ok, ct, tag} = SchwaemmCrypto.schwaemm256_256_encrypt(key, nonce, plaintext, aad)
tampered_tag = :binary.part(tag, 0, 31) <> <<0>>

try do
  case SchwaemmCrypto.schwaemm256_256_decrypt(key, nonce, ct, tampered_tag, aad) do
    {:error, _} ->
      IO.puts("✓ Tampered tag correctly rejected (error tuple)")

    {:ok, _} ->
      IO.puts("✗ Tampered tag was accepted - SECURITY FAILURE!")
      System.halt(1)
  end
rescue
  ErlangError ->
    IO.puts("✓ Tampered tag correctly rejected (exception)")
end

# Test 3: Empty plaintext
IO.puts("\n=== Test 3: Empty Plaintext ===")
{:ok, ct_empty, tag_empty} = SchwaemmCrypto.schwaemm256_256_encrypt(key, nonce, "", "")
{:ok, pt_empty} = SchwaemmCrypto.schwaemm256_256_decrypt(key, nonce, ct_empty, tag_empty, "")

if pt_empty == "" do
  IO.puts("✓ Empty plaintext handled correctly")
else
  IO.puts("✗ Empty plaintext failed")
  System.halt(1)
end

IO.puts("\n=== All Tests Passed! ===\n")
