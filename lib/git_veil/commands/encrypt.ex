defmodule GitVeil.Commands.Encrypt do
  @moduledoc """
  Encrypt files matching .gitattributes patterns.

  This command adds all files to Git, which triggers the clean filter
  to encrypt files matching your encryption patterns.
  """

  alias GitVeil.Helpers.UIPrompts
  alias GitVeil.Workflows.EncryptedAdd

  @doc """
  Encrypt all files matching .gitattributes patterns.

  This is a convenience wrapper around `git add -A` that shows progress
  and makes the encryption process transparent.
  """
  def run(opts \\ []) do
    IO.puts("🔐  Encrypting files...")
    IO.puts("")

    force = Keyword.get(opts, :force, false)

    with :ok <- verify_git_repository(),
         :ok <- verify_gitveil_initialized(),
         :ok <- check_patterns_configured(),
         key_action <- check_key_and_prompt(force),
         :ok <- maybe_generate_new_key(key_action),
         result <- encrypt_files() do
      case result do
        :ok -> {:ok, success_message(key_action)}
        {:ok, message} -> {:ok, message}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_git_repository do
    case System.cmd("git", ["rev-parse", "--git-dir"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {_error, _} ->
        {:error, "Not a Git repository. Run this command inside a Git repository."}
    end
  end

  defp verify_gitveil_initialized do
    if File.exists?(".git/git_veil/master.key") do
      :ok
    else
      {:error, "GitVeil not initialized. Run 'git-veil init' first."}
    end
  end

  defp check_patterns_configured do
    if File.exists?(".gitattributes") do
      case File.read(".gitattributes") do
        {:ok, content} ->
          if String.contains?(content, "filter=gitveil") do
            :ok
          else
            offer_to_configure_patterns()
          end

        {:error, _} ->
          offer_to_configure_patterns()
      end
    else
      offer_to_configure_patterns()
    end
  end

  defp offer_to_configure_patterns do
    IO.puts("⚠️     No encryption patterns configured!")
    IO.puts("")
    IO.puts("GitVeil needs to know which files to encrypt.")
    IO.puts("Without patterns, no files will be encrypted.")
    IO.puts("")
    IO.puts("Would you like to configure patterns now?")
    IO.puts("")
    IO.puts("   [Y] Yes - Configure patterns (interactive menu)")
    IO.puts("   [n] No  - Skip for now")
    IO.puts("")
    UIPrompts.print_separator()

    answer = safe_gets("\nConfigure patterns? [Y/n]: ") |> String.downcase()

    case answer do
      "" -> run_configure_patterns()
      "y" -> run_configure_patterns()
      "yes" -> run_configure_patterns()
      _ ->
        IO.puts("\n⚠️     Skipping pattern configuration.")
        IO.puts("   Run 'git-veil configure' when ready.\n")
        :ok
    end
  end

  defp run_configure_patterns do
    IO.puts("")
    alias GitVeil.Commands.Init

    case Init.configure_patterns() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_key_and_prompt(force) do
    if force do
      IO.puts("⚠️     Creating new encryption key (--force flag)\n")
      {:generate_new}
    else
      prompt_key_choice()
    end
  end

  defp prompt_key_choice do
    case UIPrompts.prompt_key_choice(purpose: "encrypt files") do
      {:use_existing} ->
        IO.puts("\n✅  Using existing encryption key\n")
        {:use_existing}

      {:create_new} ->
        case backup_existing_key() do
          {:ok, backup_path} ->
            IO.puts(UIPrompts.format_key_backup_message(backup_path))
            {:generate_new}

          {:error, reason} ->
            {:error, UIPrompts.format_error_message(
              "Failed to backup existing key: #{UIPrompts.format_error(reason)}"
            )}
        end

      {:invalid, _message} ->
        IO.puts("\n❌  Invalid choice. Using existing key.\n")
        {:use_existing}
    end
  end

  defp backup_existing_key do
    timestamp = DateTime.utc_now()
                |> DateTime.to_iso8601()
                |> String.replace(":", "-")
                |> String.replace(".", "-")

    backup_filename = "master.key.backup.#{timestamp}"
    backup_path = ".git/git_veil/#{backup_filename}"

    case File.rename(".git/git_veil/master.key", backup_path) do
      :ok ->
        {:ok, backup_path}

      {:error, reason} ->
        {:error, UIPrompts.format_error(reason)}
    end
  end

  defp maybe_generate_new_key({:use_existing}), do: :ok
  defp maybe_generate_new_key({:generate_new}) do
    alias GitVeil.Adapters.FileKeyStorage

    with {:ok, keypair} <- FileKeyStorage.generate_keypair(),
         :ok <- FileKeyStorage.store_keypair(keypair) do
      :ok
    else
      {:error, reason} ->
        {:error, "Failed to generate keypair: #{UIPrompts.format_error(reason)}"}
    end
  end
  defp maybe_generate_new_key({:error, reason}), do: {:error, reason}

  defp encrypt_files do
    # Get ALL tracked files (Git will apply clean filter based on .gitattributes)
    # Also get untracked files to include new files
    tracked_result = System.cmd("git", ["ls-files"], stderr_to_stdout: true)
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
        total = length(all_files)

        if total == 0 do
          {:ok, "No files to encrypt."}
        else
          IO.puts("🔒  Encrypting #{total} files...\n")
          run_encrypted_add(all_files, total)
        end

      {{error, _}, _} ->
        {:error, "Failed to list tracked files: #{String.trim(error)}"}

      {_, {error, _}} ->
        {:error, "Failed to list untracked files: #{String.trim(error)}"}
    end
  end

  defp run_encrypted_add(files, total) do
    options = [
      progress_opts: [
        label: "   Running git add (encrypting files)"
      ]
    ]

    case EncryptedAdd.add_files(files, options) do
      {:ok, %{processed: ^total}} ->
        IO.puts("")
        :ok

      {:ok, %{processed: processed}} ->
        {:error,
         "Encryption completed partially: processed #{processed} of #{total} files before exiting."}

      {:error, _reason, context} ->
        {:error, format_encrypted_add_error(context)}
    end
  end

  defp format_encrypted_add_error(context) do
    path =
      context
      |> Map.get(:failed_paths, [])
      |> List.wrap()
      |> List.first()

    detail = extract_error_detail(context)

    case path do
      nil -> "git add failed: #{detail}"
      path -> "Failed to add #{path}: #{detail}"
    end
  end

  defp extract_error_detail(%{message: message}) when is_binary(message) and message != "" do
    String.trim(message)
  end

  defp extract_error_detail(%{stderr: stderr}) when is_binary(stderr) and stderr != "" do
    String.trim(stderr)
  end

  defp extract_error_detail(%{stdout: stdout}) when is_binary(stdout) and stdout != "" do
    String.trim(stdout)
  end

  defp extract_error_detail(%{exception: %_{} = exception}) do
    Exception.message(exception)
  rescue
    _ -> inspect(exception)
  end

  defp extract_error_detail(%{exception: exception}) when not is_nil(exception) do
    inspect(exception)
  end

  defp extract_error_detail(%{exit_status: status}) when is_integer(status) do
    "git exited with status #{status}"
  end

  defp extract_error_detail(%{reason: reason}) when is_atom(reason) do
    Atom.to_string(reason)
  end

  defp extract_error_detail(_), do: "unknown error"

  defp success_message(key_action) do
    key_info = case key_action do
      {:use_existing} -> "Used existing encryption key (.git/git_veil/master.key)"
      {:generate_new} -> "Used newly generated encryption key (.git/git_veil/master.key)"
      _ -> "Used encryption key (.git/git_veil/master.key)"
    end

    """
    ✅  Encryption complete!

    📋  What happened:
       #{key_info}
       Files matching your .gitattributes patterns were encrypted.

       🔍  What this did:
          git ls-files                    # List all tracked files
          git ls-files --others           # List untracked files
          git add <each-file>             # Add each file (triggers clean filter)

    💡  Next step - commit the encrypted files:
       git-veil commit

       🔍  What this does:
          git add .
          git commit -m "Add encrypted files"

    📌 Note: Files in your working directory remain plaintext.
       Only the versions stored in Git are encrypted.
    """
  end

  # Safe wrapper for IO.gets that handles EOF from piped input
  defp safe_gets(prompt, default \\ "") do
    case IO.gets(prompt) do
      :eof -> default
      input -> String.trim(input)
    end
  end
end
