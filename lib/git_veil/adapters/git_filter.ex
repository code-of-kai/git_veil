defmodule GitVeil.Adapters.GitFilter do
  @moduledoc """
  Git clean/smudge filter adapter.

  **Git Filter Protocol:**
  - Clean: Encrypts plaintext when adding files to Git (git add)
  - Smudge: Decrypts ciphertext when checking out files (git checkout)

  **Integration:**
  Git calls this via configured filter commands:
  ```
  git config filter.gitveil.clean "git-veil clean %f"
  git config filter.gitveil.smudge "git-veil smudge %f"
  ```

  **Data Flow:**
  - Clean: stdin (plaintext) → encrypt → stdout (ciphertext)
  - Smudge: stdin (ciphertext) → decrypt → stdout (plaintext)

  **Error Handling:**
  - Encryption/decryption errors written to stderr
  - Git receives empty output on error (preserves original file)
  - Non-zero exit code signals failure to Git
  """

  @behaviour GitVeil.Ports.Filter

  alias GitVeil.Core.EncryptionEngine
  alias GitVeil.Adapters.{FileKeyStorage, OpenSSLCrypto}

  require Logger

  @impl true
  def clean(plaintext, file_path) when is_binary(plaintext) and is_binary(file_path) do
    with {:ok, master_key} <- load_master_key(),
         {:ok, encrypted_blob} <- encrypt_content(plaintext, master_key, file_path),
         serialized <- EncryptionEngine.serialize(encrypted_blob) do
      {:ok, serialized}
    else
      {:error, :not_initialized} ->
        {:error, "GitVeil not initialized - run 'git-veil init' first"}

      {:error, reason} ->
        {:error, "Encryption failed: #{inspect(reason)}"}
    end
  end

  @impl true
  def smudge(encrypted, file_path) when is_binary(encrypted) and is_binary(file_path) do
    with {:ok, master_key} <- load_master_key(),
         {:ok, blob} <- EncryptionEngine.deserialize(encrypted),
         {:ok, plaintext} <- decrypt_content(blob, master_key, file_path) do
      {:ok, plaintext}
    else
      {:error, :not_initialized} ->
        {:error, "GitVeil not initialized - run 'git-veil init' first"}

      {:error, :invalid_blob_format} ->
        # Not a GitVeil encrypted file - return as-is
        # This handles files that were committed before encryption was enabled
        {:ok, encrypted}

      {:error, reason} ->
        {:error, "Decryption failed: #{inspect(reason)}"}
    end
  end

  # Loads master encryption key from storage
  defp load_master_key do
    case FileKeyStorage.initialized?() do
      true ->
        FileKeyStorage.derive_master_key()

      false ->
        {:error, :not_initialized}
    end
  end

  # Encrypts plaintext using the full encryption pipeline
  defp encrypt_content(plaintext, master_key, file_path) do
    EncryptionEngine.encrypt(
      plaintext,
      master_key,
      OpenSSLCrypto,
      OpenSSLCrypto,
      OpenSSLCrypto,
      file_path
    )
  end

  # Decrypts encrypted blob using the full decryption pipeline
  defp decrypt_content(blob, master_key, file_path) do
    EncryptionEngine.decrypt(
      blob,
      master_key,
      OpenSSLCrypto,
      OpenSSLCrypto,
      OpenSSLCrypto,
      file_path
    )
  end

  @doc """
  Processes a filter operation (clean or smudge) with proper I/O handling.

  This is the main entry point called by the CLI. It handles:
  - Reading from stdin
  - Calling the appropriate filter operation
  - Writing to stdout
  - Error logging to stderr

  Returns {:ok, exit_code} where exit_code is 0 for success, 1 for failure.
  """
  def process(operation, file_path, opts \\ [])
      when operation in [:clean, :smudge] and is_binary(file_path) do
    input_device = Keyword.get(opts, :input, :stdio)
    output_device = Keyword.get(opts, :output, :stdio)

    # Read entire input (Git provides complete file content)
    input = IO.binread(input_device, :eof)

    result =
      case operation do
        :clean -> clean(input, file_path)
        :smudge -> smudge(input, file_path)
      end

    case result do
      {:ok, output} ->
        # Write encrypted/decrypted output to stdout
        IO.binwrite(output_device, output)
        {:ok, 0}

      {:error, reason} ->
        # Log error to stderr, return empty output to Git
        IO.puts(:stderr, "GitVeil #{operation} error: #{reason}")
        {:error, 1}
    end
  end
end
