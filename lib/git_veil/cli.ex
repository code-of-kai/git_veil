defmodule GitVeil.CLI do
  @moduledoc """
  Command-line interface for GitVeil.

  ## Commands

  - `init` - Initialize GitVeil in the current Git repository
  - `clean <file>` - Clean filter (working tree → repository)
  - `smudge <file>` - Smudge filter (repository → working tree)
  - `doctor` - Run health checks
  - `version` - Show version information
  - `help` - Show help message

  ## Git Filter Integration

  GitVeil is designed to be used as a Git clean/smudge filter:

  ```
  [filter "gitveil"]
    clean = git_veil clean %f
    smudge = git_veil smudge %f
    required = true
  ```

  Files matching `.gitattributes` patterns will be automatically encrypted:

  ```
  *.env filter=gitveil
  secrets/** filter=gitveil
  ```
  """

  alias GitVeil.Adapters.{FileLogger, InMemoryKeyStorage, OpenSSLCrypto}
  alias GitVeil.Commands.{Doctor, Init}

  @version Mix.Project.config()[:version] || "dev"

  @doc """
  Main CLI entry point.

  Parses arguments and dispatches to appropriate command.
  """
  def main(args) do
    result = run(args)
    handle_result(result)
  end

  @doc """
  Run command without halting (for testing).

  Returns the result tuple instead of exiting.
  """
  def run(args) do
    parse_args(args)
    |> execute()
  end

  # ============================================================================
  # Argument Parsing
  # ============================================================================

  defp parse_args([]), do: {:help, []}
  defp parse_args(["help" | _]), do: {:help, []}
  defp parse_args(["--help" | _]), do: {:help, []}
  defp parse_args(["-h" | _]), do: {:help, []}

  defp parse_args(["version" | _]), do: {:version, []}
  defp parse_args(["--version" | _]), do: {:version, []}
  defp parse_args(["-v" | _]), do: {:version, []}

  defp parse_args(["init" | rest]), do: {:init, parse_options(rest)}
  defp parse_args(["doctor" | rest]), do: {:doctor, parse_options(rest)}

  defp parse_args(["clean", file_path | rest]) when is_binary(file_path) do
    {:clean, [file_path: file_path] ++ parse_options(rest)}
  end

  defp parse_args(["smudge", file_path | rest]) when is_binary(file_path) do
    {:smudge, [file_path: file_path] ++ parse_options(rest)}
  end

  defp parse_args(args) do
    {:error, "Unknown command: #{Enum.join(args, " ")}"}
  end

  defp parse_options(args) do
    args
    |> Enum.reduce([], fn
      "--verbose", acc -> [{:verbose, true} | acc]
      "-v", acc -> [{:verbose, true} | acc]
      "--force", acc -> [{:force, true} | acc]
      "-f", acc -> [{:force, true} | acc]
      "--skip-gitattributes", acc -> [{:skip_gitattributes, true} | acc]
      _, acc -> acc
    end)
  end

  # ============================================================================
  # Command Execution
  # ============================================================================

  defp execute({:help, _opts}) do
    {:ok, help_text()}
  end

  defp execute({:version, _opts}) do
    {:ok, "GitVeil version #{@version}"}
  end

  defp execute({:init, opts}) do
    case Init.run(opts) do
      {:ok, message} -> {:ok, message}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute({:doctor, opts}) do
    verbose = Keyword.get(opts, :verbose, false)

    # For now, use in-memory key storage for testing
    # In production, this would use FileKeyStorage
    result = Doctor.run(
      key_storage: InMemoryKeyStorage,
      crypto: OpenSSLCrypto,
      verbose: verbose
    )

    case result do
      {:ok, report} ->
        {:ok, Doctor.format_report(report)}

      {:error, failures} ->
        {:error, Doctor.format_report({:error, failures})}
    end
  end

  defp execute({:clean, opts}) do
    file_path = Keyword.fetch!(opts, :file_path)

    # Process clean filter: plaintext (stdin) → encrypted (stdout)
    # GitFilter.process handles all I/O directly
    case GitVeil.Adapters.GitFilter.process(:clean, file_path) do
      {:ok, 0} -> {:ok, ""}
      {:error, exit_code} -> {:error, exit_code}
    end
  end

  defp execute({:smudge, opts}) do
    file_path = Keyword.fetch!(opts, :file_path)

    # Process smudge filter: encrypted (stdin) → plaintext (stdout)
    # GitFilter.process handles all I/O directly
    case GitVeil.Adapters.GitFilter.process(:smudge, file_path) do
      {:ok, 0} -> {:ok, ""}
      {:error, exit_code} -> {:error, exit_code}
    end
  end

  defp execute({:error, message}) do
    {:error, message}
  end

  # ============================================================================
  # Result Handling
  # ============================================================================

  defp handle_result({:ok, output}) when is_binary(output) do
    if output != "" do
      IO.puts(output)
    end
    System.halt(0)
  end

  defp handle_result({:error, message}) when is_binary(message) do
    IO.puts(:stderr, "Error: #{message}")
    IO.puts(:stderr, "\nRun 'git_veil help' for usage information.")
    System.halt(1)
  end

  # ============================================================================
  # Help Text
  # ============================================================================

  defp help_text do
    """
    GitVeil - Quantum-resistant Git encryption

    USAGE:
        git_veil <command> [options]

    COMMANDS:
        init                Initialize GitVeil in current Git repository
        clean <file>        Clean filter (encrypt file for storage)
        smudge <file>       Smudge filter (decrypt file for working tree)
        doctor              Run health checks
        version             Show version information
        help                Show this help message

    OPTIONS:
        --verbose, -v              Show verbose output
        --help, -h                 Show help
        --force, -f                Force overwrite (for init command)
        --skip-gitattributes       Skip .gitattributes template creation

    INIT COMMAND:

        git_veil init [--force] [--skip-gitattributes]

        Initializes GitVeil by:
        • Generating Kyber1024 post-quantum keypair
        • Saving to .git/git_veil/master.key (0600 permissions)
        • Configuring Git clean/smudge filters
        • Creating .gitattributes template (unless --skip-gitattributes)

        Use --force to overwrite an existing keypair.

    EXAMPLES:

        # Initialize GitVeil (recommended first step)
        git_veil init

        # Initialize and skip .gitattributes template
        git_veil init --skip-gitattributes

        # Reinitialize with new keypair (destroys old key!)
        git_veil init --force

        # Configure which files to encrypt
        echo "*.env filter=gitveil" >> .gitattributes
        echo "secrets/** filter=gitveil" >> .gitattributes

        # Run health check
        git_veil doctor --verbose

    For more information, visit: https://github.com/code-of-kai/git_veil
    """
  end
end
