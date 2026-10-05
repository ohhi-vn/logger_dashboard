defmodule LoggerDashboard.BackgroundTaskConfig do
  @moduledoc """
  Durable storage for the configuration of the dashboard's background tasks.

  A background task that an operator can configure — scheduled retention today —
  needs somewhere to keep what they chose, somewhere that outlives the process that
  applied it. That is here: one embedded key-value store, on disk, in a directory the
  operator controls.

  ## What the store knows, and what it does not

  It knows how to read, write, and clear a value under a task's own key. It does not
  know what any value means, whether it is valid, or what to do without one. Each task
  keeps its own vocabulary and its own validation, and interprets what it reads. A
  second background task is a second key, not a second subsystem.

  The namespace is the `{task, key}` pair the store builds internally. One task's value
  is unreachable as another's, which is what makes it safe for tasks to share the file
  without agreeing on a schema.

  ## Why the failures are values rather than exceptions

  Every operation answers `{:ok, result}` or `{:error, reason}`, and none of them
  raises. A store that cannot be opened is a condition the dashboard reports and works
  around, not one it refuses to start over: this is a log viewer, and failing to read
  a retention setting is no reason to stop serving `/logs`.

  So the process stays alive with no database behind it, every operation answers
  `{:error, reason}`, and tasks fall back to their configured defaults. The failure is
  logged at startup and on every failed operation, because the alternative — a store
  that silently looks empty — is how an operator's saved policy stops applying with
  nobody noticing.

  Startup failure is contained here rather than by letting the store child crash,
  because a persistence problem should not become an availability problem.

  ## Where the file lives

  `task_config_dir`, set per environment: `tmp/dev` in development, `tmp/test` under
  test, and `TASK_CONFIG_DIR` in a release, defaulting to a directory beside the
  release. The store creates the directory if it is missing, so nothing has to exist
  before the first boot. An unwritable path degrades rather than failing, per above.

  ## One process, one directory

  The store holds a single `CubDB` process, started here and owned by the application
  supervisor. CUB allows exactly one process per data directory, so a second instance
  is a bug rather than a choice — which is also why nothing else in the system starts
  one of its own. Tests that need an isolated store start this module under their own
  name with their own directory, and those directories are the only other ones allowed
  to exist.
  """

  use GenServer

  require Logger

  @name __MODULE__

  @typedoc "A background task, named by the module that owns its configuration."
  @type task :: module()

  @type key :: term()
  @type value :: term()
  @type reason :: term()

  # ## Client

  @doc """
  Starts the store, as a child of a supervisor.

  `:name` is the registered name the client functions address, and `:data_dir`
  overrides the configured directory. Both exist for tests: production gets one
  store, on one directory, from configuration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  @doc """
  The value stored for `task` under `key`, or `nil` when there is none.

  `{:ok, nil}` means the store answered and holds nothing for that task; `{:error,
  reason}` means the store could not answer. The two are not interchangeable — a
  caller that treats a failed read as an empty store would overwrite whatever is
  really there.
  """
  @spec get(task(), key(), GenServer.server()) :: {:ok, value() | nil} | {:error, reason()}
  def get(task, key, server \\ @name) do
    GenServer.call(server, {:get, namespaced(task, key)})
  end

  @doc "Stores `value` for `task` under `key`, replacing anything already there."
  @spec put(task(), key(), value(), GenServer.server()) :: :ok | {:error, reason()}
  def put(task, key, value, server \\ @name) do
    case GenServer.call(server, {:put, namespaced(task, key), value}) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Removes whatever `task` has stored under `key`, if anything."
  @spec delete(task(), key(), GenServer.server()) :: :ok | {:error, reason()}
  def delete(task, key, server \\ @name) do
    case GenServer.call(server, {:delete, namespaced(task, key)}) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Whether the store can be used, and where it is looking.

  `{:ok, dir}` when it is open, `{:error, reason}` when it is not. This exists so a
  page showing a task's configuration can say that the value it is showing is not
  being persisted, rather than implying that it is.
  """
  @spec status(GenServer.server()) :: {:ok, Path.t()} | {:error, reason()}
  def status(server \\ @name), do: GenServer.call(server, :status)

  @doc """
  The directory this store uses, given an explicit override.

  Falling back through an explicit `:data_dir`, then `task_config_dir`, then a path
  beside the release. The last step keeps a release started without `TASK_CONFIG_DIR`
  working, at the cost of a directory nobody named — which is why the compose stack
  and the image documentation both point at an explicit value.
  """
  @spec dir(Path.t() | nil) :: Path.t()
  def dir(nil) do
    Application.get_env(:logger_dashboard, :task_config_dir) ||
      Path.join(File.cwd!(), "task_config")
  end

  def dir(explicit) when is_binary(explicit), do: explicit

  # A task's key is qualified by the task, so two tasks sharing this file cannot read,
  # write, or clear each other's values.
  defp namespaced(task, key), do: {task, key}

  # ## Callbacks

  @impl GenServer
  def init(opts) do
    # Trapping exits turns the store process's death into a message rather than an
    # exit signal, so it can be handled as a reason to stop and be restarted by the
    # supervisor — which retries the open — instead of taking this process with it.
    # It is also what makes `CubDB.start_link/1` answer `{:error, reason}` rather than
    # exiting when the directory cannot be opened.
    Process.flag(:trap_exit, true)

    target = dir(Keyword.get(opts, :data_dir))

    case CubDB.start_link(data_dir: target) do
      {:ok, db} ->
        {:ok, %{dir: target, db: db, reason: nil}}

      {:error, reason} ->
        degraded(target, reason)
    end
  end

  @impl GenServer
  def handle_call({:get, key}, _from, state) do
    {:reply, attempt(state, &CubDB.get(&1, key)), state}
  end

  def handle_call({:put, key, value}, _from, state) do
    {:reply, attempt(state, &CubDB.put(&1, key, value)), state}
  end

  def handle_call({:delete, key}, _from, state) do
    {:reply, attempt(state, &CubDB.delete(&1, key)), state}
  end

  def handle_call(:status, _from, %{db: nil} = state) do
    {:reply, {:error, state.reason}, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, {:ok, state.dir}, state}
  end

  @impl GenServer
  def handle_info({:EXIT, _db, reason}, state) do
    # The store process is gone. Stopping lets the supervisor start a new one, which
    # retries the open — the alternative is a live process reporting a database that
    # no longer exists.
    {:stop, reason, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # ## Internals

  # Starting without a database behind it. Logged here rather than only on each
  # operation, so the reason appears once at boot even if nothing ever asks again.
  defp degraded(target, reason) do
    Logger.error(
      "[task config] store unavailable at #{target}: #{inspect(reason)}; " <>
        "background tasks use their configured defaults and nothing will be persisted"
    )

    {:ok, %{dir: target, db: nil, reason: reason}}
  end

  defp attempt(%{db: nil} = state, _fun) do
    Logger.error("[task config] cannot reach the store at #{state.dir}: #{inspect(state.reason)}")

    {:error, state.reason}
  end

  defp attempt(%{db: db}, fun) do
    case safe(fun, db) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        # A corrupt file or a vanished directory reaches here. It is reported every
        # time rather than cached, so recovering by fixing the path needs no restart.
        Logger.error("[task config] store operation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # CUB's own failures reach this process as raises rather than as return values, and
  # a raised error out of a `call` would take the caller down instead of answering it.
  defp safe(fun, db) do
    {:ok, fun.(db)}
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, Exception.normalize(kind, reason, __STACKTRACE__)}
  end
end
