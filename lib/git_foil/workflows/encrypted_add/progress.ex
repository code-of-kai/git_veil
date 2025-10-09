defmodule GitFoil.Workflows.EncryptedAdd.Progress do
  @moduledoc """
  Behaviour for rendering progress while staging files concurrently.

  Implementations receive the total number of files on `start/2`, the number of
  files processed for each chunk through `advance/3`, and a final `finish/1`
  callback that should tidy up terminal output.
  """

  @typedoc "Implementation-defined progress state."
  @type state :: term()

  @callback start(total :: non_neg_integer(), options :: keyword()) :: state
  @callback advance(state, processed :: pos_integer(), context :: map()) :: state
  @callback finish(state) :: state
end
