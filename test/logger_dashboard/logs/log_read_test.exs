defmodule LoggerDashboard.Logs.LogReadTest do
  use ExUnit.Case, async: false

  alias LoggerDashboard.Logs.Filter
  alias LoggerDashboard.Logs.LogRead

  @moduletag :clickhouse

  describe "columns/0 and table/0" do
    test "projection covers every public LogView attribute" do
      expected =
        LoggerDashboard.Logs.LogView
        |> Ash.Resource.Info.attributes()
        |> Enum.filter(& &1.public?)
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert Enum.sort(LogRead.columns()) == expected
      assert :id in LogRead.columns()
      assert :message in LogRead.columns()
    end

    test "table is derived from the resource" do
      assert LogRead.table() =~ "logs"
    end
  end

  describe "decode/1" do
    test "maps positional rows onto atom keys and casts types" do
      row = [
        "d600f4ec-f743-47f2-997d-088ef1fafadc",
        "2026-09-01 01:15:54.343170",
        "error",
        "boom",
        "Test",
        nil,
        12,
        "run",
        %{},
        "a@b"
      ]

      assert [decoded] = LogRead.decode([row])

      assert decoded.id == "d600f4ec-f743-47f2-997d-088ef1fafadc"
      assert decoded.timestamp == ~U[2026-09-01 01:15:54.343170Z]
      assert decoded.level == :error
      assert decoded.message == "boom"
      assert decoded.node == "a@b"
    end

    test "leaves an unrecognized level as a string" do
      index = Enum.find_index(LogRead.columns(), &(&1 == :level))
      row = List.duplicate("x", length(LogRead.columns())) |> List.replace_at(index, "fatal")

      assert [decoded] = LogRead.decode([row])
      assert decoded.level == "fatal"
    end
  end

  describe "list_logs/2" do
    setup do
      tag = "read-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}@host"
      on_exit(fn -> delete_tag(tag) end)
      %{tag: tag}
    end

    test "returns rows typed as the viewer expects", %{tag: tag} do
      seed(tag, "raw read typing", :info, ~U[2026-01-01 00:00:00.000000Z])

      {:ok, [row | _], _has_more} = LogRead.list_logs(%Filter{nodes: [tag], search: "*raw read*"})

      assert row.node == tag
      assert is_binary(row.id)
      assert %DateTime{} = row.timestamp
      assert row.level == :info
      assert row.message == "raw read typing"
    end

    test "finds matches beyond the newest page", %{tag: tag} do
      # 60 non-matching newer rows plus one much older match. A naive
      # newest-first window small enough to miss it would return nothing.
      base = ~U[2026-01-01 00:00:00.000000Z]
      for i <- 1..60, do: seed(tag, "noise #{i}", :info, DateTime.add(base, i, :minute))
      seed(tag, "the ancient needle", :error, base)

      {:ok, rows, _has_more} =
        LogRead.list_logs(%Filter{nodes: [tag], search: "*ancient needle*", limit: 50})

      assert Enum.map(rows, & &1.message) == ["the ancient needle"]
    end

    test "honors level and range filters", %{tag: tag} do
      # Fixed, widely-spaced timestamps so ordering and bounds are deterministic
      # regardless of when the test runs.
      seed(tag, "old error", :error, ~U[2026-01-01 00:00:00.000000Z])
      seed(tag, "new error", :error, ~U[2026-06-01 00:00:00.000000Z])
      seed(tag, "new info", :info, ~U[2026-06-01 00:00:00.000000Z])

      {:ok, rows, _has_more} = LogRead.list_logs(%Filter{nodes: [tag], level: "error"})
      assert Enum.map(rows, & &1.message) == ["new error", "old error"]

      {:ok, rows, _has_more} =
        LogRead.list_logs(%Filter{nodes: [tag], from: ~U[2026-03-01 00:00:00.000000Z]})

      assert Enum.sort(Enum.map(rows, & &1.message)) == ["new error", "new info"]

      {:ok, rows, _has_more} =
        LogRead.list_logs(%Filter{nodes: [tag], to: ~U[2026-03-01 00:00:00.000000Z]})

      assert Enum.map(rows, & &1.message) == ["old error"]
    end

    test "applies limit and offset over the full match set", %{tag: tag} do
      for i <- 1..5 do
        seed(tag, "page row #{i}", :info, DateTime.add(~U[2026-01-01 00:00:00.000000Z], i, :day))
      end

      # Row 5 is newest (offset by 5 days), so DESC yields 5, 4, 3, 2, 1.
      {:ok, first, _has_more} = LogRead.list_logs(%Filter{nodes: [tag], limit: 2})
      assert Enum.map(first, & &1.message) == ["page row 5", "page row 4"]

      {:ok, second, _has_more} = LogRead.list_logs(%Filter{nodes: [tag], limit: 2, offset: 2})
      assert Enum.map(second, & &1.message) == ["page row 3", "page row 2"]

      {:ok, third, _has_more} = LogRead.list_logs(%Filter{nodes: [tag], limit: 2, offset: 4})
      assert Enum.map(third, & &1.message) == ["page row 1"]
    end

    test "returns an empty list when nothing matches", %{tag: tag} do
      assert {:ok, [], _has_more} =
               LogRead.list_logs(%Filter{nodes: ["no-such-node-#{tag}"], search: "*x*"})
    end

    test "reports no further rows when the match count is exactly the page size", %{tag: tag} do
      # The boundary the inference `length(rows) >= limit` got wrong: a total that
      # is an exact multiple of the page size fills the last page and has nothing
      # behind it, so it must report no next page rather than leading to an empty
      # one.
      for i <- 1..4,
          do:
            seed(
              tag,
              "exact #{i}",
              :info,
              DateTime.add(~U[2026-01-01 00:00:00.000000Z], i, :minute)
            )

      assert {:ok, rows, has_more} = LogRead.list_logs(%Filter{nodes: [tag], limit: 4})

      assert length(rows) == 4
      refute has_more
    end

    test "reports a further page when exactly one row sits past the page size", %{tag: tag} do
      for i <- 1..5,
          do:
            seed(
              tag,
              "beyond #{i}",
              :info,
              DateTime.add(~U[2026-01-01 00:00:00.000000Z], i, :minute)
            )

      assert {:ok, rows, has_more} = LogRead.list_logs(%Filter{nodes: [tag], limit: 4})

      assert length(rows) == 4
      assert has_more
    end

    test "never returns the detection row", %{tag: tag} do
      # The row fetched past the page exists only to answer `has_more`. It must not
      # reach the caller, because the caller displays and exports exactly this list.
      for i <- 1..5,
          do:
            seed(
              tag,
              "probe #{i}",
              :info,
              DateTime.add(~U[2026-01-01 00:00:00.000000Z], i, :minute)
            )

      assert {:ok, rows, has_more} = LogRead.list_logs(%Filter{nodes: [tag], limit: 4})

      assert has_more
      assert length(rows) == 4
      refute Enum.any?(rows, &(&1.message == "probe 1"))
    end

    test "the detection row does not shift the next page", %{tag: tag} do
      # Advancing must not skip or repeat a row: the probe is consumed by the page
      # that fetched it, not carried into the following offset.
      for i <- 1..5,
          do:
            seed(
              tag,
              "sequence #{i}",
              :info,
              DateTime.add(~U[2026-01-01 00:00:00.000000Z], i, :minute)
            )

      assert {:ok, first, _} = LogRead.list_logs(%Filter{nodes: [tag], limit: 4})

      assert {:ok, second, has_more} =
               LogRead.list_logs(%Filter{nodes: [tag], limit: 4, offset: 4})

      refute has_more

      assert Enum.map(first, & &1.message) == [
               "sequence 5",
               "sequence 4",
               "sequence 3",
               "sequence 2"
             ]

      assert Enum.map(second, & &1.message) == ["sequence 1"]
    end

    test "reads rows from two selected nodes and excludes a third", %{tag: tag} do
      # The setup tag stands in for the first selected node; `other` is the
      # second. Both share a search term so the node predicate is the only
      # difference between the two queries.
      other = "read-other-#{System.system_time(:millisecond)}@host"
      excluded = "read-excluded-#{System.system_time(:millisecond)}@host"

      on_exit(fn ->
        ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE node = ?", [other])
        ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE node = ?", [excluded])
      end)

      base = ~U[2026-01-01 00:00:00.000000Z]
      seed(tag, "multi node a", :info, base)
      seed(other, "multi node b", :info, DateTime.add(base, 1, :minute))
      seed(excluded, "multi node c", :info, DateTime.add(base, 2, :minute))

      assert {:ok, rows, _has_more} =
               LogRead.list_logs(%Filter{
                 nodes: [tag, other],
                 search: "*multi node*",
                 limit: 50
               })

      assert Enum.map(rows, & &1.message) |> Enum.sort() == ["multi node a", "multi node b"]
      refute Enum.any?(rows, &(&1.message == "multi node c"))

      # Dropping one node from the set drops exactly its rows.
      assert {:ok, rows, _has_more} =
               LogRead.list_logs(%Filter{nodes: [other], search: "*multi node*", limit: 50})

      assert Enum.map(rows, & &1.message) == ["multi node b"]
    end

    test "treats a nil rows field as an error, not an empty list" do
      # An unsupported `default_format` yields `%Result{rows: nil}` with no raise.
      # That must surface as a failure, otherwise the viewer renders as if the
      # node had produced no logs at all.
      assert {:error, message} = LogRead.handle_result({:ok, %{rows: nil, columns: nil}})
      assert message =~ "unrecognized response format"

      assert {:ok, []} = LogRead.handle_result({:ok, %{rows: []}})
    end

    test "propagates driver errors" do
      assert {:error, :boom} = LogRead.handle_result({:error, :boom})
    end
  end

  defp seed(tag, message, level, timestamp) do
    row = %{
      id: Ash.UUID.generate(),
      timestamp: timestamp,
      level: Atom.to_string(level),
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

  defp delete_tag(tag) do
    ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE node = ?", [tag])
  end
end
