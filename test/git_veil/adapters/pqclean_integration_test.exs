defmodule GitVeil.Adapters.PQCleanIntegrationTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Integration test for REAL post-quantum cryptography using pqclean NIF.

  Verifies that Kyber1024 (ML-KEM-1024) keypair generation works correctly.
  """

  alias GitVeil.Adapters.InMemoryKeyStorage

  setup do
    {:ok, _} = start_supervised(InMemoryKeyStorage)
    :ok
  end

  describe "REAL Post-Quantum Cryptography with pqclean NIF" do
    test "generates REAL Kyber1024 keypairs" do
      {:ok, keypair} = InMemoryKeyStorage.generate_keypair()

      # Verify keypair structure
      assert is_binary(keypair.classical_public)
      assert is_binary(keypair.classical_secret)
      assert is_binary(keypair.pq_public)
      assert is_binary(keypair.pq_secret)

      # Verify classical key sizes (placeholder)
      assert byte_size(keypair.classical_public) == 32
      assert byte_size(keypair.classical_secret) == 32

      # Verify Kyber1024 key sizes (NIST Level 5)
      assert byte_size(keypair.pq_public) == 1_568, "Kyber1024 public key must be 1,568 bytes"
      assert byte_size(keypair.pq_secret) == 3_168, "Kyber1024 secret key must be 3,168 bytes"
    end

    test "generates different keypairs each time" do
      {:ok, keypair1} = InMemoryKeyStorage.generate_keypair()
      {:ok, keypair2} = InMemoryKeyStorage.generate_keypair()

      # Post-quantum keys should be different (randomized)
      assert keypair1.pq_public != keypair2.pq_public
      assert keypair1.pq_secret != keypair2.pq_secret

      # Classical keys should also be different
      assert keypair1.classical_public != keypair2.classical_public
      assert keypair1.classical_secret != keypair2.classical_secret
    end

    test "derives deterministic 32-byte master key from REAL PQ keypair" do
      {:ok, keypair} = InMemoryKeyStorage.generate_keypair()
      :ok = InMemoryKeyStorage.save_keypair(keypair)

      {:ok, master_key1} = InMemoryKeyStorage.derive_master_key()
      {:ok, master_key2} = InMemoryKeyStorage.derive_master_key()

      # Master key derivation must be deterministic
      assert master_key1 == master_key2
      assert %GitVeil.Core.Types.EncryptionKey{} = master_key1
      assert byte_size(master_key1.key) == 32
    end

    test "master key changes with different PQ keypairs" do
      # Generate first keypair
      {:ok, keypair1} = InMemoryKeyStorage.generate_keypair()
      :ok = InMemoryKeyStorage.save_keypair(keypair1)
      {:ok, master_key1} = InMemoryKeyStorage.derive_master_key()

      # Stop and restart storage
      stop_supervised(InMemoryKeyStorage)
      {:ok, _} = start_supervised(InMemoryKeyStorage)

      # Generate second keypair
      {:ok, keypair2} = InMemoryKeyStorage.generate_keypair()
      :ok = InMemoryKeyStorage.save_keypair(keypair2)
      {:ok, master_key2} = InMemoryKeyStorage.derive_master_key()

      # Master keys should be different (derived from different PQ keypairs)
      assert master_key1 != master_key2
    end

    test "master key includes post-quantum entropy" do
      {:ok, keypair} = InMemoryKeyStorage.generate_keypair()
      :ok = InMemoryKeyStorage.save_keypair(keypair)

      {:ok, master_key} = InMemoryKeyStorage.derive_master_key()

      # Master key is first 32 bytes of SHA-512(classical_secret || pq_secret)
      # Verify it's derived from both components
      expected_bytes = :crypto.hash(:sha512, keypair.classical_secret <> keypair.pq_secret)
                       |> binary_part(0, 32)

      assert master_key.key == expected_bytes
      assert byte_size(master_key.key) == 32
    end
  end

  describe "pqclean NIF availability" do
    test "pqclean_nif module is loaded" do
      # Verify the NIF is actually loaded
      assert Code.ensure_loaded?(:pqclean_nif)
    end

    test "can call Kyber1024 functions directly" do
      # Direct test of pqclean_nif functions
      {pk, sk} = :pqclean_nif.kyber1024_keypair()

      assert is_binary(pk)
      assert is_binary(sk)
      assert byte_size(pk) == 1_568
      assert byte_size(sk) == 3_168
    end

    test "Kyber1024 provides NIST Level 5 security" do
      # Kyber1024 parameters (from pqclean documentation):
      # - Public Key: 1,568 bytes
      # - Secret Key: 3,168 bytes
      # - Ciphertext: 1,568 bytes
      # - Shared Secret: 32 bytes
      # - NIST Security Level: 5 (highest)

      {pk, sk} = :pqclean_nif.kyber1024_keypair()

      # Encapsulate a shared secret
      {ciphertext, shared_secret} = :pqclean_nif.kyber1024_encapsulate(pk)

      assert byte_size(ciphertext) == 1_568, "Kyber1024 ciphertext must be 1,568 bytes"
      assert byte_size(shared_secret) == 32, "Kyber1024 shared secret must be 32 bytes"

      # Decapsulate to recover the same shared secret
      recovered_secret = :pqclean_nif.kyber1024_decapsulate(ciphertext, sk)

      assert recovered_secret == shared_secret, "Decapsulation must recover the same shared secret"
    end
  end
end
