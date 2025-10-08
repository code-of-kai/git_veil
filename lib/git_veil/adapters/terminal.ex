defmodule GitVeil.Adapters.Terminal do
  @moduledoc """
  Terminal adapter that delegates to the infrastructure implementation.

  This keeps the public port stable while allowing the infrastructure layer to
  evolve independently.
  """

  @behaviour GitVeil.Ports.Terminal

  alias GitVeil.Infrastructure.Terminal, as: Impl

  @impl true
  def with_spinner(label, work_fn, opts \\ []) do
    Impl.with_spinner(label, work_fn, opts)
  end

  @impl true
  def progress_bar(current, total, width \\ 20) do
    Impl.progress_bar(current, total, width)
  end

  @impl true
  def safe_gets(prompt, default \\ "") do
    Impl.safe_gets(prompt, default)
  end

  @impl true
  def format_number(number) do
    Impl.format_number(number)
  end

  @impl true
  def pluralize(word, count) do
    Impl.pluralize(word, count)
  end
end
