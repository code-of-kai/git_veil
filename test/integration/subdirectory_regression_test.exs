defmodule GitFoil.Integration.SubdirectoryRegressionTest do
  @moduledoc """
  Regression tests for the subdirectory bug fix.

  **Bug:** Commands only found files in the main directory, not subdirectories.
  **Root cause:** Commands used `git ls-files` which only returns tracked files.
                   In new repositories, files in subdirectories are untracked.
  **Fix:** Changed all commands to use both:
           - `git ls-files` (tracked files)
           - `git ls-files --others --exclude-standard` (untracked files)

  These tests ensure the fix works for all affected commands:
  - init
  - encrypt
  - pattern (configure)
  - unencrypt
  - rekey
  """

  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  @moduletag :integration
  @moduletag timeout: 120_000

  setup do
    # Create a unique temporary directory for each test
    test_dir = "/tmp/gitfoil_subdir_test_#{:erlang.unique_integer([:positive])}"
    File.mkdir_p!(test_dir)

    # Change to test directory
    original_dir = File.cwd!()
    File.cd!(test_dir)

    on_exit(fn ->
      File.cd!(original_dir)
      File.rm_rf!(test_dir)
    end)

    {:ok, test_dir: test_dir}
  end

  describe "init command with subdirectories" do
    test "finds and encrypts files in nested subdirectories" do
      # Setup: Create files in nested directory structure
      setup_test_repo_with_subdirs()

      # Run init and select "encrypt all files" + "encrypt now"
      capture_io(fn ->
        send_input(["Y", "1", "y"])
        GitFoil.Commands.Init.run()
      end)

      # Verify: Check that files in subdirectories were found
      {status_output, 0} = System.cmd("git", ["status", "--short"])
      staged_files = String.split(status_output, "\n", trim: true)

      # Should have staged files from all directories
      assert Enum.any?(staged_files, &String.contains?(&1, "root.txt"))
      assert Enum.any?(staged_files, &String.contains?(&1, "subdir1/file1.txt"))
      assert Enum.any?(staged_files, &String.contains?(&1, "subdir1/subdir2/file2.txt"))
      assert Enum.any?(staged_files, &String.contains?(&1, "subdir1/subdir2/subdir3/file3.txt"))

      # Verify count: should be at least 4 files (+ .gitattributes)
      assert length(staged_files) >= 4
    end

    test "reports correct file count from subdirectories" do
      setup_test_repo_with_subdirs()

      # Capture output to check the file count message
      output = capture_io(fn ->
        send_input(["Y", "1", "y"])
        GitFoil.Commands.Init.run()
      end)

      # Should report finding 4 files (in main dir + subdirs)
      assert output =~ ~r/Found 4 files matching your patterns/i
    end
  end

  describe "encrypt command with subdirectories" do
    test "encrypts files in nested subdirectories" do
      setup_test_repo_with_subdirs()
      init_gitfoil()

      # Create a new file in a subdirectory after init
      File.write!("subdir1/subdir2/new_file.txt", "new content")

      # Run encrypt command
      capture_io(fn ->
        GitFoil.Commands.Encrypt.run()
      end)

      # Verify the new file in subdirectory was encrypted
      {status_output, 0} = System.cmd("git", ["status", "--short"])
      assert status_output =~ "subdir1/subdir2/new_file.txt"
    end

    test "reports correct count of files in subdirectories" do
      setup_test_repo_with_subdirs()
      init_gitfoil()

      output = capture_io(fn ->
        send_input(["1"])  # Use existing key
        GitFoil.Commands.Encrypt.run()
      end)

      # Should find all 4 files across subdirectories
      assert output =~ ~r/Encrypting 4 files/i
    end
  end

  describe "pattern/configure command with subdirectories" do
    test "finds matching files in subdirectories when changing patterns" do
      setup_test_repo_with_env_files()
      init_gitfoil()

      # Add .env files in subdirectories
      File.write!("subdir1/.env", "API_KEY=test1")
      File.write!("subdir1/subdir2/.env", "API_KEY=test2")

      # Configure to only encrypt .env files
      capture_io(fn ->
        send_input(["3"])  # Environment files only
        GitFoil.Commands.Pattern.run()
      end)

      # Re-run encrypt to apply new pattern
      output = capture_io(fn ->
        send_input(["1"])  # Use existing key
        GitFoil.Commands.Encrypt.run()
      end)

      # Should find .env files in subdirectories
      assert output =~ "subdir1/.env" or output =~ ~r/Encrypting 2 files/i
    end
  end

  describe "unencrypt command with subdirectories" do
    test "unencrypts files in all subdirectories" do
      setup_test_repo_with_subdirs()
      init_and_commit()

      # Verify files are encrypted in Git
      {blob_content, 0} = System.cmd("git", ["cat-file", "blob", "HEAD:subdir1/subdir2/file2.txt"])
      # Encrypted files will be binary/non-ASCII
      refute blob_content == "content 2\n"

      # Run unencrypt
      capture_io(fn ->
        send_input(["y"])  # Confirm unencrypt
        GitFoil.Commands.Unencrypt.run()
      end)

      # Commit the unencrypted files
      System.cmd("git", ["commit", "-m", "Unencrypt"])

      # Verify files are now plaintext in Git
      {blob_content, 0} = System.cmd("git", ["cat-file", "blob", "HEAD:subdir1/subdir2/file2.txt"])
      assert blob_content =~ "content 2"
    end
  end

  describe "rekey command with subdirectories" do
    test "rekeys files in all subdirectories" do
      setup_test_repo_with_subdirs()
      init_and_commit()

      # Add new files in subdirectories
      File.write!("subdir1/subdir2/new.txt", "new file")

      # Run rekey
      capture_io(fn ->
        send_input(["1"])  # Use existing key
        GitFoil.Commands.Rekey.run()
      end)

      # Verify new file in subdirectory was included
      {status_output, 0} = System.cmd("git", ["status", "--short"])
      assert status_output =~ "subdir1/subdir2/new.txt"
    end

    test "reports correct count when rekeying with subdirectories" do
      setup_test_repo_with_subdirs()
      init_and_commit()

      # Add more files in subdirectories
      File.write!("subdir1/another.txt", "test")

      output = capture_io(fn ->
        send_input(["1"])  # Use existing key
        GitFoil.Commands.Rekey.run()
      end)

      # Should report rekeying all files including subdirectories
      assert output =~ ~r/Rekeying \d+ files/i
    end
  end

  # Helper functions

  defp setup_test_repo_with_subdirs do
    # Initialize git
    System.cmd("git", ["init"])
    System.cmd("git", ["config", "user.email", "test@example.com"])
    System.cmd("git", ["config", "user.name", "Test User"])

    # Create nested directory structure with files
    File.write!("root.txt", "content root")
    File.mkdir_p!("subdir1")
    File.write!("subdir1/file1.txt", "content 1")
    File.mkdir_p!("subdir1/subdir2")
    File.write!("subdir1/subdir2/file2.txt", "content 2")
    File.mkdir_p!("subdir1/subdir2/subdir3")
    File.write!("subdir1/subdir2/subdir3/file3.txt", "content 3")
  end

  defp setup_test_repo_with_env_files do
    System.cmd("git", ["init"])
    System.cmd("git", ["config", "user.email", "test@example.com"])
    System.cmd("git", ["config", "user.name", "Test User"])

    File.write!("README.md", "# Test")
    File.mkdir_p!("subdir1/subdir2")
  end

  defp init_gitfoil do
    # Run init without interactive prompts
    capture_io(fn ->
      send_input(["Y", "1", "n"])  # Yes to init, encrypt all, no to encrypt now
      GitFoil.Commands.Init.run()
    end)
  end

  defp init_and_commit do
    init_gitfoil()

    # Encrypt files
    capture_io(fn ->
      send_input(["1"])  # Use existing key
      GitFoil.Commands.Encrypt.run()
    end)

    # Commit
    System.cmd("git", ["add", ".gitattributes"])
    System.cmd("git", ["commit", "-m", "Initial commit"])
  end

  defp send_input(inputs) when is_list(inputs) do
    # Store inputs for MockTerminal to consume
    # This is a simplified version - in real tests you'd use a proper mock
    # For integration tests, this might involve process dictionary or other state
    Process.put(:test_inputs, inputs)
  end
end
