defmodule GitVeil.Infrastructure.Git do
  @moduledoc """
  Git command-line operations.

  This module wraps all Git CLI interactions, keeping them isolated
  from business logic and UX flows.

  **Design principle:** Generic Git operations only. No UX messaging.
  """

  @behaviour GitVeil.Ports.Repository

  @doc """
  Verify that we're in a Git repository.

  Returns the .git directory path if successful.
  """
  @impl true
  @spec verify_repository() :: {:ok, String.t()} | {:error, String.t()}
  def verify_repository do
    case System.cmd("git", ["rev-parse", "--git-dir"], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, String.trim(output)}

      {error, _} ->
        {:error, String.trim(error)}
    end
  end

  @doc """
  Initialize a new Git repository in the current directory.
  """
  @impl true
  @spec init_repository() :: {:ok, String.t()} | {:error, String.t()}
  def init_repository do
    case System.cmd("git", ["init"], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, String.trim(output)}

      {error, _} ->
        {:error, String.trim(error)}
    end
  end

  @doc """
  Get a Git configuration value.
  """
  @impl true
  @spec get_config(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def get_config(key) do
    case System.cmd("git", ["config", key], stderr_to_stdout: true) do
      {output, 0} when byte_size(output) > 0 ->
        {:ok, String.trim(output)}

      {_, 0} ->
        {:error, :not_found}

      {error, _} ->
        {:error, String.trim(error)}
    end
  end

  @doc """
  Set a Git configuration value.
  """
  @impl true
  @spec set_config(String.t(), String.t()) :: :ok | {:error, String.t()}
  def set_config(key, value) do
    case System.cmd("git", ["config", key, value], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {error, _} ->
        {:error, "Failed to set #{key}: #{String.trim(error)}"}
    end
  end

  @doc """
  List all tracked files in the repository.
  """
  @impl true
  @spec list_files() :: {:ok, [String.t()]} | {:error, String.t()}
  def list_files do
    case System.cmd("git", ["ls-files"], stderr_to_stdout: true) do
      {output, 0} ->
        files =
          output
          |> String.split("\n", trim: true)
          |> Enum.reject(&(&1 == ""))

        {:ok, files}

      {error, _} ->
        {:error, "Failed to list repository files: #{String.trim(error)}"}
    end
  end

  @doc """
  List all files in the repository (both tracked and untracked).
  Excludes files in .gitignore.
  """
  @impl true
  @spec list_all_files() :: {:ok, [String.t()]} | {:error, String.t()}
  def list_all_files do
    # Get tracked files
    tracked_result = System.cmd("git", ["ls-files"], stderr_to_stdout: true)
    # Get untracked files (excluding those in .gitignore)
    untracked_result = System.cmd("git", ["ls-files", "--others", "--exclude-standard"], stderr_to_stdout: true)

    case {tracked_result, untracked_result} do
      {{tracked_output, 0}, {untracked_output, 0}} ->
        tracked_files = tracked_output
                       |> String.split("\n", trim: true)
                       |> Enum.reject(&(&1 == ""))

        untracked_files = untracked_output
                         |> String.split("\n", trim: true)
                         |> Enum.reject(&(&1 == ""))

        all_files = (tracked_files ++ untracked_files) |> Enum.uniq()

        {:ok, all_files}

      {{error, _}, _} ->
        {:error, "Failed to list tracked files: #{String.trim(error)}"}

      {_, {error, _}} ->
        {:error, "Failed to list untracked files: #{String.trim(error)}"}
    end
  end

  @doc """
  Check the value of a Git attribute for a file.

  Returns the attribute value or :unset if not set.
  """
  @impl true
  @spec check_attr(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def check_attr(attr, file) do
    case System.cmd("git", ["check-attr", attr, file], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, String.trim(output)}

      {error, _} ->
        {:error, String.trim(error)}
    end
  end

  @doc """
  Check the value of a Git attribute for multiple files in a single call.

  Returns a list of {file, attribute_value} tuples.
  This is much more efficient than calling check_attr for each file individually.
  """
  @impl true
  @spec check_attr_batch(String.t(), [String.t()]) :: {:ok, [{String.t(), String.t()}]} | {:error, String.t()}
  def check_attr_batch(attr, files) when is_list(files) do
    # Process files in chunks to avoid System.cmd argument list limits
    # FALLBACK APPROACH: Pass files as arguments instead of stdin
    # This avoids System.cmd stdin limitations while still batching for performance
    # 100 files per command instead of 1 = 100x fewer process spawns
    chunk_size = 100

    files
    |> Enum.chunk_every(chunk_size)
    |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, acc} ->
      # Pass files as arguments instead of via stdin
      # git check-attr <attr> <file1> <file2> ...
      case System.cmd("git", ["check-attr", attr] ++ chunk, stderr_to_stdout: true) do
        {output, 0} ->
          # Parse output: each line is "filename: attr: value"
          results = output
          |> String.split("\n", trim: true)
          |> Enum.map(fn line ->
            # Split on first two colons to handle filenames with colons
            case String.split(line, ": ", parts: 3) do
              [file, ^attr, value] -> {file, String.trim(value)}
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

          {:cont, {:ok, acc ++ results}}

        {error, _} ->
          {:halt, {:error, String.trim(error)}}
      end
    end)
  end

  @doc """
  Stage a file (git add).
  """
  @impl true
  @spec add_file(String.t()) :: :ok | {:error, String.t()}
  def add_file(path) do
    case System.cmd("git", ["add", path], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {error, _} ->
        {:error, "Failed to add #{path}: #{String.trim(error)}"}
    end
  end

  @doc """
  Get the absolute path to the repository root.
  """
  @impl true
  @spec repository_root() :: {:ok, String.t()} | {:error, String.t()}
  def repository_root do
    case System.cmd("git", ["rev-parse", "--show-toplevel"], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, String.trim(output)}

      {error, _} ->
        {:error, String.trim(error)}
    end
  end

  @doc """
  Check if a Git config key exists and has a value.
  """
  @impl true
  @spec config_exists?(String.t()) :: boolean()
  def config_exists?(key) do
    case get_config(key) do
      {:ok, _value} -> true
      _ -> false
    end
  end
end
