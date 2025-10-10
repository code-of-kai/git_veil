defmodule GitFoil.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Git-foil is a CLI tool, not a long-running server
    # Execute the CLI command and exit immediately
    GitFoil.CLI.main(System.argv())
    System.halt(0)
  end
end
