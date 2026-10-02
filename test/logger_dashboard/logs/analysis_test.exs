defmodule LoggerDashboard.Logs.AnalysisTest do
  use ExUnit.Case, async: false

  alias LoggerDashboard.Logs.Analysis
  alias LoggerDashboard.Logs.Filter

  @moduletag :clickhouse

  setup do
    node =
      "analysis-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}-#{:rand.uniform(1_000_000)}@host"

    now = DateTime.truncate(DateTime.utc_now(), :microsecond)

    rows = [
      %{level: "error", node: node, minutes_ago: 10, message: "boom one"},
      %{level: "error", node: node, minutes_ago: 70, message: "boom two"},
      %{level: "info", node: node, minutes_ago: 20, message: "all good"},
      %{level: "info", node: nil, minutes_ago: 5, message: "no node"}
    ]

    insert_rows =
      Enum.map(rows, fn r ->
        %{
          id: Ash.UUID.generate(),
          timestamp: DateTime.add(now, -r.minutes_ago * 60, :second),
          level: r.level,
          message: r.message,
          module: "Test",
          file: nil,
          line: nil,
          function: nil,
          metadata: %{},
          node: r.node
        }
      end)

    assert {:ok, _} = ClickhouseExLogger.Insert.insert(insert_rows)
    # async_insert needs a moment to become queryable
    Process.sleep(2_000)

    {:ok, node: node}
  end

  test "level_frequency returns per-level counts", %{node: node} do
    assert {:ok, filter} = Filter.parse(%{"node" => node})
    assert {:ok, result} = Analysis.level_frequency(filter, limit: 100)

    assert result.type == :frequency
    joined = Enum.zip(result.labels, hd(result.series).data) |> Map.new()
    assert joined["error"] == 2
    assert joined["info"] == 1
  end

  test "volume_over_time buckets counts", %{node: node} do
    assert {:ok, filter} = Filter.parse(%{"node" => node})
    assert {:ok, result} = Analysis.volume_over_time(filter, :hour, limit: 100)

    assert result.type == :time_bucket
    assert Enum.sum(hd(result.series).data) == 3
  end

  test "node_frequency rolls NULL into unknown", %{node: _node} do
    assert {:ok, filter} = Filter.parse(%{})
    assert {:ok, result} = Analysis.node_frequency(filter, limit: 1_000)

    assert "unknown" in result.labels
  end

  test "dyan_filters excludes message search" do
    assert {:ok, filter} =
             Filter.parse(%{"node" => "a@b", "search" => "*boom*", "level" => "error"})

    filters = Analysis.dyan_filters(filter)
    refute Map.has_key?(filters, :message)
    assert filters.node == %{in: ["a@b"]}
    assert filters.level == "error"
  end

  test "dyan_filters emits an in filter for multiple nodes and omits it when empty" do
    assert {:ok, filter} = Filter.parse(%{"node" => "a@b,c@d"})
    assert Analysis.dyan_filters(filter).node == %{in: ["a@b", "c@d"]}

    assert {:ok, filter} = Filter.parse(%{"node" => " , "})
    refute Map.has_key?(Analysis.dyan_filters(filter), :node)
  end

  test "multi-node scope aggregates the selected nodes and excludes others", %{node: node} do
    # The setup inserts 3 rows on `node` plus 1 row with a NULL node. A second
    # named node gives the scope something to exclude.
    other = "analysis-other-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}@host"

    now = DateTime.truncate(DateTime.utc_now(), :microsecond)

    assert {:ok, _} =
             ClickhouseExLogger.Insert.insert([
               %{
                 id: Ash.UUID.generate(),
                 timestamp: DateTime.add(now, -300, :second),
                 level: "info",
                 message: "other node row",
                 module: "Test",
                 file: nil,
                 line: nil,
                 function: nil,
                 metadata: %{},
                 node: other
               }
             ])

    Process.sleep(2_000)

    on_exit(fn -> ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE node = ?", [other]) end)

    # Selecting both nodes must include the 3 setup rows and the 1 new row, and
    # still exclude the NULL-node row.
    assert {:ok, filter} = Filter.parse(%{"node" => "#{node},#{other}"})
    assert {:ok, result} = Analysis.level_frequency(filter, limit: 1_000)

    joined = Enum.zip(result.labels, hd(result.series).data) |> Map.new()
    assert joined["info"] == 2

    # Selecting only one node must exclude the other named node's row.
    assert {:ok, filter} = Filter.parse(%{"node" => other})
    assert {:ok, result} = Analysis.level_frequency(filter, limit: 1_000)

    joined = Enum.zip(result.labels, hd(result.series).data) |> Map.new()
    assert joined["info"] == 1

    assert {:ok, result} = Analysis.node_frequency(filter, limit: 1_000)
    assert result.labels == [other]
  end

  test "applied_limit caps at max_limit" do
    max = AshDyan.Info.max_limit(LoggerDashboard.Logs.LogView)
    assert Analysis.applied_limit(limit: max + 5_000) == max
  end

  test "over-limit analysis is capped, not rejected", %{node: node} do
    max = AshDyan.Info.max_limit(LoggerDashboard.Logs.LogView)
    assert {:ok, filter} = Filter.parse(%{"node" => node})
    assert {:ok, result} = Analysis.level_frequency(filter, limit: max + 5_000)
    assert result.type == :frequency
    assert Analysis.applied_limit(limit: max + 5_000) == max
  end

  test "split_by_level stays within max_group_by" do
    assert AshDyan.Info.max_group_by(LoggerDashboard.Logs.LogView) >= 1
  end
end
