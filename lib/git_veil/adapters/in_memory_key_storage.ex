defmodule GitVeil.Adapters.InMemoryKeyStorage do
  @moduledoc """
  In-memory key storage adapter for testing.

  Uses an Agent to store a keypair in memory. Data is lost when the process stops.

  **NOW WITH REAL POST-QUANTUM CRYPTOGRAPHY:**
  Uses pqclean NIF to generate Kyber1024 (ML-KEM-1024) keypairs.

  **For Testing Only** - Do not use in production (keys not persisted).
  """

  @behaviour GitVeil.Ports.KeyStorage

  use Agent

  alias GitVeil.Core.Types.Keypair

  @doc """
  Start the in-memory key storage agent.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{keypair: nil} end, name: name)
  end

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
  def save_keypair(keypair) do
    Agent.update(__MODULE__, fn state ->
      %{state | keypair: keypair}
    end)

    :ok
  end

  @impl true
  def load_keypair do
    case Agent.get(__MODULE__, fn state -> state.keypair end) do
      nil -> {:error, :not_initialized}
      keypair -> {:ok, keypair}
    end
  end

  @impl true
  def derive_master_key do
    case load_keypair() do
      {:ok, keypair} ->
        # Deterministic derivation: SHA-512(classical_secret || pq_secret)
        combined = keypair.classical_secret <> keypair.pq_secret
        master_key = :crypto.hash(:sha512, combined)
        {:ok, master_key}

      error ->
        error
    end
  end

  @impl true
  def initialized? do
    case Agent.get(__MODULE__, fn state -> state.keypair end) do
      nil -> false
      _ -> true
    end
  end
end
