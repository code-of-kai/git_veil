defmodule GitFoil.Ports.KeyStorage do
  @moduledoc """
  Port for key persistence and retrieval.

  **Responsibilities:**
  - Store/retrieve master keypair (Kyber1024 + classical)
  - Store/retrieve file-specific encryption keys
  - Generate new keypairs when needed

  **Security:**
  Keys should be stored encrypted at rest in production implementations.
  """

  alias GitFoil.Core.Types.{Keypair, EncryptionKey}

  @callback store_keypair(Keypair.t()) :: :ok | {:error, term()}
  @callback retrieve_keypair() :: {:ok, Keypair.t()} | {:error, :not_found} | {:error, term()}
  @callback generate_keypair() :: {:ok, Keypair.t()} | {:error, term()}

  @callback store_file_key(path :: String.t(), EncryptionKey.t()) ::
              :ok | {:error, term()}

  @callback retrieve_file_key(path :: String.t()) ::
              {:ok, EncryptionKey.t()} | {:error, :not_found} | {:error, term()}

  @callback delete_file_key(path :: String.t()) :: :ok | {:error, term()}
end
