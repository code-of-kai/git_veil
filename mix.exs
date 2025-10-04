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
      escript: [main_module: GitVeil.CLI],
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
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {GitVeil.Application, []}
    ]
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
