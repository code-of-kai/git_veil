defmodule GitVeil.MixProject do
  use Mix.Project

  def project do
    [
      app: :git_veil,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # CLI escript configuration
      escript: [main_module: GitVeil.CLI, name: "git-veil"],
      # Test coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ],
      # Dialyzer for type checking
      dialyzer: [
        plt_add_apps: [:mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      # Mix Release configuration
      releases: [
        git_veil: [
          include_executables_for: [:unix],
          applications: [runtime_tools: :permanent],
          steps: [:assemble, &create_cli_wrapper/1, :tar]
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {GitVeil.Application, []}
    ]
  end

  # Custom release step to create CLI wrapper
  defp create_cli_wrapper(release) do
    bin_path = Path.join([release.path, "bin", "git-veil-cli"])

    wrapper_script = """
    #!/bin/sh
    set -e

    SELF=$(readlink "$0" || true)
    if [ -z "$SELF" ]; then SELF="$0"; fi
    RELEASE_ROOT="$(cd "$(dirname "$SELF")/.." && pwd -P)"
    export RELEASE_ROOT

    # Build arguments list for Elixir
    ARGS=""
    for arg in "$@"; do
      ARGS="$ARGS,\\\"$arg\\\""
    done
    ARGS=$(echo "$ARGS" | sed 's/^,//')

    exec "$RELEASE_ROOT/bin/git_veil" eval "GitVeil.CLI.main([$ARGS])"
    """

    File.write!(bin_path, wrapper_script)
    File.chmod!(bin_path, 0o755)

    release
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Post-quantum cryptography
      {:pqclean, "~> 0.0.3"},

      # Alternative crypto implementation (libsodium)
      # DISABLED: enacl not compatible with OTP 28 yet
      # {:enacl, "~> 1.2"},

      # Code quality and static analysis
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # Test coverage
      {:excoveralls, "~> 0.18", only: :test},

      # Property-based testing
      {:stream_data, "~> 1.1", only: :test}
    ]
  end
end
