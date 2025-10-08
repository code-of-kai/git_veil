defmodule GitVeil.Workflows.EncryptedAddTest do
  use ExUnit.Case, async: true

  alias GitVeil.Workflows.EncryptedAdd
  alias GitVeil.Workflows.EncryptedAdd.Progress.Noop

  describe "add_files/2" do
    test "stages each file and reports processed counts" do
      parent = self()

      runner = fn chunk, _opts ->
        send(parent, {:chunk, chunk})
        {:ok, %{stdout: "", stderr: ""}}
      end

      assert {:ok, %{processed: 3, batches: 3, total: 3}} =
               EncryptedAdd.add_files(
                 ["file1", "file2", "file3"],
                 command_runner: runner,
                 progress_adapter: Noop,
                 max_concurrency: 1
               )

      assert_receive {:chunk, ["file1"]}
      assert_receive {:chunk, ["file2"]}
      assert_receive {:chunk, ["file3"]}
      refute_receive _
    end

    test "groups files into batches when batch_size is set" do
      parent = self()

      runner = fn chunk, _opts ->
        send(parent, {:chunk, chunk})
        {:ok, %{stdout: "", stderr: ""}}
      end

      assert {:ok, %{processed: 3, batches: 2, total: 3}} =
               EncryptedAdd.add_files(
                 ["alpha", "bravo", "charlie"],
                 command_runner: runner,
                 progress_adapter: Noop,
                 batch_size: 2,
                 max_concurrency: 1
               )

      assert_receive {:chunk, ["alpha", "bravo"]}
      assert_receive {:chunk, ["charlie"]}
      refute_receive _
    end

    test "returns detailed context when a batch fails" do
      runner = fn chunk, _opts ->
        case chunk do
          ["ok"] -> {:ok, %{stdout: "", stderr: ""}}
          ["fail"] -> {:error, %{reason: :non_zero_exit, stderr: "boom!"}}
        end
      end

      assert {:error, :non_zero_exit, context} =
               EncryptedAdd.add_files(
                 ["ok", "fail"],
                 command_runner: runner,
                 progress_adapter: Noop,
                 max_concurrency: 1
               )

      assert context.failed_paths == ["fail"]
      assert context.stderr == "boom!"
      assert context.processed == 1
      assert context.remaining == 1
      assert context.total == 2
    end

    test "captures exceptions from the command runner" do
      runner = fn _chunk, _opts ->
        raise "unexpected crash"
      end

      assert {:error, :exception, context} =
               EncryptedAdd.add_files(
                 ["oops"],
                 command_runner: runner,
                 progress_adapter: Noop,
                 max_concurrency: 1
               )

      assert context.failed_paths == ["oops"]
      assert context.processed == 0
      assert context.reason == :exception
    end

    test "deduplicates repeated file paths" do
      parent = self()

      runner = fn chunk, _opts ->
        send(parent, {:chunk, chunk})
        {:ok, %{stdout: "", stderr: ""}}
      end

      assert {:ok, %{processed: 1, batches: 1, total: 1}} =
               EncryptedAdd.add_files(
                 ["duplicate.txt", "duplicate.txt"],
                 command_runner: runner,
                 progress_adapter: Noop,
                 max_concurrency: 1
               )

      assert_receive {:chunk, ["duplicate.txt"]}
      refute_receive _
    end

    test "handles empty input gracefully" do
      assert {:ok, %{processed: 0, batches: 0, total: 0}} =
               EncryptedAdd.add_files([], progress_adapter: Noop)
    end
  end
end
