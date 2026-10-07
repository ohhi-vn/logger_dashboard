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

    {sql, params} = Prune.where_clause(filter)
    assert sql =~ "node IN (?)"
    assert sql =~ "level IN (?)"
    assert sql =~ "timestamp >="
    assert length(params) == 3
    refute sql =~ "message"
  end

  describe "preview/1" do
    setup do
      uniq = "#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}"
      node = "prune-preview-#{uniq}@host"
      now = DateTime.truncate(DateTime.utc_now(), :microsecond)

      on_exit(fn -> ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE node = ?", [node]) end)

      %{node: node, now: now}
    end

    test "counts the scope and returns its newest sample", %{node: node, now: now} do
      insert_rows(node, now, ["preview newest", "preview middle", "preview oldest"])

      assert {:ok, filter, :node} =
               Prune.parse(%{
                 "scope" => "node",
                 "node" => node,
                 "from" => DateTime.to_iso8601(DateTime.add(now, -60, :minute))
               })

      assert {:ok, %{count: 3, rows: sample}} = Prune.preview(filter)

      assert Enum.map(sample, & &1.message) == [
               "preview newest",
               "preview middle",
               "preview oldest"
             ]
    end

    test "caps the sample while reporting the full count", %{node: node, now: now} do
      insert_rows(node, now, Enum.map(1..7, &"preview row #{&1}"))

      assert {:ok, filter, :node} =
               Prune.parse(%{
                 "scope" => "node",
                 "node" => node,
                 "from" => DateTime.to_iso8601(DateTime.add(now, -60, :minute))
               })

      assert {:ok, %{count: 7, rows: sample}} = Prune.preview(filter)
      assert length(sample) == 5

      assert Enum.map(sample, & &1.message) == [
               "preview row 1",
               "preview row 2",
               "preview row 3",
               "preview row 4",
               "preview row 5"
             ]
    end

    test "reports a zero count and no rows for an empty scope", %{node: node} do
      assert {:ok, filter, :node} =
               Prune.parse(%{
                 "scope" => "node",
                 "node" => node,
                 "from" => "2000-01-01T00:00:00Z"
               })

      assert {:ok, %{count: 0, rows: []}} = Prune.preview(filter)
    end
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

  defp insert_rows(node, now, messages) do
    rows =
      messages
      |> Enum.with_index(1)
      |> Enum.map(fn {message, minutes_ago} ->
        %{
          id: Ash.UUID.generate(),
          timestamp: DateTime.add(now, -minutes_ago, :minute),
          level: "info",
          message: message,
          module: "Test",
          file: nil,
          line: nil,
          function: nil,
          metadata: %{},
          node: node
        }
      end)

    assert {:ok, _} = ClickhouseExLogger.Insert.insert(rows)
    Process.sleep(2_000)
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
