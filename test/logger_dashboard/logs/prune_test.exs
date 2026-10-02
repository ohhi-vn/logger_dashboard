defmodule LoggerDashboard.Logs.PruneTest do
  use ExUnit.Case, async: false

  alias LoggerDashboard.Logs.Prune

  @moduletag :clickhouse

  test "parse rejects node scope without node" do
    assert {:error, _} = Prune.parse(%{"scope" => "node", "node" => ""})
  end

  test "parse rejects an absent scope instead of defaulting to whole-system" do
    assert {:error, message} = Prune.parse(%{})
    assert message =~ "scope"

    assert {:error, _} = Prune.parse(%{"node" => "a@b"})
  end

  test "parse accepts all-nodes scope when bounded" do
    assert {:ok, filter, :all} =
             Prune.parse(%{"scope" => "all", "from" => "2026-09-01T00:00:00Z"})

    assert filter.nodes == []
  end

  test "parse rejects a multi-node value for node scope" do
    # A prune deletes rows and its confirmation names one node. Accepting a
    # comma-separated value would let the confirmation understate the blast
    # radius, so the request is rejected rather than narrowed to one node.
    assert {:error, message} =
             Prune.parse(%{
               "scope" => "node",
               "node" => "a@b,c@d",
               "from" => "2026-09-01T00:00:00Z"
             })

    assert message =~ "exactly one node"

    # Duplicates of a single node still resolve to one node.
    assert {:ok, filter, :node} =
             Prune.parse(%{
               "scope" => "node",
               "node" => "a@b, a@b",
               "from" => "2026-09-01T00:00:00Z"
             })

    assert filter.nodes == ["a@b"]
  end

  test "parse rejects an unbounded prune" do
    assert {:error, message} = Prune.parse(%{"scope" => "all"})
    assert message =~ "from"
    assert message =~ "to"

    assert {:error, _} = Prune.parse(%{"scope" => "node", "node" => "a@b"})
  end

  test "parse accepts a one-sided range" do
    assert {:ok, f, :node} =
             Prune.parse(%{"scope" => "node", "node" => "a@b", "from" => "2026-09-01T00:00:00Z"})

    assert f.from != nil
    assert f.to == nil

    assert {:ok, f, :node} =
             Prune.parse(%{"scope" => "node", "node" => "a@b", "to" => "2026-09-02T00:00:00Z"})

    assert f.from == nil
    assert f.to != nil
  end

  test "where_clause only uses validated fields" do
    assert {:ok, filter, :node} =
             Prune.parse(%{
               "scope" => "node",
               "node" => "a@b",
               "level" => "error",
               "from" => "2026-09-01T00:00:00Z"
             })

    {sql, params} = Prune.where_clause(filter, :node)
    assert sql =~ "node IN (?)"
    assert sql =~ "level = ?"
    assert sql =~ "timestamp >="
    assert length(params) == 3
    refute sql =~ "message"
  end

  test "run deletes only scoped rows" do
    uniq = "#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}"
    keep = "prune-keep-#{uniq}@host"
    del = "prune-del-#{uniq}@host"
    now = DateTime.truncate(DateTime.utc_now(), :microsecond)

    rows = [
      %{
        id: Ash.UUID.generate(),
        timestamp: now,
        level: "info",
        message: "keep",
        module: "Test",
        file: nil,
        line: nil,
        function: nil,
        metadata: %{},
        node: keep
      },
      %{
        id: Ash.UUID.generate(),
        timestamp: now,
        level: "info",
        message: "delete",
        module: "Test",
        file: nil,
        line: nil,
        function: nil,
        metadata: %{},
        node: del
      }
    ]

    assert {:ok, 2} = ClickhouseExLogger.Insert.insert(rows)
    Process.sleep(2_000)

    assert {:ok, filter, :node} =
             Prune.parse(%{
               "scope" => "node",
               "node" => del,
               "from" => DateTime.to_iso8601(DateTime.add(now, -60, :second))
             })

    assert {:ok, message} = Prune.run(filter, :node)
    assert message =~ "asynchronously"

    assert eventually(fn -> count_rows(del) == 0 end, 30_000)
    assert count_rows(keep) == 1
  end

  defp count_rows(node) do
    require Ash.Query

    LoggerDashboard.Logs.LogView
    |> Ash.Query.filter(node == ^node)
    |> Ash.read!(domain: LoggerDashboard.Logs)
    |> length()
  end

  defp eventually(fun, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll(fun, deadline)
  end

  defp poll(fun, deadline) do
    if fun.() do
      true
    else
      if System.monotonic_time(:millisecond) > deadline do
        false
      else
        Process.sleep(1_000)
        poll(fun, deadline)
      end
    end
  end
end
