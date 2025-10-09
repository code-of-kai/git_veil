defmodule GitFoil.Integration.EncryptedAddWorkflowTest do
  use ExUnit.Case, async: false

  alias GitFoil.Test.GitTestHelper
  alias GitFoil.Workflows.EncryptedAdd
  alias GitFoil.Workflows.EncryptedAdd.Progress.Noop

  @moduletag :integration

  setup do
    repo_path = GitTestHelper.create_test_repo()

    init_output =
      case GitTestHelper.run_init(repo_path) do
        {output, 0} -> output
        other -> flunk("git-foil init failed: #{inspect(other)}")
      end

    on_exit(fn -> GitTestHelper.cleanup_test_repo(repo_path) end)

    {:ok, repo_path: repo_path, init_output: init_output}
  end

  describe "EncryptedAdd.add_files/2 against a real repository" do
    test "stages files concurrently and they appear encrypted in the index", %{repo_path: repo_path} do
      files =
        for i <- 1..12 do
          relative = Path.join("secrets", "file#{i}.txt")
          absolute = Path.join(repo_path, relative)
          File.mkdir_p!(Path.dirname(absolute))
          File.write!(absolute, "secret #{i}")
          relative
        end

      {:ok, result} =
        File.cd!(repo_path, fn ->
          EncryptedAdd.add_files(files,
            max_concurrency: 4,
            batch_size: 3,
            progress_adapter: Noop
          )
        end)

      assert result.processed == 12
      assert result.total == 12
      assert result.batches >= 1

      {status_output, 0} = System.cmd("git", ["status", "--short"], cd: repo_path)

      Enum.each(files, fn file ->
        assert status_output =~ "A  #{file}"
        assert GitTestHelper.get_encrypted_first_byte(repo_path, file) == 0x03
      end)
    end

    test "returns structured error context when git add fails", %{repo_path: repo_path} do
      missing_files = ["does-not-exist.txt", "still-missing.txt"]

      {:error, :non_zero_exit, context} =
        File.cd!(repo_path, fn ->
          EncryptedAdd.add_files(missing_files,
            max_concurrency: 2,
            batch_size: 2,
            progress_adapter: Noop
          )
        end)

      assert context.exit_status != 0
      assert context.reason == :non_zero_exit
      assert Enum.sort(context.failed_paths) == Enum.sort(missing_files)
      assert String.contains?(context.stderr, "pathspec")
      assert context.processed == 0
    end
  end
end
