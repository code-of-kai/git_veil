defmodule Integration.UnencryptTest do
  use ExUnit.Case, async: false

  alias GitFoil.Test.GitTestHelper

  @moduledoc """
  Real integration tests for git-foil unencrypt.

  Tests that unencrypt actually converts encrypted files to plaintext in git storage.
  """

  describe "git-foil unencrypt" do
    test "converts encrypted files to plaintext in git storage" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create and encrypt a file
        GitTestHelper.create_file(repo_path, "secret.txt", "API_KEY=secret123")
        {_output, 0} = GitTestHelper.run_init(repo_path)
        {_output, 0} = GitTestHelper.commit_files(repo_path)

        # Verify encrypted
        first_byte_before = GitTestHelper.get_encrypted_first_byte(repo_path, "secret.txt")
        assert first_byte_before == 0x03, "Should be encrypted initially"

        # Unencrypt
        {output, 0} = GitTestHelper.run_unencrypt(repo_path)
        assert output =~ "GitFoil encryption removed"

        # THIS IS THE BUG TEST: Files in git should now be plaintext
        # The bug was: files stayed encrypted in git storage even after unencrypt
        is_plaintext = GitTestHelper.is_plaintext_in_git?(repo_path, "secret.txt")
        assert is_plaintext,
          "BUG: Files should be plaintext in git storage after unencrypt, but they're still encrypted"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "removes git filters" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Initialize encryption
        {_output, 0} = GitTestHelper.run_init(repo_path)
        assert GitTestHelper.filters_configured?(repo_path), "Filters should be configured"

        # Unencrypt
        {_output, 0} = GitTestHelper.run_unencrypt(repo_path)

        # Filters should be removed
        refute GitTestHelper.filters_configured?(repo_path), "Filters should be removed"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "deletes master encryption key" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Initialize encryption
        {_output, 0} = GitTestHelper.run_init(repo_path)
        assert GitTestHelper.gitfoil_initialized?(repo_path), "Key should exist"

        # Unencrypt
        {_output, 0} = GitTestHelper.run_unencrypt(repo_path)

        # Key should be deleted
        refute GitTestHelper.gitfoil_initialized?(repo_path), "Key should be deleted"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "removes .gitattributes patterns" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Initialize (creates .gitattributes)
        {_output, 0} = GitTestHelper.run_init(repo_path)

        gitattributes_path = Path.join(repo_path, ".gitattributes")
        assert File.exists?(gitattributes_path), ".gitattributes should exist"

        # Unencrypt
        {_output, 0} = GitTestHelper.run_unencrypt(repo_path)

        # .gitattributes should be removed or have no gitfoil patterns
        if File.exists?(gitattributes_path) do
          content = File.read!(gitattributes_path)
          refute content =~ "filter=gitfoil", ".gitattributes should not contain gitfoil patterns"
        end
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles multiple files correctly" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create multiple files
        GitTestHelper.create_file(repo_path, "file1.txt", "content1")
        GitTestHelper.create_file(repo_path, "file2.txt", "content2")
        GitTestHelper.create_file(repo_path, "file3.txt", "content3")

        # Encrypt and commit
        {_output, 0} = GitTestHelper.run_init(repo_path)
        {_output, 0} = GitTestHelper.commit_files(repo_path)

        # All should be encrypted
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "file1.txt") == 0x03
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "file2.txt") == 0x03
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "file3.txt") == 0x03

        # Unencrypt
        {_output, 0} = GitTestHelper.run_unencrypt(repo_path)

        # All should be plaintext
        assert GitTestHelper.is_plaintext_in_git?(repo_path, "file1.txt")
        assert GitTestHelper.is_plaintext_in_git?(repo_path, "file2.txt")
        assert GitTestHelper.is_plaintext_in_git?(repo_path, "file3.txt")
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "working directory files remain unchanged" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create file with known content
        content = "This is secret data"
        GitTestHelper.create_file(repo_path, "data.txt", content)

        # Encrypt and commit
        {_output, 0} = GitTestHelper.run_init(repo_path)
        {_output, 0} = GitTestHelper.commit_files(repo_path)

        # Unencrypt
        {_output, 0} = GitTestHelper.run_unencrypt(repo_path)

        # Working directory file should still be plaintext and unchanged
        file_path = Path.join(repo_path, "data.txt")
        actual_content = File.read!(file_path)
        assert actual_content == content, "Working directory file should be unchanged"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end
end
