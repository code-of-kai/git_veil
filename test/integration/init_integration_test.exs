defmodule Integration.InitTest do
  use ExUnit.Case, async: false

  alias GitVeil.Test.GitTestHelper

  @moduledoc """
  Real integration tests for git-veil init.

  These tests use actual git repositories and git-veil commands to catch
  real bugs that mocks would hide (like the git add filter bug).
  """

  describe "git-veil init with fresh repository" do
    test "initializes encryption on empty repo" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Run init
        {output, 0} = GitTestHelper.run_init(repo_path)

        # Verify setup
        assert GitTestHelper.gitveil_initialized?(repo_path)
        assert GitTestHelper.filters_configured?(repo_path)
        assert output =~ "setup complete"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "encrypts files with 6-layer encryption (03 byte)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create test file
        GitTestHelper.create_file(repo_path, "secret.txt", "API_KEY=secret123")

        # Run init
        {_output, 0} = GitTestHelper.run_init(repo_path)

        # Commit the file
        {_output, 0} = GitTestHelper.commit_files(repo_path)

        # Verify file is encrypted with 6-layer format (first byte is 0x03)
        first_byte = GitTestHelper.get_encrypted_first_byte(repo_path, "secret.txt")
        assert first_byte == 0x03, "Expected 6-layer encryption (0x03), got: #{inspect(first_byte)}"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "encrypts existing files when user confirms" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create and commit files BEFORE init
        GitTestHelper.create_file(repo_path, "file1.txt", "content1")
        GitTestHelper.create_file(repo_path, "file2.txt", "content2")
        {_output, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_output, 0} = System.cmd("git", ["commit", "-m", "Initial commit"], cd: repo_path)

        # Now run init (should encrypt existing files)
        {output, 0} = GitTestHelper.run_init(repo_path)

        # Verify encryption happened
        assert output =~ "Encrypting"
        assert output =~ "files"

        # Verify both files are encrypted with 6-layer format
        first_byte_1 = GitTestHelper.get_encrypted_first_byte(repo_path, "file1.txt")
        first_byte_2 = GitTestHelper.get_encrypted_first_byte(repo_path, "file2.txt")

        assert first_byte_1 == 0x03, "file1.txt should be encrypted with 0x03"
        assert first_byte_2 == 0x03, "file2.txt should be encrypted with 0x03"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  describe "git-veil init after unencrypt (regression test for bug)" do
    test "re-encrypts files after unencrypt" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create test file
        GitTestHelper.create_file(repo_path, "test.txt", "secret data")

        # Initialize and commit
        {_output, 0} = GitTestHelper.run_init(repo_path)
        {_output, 0} = GitTestHelper.commit_files(repo_path)

        # Verify encrypted
        first_byte = GitTestHelper.get_encrypted_first_byte(repo_path, "test.txt")
        assert first_byte == 0x03, "Should be encrypted initially"

        # Unencrypt
        {_output, 0} = GitTestHelper.run_unencrypt(repo_path)

        # Verify decrypted (plaintext in git)
        is_plaintext = GitTestHelper.is_plaintext_in_git?(repo_path, "test.txt")
        assert is_plaintext, "Should be plaintext after unencrypt"

        # Re-initialize
        {_output, 0} = GitTestHelper.run_init(repo_path)

        # THIS IS THE BUG TEST: Files should be re-encrypted
        # The bug was: files stayed plaintext because git add on already-staged files
        # didn't re-run the clean filter
        first_byte_after_reinit = GitTestHelper.get_encrypted_first_byte(repo_path, "test.txt")
        assert first_byte_after_reinit == 0x03,
          "BUG: Files should be re-encrypted with 0x03 after init, got: #{inspect(first_byte_after_reinit)}"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  describe "git-veil init with already staged files" do
    test "re-encrypts files that are already staged" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create file and add to git (but not encrypted)
        GitTestHelper.create_file(repo_path, "test.txt", "data")
        {_output, 0} = System.cmd("git", ["add", "test.txt"], cd: repo_path)
        {_output, 0} = System.cmd("git", ["commit", "-m", "Add plaintext"], cd: repo_path)

        # File is plaintext in git
        is_plaintext_before = GitTestHelper.is_plaintext_in_git?(repo_path, "test.txt")
        assert is_plaintext_before, "Should be plaintext before init"

        # Now init git-veil
        {_output, 0} = GitTestHelper.run_init(repo_path)

        # The staged file should now be encrypted
        first_byte = GitTestHelper.get_encrypted_first_byte(repo_path, "test.txt")
        assert first_byte == 0x03,
          "Previously plaintext file should be encrypted after init, got: #{inspect(first_byte)}"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  describe "git-veil init with multiple files of different sizes" do
    test "encrypts small, medium, and large files correctly" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create files of different sizes
        GitTestHelper.create_file(repo_path, "small.txt", "tiny")
        GitTestHelper.create_file(repo_path, "medium.txt", String.duplicate("data", 100))
        GitTestHelper.create_file(repo_path, "large.txt", String.duplicate("X", 10000))

        # Initialize and commit
        {_output, 0} = GitTestHelper.run_init(repo_path)
        {_output, 0} = GitTestHelper.commit_files(repo_path)

        # All should be encrypted with 6-layer format
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "small.txt") == 0x03
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "medium.txt") == 0x03
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "large.txt") == 0x03
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end
end
