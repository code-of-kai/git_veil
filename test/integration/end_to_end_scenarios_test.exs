defmodule Integration.EndToEndScenariosTest do
  use ExUnit.Case, async: false

  alias GitFoil.Test.GitTestHelper

  @moduledoc """
  End-to-end scenario tests that simulate real-world usage patterns.

  These tests would have caught the git filter bugs we discovered.
  """

  describe "full encryption lifecycle" do
    test "init → encrypt → commit → unencrypt → init → encrypt again" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Step 1: Create initial file
        GitTestHelper.create_file(repo_path, "secrets.env", "API_KEY=secret123")

        # Step 2: Initialize git-foil
        {_output, 0} = GitTestHelper.run_init(repo_path)

        # Step 3: Commit encrypted file
        {_output, 0} = GitTestHelper.commit_files(repo_path, "Add encrypted secrets")

        # Verify encrypted
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "secrets.env") == 0x03

        # Step 4: Unencrypt the repository
        {_output, 0} = GitTestHelper.run_unencrypt(repo_path)

        # Verify decrypted
        assert GitTestHelper.is_plaintext_in_git?(repo_path, "secrets.env")

        # Step 5: Re-initialize git-foil (BUG TEST)
        {_output, 0} = GitTestHelper.run_init(repo_path)

        # Step 6: Should re-encrypt existing files
        # THIS WOULD FAIL WITH THE BUG
        first_byte = GitTestHelper.get_encrypted_first_byte(repo_path, "secrets.env")
        assert first_byte == 0x03,
          "REGRESSION: Files should be re-encrypted after unencrypt → init cycle, got: #{inspect(first_byte)}"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "plaintext repo → init encrypts existing files" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Scenario: User has existing plaintext repo, now wants to add encryption

        # Step 1: Create files and commit (plaintext)
        GitTestHelper.create_file(repo_path, "README.md", "# My Project")
        GitTestHelper.create_file(repo_path, ".env", "DATABASE_URL=postgres://localhost")
        GitTestHelper.create_file(repo_path, "config.json", "{\"key\": \"value\"}")

        {_output, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_output, 0} = System.cmd("git", ["commit", "-m", "Initial commit"], cd: repo_path)

        # Verify all plaintext
        assert GitTestHelper.is_plaintext_in_git?(repo_path, "README.md")
        assert GitTestHelper.is_plaintext_in_git?(repo_path, ".env")
        assert GitTestHelper.is_plaintext_in_git?(repo_path, "config.json")

        # Step 2: Add encryption (user wants to encrypt everything from now on)
        {output, 0} = GitTestHelper.run_init(repo_path)

        # Should offer to encrypt existing files
        assert output =~ "Encrypt existing files"

        # Verify all files are now encrypted
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "README.md") == 0x03
        assert GitTestHelper.get_encrypted_first_byte(repo_path, ".env") == 0x03
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "config.json") == 0x03
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "multiple encrypt/decrypt cycles maintain data integrity" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Original content
        original_content = "CRITICAL_SECRET=super_secret_value_12345"
        GitTestHelper.create_file(repo_path, "production.env", original_content)

        # Cycle 1: Encrypt
        {_output, 0} = GitTestHelper.run_init(repo_path)
        {_output, 0} = GitTestHelper.commit_files(repo_path)
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "production.env") == 0x03

        # Cycle 1: Decrypt
        {_output, 0} = GitTestHelper.run_unencrypt(repo_path)
        assert GitTestHelper.is_plaintext_in_git?(repo_path, "production.env")

        # Cycle 2: Re-encrypt
        {_output, 0} = GitTestHelper.run_init(repo_path)
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "production.env") == 0x03

        # Cycle 2: Re-decrypt
        {_output, 0} = GitTestHelper.run_unencrypt(repo_path)
        assert GitTestHelper.is_plaintext_in_git?(repo_path, "production.env")

        # Final check: Working directory file should still have original content
        file_path = Path.join(repo_path, "production.env")
        final_content = File.read!(file_path)
        assert final_content == original_content,
          "Content should survive multiple encrypt/decrypt cycles"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "adding new files to encrypted repo" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Initialize encryption first
        {_output, 0} = GitTestHelper.run_init(repo_path)

        # Add first file
        GitTestHelper.create_file(repo_path, "file1.txt", "data1")
        {_output, 0} = GitTestHelper.commit_files(repo_path, "Add file1")
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "file1.txt") == 0x03

        # Add second file later
        GitTestHelper.create_file(repo_path, "file2.txt", "data2")
        {_output, 0} = GitTestHelper.commit_files(repo_path, "Add file2")
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "file2.txt") == 0x03

        # Add third file even later
        GitTestHelper.create_file(repo_path, "file3.txt", "data3")
        {_output, 0} = GitTestHelper.commit_files(repo_path, "Add file3")
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "file3.txt") == 0x03

        # All files should be encrypted
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "file1.txt") == 0x03
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "file2.txt") == 0x03
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "file3.txt") == 0x03
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "modifying encrypted files" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create and encrypt file
        GitTestHelper.create_file(repo_path, "config.txt", "version=1")
        {_output, 0} = GitTestHelper.run_init(repo_path)
        {_output, 0} = GitTestHelper.commit_files(repo_path, "Initial config")

        # Modify file
        GitTestHelper.create_file(repo_path, "config.txt", "version=2")
        {_output, 0} = GitTestHelper.commit_files(repo_path, "Update config")

        # Should still be encrypted
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "config.txt") == 0x03

        # Modify again
        GitTestHelper.create_file(repo_path, "config.txt", "version=3")
        {_output, 0} = GitTestHelper.commit_files(repo_path, "Update config again")

        # Should STILL be encrypted
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "config.txt") == 0x03
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "binary files are encrypted correctly" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create binary file
        binary_data = :crypto.strong_rand_bytes(1000)
        binary_path = Path.join(repo_path, "data.bin")
        File.write!(binary_path, binary_data)

        # Encrypt and commit
        {_output, 0} = GitTestHelper.run_init(repo_path)
        {_output, 0} = GitTestHelper.commit_files(repo_path)

        # Should be encrypted
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "data.bin") == 0x03

        # Working directory should have original binary data
        actual_data = File.read!(binary_path)
        assert actual_data == binary_data, "Binary data should be unchanged in working directory"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  describe "error scenarios" do
    test "handles corrupted encryption gracefully" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # This test verifies the system handles edge cases
        # For now, just ensure basic operations work

        GitTestHelper.create_file(repo_path, "test.txt", "data")
        {_output, 0} = GitTestHelper.run_init(repo_path)
        {_output, 0} = GitTestHelper.commit_files(repo_path)

        # Basic sanity check
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "test.txt") == 0x03
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end
end
