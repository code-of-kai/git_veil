defmodule GitFoil.Workflows.EncryptedAddPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GitFoil.Workflows.EncryptedAdd
  alias GitFoil.Workflows.EncryptedAdd.Progress.Noop

  property "processes each unique path exactly once regardless of duplicates" do
    check all raw_files <-
                list_of(
                  string(:alphanumeric, min_length: 1),
                  min_length: 1,
                  max_length: 20
                ),
              batch_size <- integer(1..5),
              max_concurrency <- integer(1..4) do
      files =
        raw_files
        |> Enum.map(&String.downcase/1)
        |> Enum.map(&("file_" <> &1))

      unique_files = files |> Enum.uniq()
      unique_count = length(unique_files)

      {:ok, tracker} = Agent.start_link(fn -> %{} end)

      runner = fn chunk, _opts ->
        Agent.update(tracker, fn counts ->
          Enum.reduce(chunk, counts, fn file, acc ->
            Map.update(acc, file, 1, &(&1 + 1))
          end)
        end)

        {:ok, %{stdout: "", stderr: ""}}
      end

      opts = [
        command_runner: runner,
        progress_adapter: Noop,
        batch_size: batch_size,
        max_concurrency: max_concurrency
      ]

      assert {:ok, %{processed: ^unique_count, batches: batches, total: ^unique_count}} =
               EncryptedAdd.add_files(files, opts)

      assert batches >= 1

      counts = Agent.get(tracker, & &1)
      assert map_size(counts) == unique_count
      assert Enum.all?(counts, fn {_file, count} -> count == 1 end)
    end
  end
end
