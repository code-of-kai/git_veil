defmodule GitFoil.Adapters.GitFilterTest do
  use ExUnit.Case, async: false

  alias GitFoil.Adapters.{GitFilter, FileKeyStorage}

  @test_key_dir ".git/git_foil"

  setup do
    # Clean up and generate test keypair
    File.rm_rf!(@test_key_dir)

    # Generate and save keypair
    {:ok, keypair} = FileKeyStorage.generate_keypair()
    :ok = FileKeyStorage.store_keypair(keypair)

    on_exit(fn -> File.rm_rf!(@test_key_dir) end)

    :ok
  end

  describe "clean (encryption)" do
    test "encrypts plaintext successfully" do
      plaintext = "This is secret content that will be encrypted"
      file_path = "secrets/credentials.txt"

      {:ok, encrypted} = GitFilter.clean(plaintext, file_path)

      assert is_binary(encrypted)
      assert byte_size(encrypted) > byte_size(plaintext)
      # Should not contain plaintext
      refute String.contains?(encrypted, plaintext)
    end

    test "produces deterministic output (same input → same output)" do
      plaintext = "Deterministic encryption test"
      file_path = "test/file.txt"

      {:ok, encrypted1} = GitFilter.clean(plaintext, file_path)
      {:ok, encrypted2} = GitFilter.clean(plaintext, file_path)

      # Critical for Git: same input must produce identical output
      assert encrypted1 == encrypted2
    end

    test "different file paths produce different ciphertexts" do
      plaintext = "Same content, different files"

      {:ok, encrypted1} = GitFilter.clean(plaintext, "file1.txt")
      {:ok, encrypted2} = GitFilter.clean(plaintext, "file2.txt")

      # Context separation via HKDF
      assert encrypted1 != encrypted2
    end

    test "handles empty plaintext" do
      {:ok, encrypted} = GitFilter.clean("", "empty.txt")

      assert is_binary(encrypted)
      assert byte_size(encrypted) > 0  # Has version + tags
    end

    test "handles large files (1MB)" do
      # 1MB of random data
      plaintext = :crypto.strong_rand_bytes(1_024 * 1_024)

      {:ok, encrypted} = GitFilter.clean(plaintext, "large.bin")

      assert is_binary(encrypted)
      assert byte_size(encrypted) > byte_size(plaintext)
    end

    test "returns error when not initialized" do
      # Remove keypair to simulate uninitialized state
      File.rm_rf!(@test_key_dir)

      result = GitFilter.clean("data", "file.txt")

      assert {:error, message} = result
      assert message =~ "not initialized"
    end
  end

  describe "smudge (decryption)" do
    test "decrypts encrypted content successfully" do
      plaintext = "Original secret content"
      file_path = "secrets/api_key.txt"

      # Encrypt first
      {:ok, encrypted} = GitFilter.clean(plaintext, file_path)

      # Then decrypt
      {:ok, decrypted} = GitFilter.smudge(encrypted, file_path)

      assert decrypted == plaintext
    end

    test "round-trip encryption/decryption preserves data" do
      plaintext = "Round-trip test with special chars: 日本語 émojis 🔐"
      file_path = "test/unicode.txt"

      {:ok, encrypted} = GitFilter.clean(plaintext, file_path)
      {:ok, decrypted} = GitFilter.smudge(encrypted, file_path)

      assert decrypted == plaintext
    end

    test "handles binary files" do
      # Simulate a binary file (PNG header)
      binary_data = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13>>
      file_path = "image.png"

      {:ok, encrypted} = GitFilter.clean(binary_data, file_path)
      {:ok, decrypted} = GitFilter.smudge(encrypted, file_path)

      assert decrypted == binary_data
    end

    test "returns original data for non-encrypted files (invalid blob format)" do
      # Simulate a file that was never encrypted
      plaintext = "This is not an encrypted file"
      file_path = "plain.txt"

      # Try to decrypt non-encrypted data
      {:ok, result} = GitFilter.smudge(plaintext, file_path)

      # Should return original data unchanged
      assert result == plaintext
    end

    test "returns error when not initialized" do
      # Remove keypair to simulate uninitialized state
      File.rm_rf!(@test_key_dir)

      result = GitFilter.smudge("data", "file.txt")

      assert {:error, message} = result
      assert message =~ "not initialized"
    end

    test "returns error for corrupted encrypted data" do
      plaintext = "Original content"
      file_path = "test.txt"

      # Encrypt
      {:ok, encrypted} = GitFilter.clean(plaintext, file_path)

      # Corrupt the encrypted data
      <<first::binary-10, _::binary-5, rest::binary>> = encrypted
      corrupted = first <> <<255, 255, 255, 255, 255>> <> rest

      # Try to decrypt corrupted data
      result = GitFilter.smudge(corrupted, file_path)

      assert {:error, message} = result
      assert message =~ "Decryption failed"
    end
  end

  describe "process/3 (I/O integration)" do
    test "clean operation processes stdin to stdout" do
      plaintext = "Test content for clean filter"
      file_path = "test.txt"

      # Create StringIO devices for testing
      input = StringIO.open(plaintext)
      output = StringIO.open("")

      {:ok, input_device} = input
      {:ok, output_device} = output

      # Process clean operation
      {:ok, 0} = GitFilter.process(:clean, file_path, input: input_device, output: output_device)

      # Read the output
      {_input_state, encrypted} = StringIO.contents(output_device)
      StringIO.close(input_device)
      StringIO.close(output_device)

      assert is_binary(encrypted)
      assert byte_size(encrypted) > 0
    end

    test "smudge operation processes stdin to stdout" do
      plaintext = "Test content for smudge filter"
      file_path = "test.txt"

      # First encrypt
      {:ok, encrypted} = GitFilter.clean(plaintext, file_path)

      # Create StringIO for encrypted input
      input = StringIO.open(encrypted)
      output = StringIO.open("")

      {:ok, input_device} = input
      {:ok, output_device} = output

      # Process smudge operation
      {:ok, 0} = GitFilter.process(:smudge, file_path, input: input_device, output: output_device)

      # Read the output
      {_input_state, decrypted} = StringIO.contents(output_device)
      StringIO.close(input_device)
      StringIO.close(output_device)

      assert decrypted == plaintext
    end

    test "returns error exit code on failure" do
      # Remove keypair to force error
      File.rm_rf!(@test_key_dir)

      input = StringIO.open("data")
      output = StringIO.open("")
      {:ok, input_device} = input
      {:ok, output_device} = output

      {:error, 1} = GitFilter.process(:clean, "test.txt", input: input_device, output: output_device)

      StringIO.close(input_device)
      StringIO.close(output_device)
    end
  end

  describe "Git integration compatibility" do
    test "encrypted output is stable across process restarts" do
      plaintext = "Git requires stability"
      file_path = "stable.txt"

      # Encrypt with first "process"
      {:ok, encrypted1} = GitFilter.clean(plaintext, file_path)

      # Simulate process restart - FileKeyStorage persists the key to disk
      # so it survives across "process restarts" (simulated here by just
      # encrypting again, but the key is loaded from disk each time)
      {:ok, encrypted2} = GitFilter.clean(plaintext, file_path)

      # With same key persisted to disk, should produce identical output
      # This is critical for Git - deterministic encryption
      assert encrypted1 == encrypted2
    end

    test "handles files with no extension" do
      plaintext = "File with no extension"

      {:ok, encrypted} = GitFilter.clean(plaintext, "README")
      {:ok, decrypted} = GitFilter.smudge(encrypted, "README")

      assert decrypted == plaintext
    end

    test "handles deeply nested file paths" do
      plaintext = "Deeply nested file"
      file_path = "path/to/very/deeply/nested/directory/file.txt"

      {:ok, encrypted} = GitFilter.clean(plaintext, file_path)
      {:ok, decrypted} = GitFilter.smudge(encrypted, file_path)

      assert decrypted == plaintext
    end

    test "handles file paths with spaces and special characters" do
      plaintext = "Special path file"
      file_path = "my documents/file (copy).txt"

      {:ok, encrypted} = GitFilter.clean(plaintext, file_path)
      {:ok, decrypted} = GitFilter.smudge(encrypted, file_path)

      assert decrypted == plaintext
    end
  end

  describe "performance" do
    test "encrypts/decrypts 100KB files quickly" do
      plaintext = :crypto.strong_rand_bytes(100 * 1024)
      file_path = "medium.bin"

      {encrypt_time, {:ok, encrypted}} =
        :timer.tc(fn -> GitFilter.clean(plaintext, file_path) end)

      {decrypt_time, {:ok, decrypted}} =
        :timer.tc(fn -> GitFilter.smudge(encrypted, file_path) end)

      assert decrypted == plaintext

      # Should complete in reasonable time (< 100ms for 100KB)
      assert encrypt_time < 100_000, "Encryption took #{encrypt_time}µs (> 100ms)"
      assert decrypt_time < 100_000, "Decryption took #{decrypt_time}µs (> 100ms)"
    end
  end
end
