defmodule GitFoil.Ports.Terminal do
  @moduledoc """
  Port for terminal UI primitives.

  This port abstracts terminal interactions like spinners, progress bars,
  and safe input handling. It does NOT include domain-specific messaging -
  that stays with business logic.

  **Design principle:** Generic UI primitives only. No domain UX.
  """

  @doc """
  Run work function with animated spinner.

  Returns the result of the work function.

  ## Options
  - `:min_duration` - Minimum time to show spinner (default: 0ms)
  """
  @callback with_spinner(String.t(), (-> result), keyword()) :: result when result: any()

  @doc """
  Build a progress bar string.

  Returns a string like: "████████████░░░░░░░░ 60%"

  ## Parameters
  - `current` - Current progress (e.g., 6)
  - `total` - Total items (e.g., 10)
  - `width` - Width of the bar in characters (default: 20)
  """
  @callback progress_bar(non_neg_integer(), pos_integer(), pos_integer()) :: String.t()

  @doc """
  Safe wrapper for input that handles EOF from piped input.

  Returns the default value if EOF is encountered (e.g., in tests or CI).
  """
  @callback safe_gets(String.t(), String.t()) :: String.t()

  @doc """
  Format a number with comma separators (e.g., 1000 -> "1,000").
  """
  @callback format_number(integer()) :: String.t()

  @doc """
  Pluralize a word based on count.

  ## Examples
      iex> pluralize("file", 1)
      "file"

      iex> pluralize("file", 5)
      "files"
  """
  @callback pluralize(String.t(), non_neg_integer()) :: String.t()
end
