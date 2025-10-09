defmodule GitFoil.Adapters.FileKeyStorage do
  @moduledoc """
  File-based key storage adapter for production use.

  Stores the master keypair in `.git/git_foil/master.key` using Erlang's
  external term format for serialization.

  **Post-Quantum Cryptography:**
  Uses pqclean NIF to generate Kyber1024 (ML-KEM-1024) keypairs.

  **No Process Dependencies:**
  This adapter uses pure file I/O without requiring supervision or Agent processes,
  making it suitable for Git filters (which run as standalone processes).

  **Security:**
  - Files stored with 0600 permissions (owner read/write only)
  - Keys stored in binary format
  - TODO: Add encryption-at-rest for master.key
  """

  @behaviour GitFoil.Ports.KeyStorage

  alias GitFoil.Core.Types.{Keypair, EncryptionKey}

  @key_dir ".git/git_foil"
  @key_file "master.key"

  @impl true
  def generate_keypair do
    # Generate REAL post-quantum keypair using pqclean NIF
    # Kyber1024 provides NIST Level 5 security
    {pq_public, pq_secret} = :pqclean_nif.kyber1024_keypair()

    # For now, use random bytes for classical keypair
    # TODO: Add X25519 classical keypair in future iteration
    classical_public = :crypto.strong_rand_bytes(32)
    classical_secret = :crypto.strong_rand_bytes(32)

    keypair = %Keypair{
      classical_public: classical_public,
      classical_secret: classical_secret,
      pq_public: pq_public,
      pq_secret: pq_secret
    }

    {:ok, keypair}
  end

  @impl true
  def store_keypair(keypair) do
    key_path = key_file_path()

    with :ok <- ensure_key_directory_exists(),
         serialized <- :erlang.term_to_binary(keypair),
         :ok <- File.write(key_path, serialized),
         :ok <- set_secure_permissions(key_path) do
      :ok
    else
      {:error, reason} -> {:error, "Failed to store keypair: #{inspect(reason)}"}
    end
  end

  @impl true
  def retrieve_keypair do
    key_path = key_file_path()

    case File.read(key_path) do
      {:ok, binary} ->
        keypair = :erlang.binary_to_term(binary)
        {:ok, keypair}

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, "Failed to read keypair: #{inspect(reason)}"}
    end
  end

  @impl true
  def store_file_key(_path, _key) do
    # Not implemented yet - reserved for file-specific key caching
    {:error, :not_implemented}
  end

  @impl true
  def retrieve_file_key(_path) do
    # Not implemented yet - reserved for file-specific key caching
    {:error, :not_found}
  end

  @impl true
  def delete_file_key(_path) do
    # Not implemented yet - reserved for file-specific key caching
    :ok
  end

  @doc """
  Derives the master encryption key from the stored keypair.

  This is a convenience function that combines retrieve_keypair/0
  with key derivation logic.
  """
  def derive_master_key do
    case retrieve_keypair() do
      {:ok, keypair} ->
        # Deterministic derivation: SHA-512(classical_secret || pq_secret)
        # Take first 32 bytes for 256-bit key
        combined = keypair.classical_secret <> keypair.pq_secret
        master_key_bytes = :crypto.hash(:sha512, combined) |> binary_part(0, 32)
        master_key = EncryptionKey.new(master_key_bytes)
        {:ok, master_key}

      {:error, :not_found} ->
        {:error, :not_initialized}

      error ->
        error
    end
  end

  @doc """
  Checks if GitFoil has been initialized (keypair exists).
  """
  def initialized? do
    File.exists?(key_file_path())
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp key_file_path do
    Path.join(@key_dir, @key_file)
  end

  defp ensure_key_directory_exists do
    case File.mkdir_p(@key_dir) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp set_secure_permissions(path) do
    # Set file permissions to 0600 (owner read/write only)
    case File.chmod(path, 0o600) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
