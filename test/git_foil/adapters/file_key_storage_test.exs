defmodule GitFoil.Adapters.FileKeyStorageTest do
  use ExUnit.Case, async: false

  alias GitFoil.Adapters.FileKeyStorage
  alias GitFoil.Core.Types.{Keypair, EncryptionKey}

  @test_key_dir ".git/git_foil"
  @test_key_file ".git/git_foil/master.key"

  setup do
    # Clean up test key file before each test
    File.rm_rf!(@test_key_dir)
    on_exit(fn -> File.rm_rf!(@test_key_dir) end)
    :ok
  end

  describe "generate_keypair/0" do
    test "generates a valid Kyber1024 keypair" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()

      assert %Keypair{} = keypair
      assert byte_size(keypair.pq_public) > 0
      assert byte_size(keypair.pq_secret) > 0
      assert byte_size(keypair.classical_public) == 32
      assert byte_size(keypair.classical_secret) == 32
    end

    test "generates unique keypairs on each call" do
      {:ok, keypair1} = FileKeyStorage.generate_keypair()
      {:ok, keypair2} = FileKeyStorage.generate_keypair()

      # Different keypairs should have different secrets
      refute keypair1.pq_secret == keypair2.pq_secret
      refute keypair1.classical_secret == keypair2.classical_secret
    end
  end

  describe "store_keypair/1 and retrieve_keypair/0" do
    test "stores and retrieves keypair successfully" do
      {:ok, original_keypair} = FileKeyStorage.generate_keypair()

      # Store keypair
      assert :ok = FileKeyStorage.store_keypair(original_keypair)

      # Retrieve keypair
      assert {:ok, retrieved_keypair} = FileKeyStorage.retrieve_keypair()

      # Verify keypair matches
      assert retrieved_keypair.pq_public == original_keypair.pq_public
      assert retrieved_keypair.pq_secret == original_keypair.pq_secret
      assert retrieved_keypair.classical_public == original_keypair.classical_public
      assert retrieved_keypair.classical_secret == original_keypair.classical_secret
    end

    test "creates .git/git_foil directory if it doesn't exist" do
      refute File.exists?(@test_key_dir)

      {:ok, keypair} = FileKeyStorage.generate_keypair()
      :ok = FileKeyStorage.store_keypair(keypair)

      assert File.exists?(@test_key_dir)
      assert File.dir?(@test_key_dir)
    end

    test "overwrites existing keypair when storing new one" do
      {:ok, keypair1} = FileKeyStorage.generate_keypair()
      {:ok, keypair2} = FileKeyStorage.generate_keypair()

      :ok = FileKeyStorage.store_keypair(keypair1)
      :ok = FileKeyStorage.store_keypair(keypair2)

      {:ok, retrieved} = FileKeyStorage.retrieve_keypair()

      # Should retrieve the second keypair
      assert retrieved.pq_secret == keypair2.pq_secret
    end

    test "returns :not_found when keypair doesn't exist" do
      assert {:error, :not_found} = FileKeyStorage.retrieve_keypair()
    end

    test "sets secure file permissions (0600)" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      :ok = FileKeyStorage.store_keypair(keypair)

      # Check file permissions (owner read/write only)
      stat = File.stat!(@test_key_file)
      # On Unix systems, 0o100600 = regular file with 0600 permissions
      assert stat.mode == 0o100600
    end
  end

  describe "derive_master_key/0" do
    test "derives deterministic master key from keypair" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      :ok = FileKeyStorage.store_keypair(keypair)

      {:ok, master_key1} = FileKeyStorage.derive_master_key()
      {:ok, master_key2} = FileKeyStorage.derive_master_key()

      # Same keypair should produce same master key
      assert master_key1 == master_key2
      assert %EncryptionKey{} = master_key1
      assert byte_size(master_key1.key) == 32
    end

    test "different keypairs produce different master keys" do
      {:ok, keypair1} = FileKeyStorage.generate_keypair()
      :ok = FileKeyStorage.store_keypair(keypair1)
      {:ok, master_key1} = FileKeyStorage.derive_master_key()

      {:ok, keypair2} = FileKeyStorage.generate_keypair()
      :ok = FileKeyStorage.store_keypair(keypair2)
      {:ok, master_key2} = FileKeyStorage.derive_master_key()

      refute master_key1 == master_key2
    end

    test "returns :not_initialized when keypair doesn't exist" do
      assert {:error, :not_initialized} = FileKeyStorage.derive_master_key()
    end

    test "master key derivation matches expected SHA-512 truncation" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      :ok = FileKeyStorage.store_keypair(keypair)

      {:ok, master_key} = FileKeyStorage.derive_master_key()

      # Verify derivation: SHA-512(classical_secret || pq_secret)[0..31]
      combined = keypair.classical_secret <> keypair.pq_secret
      expected_key_bytes = :crypto.hash(:sha512, combined) |> binary_part(0, 32)

      assert master_key.key == expected_key_bytes
    end
  end

  describe "initialized?/0" do
    test "returns false when not initialized" do
      refute FileKeyStorage.initialized?()
    end

    test "returns true when keypair exists" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      :ok = FileKeyStorage.store_keypair(keypair)

      assert FileKeyStorage.initialized?()
    end

    test "returns false after keypair is deleted" do
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      :ok = FileKeyStorage.store_keypair(keypair)
      assert FileKeyStorage.initialized?()

      File.rm!(@test_key_file)
      refute FileKeyStorage.initialized?()
    end
  end

  describe "serialization" do
    test "serializes and deserializes keypair correctly" do
      {:ok, original} = FileKeyStorage.generate_keypair()
      :ok = FileKeyStorage.store_keypair(original)

      # Read raw file and verify it's binary format
      {:ok, file_content} = File.read(@test_key_file)
      assert is_binary(file_content)
      assert byte_size(file_content) > 100  # Should be substantial size

      # Verify deserialization produces correct keypair
      {:ok, retrieved} = FileKeyStorage.retrieve_keypair()
      assert retrieved == original
    end
  end

  describe "file-specific key operations (not implemented)" do
    test "store_file_key/2 returns :not_implemented" do
      dummy_key = EncryptionKey.new(:crypto.strong_rand_bytes(32))
      assert {:error, :not_implemented} = FileKeyStorage.store_file_key("test.txt", dummy_key)
    end

    test "retrieve_file_key/1 returns :not_found" do
      assert {:error, :not_found} = FileKeyStorage.retrieve_file_key("test.txt")
    end

    test "delete_file_key/1 returns :ok" do
      assert :ok = FileKeyStorage.delete_file_key("test.txt")
    end
  end

  describe "error handling" do
    test "handles corrupted key file gracefully" do
      # Write invalid binary to key file
      File.mkdir_p!(@test_key_dir)
      File.write!(@test_key_file, "not a valid erlang term")

      # Should handle deserialization error
      assert_raise ArgumentError, fn ->
        FileKeyStorage.retrieve_keypair()
      end
    end
  end
end
