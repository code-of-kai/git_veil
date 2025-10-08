defmodule GitVeil.Workflows.EncryptedAdd do
  @moduledoc """
  Orchestrates parallel `git add` executions so Git clean filters can encrypt
  files efficiently while keeping the hexagonal boundary intact.

  The workflow accepts a list of paths, stages them using Git with back-pressure
  via `Task.async_stream/3`, emits telemetry, and reports rich error metadata
  without exposing callers to the underlying command runner.
  """

  alias GitVeil.Workflows.EncryptedAdd.Progress.{Noop, ProgressBar}

  @typedoc "Callback for staging a batch of files."
  @type command_runner ::
          ([String.t()], keyword() ->
             {:ok, %{optional(atom()) => term()}} | {:error, %{optional(atom()) => term()}})

  @default_progress ProgressBar
  @default_batch_size 1
  @default_timeout :infinity
  @default_telemetry_prefix [:git_veil, :encrypted_add]
  @default_index_lock_retries 25
  @default_retry_backoff_ms 50

  @doc """
  Stage the provided `paths`, returning details about the work performed.

  ## Options

    * `:max_concurrency` — maximum number of concurrent Git invocations.
      Defaults to the number of online schedulers.
    * `:batch_size` — number of files passed to each Git invocation. Defaults
      to 1 (one process per file).
    * `:timeout` — task timeout in milliseconds. Defaults to `:infinity`.
    * `:command_runner` — function used to execute Git. Defaults to a wrapper
      around `Rambo.run/3`.
    * `:command_opts` — additional options forwarded to the command runner.
    * `:progress_adapter` — module that implements
      `GitVeil.Workflows.EncryptedAdd.Progress`. Defaults to a terminal
      progress bar; pass `GitVeil.Workflows.EncryptedAdd.Progress.Noop` to
      disable visuals.
    * `:progress_opts` — options forwarded to the progress adapter.
    * `:telemetry_prefix` — telemetry event prefix, defaults to
      `[:git_veil, :encrypted_add]`.
  """
  @spec add_files([String.t()], keyword()) ::
          {:ok, %{processed: non_neg_integer(), batches: non_neg_integer(), total: non_neg_integer()}}
          | {:error, atom(), map()}
  def add_files(paths, opts \\ [])

  def add_files(paths, opts) when is_list(paths) do
    options = build_options(opts)
    sanitized_paths = normalize_paths(paths)
    total = length(sanitized_paths)

    metadata = %{
      total: total,
      max_concurrency: options.max_concurrency,
      batch_size: options.batch_size
    }

    started_at = System.monotonic_time(:native)
    dispatch_telemetry(options.telemetry_prefix, :start, %{total: total}, metadata)

    result =
      if total == 0 do
        {:ok, %{processed: 0, batches: 0, total: 0}}
      else
        run_pipeline(sanitized_paths, total, options)
      end

    duration =
      System.monotonic_time(:native)
      |> Kernel.-(started_at)
      |> System.convert_time_unit(:native, :microsecond)

    dispatch_telemetry(
      options.telemetry_prefix,
      :stop,
      %{duration: duration},
      Map.put(metadata, :status, telemetry_status(result))
    )

    result
  end

  def add_files(_invalid, _opts), do: {:error, :invalid_paths, %{failed_paths: []}}

  # ----------------------------------------------------------------------------
  # Pipeline
  # ----------------------------------------------------------------------------

  defp run_pipeline(paths, total, options) do
    progress_state = start_progress(options, total)

    initial_stats = %{processed: 0, batches: 0}

    reducer = fn
      {:ok, {:ok, chunk_result}}, {:ok, stats, progress} ->
        stats = increment_stats(stats, chunk_result)
        progress = advance_progress(options, progress, chunk_result)
        {:cont, {:ok, stats, progress}}

      {:ok, {:error, failure}}, {:ok, stats, progress} ->
        failure = enrich_failure(failure, stats, total)
        {:halt, {{:error, failure}, stats, progress}}

      {:exit, reason}, {:ok, stats, progress} ->
        failure = enrich_failure(%{reason: :task_exit, exit: reason, failed_paths: []}, stats, total)
        {:halt, {{:error, failure}, stats, progress}}
    end

    result =
      paths
      |> Enum.chunk_every(options.batch_size)
      |> Task.async_stream(
        &execute_chunk(&1, options),
        max_concurrency: options.max_concurrency,
        timeout: options.timeout,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.reduce_while({:ok, initial_stats, progress_state}, reducer)

    case result do
      {:ok, stats, progress} ->
        finish_progress(options, progress, success: stats.processed == total)
        {:ok, Map.put(stats, :total, total)}

      {{:error, failure}, stats, progress} ->
        finish_progress(options, progress, success: false)
        {:error, normalize_reason(failure), failure |> Map.put(:batches, stats.batches)}
    end
  end

  defp execute_chunk([], _options), do: {:ok, %{chunk: [], count: 0, output: %{}}}

  defp execute_chunk(chunk, options) do
    do_execute_chunk(chunk, options, 0)
  end

  defp do_execute_chunk(chunk, options, attempt) do
    case options.command_runner.(chunk, options.command_opts) do
      {:ok, command_result} ->
        {:ok,
         %{
           chunk: chunk,
           count: length(chunk),
           output: command_result
         }}

      {:error, failure} ->
        if index_lock_conflict?(failure) and retry_allowed?(attempt, options.index_lock_retries) do
          wait_ms = compute_backoff(options.retry_backoff_ms, attempt)
          jitter = rem(:erlang.unique_integer([:positive]), 17)
          Process.sleep(wait_ms + jitter)
          do_execute_chunk(chunk, options, attempt + 1)
        else
          {:error,
           failure
           |> Map.put_new(:failed_paths, chunk)
           |> Map.put_new(:chunk, chunk)
           |> Map.put_new(:stdout, Map.get(failure, :stdout, ""))
           |> Map.put_new(:stderr, Map.get(failure, :stderr, ""))
           |> Map.put_new(:exit_status, Map.get(failure, :exit_status))
           |> Map.put_new(:reason, Map.get(failure, :reason, :command_failed))}
        end
    end
  rescue
    exception ->
      {:error,
       %{
         reason: :exception,
         exception: exception,
         stacktrace: __STACKTRACE__,
         failed_paths: chunk
       }}
  end

  # ----------------------------------------------------------------------------
  # Progress helpers
  # ----------------------------------------------------------------------------

  defp start_progress(%{progress_module: nil}, _total), do: nil
  defp start_progress(_options, total) when total <= 0, do: nil

  defp start_progress(%{progress_module: module, progress_opts: opts}, total) do
    module.start(total, opts)
  end

  defp advance_progress(%{progress_module: nil}, state, _chunk_result), do: state
  defp advance_progress(_options, nil, _chunk_result), do: nil

  defp advance_progress(%{progress_module: module}, state, %{count: processed} = context) do
    module.advance(state, processed, context)
  end

  defp finish_progress(%{progress_module: nil}, _state, _opts), do: :ok
  defp finish_progress(_options, nil, _opts), do: :ok
  defp finish_progress(%{progress_module: module}, state, _opts), do: module.finish(state)

  # ----------------------------------------------------------------------------
  # Option parsing
  # ----------------------------------------------------------------------------

  defp build_options(opts) when is_list(opts) do
    max_concurrency =
      opts
      |> Keyword.get(:max_concurrency, System.schedulers_online())
      |> normalize_positive_integer(System.schedulers_online())

    batch_size =
      opts
      |> Keyword.get(:batch_size, @default_batch_size)
      |> normalize_positive_integer(@default_batch_size)

    progress_module =
      opts
      |> Keyword.get(:progress_adapter, @default_progress)
      |> normalize_progress_module()

    %{
      max_concurrency: max_concurrency,
      batch_size: batch_size,
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      command_runner: Keyword.get(opts, :command_runner, &run_git_add/2),
      command_opts: build_command_opts(opts),
      progress_module: progress_module,
      progress_opts: Keyword.get(opts, :progress_opts, []),
      telemetry_prefix: Keyword.get(opts, :telemetry_prefix, @default_telemetry_prefix),
      index_lock_retries:
        opts
        |> Keyword.get(:index_lock_retries, @default_index_lock_retries)
        |> normalize_retry_limit(),
      retry_backoff_ms:
        Keyword.get(opts, :retry_backoff_ms, @default_retry_backoff_ms)
        |> max(0)
    }
  end

  defp build_command_opts(opts) do
    opts
    |> Keyword.get(:command_opts, [])
    |> Keyword.take([:cd, :env])
  end

  defp normalize_progress_module(:none), do: nil
  defp normalize_progress_module(nil), do: nil
  defp normalize_progress_module(Noop = module), do: module
  defp normalize_progress_module(module) when is_atom(module), do: module
  defp normalize_progress_module(_invalid), do: nil

  defp normalize_positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp normalize_positive_integer(value, _default) when is_float(value) and value > 0 do
    value
    |> Float.ceil()
    |> trunc()
  end

  defp normalize_positive_integer(_value, default), do: default

  # ----------------------------------------------------------------------------
  # Stats / failure enrichment
  # ----------------------------------------------------------------------------

  defp increment_stats(stats, %{count: count}) do
    stats
    |> Map.update!(:processed, &(&1 + count))
    |> Map.update!(:batches, &(&1 + 1))
  end

  defp enrich_failure(failure, stats, total) do
    failure
    |> Map.put(:processed, stats.processed)
    |> Map.put(:remaining, max(total - stats.processed, 0))
    |> Map.put(:total, total)
    |> Map.update(:failed_paths, [], fn paths ->
      paths |> List.wrap() |> Enum.map(&to_string/1)
    end)
  end

  defp normalize_reason(%{reason: reason}) when is_atom(reason), do: reason
  defp normalize_reason(_failure), do: :command_failed

  # ----------------------------------------------------------------------------
  # Command runner
  # ----------------------------------------------------------------------------

  defp run_git_add([], _opts), do: {:ok, %{stdout: "", stderr: "", exit_status: 0}}

  defp run_git_add(paths, opts) do
    args = ["add", "--"] ++ paths
    system_opts = Keyword.merge(opts, [stderr_to_stdout: true])

    case System.cmd("git", args, system_opts) do
      {output, 0} ->
        {:ok, %{stdout: output, stderr: "", exit_status: 0}}

      {output, status} ->
        {:error,
         %{
           reason: :non_zero_exit,
           exit_status: status,
           stdout: "",
           stderr: output
         }}
    end
  rescue
    exception ->
      {:error,
       %{
         reason: :command_error,
         exception: exception,
         message: Exception.message(exception),
         failed_paths: paths
       }}
  end

  # ----------------------------------------------------------------------------
  # Utilities
  # ----------------------------------------------------------------------------

  defp normalize_paths(paths) do
    paths
    |> Enum.map(&to_string/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.uniq()
  end

  defp telemetry_status({:ok, _}), do: :ok
  defp telemetry_status({:error, _, _}), do: :error
  defp telemetry_status(_), do: :error

  defp dispatch_telemetry(prefix, event, measurements, metadata) do
    _ = Application.ensure_all_started(:telemetry)
    :telemetry.execute(prefix ++ [event], measurements, metadata)
  rescue
    _ -> :ok
  end

  defp index_lock_conflict?(failure) do
    message =
      failure
      |> Map.get(:stderr, "")
      |> Kernel.<>(Map.get(failure, :stdout, ""))
      |> String.downcase()

    String.contains?(message, "index.lock")
  end

  defp compute_backoff(base_ms, _attempt) when base_ms <= 0, do: 0

  defp compute_backoff(base_ms, attempt) do
    factor = :math.pow(2, attempt)
    round(base_ms * factor)
  end

  defp retry_allowed?(_attempt, :infinity), do: true
  defp retry_allowed?(attempt, limit) when attempt < limit, do: true
  defp retry_allowed?(_attempt, _limit), do: false

  defp normalize_retry_limit(:infinity), do: :infinity

  defp normalize_retry_limit(value) when is_integer(value) and value >= 0 do
    value
  end

  defp normalize_retry_limit(_), do: @default_index_lock_retries
end
