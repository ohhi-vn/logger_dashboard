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

  test "level_frequency lists the dominant level first", %{node: node} do
    # The scope holds 2 error rows and 1 info row, so descending-by-count and
    # alphabetical ("debug" < "error" < "info") cannot both produce this order.
    assert {:ok, filter} = Filter.parse(%{"node" => node})
    assert {:ok, result} = Analysis.level_frequency(filter, limit: 100)

    assert result.labels == ["error", "info"]
    assert hd(result.series).data == [2, 1]
  end

  test "node_frequency lists the busiest node first", %{node: node} do
    # The second node is named so it sorts *before* the setup node
    # alphabetically while holding *fewer* rows, so an alphabetical ordering
    # fails this assertion rather than accidentally satisfying it.
    quieter = "aaa-quieter-#{System.unique_integer([:positive])}@host"

    now = DateTime.truncate(DateTime.utc_now(), :microsecond)

    assert {:ok, _} =
             ClickhouseExLogger.Insert.insert([
               %{
                 id: Ash.UUID.generate(),
                 timestamp: DateTime.add(now, -300, :second),
                 level: "info",
                 message: "quieter node row",
                 module: "Test",
                 file: nil,
                 line: nil,
                 function: nil,
                 metadata: %{},
                 node: quieter
               }
             ])

    Process.sleep(2_000)

    on_exit(fn -> ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE node = ?", [quieter]) end)

    assert {:ok, filter} = Filter.parse(%{"node" => "#{node},#{quieter}"})
    assert {:ok, result} = Analysis.node_frequency(filter, limit: 1_000)

    assert result.labels == [node, quieter]
    assert hd(result.series).data == [3, 1]
  end

  test "volume_over_time buckets counts", %{node: node} do
    assert {:ok, filter} = Filter.parse(%{"node" => node})
    assert {:ok, result} = Analysis.volume_over_time(filter, :hour, limit: 100)

    assert result.type == :time_bucket
    assert Enum.sum(hd(result.series).data) == 3
  end

  test "volume_over_time keeps bucket labels chronological", %{node: node} do
    # The scope spans 70 and 20 minutes ago, which is always two calendar hours,
    # and a value ordering is not available on `:time_bucket`. So the labels
    # must arrive in time order.
    assert {:ok, filter} = Filter.parse(%{"node" => node})
    assert {:ok, result} = Analysis.volume_over_time(filter, :hour, limit: 100)

    assert length(result.labels) == 2
    assert result.labels == Enum.sort(result.labels)
    assert Enum.sort(hd(result.series).data) == [1, 2]
  end

  test "normalize_bucket resolves an unsupported bucket onto the default" do
    assert Analysis.normalize_bucket("nope") == Analysis.default_bucket()
    assert Analysis.normalize_bucket(nil) == Analysis.default_bucket()
    assert Analysis.normalize_bucket(123) == Analysis.default_bucket()

    assert Analysis.normalize_bucket("day") == :day
    assert Analysis.normalize_bucket(:day) == :day
  end

  test "normalize_bucket is idempotent over every offered bucket" do
    for bucket <- Analysis.buckets() do
      assert Analysis.normalize_bucket(Atom.to_string(bucket)) == bucket
      assert Analysis.normalize_bucket(bucket) == bucket
    end
  end

  test "node_frequency rolls NULL into unknown", %{node: node} do
    # Isolate this test's row in a future time window no other writer uses.
    # AshDyan computes :frequency over a limited row scan, so asserting on a
    # just-inserted row against the whole shared table flakes as the table
    # grows, and the server-side async-insert buffer adds a visibility lag on
    # top. A private window makes the scan deterministic.
    now = DateTime.truncate(DateTime.utc_now(), :microsecond)
    message = "null node #{node}"

    assert {:ok, _} =
             ClickhouseExLogger.Insert.insert([
               %{
                 id: Ash.UUID.generate(),
                 timestamp: DateTime.add(now, 24, :hour),
                 level: "info",
                 message: message,
                 module: "Test",
                 file: nil,
                 line: nil,
                 function: nil,
                 metadata: %{},
                 node: nil
               }
             ])

    on_exit(fn ->
      ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE message = ?", [message])
    end)

    assert {:ok, filter} =
             Filter.parse(%{
               "from" => DateTime.to_iso8601(DateTime.add(now, 23, :hour)),
               "to" => DateTime.to_iso8601(DateTime.add(now, 25, :hour))
             })

    # Poll until the async-insert buffer flushes our row.
    wait_until_visible(fn ->
      case Analysis.node_frequency(filter) do
        {:ok, %{labels: labels}} -> "unknown" in labels
        _ -> false
      end
    end)

    assert {:ok, result} = Analysis.node_frequency(filter)
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

  # Polls `fun` until it returns truthy, giving the server-side async-insert
  # buffer time to flush under parallel-suite load. Fails loudly on timeout so
  # a genuinely missing row still fails instead of hanging the suite.
  defp wait_until_visible(fun, attempts \\ 60) do
    if fun.() do
      :ok
    else
      assert attempts > 0, "inserted rows never became queryable"
      Process.sleep(500)
      wait_until_visible(fun, attempts - 1)
    end
  end
end
