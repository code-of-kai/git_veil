defmodule GitFoil.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Only run CLI if we're not in test or dev environment
    # This allows mix test and other mix commands to work normally
    case Mix.env() do
      env when env in [:test, :dev] ->
        # In test/dev, just start a minimal supervisor
        children = []
        opts = [strategy: :one_for_one, name: GitFoil.Supervisor]
        Supervisor.start_link(children, opts)

      _prod ->
        # In production (Homebrew installation), run CLI and exit
        GitFoil.CLI.main(System.argv())
        System.halt(0)
    end
  end
end
