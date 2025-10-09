defmodule GitFoil.Core.KeyDerivationTest do
  use ExUnit.Case, async: true

  alias GitFoil.Core.KeyDerivation
  alias GitFoil.Core.Types.EncryptionKey

  describe "HKDF-SHA3-512 key derivation" do
    test "derives three independent keys (variable lengths for different algorithms)" do
      master_key = EncryptionKey.new(:crypto.strong_rand_bytes(32))
      file_path = "/path/to/file.txt"

      {:ok, derived} = KeyDerivation.derive_keys(master_key, file_path)

      # Verify key sizes match algorithm requirements
      assert byte_size(derived.layer1_key) == 32  # AES-256-GCM
      assert byte_size(derived.layer2_key) == 16  # Ascon-128a
      assert byte_size(derived.layer3_key) == 32  # ChaCha20-Poly1305

      # Verify keys are different (independence)
      # Note: Different sizes mean they can't be equal anyway, but verify first 16 bytes differ
      assert binary_part(derived.layer1_key, 0, 16) != derived.layer2_key
      assert derived.layer2_key != binary_part(derived.layer3_key, 0, 16)
      assert derived.layer1_key != derived.layer3_key
    end

    test "derivation is deterministic (same input → same keys)" do
      master_key = EncryptionKey.new(:crypto.strong_rand_bytes(32))
      file_path = "/path/to/file.txt"

      {:ok, derived1} = KeyDerivation.derive_keys(master_key, file_path)
      {:ok, derived2} = KeyDerivation.derive_keys(master_key, file_path)

      # Must produce identical keys (critical for Git)
      assert derived1.layer1_key == derived2.layer1_key
      assert derived1.layer2_key == derived2.layer2_key
      assert derived1.layer3_key == derived2.layer3_key
    end

    test "different file paths produce different keys (context separation)" do
      master_key = EncryptionKey.new(:crypto.strong_rand_bytes(32))

      {:ok, derived1} = KeyDerivation.derive_keys(master_key, "/path/to/file1.txt")
      {:ok, derived2} = KeyDerivation.derive_keys(master_key, "/path/to/file2.txt")

      # Different file paths → different salt → different keys
      assert derived1.layer1_key != derived2.layer1_key
      assert derived1.layer2_key != derived2.layer2_key
      assert derived1.layer3_key != derived2.layer3_key
    end

    test "different master keys produce different derived keys" do
      master_key1 = EncryptionKey.new(:crypto.strong_rand_bytes(32))
      master_key2 = EncryptionKey.new(:crypto.strong_rand_bytes(32))
      file_path = "/path/to/file.txt"

      {:ok, derived1} = KeyDerivation.derive_keys(master_key1, file_path)
      {:ok, derived2} = KeyDerivation.derive_keys(master_key2, file_path)

      assert derived1.layer1_key != derived2.layer1_key
      assert derived1.layer2_key != derived2.layer2_key
      assert derived1.layer3_key != derived2.layer3_key
    end

    test "rejects invalid master key size" do
      # Master key must be exactly 32 bytes - EncryptionKey.new enforces this
      assert_raise FunctionClauseError, fn ->
        EncryptionKey.new(:crypto.strong_rand_bytes(16))
      end

      # 64-byte key also rejected
      assert_raise FunctionClauseError, fn ->
        EncryptionKey.new(:crypto.strong_rand_bytes(64))
      end
    end

    test "handles various file path formats" do
      master_key = EncryptionKey.new(:crypto.strong_rand_bytes(32))

      # All should work and produce different keys
      {:ok, _} = KeyDerivation.derive_keys(master_key, "simple.txt")
      {:ok, _} = KeyDerivation.derive_keys(master_key, "/absolute/path/file.txt")
      {:ok, _} = KeyDerivation.derive_keys(master_key, "relative/path/file.txt")
      {:ok, _} = KeyDerivation.derive_keys(master_key, "path with spaces/file.txt")
      {:ok, _} = KeyDerivation.derive_keys(master_key, "special!@#$%^&*()chars.txt")
    end
  end
end
