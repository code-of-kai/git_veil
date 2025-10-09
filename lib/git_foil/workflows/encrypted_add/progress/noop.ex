defmodule GitFoil.Workflows.EncryptedAdd.Progress.Noop do
  @moduledoc """
  Disabled progress renderer used in tests or headless environments.
  """

  @behaviour GitFoil.Workflows.EncryptedAdd.Progress

  @impl true
  def start(_total, _options), do: :ok

  @impl true
  def advance(state, _processed, _context), do: state

  @impl true
  def finish(state), do: state
end
