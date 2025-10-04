defmodule GitVeil.Commands.Init do
  @moduledoc """
  Initialize GitVeil in a Git repository.

  This command:
  1. Verifies we're in a Git repository
  2. Generates a post-quantum keypair (Kyber1024 + classical)
  3. Saves keypair to .git/git_veil/master.key
  4. Configures Git clean/smudge filters
  5. Creates .gitattributes template (optional)
  """

  alias GitVeil.Adapters.FileKeyStorage

  @doc """
  Run the initialization process.

  ## Options
  - `:force` - Overwrite existing keypair if present (default: false)
  - `:skip_gitattributes` - Don't create .gitattributes template (default: false)

  ## Returns
  - `{:ok, message}` - Success with helpful message
  - `{:error, reason}` - Failure with error message
  """
  def run(opts \\ []) do
    force = Keyword.get(opts, :force, false)
    skip_gitattributes = Keyword.get(opts, :skip_gitattributes, false)

    with :ok <- verify_git_repository(),
         :ok <- check_existing_initialization(force),
         {:ok, _keypair} <- generate_and_save_keypair(),
         :ok <- configure_git_filters(),
         :ok <- maybe_create_gitattributes(skip_gitattributes) do
      {:ok, success_message()}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # Verification Steps
  # ============================================================================

  defp verify_git_repository do
    case System.cmd("git", ["rev-parse", "--git-dir"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {error, _} ->
        {:error, "Not a Git repository: #{String.trim(error)}"}
    end
  end

  defp check_existing_initialization(force) do
    case FileKeyStorage.initialized?() do
      false ->
        :ok

      true when force ->
        :ok

      true ->
        {:error, "GitVeil already initialized. Use --force to overwrite existing keypair."}
    end
  end

  # ============================================================================
  # Keypair Generation
  # ============================================================================

  defp generate_and_save_keypair do
    with {:ok, keypair} <- FileKeyStorage.generate_keypair(),
         :ok <- FileKeyStorage.store_keypair(keypair) do
      {:ok, keypair}
    else
      {:error, reason} ->
        {:error, "Failed to generate keypair: #{inspect(reason)}"}
    end
  end

  # ============================================================================
  # Git Configuration
  # ============================================================================

  defp configure_git_filters do
    # Determine the correct path to git-veil executable
    executable_path = get_executable_path()

    filters = [
      {"filter.gitveil.clean", "#{executable_path} clean %f"},
      {"filter.gitveil.smudge", "#{executable_path} smudge %f"},
      {"filter.gitveil.required", "true"}
    ]

    results =
      Enum.map(filters, fn {key, value} ->
        case System.cmd("git", ["config", key, value], stderr_to_stdout: true) do
          {_, 0} -> :ok
          {error, _} -> {:error, "Failed to set #{key}: #{String.trim(error)}"}
        end
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end

  # ============================================================================
  # .gitattributes Template
  # ============================================================================

  defp maybe_create_gitattributes(true), do: :ok

  defp maybe_create_gitattributes(false) do
    template = """
    # GitVeil - Quantum-resistant Git encryption
    # Uncomment patterns below to encrypt specific files

    # Environment files
    # .env filter=gitveil
    # .env.* filter=gitveil

    # Secrets directory
    # secrets/** filter=gitveil

    # Credentials
    # **/credentials.json filter=gitveil
    # **/api_keys.txt filter=gitveil

    # Private keys
    # *.pem filter=gitveil
    # *.key filter=gitveil
    """

    case File.exists?(".gitattributes") do
      false ->
        # Create new .gitattributes
        case File.write(".gitattributes", template) do
          :ok -> :ok
          {:error, reason} -> {:error, "Failed to create .gitattributes: #{inspect(reason)}"}
        end

      true ->
        # .gitattributes exists, don't overwrite
        # Could append or skip - for now, skip
        :ok
    end
  end

  # ============================================================================
  # Executable Path Detection
  # ============================================================================

  defp get_executable_path do
    cond do
      # Running in Mix Release
      release_path = System.get_env("RELEASE_ROOT") ->
        Path.join([release_path, "bin", "git_veil"])

      # Running via escript
      escript_path = System.get_env("_") ->
        escript_path

      # Fallback: assume git-veil is in PATH
      true ->
        "git-veil"
    end
  end

  # ============================================================================
  # Messages
  # ============================================================================

  defp success_message do
    """
    ✅ GitVeil initialized successfully!

    What was configured:
    • Generated Kyber1024 post-quantum keypair
    • Saved to .git/git_veil/master.key (permissions: 0600)
    • Configured Git filters in .git/config:
      - filter.gitveil.clean
      - filter.gitveil.smudge
      - filter.gitveil.required

    Next steps:
    1. Edit .gitattributes to specify which files to encrypt
       Example: echo "*.env filter=gitveil" >> .gitattributes

    2. Add and commit your changes:
       git add .gitattributes
       git commit -m "Configure GitVeil encryption"

    3. Encrypted files will be automatically encrypted on commit
       and decrypted on checkout

    ⚠️  IMPORTANT: Back up your master.key securely!
       Without it, you cannot decrypt your files.
       Location: .git/git_veil/master.key
    """
  end
end
