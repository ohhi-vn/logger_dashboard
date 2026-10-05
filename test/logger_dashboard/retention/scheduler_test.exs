defmodule LoggerDashboard.Retention.SchedulerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias LoggerDashboard.BackgroundTaskConfig
  alias LoggerDashboard.BackgroundTaskConfig, as: Store
  alias LoggerDashboard.Logs.Filter
  alias LoggerDashboard.Retention.Policy
  alias LoggerDashboard.Retention.Scheduler

  setup do
    # Every test gets a scheduler under its own name, so none of them share the
    # policy one loaded from the store. `start_supervised!/2` guarantees it is torn
    # down between tests.
    name = fresh_name()

    # The store is shared, so its retention key is cleared either side of the test: a
    # value left behind would be the next test's starting policy.
    Store.delete(Policy, :policy)
    on_exit(fn -> Store.delete(Policy, :policy) end)

    pid = start_scheduler(name: name)

    %{name: name, pid: pid}
  end

  # `use GenServer` gives every child the same id, so a second scheduler in one test
  # would collide with the first. The name is the id instead, which is unique.
  defp start_scheduler(opts) do
    name = Keyword.fetch!(opts, :name)

    start_supervised!(%{id: name, start: {Scheduler, :start_link, [opts]}})
  end

  defp start_store(opts) do
    name = Keyword.fetch!(opts, :name)

    start_supervised!(%{id: name, start: {BackgroundTaskConfig, :start_link, [opts]}})
  end

  # Starts a scheduler with whatever it logs swallowed, and hands back the report it
  # settled on. `capture_log/1` answers the log, not the block, so the report is read
  # back off the process.
  defp capture_start(name, opts \\ []) do
    capture_log(fn -> start_scheduler([name: name] ++ opts) end)

    %{report: report} = :sys.get_state(name)
    report
  end

  # `:monotonic` matters here: the default counter can be reused, and a reused
  # name would collide with a scheduler an earlier test left registered.
  defp fresh_name, do: :"scheduler_test_#{System.unique_integer([:positive, :monotonic])}"

  defp configure(retention) do
    Application.put_env(:logger_dashboard, :retention, retention)
    on_exit(fn -> Application.delete_env(:logger_dashboard, :retention) end)
  end

  describe "the policy is stored, and lives in the store" do
    test "a policy set through the process is readable from another process", ctx do
      # The write and the read happen in different processes, which is the real
      # arrangement: a LiveView sets it, another request reads it. The value belongs to
      # the store rather than to either caller.
      Task.async(fn ->
        Scheduler.set_override(
          %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "1h"},
          ctx.name
        )
      end)
      |> Task.await()

      reader = Task.async(fn -> Scheduler.effective_policy(ctx.name) end)

      assert {:ok, report} = Task.await(reader)
      assert report.policy.keep == "1h"
      assert report.source == :stored
    end

    test "a set policy is in the store, under retention's own key", ctx do
      Scheduler.set_override(
        %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "1h"},
        ctx.name
      )

      # The durability is the point: the value is on disk under a namespaced key,
      # which is what another process — and the next boot — can find.
      assert {:ok, params} = Store.get(Policy, :policy)
      assert params["keep"] == "1h"
      assert {:ok, nil} = Store.get(LoggerDashboard.BackgroundTaskConfig, :policy)
    end

    test "nothing is written into the deployment's own configuration", ctx do
      configure(%{"enabled" => "true", "keep" => "30d"})

      Scheduler.set_override(
        %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "1h"},
        ctx.name
      )

      # The dashboard writes its operational configuration and never rewrites the
      # environment it was deployed with.
      assert Application.get_env(:logger_dashboard, :retention) == %{
               "enabled" => "true",
               "keep" => "30d"
             }
    end

    test "clearing removes the stored policy and returns to the configured default", ctx do
      configure(%{"enabled" => "true", "keep" => "30d"})

      Scheduler.set_override(
        %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "1h"},
        ctx.name
      )

      assert {:ok, %{source: :stored}} = Scheduler.effective_policy(ctx.name)

      assert :ok = Scheduler.clear_override(ctx.name)

      assert {:ok, %{policy: policy, source: :configured}} = Scheduler.effective_policy(ctx.name)
      assert policy.keep == "30d"

      # Removed, not ignored: a scheduler started now would find nothing stored.
      assert {:ok, nil} = Store.get(Policy, :policy)
    end

    test "a stored policy outranks the configured default", ctx do
      configure(%{"enabled" => "true", "keep" => "30d"})

      Scheduler.set_override(
        %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "1h"},
        ctx.name
      )

      assert {:ok, %{policy: policy, source: :stored}} = Scheduler.effective_policy(ctx.name)
      assert policy.keep == "1h"
    end

    test "a changed configured default does not discard a stored policy", ctx do
      Scheduler.set_override(
        %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "1h"},
        ctx.name
      )

      configure(%{"enabled" => "true", "keep" => "90d"})

      # Only an explicit removal brings the configured value back. A redeploy that
      # changes the environment must not silently re-arm something the operator
      # replaced with their own policy.
      assert {:ok, %{policy: policy, source: :stored}} = Scheduler.effective_policy(ctx.name)
      assert policy.keep == "1h"
    end
  end

  describe "loading at startup" do
    test "a stored policy is what a restart finds", ctx do
      Scheduler.set_override(
        %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "1h"},
        ctx.name
      )

      stop_supervised(ctx.name)

      # `init/1` is what a restart runs, and the store is where the policy is now.
      restarted = fresh_name()
      start_scheduler(name: restarted)

      assert {:ok, %{policy: policy, source: :stored}} = Scheduler.effective_policy(restarted)
      assert policy.keep == "1h"
    end

    test "with nothing stored the configured default is in force", ctx do
      configure(%{"enabled" => "true", "keep" => "30d"})

      stop_supervised(ctx.name)

      restarted = fresh_name()
      start_scheduler(name: restarted)

      assert {:ok, %{policy: policy, source: :configured}} =
               Scheduler.effective_policy(restarted)

      assert policy.keep == "30d"
    end

    test "the loaded policy is held in the process, not re-read per call", ctx do
      Scheduler.set_override(
        %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "1h"},
        ctx.name
      )

      # The timer is derived from the policy, so a schedule whose subject could change
      # underneath it would be a schedule nobody is tracking.
      assert %{report: report, timer: timer} = :sys.get_state(ctx.pid)
      assert report.policy.keep == "1h"
      assert is_reference(timer)
    end
  end

  describe "a stored policy that cannot be used" do
    test "falls back to the configured default without scheduling from it" do
      configure(%{"enabled" => "true", "keep" => "30d"})
      # A retained age that is no longer in the vocabulary: the file was written by a
      # release whose `:age` family differed, or edited by hand.
      :ok = Store.put(Policy, :policy, %{"enabled" => "true", "keep" => "99y"})

      name = fresh_name()
      report = capture_start(name)

      assert {:ok, ^report} = Scheduler.effective_policy(name)
      assert report.policy.keep == "30d"
      assert report.source == :configured
      assert report.stored_error =~ "99y"
    end

    test "leaves the stored value in place rather than rewriting it" do
      :ok = Store.put(Policy, :policy, %{"enabled" => "true", "keep" => "99y"})

      name = fresh_name()
      capture_start(name)

      assert {:ok, %{stored_error: _}} = Scheduler.effective_policy(name)

      # The operator's only copy of a policy a vocabulary change invalidated. Silently
      # replacing it with the default would destroy the thing they were trying to keep.
      assert {:ok, %{"keep" => "99y"}} = Store.get(Policy, :policy)
    end

    test "a value that is not a policy at all is treated as unusable" do
      configure(%{"enabled" => "true", "keep" => "30d"})
      :ok = Store.put(Policy, :policy, "keep 7 days")

      name = fresh_name()
      report = capture_start(name)

      assert {:ok, ^report} = Scheduler.effective_policy(name)
      assert report.policy.keep == "30d"
      assert report.stored_error =~ "not a policy"
    end
  end

  describe "a store that cannot be written" do
    setup do
      # A store whose database file path is a directory, so nothing can be saved. The
      # scheduler under test reads and writes through this one.
      dir = Path.join(System.tmp_dir!(), "scheduler_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(dir, "0.cub"))
      on_exit(fn -> File.rm_rf!(dir) end)

      store = fresh_name()
      name = fresh_name()

      capture_log(fn ->
        start_store(name: store, data_dir: dir)
        start_scheduler(name: name, store: store)
      end)

      %{name: name, store: store}
    end

    test "saving reports the failure and leaves the schedule and the store alone", ctx do
      # A policy that could not be persisted must not be armed: a schedule a restart
      # would silently undo is the failure this ordering exists to prevent.
      enabled = %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "1d"}

      capture_log(fn -> assert {:error, _reason} = Scheduler.set_override(enabled, ctx.name) end)

      assert %{report: report, timer: timer} = :sys.get_state(ctx.name)
      assert report.policy.enabled == false
      assert timer == nil
      assert {:error, _reason} = BackgroundTaskConfig.status(ctx.store)
    end

    test "removing reports the failure and leaves the stored policy in force", ctx do
      capture_log(fn -> assert {:error, _reason} = Scheduler.clear_override(ctx.name) end)

      assert %{report: report} = :sys.get_state(ctx.name)
      assert report.policy.enabled == false
    end
  end

  describe "next_occurrence/2" do
    test "returns today's run time when it is still ahead" do
      policy = %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "7d"}
      now = ~U[2026-09-02 01:00:00Z]

      assert Scheduler.next_occurrence(policy, now) == ~U[2026-09-02 03:00:00Z]
    end

    test "rolls to tomorrow when today's run time has passed" do
      policy = %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "7d"}
      now = ~U[2026-09-02 05:00:00Z]

      assert Scheduler.next_occurrence(policy, now) == ~U[2026-09-03 03:00:00Z]
    end

    test "rolls forward when now is exactly the run time" do
      # The occurrence at `now` is the one just gone. Returning it would fire
      # immediately and then again a day later, so the next one is a day out.
      policy = %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "7d"}
      now = ~U[2026-09-02 03:00:00Z]

      assert Scheduler.next_occurrence(policy, now) == ~U[2026-09-03 03:00:00Z]
    end

    test "always returns a strictly future instant" do
      policy = %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "7d"}
      now = ~U[2026-09-02 03:00:00Z]

      for minute <- 0..59 do
        at = %{now | minute: minute, second: 0, microsecond: {0, 0}}
        next = Scheduler.next_occurrence(policy, at)

        assert DateTime.compare(next, at) == :gt
      end
    end

    test "resolves in UTC rather than the server's local zone" do
      policy = %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "7d"}
      now = ~U[2026-09-02 01:00:00Z]

      assert Scheduler.next_occurrence(policy, now).time_zone == "Etc/UTC"
      assert Scheduler.next_occurrence(policy, now) == ~U[2026-09-02 03:00:00Z]
    end

    test "recomputes from the clock after a jump rather than advancing by a day" do
      # Two calls from very different instants each land on their own next
      # occurrence. A fixed-interval sleep, or advancing by exactly one day, would
      # not track a clock that moved.
      policy = %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "7d"}

      before_jump = Scheduler.next_occurrence(policy, ~U[2026-09-02 01:00:00Z])
      after_jump = Scheduler.next_occurrence(policy, ~U[2026-09-05 23:00:00Z])

      assert before_jump == ~U[2026-09-02 03:00:00Z]
      assert after_jump == ~U[2026-09-06 03:00:00Z]
    end
  end

  describe "time_until_next/1" do
    test "is :none for a disabled policy" do
      assert Scheduler.time_until_next(Policy.default()) == :none
    end

    test "is positive and within a day for an enabled policy" do
      policy = %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "7d"}

      delay = Scheduler.time_until_next(policy)

      assert is_integer(delay)
      assert delay > 0
      assert delay <= 24 * 60 * 60 * 1000
    end
  end

  describe "startup is inert" do
    test "starting with a missed occurrence dispatches nothing" do
      # Enabled, but proving no catch-up means waiting for 03:00. What can be
      # asserted instead is the shape of `init/1`: it holds a pending timer and has
      # dispatched nothing. A catch-up implementation would either have no timer
      # (already "caught up") or would have logged a delete.
      configure(%{"enabled" => "true", "run_at" => "03:00 UTC", "keep" => "7d"})

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, %{timer: timer, report: report}} = Scheduler.init([])
          # A pending timer, not an absent one: nothing has fired, and something is
          # scheduled.
          assert is_reference(timer)
          assert report.policy.enabled
        end)

      refute log =~ "[retention] unattended prune"

      # The configured policy is armed and its next run is in the future, so the
      # timer corresponds to a real occurrence rather than to an immediate retry.
      assert Scheduler.time_until_next(%Policy{
               enabled: true,
               run_at: {"03:00", "UTC"},
               keep: "7d"
             }) > 0
    end

    test "a stored enabled policy still dispatches nothing on boot" do
      # The policy is durable now, so after the first save there is always something
      # to run. A catch-up implementation would therefore have something to catch up
      # with on every boot of a crash-looping dashboard — which is why the store does
      # not make the schedule retroactively true.
      configure(%{"enabled" => "false", "run_at" => "03:00 UTC", "keep" => "7d"})

      :ok =
        Store.put(
          Policy,
          :policy,
          Policy.to_params(%Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "1d"})
        )

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          name = fresh_name()
          start_scheduler(name: name)

          # Armed and still silent: a pending timer, and no delete.
          assert %{timer: timer, report: %{source: :stored}} = :sys.get_state(name)
          assert is_reference(timer)
        end)

      refute log =~ "[retention] unattended prune"
    end

    test "a disabled policy schedules no timer at all", ctx do
      pid = ctx.pid

      # No timer means there is nothing that can fire, and so nothing to catch up
      # on later either.
      assert %{timer: nil} = :sys.get_state(pid)
    end
  end

  describe "retention_filter/2" do
    test "carries an explicit cutoff rather than a preset id" do
      policy = %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "7d"}
      now = ~U[2026-09-02 12:00:00Z]

      assert {:ok, filter} = Scheduler.retention_filter(policy, now)

      assert filter.to == ~U[2026-08-26 12:00:00Z]
      assert filter.from == nil
      # An explicit `to` means the delete cannot be re-resolved against a later
      # clock into a different range than the one resolved here.
      assert filter.preset == nil
    end

    test "resolves an hour-valued retained age to a sub-day cutoff" do
      policy = %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "6h"}
      now = ~U[2026-09-02 12:00:00Z]

      assert {:ok, filter} = Scheduler.retention_filter(policy, now)

      assert filter.to == ~U[2026-09-02 06:00:00Z]
    end

    test "agrees with a manual age cutoff on the same duration" do
      # The same named duration must mean the same cutoff on both surfaces, which
      # is why both go through `Filter`.
      now = ~U[2026-09-02 12:00:00Z]

      assert {:ok, scheduled} =
               Scheduler.retention_filter(
                 %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "7d"},
                 now
               )

      assert {:ok, manual} = Filter.parse(%{"preset" => "age:7d"})

      # The manual path resolves its preset at parse time against its own clock;
      # comparing the resolved instants is what matters, so re-resolve it at `now`.
      assert {:ok, {nil, manual_to}} = Filter.resolve_preset("age:7d", now)

      assert scheduled.to == manual_to
      assert manual.preset == "age:7d"
    end

    test "produces a filter the pruning bound requirement accepts" do
      # `Prune` refuses a delete bounded at neither end. Retention is bounded by
      # construction because an age cutoff always sets the upper bound, so this
      # is the condition `require_bounds/1` checks.
      assert {:ok, filter} =
               Scheduler.retention_filter(
                 %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "1d"},
                 DateTime.utc_now()
               )

      refute filter.to == nil
    end

    test "is bounded at one end only, so the delete can never be unbounded" do
      assert {:ok, filter} =
               Scheduler.retention_filter(
                 %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "1d"},
                 DateTime.utc_now()
               )

      assert filter.from == nil
      refute filter.to == nil
    end
  end

  describe "predicate construction" do
    test "builds the delete predicate through Filter and Prune only" do
      # The retention path composes what already exists. If it grew its own
      # predicate builder there would be a second place to get bound parameters
      # wrong, so the shared clause is what the delete must go through.
      {sql, params} =
        Filter.predicates(%Filter{to: ~U[2026-09-01 00:00:00Z], search: ""})

      assert sql == "timestamp <= ?"
      assert [%DateTime{}] = params
      # No node predicate: retention is system-wide.
      refute sql =~ "node"
      # No message predicate: retention never text-searches.
      refute sql =~ "message"
    end
  end
end
