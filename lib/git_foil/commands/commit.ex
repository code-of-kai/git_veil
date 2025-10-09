defmodule GitFoil.Commands.Commit do
  @moduledoc """
  Commit GitFoil configuration changes.

  This is a convenience command that stages and commits .gitattributes
  with an appropriate commit message.
  """

  @doc """
  Commit .gitattributes changes.

  ## Options
  - `:message` - Custom commit message (optional)
  """
  def run(opts \\ []) do
    custom_message = Keyword.get(opts, :message)

    IO.puts("📝  Staging .gitattributes...")

    case System.cmd("git", ["add", ".gitattributes"], stderr_to_stdout: true) do
      {_, 0} ->
        commit_message = custom_message || "Configure GitFoil encryption"
        IO.puts("💾  Committing changes...")

        case System.cmd("git", ["commit", "-m", commit_message], stderr_to_stdout: true) do
          {output, 0} ->
            {:ok, format_success(output, commit_message)}

          {error, _} ->
            # Check if it's just "nothing to commit"
            if String.contains?(error, "nothing to commit") do
              {:ok, """
              ✅  Nothing to commit

              .gitattributes is already committed or hasn't changed.
              """}
            else
              {:error, """
              Failed to commit:
              #{String.trim(error)}

              💡  Try committing manually:
                 git add .gitattributes
                 git commit -m "#{commit_message}"
              """}
            end
        end

      {error, _} ->
        {:error, """
        Failed to stage .gitattributes:
        #{String.trim(error)}

        💡  Make sure .gitattributes exists and you're in a git repository.
        """}
    end
  end

  defp format_success(git_output, message) do
    """
    ✅  Committed successfully!

    #{String.trim(git_output)}

    🔍  What this did:
       git add .gitattributes
       git commit -m "#{message}"

    Your encryption configuration is now tracked in git.
    """
  end
end
