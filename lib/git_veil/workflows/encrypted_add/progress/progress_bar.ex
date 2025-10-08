defmodule GitVeil.Workflows.EncryptedAdd.Progress.ProgressBar do
  @moduledoc """
  Lightweight determinate progress display implemented with built-in terminal helpers.

  Renders a single-line bar that updates in place and leaves the cursor on a
  fresh line when the workflow finishes or aborts.
  """

  @behaviour GitVeil.Workflows.EncryptedAdd.Progress

  defstruct [:current, :total, :label, :width]

  alias GitVeil.Infrastructure.Terminal

  @impl true
  def start(total, options) when total > 0 do
    label = Keyword.get(options, :label, "Encrypting files")
    width = Keyword.get(options, :width, 30)

    if label && label != "" do
      IO.puts(label)
    end

    state = %__MODULE__{current: 0, total: total, label: label, width: width}
    render(state)
    state
  end

  def start(_total, _options), do: nil

  @impl true
  def advance(nil, _processed, _context), do: nil

  def advance(%__MODULE__{} = state, processed, _context) when processed > 0 do
    new_current =
      state.current
      |> Kernel.+(processed)
      |> min(state.total)

    new_state = %{state | current: new_current}
    render(new_state)
    new_state
  end

  @impl true
  def finish(nil), do: nil

  def finish(%__MODULE__{} = state) do
    if state.total > 0 do
      IO.puts("")
    end

    state
  end

  defp render(%__MODULE__{total: total} = state) when total > 0 do
    bar = Terminal.progress_bar(state.current, total, state.width)
    line = "   #{bar} #{state.current}/#{state.total}"
    IO.write("\r#{line}")
    :ok
  end
end
