defmodule GitFoil.Infrastructure.Terminal do
  @moduledoc """
  Terminal UI primitives - spinners, progress bars, safe input.

  This module provides reusable terminal mechanisms. It does NOT
  contain domain-specific messaging - that stays with business logic.

  **Design principle:** Generic UI primitives only. No domain UX.
  """

  @behaviour GitFoil.Ports.Terminal

  @doc """
  Run work function with animated spinner.

  Returns the result of the work function.

  ## Options
  - `:min_duration` - Minimum time to show spinner (default: 0ms)
  """
  @impl true
  @spec with_spinner(String.t(), (-> result), keyword()) :: result when result: any()
  def with_spinner(label, work_fn, opts \\ []) do
    min_duration = Keyword.get(opts, :min_duration, 0)
    start_time = System.monotonic_time(:millisecond)

    # Start spinner in background
    spinner_task = Task.async(fn ->
      animate_spinner(label)
    end)

    # Do the work
    work_task = Task.async(work_fn)
    result = Task.await(work_task, 15_000)

    # Ensure minimum duration if specified
    if min_duration > 0 do
      elapsed = System.monotonic_time(:millisecond) - start_time
      if elapsed < min_duration do
        Process.sleep(min_duration - elapsed)
      end
    end

    # Stop spinner and clear line
    send(spinner_task.pid, :stop)
    Task.await(spinner_task)
    IO.write("\r\e[K")

    result
  end

  @doc """
  Animate a spinner with the given label.

  This function runs until it receives a :stop message.
  """
  def animate_spinner(label) do
    frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    animate_spinner_loop(label, frames, 0)
  end

  defp animate_spinner_loop(label, frames, index) do
    receive do
      :stop -> :ok
    after
      80 ->
        frame = Enum.at(frames, rem(index, length(frames)))
        IO.write("\r#{frame}  #{label}")
        animate_spinner_loop(label, frames, index + 1)
    end
  end

  @doc """
  Build a progress bar string.

  Returns a string like: "████████████░░░░░░░░ 60%"

  ## Parameters
  - `current` - Current progress (e.g., 6)
  - `total` - Total items (e.g., 10)
  - `width` - Width of the bar in characters (default: 20)
  """
  @impl true
  @spec progress_bar(non_neg_integer(), pos_integer(), pos_integer()) :: String.t()
  def progress_bar(current, total, width \\ 20) do
    percentage = current / total
    filled = round(percentage * width)
    empty = width - filled

    bar = String.duplicate("█", filled) <> String.duplicate("░", empty)
    percent = :erlang.float_to_binary(percentage * 100, decimals: 0)

    "#{bar} #{percent}%"
  end

  @doc """
  Safe wrapper for IO.gets that handles EOF from piped input.

  Returns the default value if EOF is encountered (e.g., in tests or CI).
  """
  @impl true
  @spec safe_gets(String.t(), String.t()) :: String.t()
  def safe_gets(prompt, default \\ "") do
    case IO.gets(prompt) do
      :eof -> default
      input -> String.trim(input)
    end
  end

  @doc """
  Format a number with comma separators (e.g., 1000 -> "1,000").
  """
  @impl true
  @spec format_number(integer()) :: String.t()
  def format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  @doc """
  Pluralize a word based on count.

  ## Examples
      iex> pluralize("file", 1)
      "file"

      iex> pluralize("file", 5)
      "files"
  """
  @impl true
  @spec pluralize(String.t(), non_neg_integer()) :: String.t()
  def pluralize(word, 1), do: word
  def pluralize(word, _count), do: word <> "s"
end
