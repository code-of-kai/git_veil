#!/usr/bin/env elixir

# Quick test for ChaCha20-Poly1305 NIF

alias GitFoil.Adapters.ChaCha20Poly1305Crypto

# Test 1: Basic roundtrip
IO.puts("\n=== Test 1: Basic Roundtrip ===")
key = :crypto.strong_rand_bytes(32)
nonce = :crypto.strong_rand_bytes(12)
plaintext = "Hello, ChaCha20-Poly1305!"
aad = "Additional data"

case ChaCha20Poly1305Crypto.chacha20_poly1305_encrypt(key, nonce, plaintext, aad) do
  {:ok, ciphertext, tag} ->
    IO.puts("✓ Encryption successful")
    IO.puts("  CT length: #{byte_size(ciphertext)} bytes")
    IO.puts("  Tag length: #{byte_size(tag)} bytes")

    case ChaCha20Poly1305Crypto.chacha20_poly1305_decrypt(key, nonce, ciphertext, tag, aad) do
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
{:ok, ct, tag} = ChaCha20Poly1305Crypto.chacha20_poly1305_encrypt(key, nonce, plaintext, aad)
tampered_tag = :binary.part(tag, 0, 15) <> <<0>>

try do
  case ChaCha20Poly1305Crypto.chacha20_poly1305_decrypt(key, nonce, ct, tampered_tag, aad) do
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
{:ok, ct_empty, tag_empty} = ChaCha20Poly1305Crypto.chacha20_poly1305_encrypt(key, nonce, "", "")
{:ok, pt_empty} = ChaCha20Poly1305Crypto.chacha20_poly1305_decrypt(key, nonce, ct_empty, tag_empty, "")

if pt_empty == "" do
  IO.puts("✓ Empty plaintext handled correctly")
else
  IO.puts("✗ Empty plaintext failed")
  System.halt(1)
end

# Test 4: RFC 8439 Test Vector 1
IO.puts("\n=== Test 4: RFC 8439 Test Vector ===")
# From RFC 8439 Appendix A.5 (Test Vector #1)
rfc_key = <<
  0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
  0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d, 0x8e, 0x8f,
  0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97,
  0x98, 0x99, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f
>>

rfc_nonce = <<
  0x07, 0x00, 0x00, 0x00,
  0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47
>>

rfc_plaintext = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
rfc_aad = <<0x50, 0x51, 0x52, 0x53, 0xc0, 0xc1, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7>>

rfc_expected_ct = <<
  0xd3, 0x1a, 0x8d, 0x34, 0x64, 0x8e, 0x60, 0xdb, 0x7b, 0x86, 0xaf, 0xbc,
  0x53, 0xef, 0x7e, 0xc2, 0xa4, 0xad, 0xed, 0x51, 0x29, 0x6e, 0x08, 0xfe,
  0xa9, 0xe2, 0xb5, 0xa7, 0x36, 0xee, 0x62, 0xd6, 0x3d, 0xbe, 0xa4, 0x5e,
  0x8c, 0xa9, 0x67, 0x12, 0x82, 0xfa, 0xfb, 0x69, 0xda, 0x92, 0x72, 0x8b,
  0x1a, 0x71, 0xde, 0x0a, 0x9e, 0x06, 0x0b, 0x29, 0x05, 0xd6, 0xa5, 0xb6,
  0x7e, 0xcd, 0x3b, 0x36, 0x92, 0xdd, 0xbd, 0x7f, 0x2d, 0x77, 0x8b, 0x8c,
  0x98, 0x03, 0xae, 0xe3, 0x28, 0x09, 0x1b, 0x58, 0xfa, 0xb3, 0x24, 0xe4,
  0xfa, 0xd6, 0x75, 0x94, 0x55, 0x85, 0x80, 0x8b, 0x48, 0x31, 0xd7, 0xbc,
  0x3f, 0xf4, 0xde, 0xf0, 0x8e, 0x4b, 0x7a, 0x9d, 0xe5, 0x76, 0xd2, 0x65,
  0x86, 0xce, 0xc6, 0x4b, 0x61, 0x16
>>

rfc_expected_tag = <<
  0x1a, 0xe1, 0x0b, 0x59, 0x4f, 0x09, 0xe2, 0x6a,
  0x7e, 0x90, 0x2e, 0xcb, 0xd0, 0x60, 0x06, 0x91
>>

case ChaCha20Poly1305Crypto.chacha20_poly1305_encrypt(rfc_key, rfc_nonce, rfc_plaintext, rfc_aad) do
  {:ok, ct, tag} ->
    if ct == rfc_expected_ct and tag == rfc_expected_tag do
      IO.puts("✓ RFC 8439 test vector passed!")
    else
      IO.puts("✗ RFC 8439 test vector failed!")
      IO.puts("  Expected CT: #{Base.encode16(rfc_expected_ct)}")
      IO.puts("  Got CT:      #{Base.encode16(ct)}")
      IO.puts("  Expected Tag: #{Base.encode16(rfc_expected_tag)}")
      IO.puts("  Got Tag:      #{Base.encode16(tag)}")
      System.halt(1)
    end

  {:error, reason} ->
    IO.puts("✗ RFC 8439 encryption failed: #{inspect(reason)}")
    System.halt(1)
end

IO.puts("\n=== All Tests Passed! ===\n")
