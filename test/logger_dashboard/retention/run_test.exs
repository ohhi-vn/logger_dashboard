defmodule LoggerDashboard.Retention.RunTest do
  use ExUnit.Case, async: false

  alias LoggerDashboard.Retention.Policy
  alias LoggerDashboard.Retention.Scheduler

  @moduletag :clickhouse

  setup do
    tag = "retention-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}@host"
    now = DateTime.utc_now()

    # Timestamps are relative to now, because retention's cutoff is too: a row at a
    # fixed date in the past is outside a 1-day window no matter what the clock
    # says, so both rows would be deleted and the test would prove nothing.
    seed(tag, "retention too old", DateTime.add(now, -2, :day))
    seed(tag, "retention kept", DateTime.add(now, -2, :hour))

    on_exit(fn -> ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE node = ?", [tag]) end)

    %{tag: tag}
  end

  describe "run_now/1 deletes through the shared age-cutoff path" do
    test "deletes rows past the retained age and keeps rows inside it", %{tag: tag} do
      name = :"run_test_#{System.unique_integer([:positive, :monotonic])}"
      # No retention config, so the policy is the inert default.
      Application.delete_env(:logger_dashboard, :retention)
      start_supervised!({Scheduler, name: name})

      # A cutoff one day back puts the row at +0d outside it and the row at +3d
      # inside it. Set through the real policy so the whole path is exercised:
      # preset -> cutoff -> Filter -> Prune.
      Scheduler.set_override(
        %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "1d"},
        name
      )

      assert {:ok, _message} = Scheduler.run_now(name)

      # ClickHouse applies deletes asynchronously, so poll for the mutation rather
      # than assuming it has landed.
      assert eventually(fn -> messages(tag) == ["retention kept"] end),
             "expected only the row inside the retained window to survive, got: #{inspect(messages(tag))}"
    end

    test "dispatches a system-wide prune with no node predicate", %{tag: tag} do
      name = :"scope_test_#{System.unique_integer([:positive, :monotonic])}"
      Application.delete_env(:logger_dashboard, :retention)
      start_supervised!({Scheduler, name: name})

      Scheduler.set_override(
        %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "1d"},
        name
      )

      # Retention is system-wide by construction: its filter carries no node value,
      # so a run reaches every node rather than one.
      assert {:ok, filter} =
               Scheduler.retention_filter(
                 %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "1d"},
                 DateTime.utc_now()
               )

      assert filter.nodes == []
      # The shared clause is the only predicate builder involved.
      {sql, _params} = LoggerDashboard.Logs.Filter.predicates(filter)
      refute sql =~ "node"

      assert {:ok, _message} = Scheduler.run_now(name)
      assert eventually(fn -> length(messages(tag)) == 1 end)
    end

    test "logs the scope and the cutoff for a dispatched run", %{tag: tag} do
      name = :"log_test_#{System.unique_integer([:positive, :monotonic])}"
      Application.delete_env(:logger_dashboard, :retention)
      start_supervised!({Scheduler, name: name})

      policy = %Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "1d"}
      Scheduler.set_override(policy, name)

      log = ExUnit.CaptureLog.capture_log(fn -> assert {:ok, _} = Scheduler.run_now(name) end)

      assert log =~ "[retention]"
      # The audit line names what acted and how far back it reached, so a recurring
      # unattended delete leaves a trace without an operator present.
      assert log =~ "every node"
      assert log =~ "1d"
      assert log =~ "dispatched"

      assert eventually(fn -> length(messages(tag)) == 1 end)
    end
  end

  defp eventually(check, attempts \\ 40) do
    cond do
      check.() -> true
      attempts == 0 -> false
      true -> Process.sleep(250) && eventually(check, attempts - 1)
    end
  end

  defp messages(tag) do
    {:ok, rows, _has_more} =
      LoggerDashboard.Logs.LogRead.list_logs(%LoggerDashboard.Logs.Filter{nodes: [tag]})

    rows |> Enum.map(& &1.message) |> Enum.sort()
  end

  defp seed(tag, message, timestamp) do
    row = %{
      id: Ash.UUID.generate(),
      timestamp: timestamp,
      level: "info",
      message: message,
      module: "Test",
      file: nil,
      line: nil,
      function: nil,
      metadata: %{},
      node: tag
    }

    {:ok, 1} = ClickhouseExLogger.Insert.insert([row])
  end
end
