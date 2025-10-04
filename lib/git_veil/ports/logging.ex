defmodule GitVeil.Ports.Logging do
  @moduledoc """
  Port for logging operations.

  **Log Levels:**
  - debug: Verbose operational details
  - info: General information
  - warning: Potential issues
  - error: Error conditions

  Implementations may write to files, stdout, or structured logging systems.
  """

  @type level :: :debug | :info | :warning | :error

  @callback log(level(), message :: String.t(), metadata :: keyword()) :: :ok
end
