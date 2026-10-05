defmodule LoggerDashboard.Retention.Scheduler do
  @moduledoc """
  Applies the retention policy unattended, and owns the policy in force.

  This is the project's first long-lived process that is not a Phoenix request, and
  it is the only thing that knows which retention policy is running. The policy itself
  is kept in `LoggerDashboard.BackgroundTaskConfig`, so an operator's choice survives
  a restart; this process holds the loaded value, the timer, and nothing else.

  ## Why loading happens here

  `init/1` asks the store what is stored, validates it with
  `LoggerDashboard.Retention.Policy`, and falls back to the configured default if
  there is nothing usable. Every later read comes from this process rather than from
  the store, because the timer is derived from the policy and a schedule whose
  subject could change underneath it would be a schedule nobody is tracking.

  A stored policy this process cannot interpret is treated as though nothing were
  stored — the configured default governs — while the stored value is left alone and
  the reason is reported. Rewriting it would destroy the operator's only copy of a
  policy that a vocabulary change made invalid, and silently discarding it would look
  identical to losing it.

  ## Why startup is inert

  `init/1` schedules the next occurrence and returns. It never runs the policy,
  however long it has been down. Converting a restart into a delete would mean a
  crash-looping dashboard deleted on every boot, with nobody watching; refusing
  to catch up makes the failure mode "the schedule slipped", which is visible and
  harmless.

  This matters more now that the policy is durable: after the first save there is
  always something to run, so a catch-up implementation would have something to catch
  up with on every single boot.

  ## The schedule

  Each occurrence is computed from the wall clock and the policy's run time, so
  it is recomputed after every fire rather than slept toward. A fixed interval
  would drift against the clock — and after a clock jump, would keep drifting.
  Occurrences are resolved in UTC, matching every other time in this project.

  ## The delete

  A run composes the existing age-cutoff path — `Filter.presets(:age)` →
  `Filter.parse/1` → `Prune.run/2` — rather than issuing its own SQL. Retention
  therefore inherits bound-parameter handling and the meaning of "older than N"
  from the manual path instead of developing a second opinion about either. Every
  run is logged, since this is the only destructive operation in the system with
  no human present.
  """

  use GenServer

  require Logger

  alias LoggerDashboard.BackgroundTaskConfig
  alias LoggerDashboard.Logs.Filter
  alias LoggerDashboard.Logs.Prune
  alias LoggerDashboard.Retention.Policy

  @name __MODULE__

  # The store key this process reads and writes. A task's own key in a store shared
  # with other background tasks, so retention's policy cannot collide with anything
  # else's — and nothing else in the system writes it.
  @key :policy

  # Upper bound on how far ahead a single occurrence may be scheduled. A policy
  # whose clock is unreachable cannot be expressed (the hour is validated), so
  # this only guards against an arithmetic surprise turning into a decades-long
  # timer.
  @max_lookahead_ms 366 * 24 * 60 * 60 * 1000

  @typedoc """
  What this process knows about the policy in force.

  `stored_error` and `store_error` are what the prune page has to be able to say:
  a policy that is not in effect because it could not be read, and a store that
  could not be read at all. Both are `nil` in the ordinary case.
  """
  @type report :: %{
          policy: Policy.t(),
          source: Policy.source(),
          stored_error: nil | String.t(),
          store_error: nil | term()
        }

  @type state :: %{store: GenServer.server(), report: report(), timer: reference() | nil}

  # ## Client

  @doc """
  Starts the scheduler under `name`.

  `:store` names the `LoggerDashboard.BackgroundTaskConfig` this scheduler reads its
  policy from and writes it to, defaulting to the application's own. A second
  scheduler under a different `:name` but the same store would be a second schedule
  for one policy, which is why nothing but tests does that.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  @doc """
  The policy in force, which layer supplied it, and anything to report about it.

  `stored_error` is set when a policy is stored that this process cannot interpret,
  so the policy in force is the configured default while the stored value sits there
  unused. `store_error` is set when the store could not be read, which means nothing
  can be persisted and no stored policy can be known.
  """
  @spec effective_policy(GenServer.server()) :: {:ok, report()}
  def effective_policy(server \\ @name), do: GenServer.call(server, :effective_policy)

  @doc """
  Store `policy` and make it the policy in force, or remove the stored policy with
  `nil`.

  Never writes the configured default: a stored policy lives in the store and
  nowhere else. Returns `{:error, reason}` without changing anything when the store
  cannot be written — an edit that could not be persisted must not arm a schedule
  that a restart would undo.
  """
  @spec set_override(Policy.t() | nil, GenServer.server()) :: :ok | {:error, term()}
  def set_override(policy, server \\ @name)

  def set_override(nil, server), do: clear_override(server)

  def set_override(%Policy{} = policy, server),
    do: GenServer.call(server, {:set_override, policy})

  @doc """
  Remove the stored policy, returning to the configured default.

  For this run and every later one: the value is deleted rather than ignored.
  """
  @spec clear_override(GenServer.server()) :: :ok | {:error, term()}
  def clear_override(server \\ @name), do: GenServer.call(server, :clear_override)

  @doc """
  Re-read the stored policy and reschedule, without a restart.

  The store reports failures rather than caching them, so a store that recovers — a
  directory fixed, a file repaired — would otherwise leave this process running a
  stale policy and the page showing a stale error until the next deploy. This is what
  makes that recovery mean anything.
  """
  @spec reload(GenServer.server()) :: {:ok, report()}
  def reload(server \\ @name), do: GenServer.call(server, :reload)

  @doc """
  Run the policy now, as though its scheduled time had arrived.

  Exists for the confirmation step's benefit and for tests. It dispatches the same
  delete the timer would, so a manual trigger cannot behave differently from a
  scheduled one.
  """
  @spec run_now(GenServer.server()) :: {:ok, String.t()} | {:error, String.t()}
  def run_now(server \\ @name), do: GenServer.call(server, :run_now, :infinity)

  @doc """
  Milliseconds until `policy` would next run, or `:none` when it is disabled.

  Pure, like `next_occurrence/2`, so the schedule can be checked without asking a
  process and the page can show a countdown from the same arithmetic the timer
  uses.
  """
  @spec time_until_next(Policy.t()) :: pos_integer() | :none
  def time_until_next(%Policy{enabled: false}), do: :none

  def time_until_next(%Policy{} = policy) do
    now = DateTime.utc_now()

    DateTime.diff(next_occurrence(policy, now), now, :millisecond)
    |> max(0)
    |> min(@max_lookahead_ms)
  end

  @doc """
  When the policy would next run, given `now`.

  Pure, so the schedule is testable without waiting for a real clock. Always
  returns a strictly future instant: an occurrence at or before `now` is the one
  just gone, and the next one is a day out.
  """
  @spec next_occurrence(Policy.t(), DateTime.t()) :: DateTime.t()
  def next_occurrence(%Policy{run_at: {clock, _zone}} = _policy, %DateTime{} = now) do
    {hour, minute} = split_clock(clock)

    today = %{now | hour: hour, minute: minute, second: 0, microsecond: {0, 0}}

    if DateTime.compare(today, now) != :gt do
      DateTime.add(today, 1, :day)
    else
      today
    end
  end

  @doc """
  A filter for the policy's retained age, as of `now`.

  The composition point: an age preset resolves to a cutoff through the same
  `Filter` path a manual cutoff uses, so the two cannot disagree about what
  "older than 7 days" means.

  The cutoff is carried as an explicit `to` rather than left to a preset id. A
  preset would be re-resolved against the clock at delete time and could select a
  different range than the one this resolved — and than the one the run logs.
  """
  @spec retention_filter(Policy.t(), DateTime.t()) :: {:ok, Filter.t()} | {:error, String.t()}
  def retention_filter(%Policy{keep: keep}, %DateTime{} = now) do
    with {:ok, {_from, to}} <- Filter.resolve_preset(Policy.preset_id(keep), now) do
      Filter.parse(%{"to" => iso(to)})
    end
  end

  # ## Callbacks

  @impl GenServer
  def init(opts) do
    # Deliberately inert: load the policy, schedule the next occurrence, and return.
    # No delete runs here, whatever the downtime was.
    store = Keyword.get(opts, :store, BackgroundTaskConfig)

    {:ok, schedule(%{store: store, report: load(store), timer: nil})}
  end

  @impl GenServer
  def handle_call(:effective_policy, _from, state) do
    {:reply, {:ok, state.report}, state}
  end

  def handle_call({:set_override, policy}, _from, state) do
    case BackgroundTaskConfig.put(Policy, @key, Policy.to_params(policy), state.store) do
      :ok ->
        # Stored before scheduled, so the schedule always corresponds to something
        # that exists. The reverse order would arm a policy a restart could lose.
        report = %{policy: policy, source: :stored, stored_error: nil, store_error: nil}

        {:reply, :ok, schedule(%{state | report: report})}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:clear_override, _from, state) do
    case BackgroundTaskConfig.delete(Policy, @key, state.store) do
      :ok ->
        {:reply, :ok, schedule(%{state | report: from_configured(nil)})}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:reload, _from, state) do
    state = %{state | report: load(state.store)}

    {:reply, {:ok, state.report}, schedule(state)}
  end

  def handle_call(:run_now, _from, state) do
    # The timer is untouched: a manual trigger is the same delete at a different
    # moment, not a reschedule.
    {:reply, dispatch(state.report.policy), state}
  end

  @impl GenServer
  def handle_info(:run, state) do
    dispatch(state.report.policy)

    # Recomputed from the clock rather than advanced by one day, so a slow run or
    # a clock jump cannot leave the schedule permanently behind.
    {:noreply, schedule(%{state | timer: nil})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # ## Internals

  # The policy in force at boot: whatever is stored and usable, else the configured
  # default, with the reason recorded either way.
  defp load(store) do
    case BackgroundTaskConfig.get(Policy, @key, store) do
      {:ok, nil} ->
        from_configured(nil)

      {:ok, params} ->
        from_stored(params)

      {:error, reason} ->
        Logger.error(
          "[retention] could not read the stored policy: #{inspect(reason)}; " <>
            "using the configured policy and saving nothing"
        )

        from_configured(reason)
    end
  end

  defp from_stored(params) when is_map(params) do
    # The same validator the form uses, so a stored policy and a submitted one cannot
    # disagree about what is a policy. Reused rather than duplicated for that reason:
    # an unusable retained age must never reach `Filter.resolve_preset/2` at delete
    # time.
    case Policy.build(params) do
      {:ok, policy} ->
        %{policy: policy, source: :stored, stored_error: nil, store_error: nil}

      {:error, reason} ->
        Logger.error(
          "[retention] the stored policy is not in effect: #{reason}; " <>
            "using the configured policy and leaving the stored value in place"
        )

        from_configured(nil, reason)
    end
  end

  defp from_stored(other) do
    from_configured(
      nil,
      "the stored policy is #{inspect(other)}, which is not a policy"
    )
  end

  defp from_configured(store_error, stored_error \\ nil) do
    %{
      policy: Policy.configured(),
      source: :configured,
      stored_error: stored_error,
      store_error: store_error
    }
  end

  defp schedule(state) do
    cancel(state)

    case state.report.policy do
      %Policy{enabled: true} = policy ->
        timer = Process.send_after(self(), :run, time_until_next(policy))
        %{state | timer: timer}

      %Policy{enabled: false} ->
        # Disarmed: no timer at all, so there is nothing to fire and nothing to
        # catch up on a later restart.
        %{state | timer: nil}
    end
  end

  defp cancel(%{timer: nil}), do: :ok

  defp cancel(%{timer: timer}) do
    Process.cancel_timer(timer)
    :ok
  end

  # The whole delete path, in three steps that already existed: resolve the age to
  # a cutoff through `Filter`, then hand it to `Prune.run/2`. No SQL is built here.
  defp dispatch(%Policy{} = policy) do
    now = DateTime.utc_now()

    with {:ok, filter} <- retention_filter(policy, now),
         # `:all` is retention's only scope: a per-node schedule would be a
         # fleet-wide policy in a place with no notion of a fleet.
         {:ok, message} <- Prune.run(filter, :all) do
      Logger.info("[retention] unattended prune: #{Policy.describe(policy)}; #{message}")
      {:ok, message}
    else
      {:error, reason} ->
        # A failed unattended run records why and is never reported as a success.
        # Nothing retries on its own: a broken schedule that keeps retrying would
        # keep dispatching deletes an operator never sees.
        Logger.error(
          "[retention] unattended prune failed for #{Policy.describe(policy)}: " <>
            inspect(reason)
        )

        {:error, reason}
    end
  end

  defp split_clock(clock) do
    [hour, minute] = String.split(clock, ":", parts: 2)

    {String.to_integer(hour), String.to_integer(minute)}
  end

  # The cutoff is carried as an explicit `to` rather than a preset id, so the
  # filter the delete runs against names a concrete instant. A preset would be
  # re-resolved against a later clock and could select a different range than the
  # one just logged.
  defp iso(nil), do: nil

  defp iso(%DateTime{} = datetime) do
    datetime |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
