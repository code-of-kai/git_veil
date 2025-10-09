defmodule GitFoil.Commands.Unencrypt do
  @moduledoc """
  Remove all GitFoil encryption from the repository.

  This command decrypts all files, removes GitFoil configuration,
  and leaves you with a plain Git repository containing plaintext files.
  """

  alias GitFoil.Helpers.UIPrompts

  @doc """
  Unencrypt all files and remove GitFoil from the repository.

  This will:
  1. Decrypt all encrypted files
  2. Remove GitFoil patterns from .gitattributes
  3. Remove Git filter configuration
  4. Remove the master encryption key

  This operation is IRREVERSIBLE. Once the master key is deleted,
  you cannot re-encrypt with the same key.
  """
  def run(opts \\ []) do
    IO.puts("🔓  Removing GitFoil encryption...")
    IO.puts("")

    keep_key = Keyword.get(opts, :keep_key, false)

    with :ok <- verify_git_repository(),
         :ok <- verify_gitfoil_initialized(),
         :ok <- confirm_unencrypt(keep_key),
         {:ok, files_to_decrypt} <- get_encrypted_files(),  # Get list BEFORE removing .gitattributes
         :ok <- remove_gitattributes_patterns(),
         :ok <- disable_filters(),
         :ok <- decrypt_files(files_to_decrypt),
         :ok <- remove_filter_config(),
         :ok <- remove_master_key(keep_key) do
      {:ok, success_message(keep_key)}
    else
      {:error, reason} -> {:error, reason}
      {:ok, message} -> {:ok, message}
      :cancelled -> {:ok, ""}
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

  defp verify_gitfoil_initialized do
    if File.exists?(".git/git_foil/master.key") do
      :ok
    else
      {:ok, "👋  GitFoil not initialized. Nothing to unencrypt."}
    end
  end

  defp confirm_unencrypt(keep_key) do
    IO.puts("⚠️  WAIT - Do you need this command?")
    IO.puts("")
    IO.puts("📋  Important: GitFoil decrypts files automatically!")
    IO.puts("")
    IO.puts("   When you run git commands, decryption happens automatically:")
    IO.puts("   • git checkout <file>    → File is decrypted to your working directory")
    IO.puts("   • git pull               → Files are decrypted automatically")
    IO.puts("")
    IO.puts("ℹ️  Your files on disk are already plaintext - you can read them right now!")
    IO.puts("ℹ️  Encryption only exists inside Git's database, not in your working files.")
    IO.puts("")
    IO.puts("💡  You probably DON'T need git-foil unencrypt unless:")
    IO.puts("")
    IO.puts("   • You want to permanently remove encryption from this repository")
    IO.puts("   • You want to stop using GitFoil entirely")
    IO.puts("")
    IO.puts("Most users never need this command!")
    IO.puts("")
    UIPrompts.print_separator()
    IO.puts("")

    answer = safe_gets("Do you want to continue and permanently remove encryption? [y/N]: ")
             |> String.downcase()

    case answer do
      "y" -> confirm_destructive_action(keep_key)
      "yes" -> confirm_destructive_action(keep_key)
      _ ->
        IO.puts("")
        IO.puts("✅  Good choice! Your files are already decrypted in your working directory.")
        IO.puts("   No action needed - just use git normally.")
        :cancelled
    end
  end

  defp confirm_destructive_action(keep_key) do
    IO.puts("")
    IO.puts("⚠️  WARNING: This will \e[31mPERMANENTLY\e[0m remove GitFoil encryption!")
    IO.puts("")
    IO.puts("📋  What will happen:")
    IO.puts("   1. Git's internal storage will be converted from encrypted to plaintext")
    IO.puts("      (Your working files are already plaintext and won't change)")
    IO.puts("   2. GitFoil patterns removed from .gitattributes")
    IO.puts("   3. Git filter configuration removed")

    if keep_key do
      IO.puts("   4. Master encryption key will be PRESERVED")
      IO.puts("      (You can re-encrypt later with the same key)")
    else
      IO.puts("   4. Master encryption key will be DELETED (CANNOT BE UNDONE)")
      IO.puts("      (You cannot re-encrypt with the same key)")
    end

    IO.puts("")
    UIPrompts.print_separator()
    IO.puts("")

    answer = safe_gets("Are you absolutely sure? Type 'yes' to proceed: ")
             |> String.downcase()

    case answer do
      "yes" -> :ok
      _ ->
        IO.puts("")
        IO.puts("👋  Cancelled. No changes made.")
        :cancelled
    end
  end

  defp get_encrypted_files do
    # Get list of files that have the gitfoil filter attribute
    # This must be called BEFORE removing .gitattributes
    # Get both tracked and untracked files
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

        # Filter to only files that have the gitfoil filter attribute
        encrypted_files = Enum.filter(all_files, fn file ->
          case System.cmd("git", ["check-attr", "filter", file], stderr_to_stdout: true) do
            {attr_output, 0} ->
              String.contains?(attr_output, "filter: gitfoil")
            _ ->
              false
          end
        end)
        |> Enum.reject(&(&1 == ".gitattributes"))  # Exclude .gitattributes - it's metadata, not encrypted content

        {:ok, encrypted_files}

      {{error, _}, _} ->
        {:error, "Failed to list tracked files: #{String.trim(error)}"}

      {_, {error, _}} ->
        {:error, "Failed to list untracked files: #{String.trim(error)}"}
    end
  end

  defp disable_filters do
    # Replace filter commands with cat (passthrough) instead of unsetting
    # This ensures git doesn't try to run the old gitfoil filter
    with {_, 0} <- System.cmd("git", ["config", "filter.gitfoil.clean", "cat"], stderr_to_stdout: true),
         {_, 0} <- System.cmd("git", ["config", "filter.gitfoil.smudge", "cat"], stderr_to_stdout: true) do
      :ok
    else
      {error, _} -> {:error, "Failed to disable filters: #{String.trim(error)}"}
    end
  end

  defp decrypt_files(files_to_decrypt) do
    total = length(files_to_decrypt)

    if total == 0 do
      IO.puts("🔓  No encrypted files found.\n")
      :ok
    else
      IO.puts("📝  Converting Git's internal storage to plaintext...")
      IO.puts("")
      IO.puts("   ⚠️   Your working files are SAFE and will NOT be modified!")
      IO.puts("   📂  We're only changing what Git stores internally.")
      IO.puts("   🔒  Currently: Git's database has #{total} files stored encrypted")
      IO.puts("   🔓  After: Git's database will store them as plaintext")
      IO.puts("")
      IO.puts("   Processing #{total} files in Git's storage...\n")
      decrypt_files_with_progress(files_to_decrypt, total)
    end
  end

  defp decrypt_files_with_progress(files, total) do
    files
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {file, index}, _acc ->
      # Show progress (overwrite same line)
      progress_bar = build_progress_bar(index, total)
      IO.write("\r   #{progress_bar} #{index}/#{total} files")

      # Remove from index, then re-add with disabled filters
      # This forces git to store the plaintext working directory version
      with {_, 0} <- System.cmd("git", ["rm", "--cached", file], stderr_to_stdout: true),
           {_, 0} <- System.cmd("git", ["add", file], stderr_to_stdout: true) do
        {:cont, :ok}
      else
        {error, _} ->
          IO.write("\n")
          {:halt, {:error, "Failed to decrypt #{file}: #{String.trim(error)}"}}
      end
    end)
    |> case do
      :ok ->
        IO.write("\n\n")
        :ok

      error ->
        error
    end
  end

  defp remove_gitattributes_patterns do
    IO.puts("🗑️     Removing GitFoil patterns from .gitattributes...")

    if File.exists?(".gitattributes") do
      case File.read(".gitattributes") do
        {:ok, content} ->
          # Remove GitFoil-related lines
          new_content = content
                        |> String.split("\n")
                        |> Enum.reject(fn line ->
                          String.contains?(line, "filter=gitfoil") or
                          String.contains?(line, "GitFoil") or
                          String.trim(line) == ".gitattributes -filter"
                        end)
                        |> Enum.join("\n")
                        |> String.trim()

          # Write back or delete if empty
          if new_content == "" do
            File.rm(".gitattributes")
            IO.puts("   Removed empty .gitattributes file\n")
            :ok
          else
            case File.write(".gitattributes", new_content <> "\n") do
              :ok ->
                IO.puts("   Updated .gitattributes\n")
                :ok
              {:error, reason} ->
                {:error, "Failed to update .gitattributes: #{UIPrompts.format_error(reason)}"}
            end
          end

        {:error, reason} ->
          {:error, "Failed to read .gitattributes: #{UIPrompts.format_error(reason)}"}
      end
    else
      IO.puts("   No .gitattributes file found\n")
      :ok
    end
  end

  defp remove_filter_config do
    IO.puts("🗑️     Removing Git filter configuration...")

    filters = [
      "filter.gitfoil.clean",
      "filter.gitfoil.smudge",
      "filter.gitfoil.required"
    ]

    Enum.each(filters, fn key ->
      System.cmd("git", ["config", "--unset", key], stderr_to_stdout: true)
      # Don't fail if key doesn't exist
    end)

    IO.puts("   Removed filter configuration\n")
    :ok
  end

  defp remove_master_key(keep_key) do
    if keep_key do
      IO.puts("🔑  Preserving master encryption key...")
      IO.puts("   Key location: .git/git_foil/master.key")
      IO.puts("   You can re-encrypt later with: git-foil encrypt\n")
      :ok
    else
      IO.puts("🗑️     Removing master encryption key...")

      if File.exists?(".git/git_foil") do
        case File.rm_rf(".git/git_foil") do
          {:ok, _} ->
            IO.puts("   Deleted .git/git_foil directory\n")
            :ok

          {:error, reason, _} ->
            {:error, "Failed to remove master key: #{UIPrompts.format_error(reason)}"}
        end
      else
        IO.puts("   No master key found\n")
        :ok
      end
    end
  end

  defp build_progress_bar(current, total) do
    percentage = current / total
    filled = round(percentage * 20)
    empty = 20 - filled

    bar = String.duplicate("█", filled) <> String.duplicate("░", empty)
    percent = :erlang.float_to_binary(percentage * 100, decimals: 0)

    "#{bar} #{percent}%"
  end

  defp success_message(keep_key) do
    if keep_key do
      """
      ✅  GitFoil encryption removed!

      📋  Current state:
         • Git's internal storage now contains plaintext (not encrypted)
         • GitFoil configuration removed
         • This is now a standard Git repository
         • Your encryption key is preserved at: .git/git_foil/master.key

      💡  What you can do now:
         • Use git normally - your repository works like any other Git repo
         • Your repository has uncommitted changes (converted files)
         • Commit them when you're ready
         • To re-enable encryption: run 'git-foil encrypt' (will use the same key)
         • To permanently remove the key: run 'git-foil unencrypt' without --keep-key

      📌  Note: Your encryption key is preserved.
         You can re-enable encryption at any time.
      """
    else
      """
      ✅  GitFoil encryption removed!

      📋  Current state:
         • Git's internal storage now contains plaintext (not encrypted)
         • GitFoil completely removed
         • This is now a standard Git repository
         • The encryption key has been permanently deleted

      💡  What you can do now:
         • Use git normally - your repository works like any other Git repo
         • Your repository has uncommitted changes (converted files)
         • Commit them when you're ready
         • To re-enable encryption: run 'git-foil init'

      📌  Note: GitFoil has been completely removed.
         Your repository is now a standard Git repository without encryption.
      """
    end
  end

  # Safe wrapper for IO.gets that handles EOF from piped input
  defp safe_gets(prompt, default \\ "") do
    case IO.gets(prompt) do
      :eof -> default
      input -> String.trim(input)
    end
  end
end
