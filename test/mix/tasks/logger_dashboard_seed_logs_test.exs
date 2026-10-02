defmodule Mix.Tasks.LoggerDashboard.SeedLogsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias LoggerDashboard.Logs.Filter

  @moduletag :clickhouse

  test "--help prints documented flags" do
    output = capture_io(fn -> Mix.Tasks.LoggerDashboard.SeedLogs.run(["--help"]) end)
    assert output =~ "--count"
    assert output =~ "--levels"
    assert output =~ "--nodes"
    assert output =~ "--dry-run"
  end

  test "invalid level aborts with no writes" do
    assert_raise Mix.Error, ~r/invalid level/, fn ->
      Mix.Tasks.LoggerDashboard.SeedLogs.run(["--levels", "verbose", "--dry-run"])
    end
  end

  test "prod without --allow-prod aborts" do
    previous = Mix.env()
    Mix.env(:prod)

    try do
      assert_raise Mix.Error, ~r/allow-prod/, fn ->
        Mix.Tasks.LoggerDashboard.SeedLogs.run(["--count", "5", "--dry-run"])
      end
    after
      Mix.env(previous)
    end
  end

  test "dry-run writes nothing then real run inserts exact count" do
    node =
      "seed-task-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}@host"

    from = "2026-09-01T00:00:00Z"
    to = "2026-09-02T00:00:00Z"

    dry_output =
      capture_io(fn ->
        Mix.Tasks.LoggerDashboard.SeedLogs.run([
          "--count",
          "20",
          "--nodes",
          node,
          "--from",
          from,
          "--to",
          to,
          "--seed",
          "7",
          "--dry-run"
        ])
      end)

    assert dry_output =~ "would insert 20 rows"
    assert dry_output =~ "per node: %{"
    assert dry_output =~ node

    # async_insert needs a moment to become queryable
    Process.sleep(2_000)
    assert {:ok, filter} = Filter.parse(%{"node" => node})
    assert {:ok, []} = LoggerDashboard.Logs.LogRead.list_logs(filter)

    capture_io(fn ->
      Mix.Tasks.LoggerDashboard.SeedLogs.run([
        "--count",
        "20",
        "--nodes",
        node,
        "--from",
        from,
        "--to",
        to,
        "--seed",
        "7",
        "--batch-size",
        "10"
      ])
    end)

    Process.sleep(2_000)
    assert {:ok, filter} = Filter.parse(%{"node" => node})
    assert {:ok, rows} = LoggerDashboard.Logs.LogRead.list_logs(filter)
    assert length(rows) == 20
  end
end
