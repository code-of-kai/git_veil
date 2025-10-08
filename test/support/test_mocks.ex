defmodule GitVeil.TestMocks do
  @moduledoc """
  Shared mock implementations for testing git-veil commands.

  These mocks use the process dictionary for stateful mocking,
  allowing tests to configure behavior on a per-test basis.
  """

  defmodule MockGit do
    @moduledoc """
    Mock Git repository - implements GitVeil.Ports.Repository
    """
    @behaviour GitVeil.Ports.Repository

    def configure(opts \\ []) do
      Process.put(:mock_git_config, opts)
    end

    @impl true
    def verify_repository do
      get_mock(:verify_repository, fn -> {:ok, ".git"} end).()
    end

    @impl true
    def init_repository do
      get_mock(:init_repository, fn -> {:ok, "Initialized"} end).()
    end

    @impl true
    def get_config(key) do
      get_mock(:get_config, fn _k -> {:error, :not_found} end).(key)
    end

    @impl true
    def set_config(key, value) do
      get_mock(:set_config, fn _k, _v -> :ok end).(key, value)
    end

    @impl true
    def list_files do
      get_mock(:list_files, fn -> {:ok, []} end).()
    end

    @impl true
    def list_all_files do
      get_mock(:list_all_files, fn -> {:ok, []} end).()
    end

    @impl true
    def check_attr(attr, file) do
      get_mock(:check_attr, fn _a, _f -> {:ok, "unspecified"} end).(attr, file)
    end

    @impl true
    def check_attr_batch(attr, files) do
      get_mock(:check_attr_batch, fn _a, files ->
        {:ok, Enum.map(files, fn file -> {file, "unspecified"} end)}
      end).(attr, files)
    end

    @impl true
    def add_file(file) do
      get_mock(:add_file, fn _f -> :ok end).(file)
    end

    @impl true
    def repository_root do
      get_mock(:repository_root, fn -> {:ok, "/test/repo"} end).()
    end

    @impl true
    def config_exists?(key) do
      get_mock(:config_exists?, fn _k -> false end).(key)
    end

    defp get_mock(key, default) do
      config = Process.get(:mock_git_config, [])
      Keyword.get(config, key, default)
    end
  end

  defmodule MockTerminal do
    @moduledoc """
    Mock Terminal - implements GitVeil.Ports.Terminal
    """

    def configure(opts \\ []) do
      Process.put(:mock_terminal_config, opts)

      if inputs = Keyword.get(opts, :inputs) do
        Process.put(:mock_terminal_inputs, inputs)
      end
    end

    def safe_gets(_prompt) do
      case Process.get(:mock_terminal_inputs, []) do
        [input | rest] ->
          Process.put(:mock_terminal_inputs, rest)
          input
        [] ->
          ""
      end
    end

    def with_spinner(label, work_fn, opts \\ []) do
      default_fn = fn _l, wf, _o -> wf.() end
      mock_fn = get_mock(:with_spinner, default_fn)

      case :erlang.fun_info(mock_fn)[:arity] do
        2 -> mock_fn.(label, work_fn)
        3 -> mock_fn.(label, work_fn, opts)
        _ -> default_fn.(label, work_fn, opts)
      end
    end

    def progress_bar(current, total, width \\ 20) do
      get_mock(:progress_bar, fn _c, _t, _w -> "████████" end).(current, total, width)
    end

    def format_number(number) do
      get_mock(:format_number, fn n -> Integer.to_string(n) end).(number)
    end

    def pluralize(word, count) do
      get_mock(:pluralize, fn w, 1 -> w; w, _ -> w <> "s" end).(word, count)
    end

    defp get_mock(key, default) do
      config = Process.get(:mock_terminal_config, [])
      Keyword.get(config, key, default)
    end
  end
end
