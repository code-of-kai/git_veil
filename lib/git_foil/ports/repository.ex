defmodule GitFoil.Ports.Repository do
  @moduledoc """
  Port for Git repository operations.

  This port abstracts all interactions with the Git version control system,
  enabling testing without a real Git repository and potential future support
  for alternative implementations (e.g., libgit2).

  **Design principle:** Generic Git operations only. No domain logic.
  """

  @doc """
  Verify that we're in a Git repository.

  Returns the .git directory path if successful.
  """
  @callback verify_repository() :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Initialize a new Git repository in the current directory.
  """
  @callback init_repository() :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Get a Git configuration value.
  """
  @callback get_config(String.t()) :: {:ok, String.t()} | {:error, String.t() | :not_found}

  @doc """
  Set a Git configuration value.
  """
  @callback set_config(String.t(), String.t()) :: :ok | {:error, String.t()}

  @doc """
  List all tracked files in the repository.
  """
  @callback list_files() :: {:ok, [String.t()]} | {:error, String.t()}

  @doc """
  List all files in the repository (both tracked and untracked).
  Excludes files in .gitignore.
  """
  @callback list_all_files() :: {:ok, [String.t()]} | {:error, String.t()}

  @doc """
  Check the value of a Git attribute for a file.

  Returns the attribute value or :unset if not set.
  """
  @callback check_attr(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Check the value of a Git attribute for multiple files in a single call.

  Returns a list of {file, attribute_value} tuples.
  This is much more efficient than calling check_attr for each file individually.
  """
  @callback check_attr_batch(String.t(), [String.t()]) :: {:ok, [{String.t(), String.t()}]} | {:error, String.t()}

  @doc """
  Stage a file (git add).
  """
  @callback add_file(String.t()) :: :ok | {:error, String.t()}

  @doc """
  Get the absolute path to the repository root.
  """
  @callback repository_root() :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Check if a Git config key exists and has a value.
  """
  @callback config_exists?(String.t()) :: boolean()
end
