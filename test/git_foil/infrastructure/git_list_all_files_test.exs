defmodule GitFoil.Infrastructure.GitListAllFilesTest do
  @moduledoc """
  Tests for the list_all_files() function that was added to fix the subdirectory bug.

  **Bug:** Commands only found tracked files, missing untracked files in subdirectories.
  **Fix:** Added list_all_files() that returns both tracked AND untracked files.
  """

  use ExUnit.Case, async: false

  alias GitFoil.Infrastructure.Git

  @moduletag :integration
  @moduletag timeout: 60_000

  setup do
    # Create a unique temporary directory for each test
    test_dir = "/tmp/gitfoil_list_test_#{:erlang.unique_integer([:positive])}"
    File.mkdir_p!(test_dir)

    # Change to test directory
    original_dir = File.cwd!()
    File.cd!(test_dir)

    # Initialize git
    System.cmd("git", ["init"])
    System.cmd("git", ["config", "user.email", "test@example.com"])
    System.cmd("git", ["config", "user.name", "Test User"])

    on_exit(fn ->
      File.cd!(original_dir)
      File.rm_rf!(test_dir)
    end)

    {:ok, test_dir: test_dir}
  end

  describe "list_all_files/0" do
    test "returns tracked files" do
      # Create and commit a file
      File.write!("tracked.txt", "content")
      System.cmd("git", ["add", "tracked.txt"])
      System.cmd("git", ["commit", "-m", "Add tracked file"])

      {:ok, files} = Git.list_all_files()

      assert "tracked.txt" in files
    end

    test "returns untracked files" do
      # Create untracked file
      File.write!("untracked.txt", "content")

      {:ok, files} = Git.list_all_files()

      assert "untracked.txt" in files
    end

    test "returns both tracked and untracked files" do
      # Create tracked file
      File.write!("tracked.txt", "tracked content")
      System.cmd("git", ["add", "tracked.txt"])
      System.cmd("git", ["commit", "-m", "Add tracked"])

      # Create untracked file
      File.write!("untracked.txt", "untracked content")

      {:ok, files} = Git.list_all_files()

      assert "tracked.txt" in files
      assert "untracked.txt" in files
      assert length(files) >= 2
    end

    test "finds files in subdirectories (tracked)" do
      # Create subdirectory with tracked file
      File.mkdir_p!("subdir1/subdir2")
      File.write!("subdir1/subdir2/file.txt", "content")
      System.cmd("git", ["add", "subdir1/subdir2/file.txt"])
      System.cmd("git", ["commit", "-m", "Add file in subdir"])

      {:ok, files} = Git.list_all_files()

      assert "subdir1/subdir2/file.txt" in files
    end

    test "finds files in subdirectories (untracked)" do
      # Create subdirectory with untracked files
      File.mkdir_p!("subdir1/subdir2/subdir3")
      File.write!("subdir1/file1.txt", "content 1")
      File.write!("subdir1/subdir2/file2.txt", "content 2")
      File.write!("subdir1/subdir2/subdir3/file3.txt", "content 3")

      {:ok, files} = Git.list_all_files()

      assert "subdir1/file1.txt" in files
      assert "subdir1/subdir2/file2.txt" in files
      assert "subdir1/subdir2/subdir3/file3.txt" in files
    end

    test "finds both tracked and untracked files in nested subdirectories" do
      # Create tracked file in subdirectory
      File.mkdir_p!("dir1/dir2")
      File.write!("dir1/dir2/tracked.txt", "tracked")
      System.cmd("git", ["add", "dir1/dir2/tracked.txt"])
      System.cmd("git", ["commit", "-m", "Add tracked in subdir"])

      # Create untracked file in same subdirectory
      File.write!("dir1/dir2/untracked.txt", "untracked")

      # Create untracked file in different subdirectory
      File.mkdir_p!("dir1/dir3")
      File.write!("dir1/dir3/another.txt", "another")

      {:ok, files} = Git.list_all_files()

      assert "dir1/dir2/tracked.txt" in files
      assert "dir1/dir2/untracked.txt" in files
      assert "dir1/dir3/another.txt" in files
      assert length(files) >= 3
    end

    test "excludes files in .gitignore" do
      # Create .gitignore
      File.write!(".gitignore", "ignored.txt\n*.log\n")
      System.cmd("git", ["add", ".gitignore"])
      System.cmd("git", ["commit", "-m", "Add gitignore"])

      # Create ignored files
      File.write!("ignored.txt", "should be ignored")
      File.write!("test.log", "log file")

      # Create non-ignored file
      File.write!("included.txt", "should be included")

      {:ok, files} = Git.list_all_files()

      refute "ignored.txt" in files
      refute "test.log" in files
      assert "included.txt" in files
      assert ".gitignore" in files
    end

    test "returns unique files (no duplicates)" do
      # This shouldn't happen, but let's verify
      # A file can't be both tracked and untracked, but the function should dedupe

      File.write!("file.txt", "content")
      System.cmd("git", ["add", "file.txt"])

      {:ok, files} = Git.list_all_files()

      # Count occurrences of file.txt
      count = Enum.count(files, &(&1 == "file.txt"))
      assert count == 1, "file.txt should appear exactly once, but appeared #{count} times"
    end

    test "handles empty repository" do
      # Empty repository - no files at all
      {:ok, files} = Git.list_all_files()

      assert files == []
    end

    test "handles repository with only tracked files (old behavior)" do
      # Simulates the scenario before the bug fix
      File.write!("file1.txt", "content1")
      File.write!("file2.txt", "content2")
      System.cmd("git", ["add", "."])
      System.cmd("git", ["commit", "-m", "Add files"])

      {:ok, files} = Git.list_all_files()

      assert "file1.txt" in files
      assert "file2.txt" in files
    end

    test "regression: new repository with files only in subdirectories" do
      # This is the exact bug scenario that was failing
      # New repo, files only in subdirs, nothing tracked yet

      File.mkdir_p!("src/controllers")
      File.write!("src/controllers/user.ex", "defmodule User do end")
      File.mkdir_p!("test/unit")
      File.write!("test/unit/user_test.ex", "defmodule UserTest do end")

      {:ok, files} = Git.list_all_files()

      # Bug: Would return [] because git ls-files returns nothing
      # Fixed: Returns untracked files including those in subdirs
      assert "src/controllers/user.ex" in files
      assert "test/unit/user_test.ex" in files
      assert length(files) == 2
    end
  end

  describe "list_files/0 (original function)" do
    test "returns only tracked files" do
      # Create tracked file
      File.write!("tracked.txt", "content")
      System.cmd("git", ["add", "tracked.txt"])
      System.cmd("git", ["commit", "-m", "Add tracked"])

      # Create untracked file
      File.write!("untracked.txt", "content")

      {:ok, files} = Git.list_files()

      assert "tracked.txt" in files
      refute "untracked.txt" in files
    end

    test "returns empty list in new repository" do
      # New repository with no commits
      {:ok, files} = Git.list_files()

      assert files == []
    end
  end
end
