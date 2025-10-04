defmodule GitVeil.Ports.Filter do
  @moduledoc """
  Port for Git filter integration.

  **Git Clean/Smudge:**
  - Clean: Encrypts file content before storing in Git
  - Smudge: Decrypts file content when checking out

  Implementations handle stdio communication with Git.
  """

  @callback clean(plaintext :: binary(), file_path :: String.t()) ::
              {:ok, encrypted :: binary()} | {:error, term()}

  @callback smudge(encrypted :: binary(), file_path :: String.t()) ::
              {:ok, plaintext :: binary()} | {:error, term()}
end
