defmodule LoggerDashboard.Logs.FilterTest do
  use ExUnit.Case, async: true

  alias LoggerDashboard.Logs.Filter

  describe "to_like_pattern/1" do
    test "empty returns nil" do
      assert Filter.to_like_pattern("") == nil
      assert Filter.to_like_pattern(nil) == nil
    end

    test "translates * and ? wildcards" do
      assert Filter.to_like_pattern("*timeout*") == "%timeout%"
      assert Filter.to_like_pattern("db_*") == "db\\_%"
      assert Filter.to_like_pattern("a?c") == "a_c"
    end

    test "escapes LIKE specials" do
      assert Filter.to_like_pattern("100%_x\\y") == "100\\%\\_x\\\\y"
    end
  end

  describe "predicates/1" do
    test "no active predicate yields 1 = 1" do
      assert Filter.predicates(%Filter{}) == {"1 = 1", []}
    end

    test "empty search yields no message clause" do
      assert {sql, params} = Filter.predicates(%Filter{nodes: ["a@b"]})
      assert sql == "node IN (?)"
      assert params == ["a@b"]

      assert {sql, []} = Filter.predicates(%Filter{search: ""})
      assert sql == "1 = 1"
    end

    test "multiple nodes yield one IN clause with a placeholder per node" do
      assert {sql, params} = Filter.predicates(%Filter{nodes: ["a@b", "c@d"]})
      assert sql == "node IN (?, ?)"
      assert params == ["a@b", "c@d"]
    end

    test "wildcard search yields a LIKE clause with the translated pattern" do
      assert {sql, params} = Filter.predicates(%Filter{search: "*timeout*"})
      assert sql == "message LIKE ?"
      assert params == ["%timeout%"]
    end

    test "composes node, level, range and message in filter order" do
      {:ok, filter} =
        Filter.parse(%{
          "node" => "a@b",
          "level" => "error",
          "search" => "*boom*",
          "from" => "2026-09-01T00:00:00Z",
          "to" => "2026-09-02T00:00:00Z"
        })

      assert {sql, params} = Filter.predicates(filter)

      assert sql ==
               "node IN (?) AND level = ? AND timestamp >= ? AND timestamp <= ? AND message LIKE ?"

      assert [node, level, from, to, pattern] = params
      assert node == "a@b"
      assert level == "error"
      assert from == ~U[2026-09-01 00:00:00Z]
      assert to == ~U[2026-09-02 00:00:00Z]
      assert pattern == "%boom%"
    end

    test "composes multiple nodes with the other predicates in order" do
      {:ok, filter} =
        Filter.parse(%{
          "node" => "a@b,c@d",
          "level" => "error",
          "from" => "2026-09-01T00:00:00Z"
        })

      assert {sql, params} = Filter.predicates(filter)

      assert sql == "node IN (?, ?) AND level = ? AND timestamp >= ?"
      assert params == ["a@b", "c@d", "error", ~U[2026-09-01 00:00:00Z]]
    end

    test "every predicate value is a bound parameter, never inlined SQL" do
      {:ok, filter} =
        Filter.parse(%{
          "node" => "'; DROP TABLE logs; --",
          "level" => "error",
          "search" => "*boom*"
        })

      {sql, params} = Filter.predicates(filter)

      assert sql == "node IN (?) AND level = ? AND message LIKE ?"
      refute sql =~ "DROP"
      assert params == ["'; DROP TABLE logs; --", "error", "%boom%"]
    end

    test "an injection attempt among several nodes stays bound" do
      {:ok, filter} = Filter.parse(%{"node" => "a@b,'; DROP TABLE logs; --"})

      {sql, params} = Filter.predicates(filter)

      assert sql == "node IN (?, ?)"
      refute sql =~ "DROP"
      assert params == ["a@b", "'; DROP TABLE logs; --"]
    end

    test "all level and empty node list apply no predicate" do
      {:ok, filter} = Filter.parse(%{"level" => "all", "node" => ""})
      assert {sql, []} = Filter.predicates(filter)
      assert sql == "1 = 1"
    end
  end

  describe "parse_nodes/1" do
    test "splits comma-separated values" do
      assert Filter.parse_nodes(%{"node" => "a@b,c@d"}) == ["a@b", "c@d"]
    end

    test "trims entries and drops blanks" do
      assert Filter.parse_nodes(%{"node" => " a@b , , c@d ,"}) == ["a@b", "c@d"]
    end

    test "de-duplicates repeated nodes" do
      assert Filter.parse_nodes(%{"node" => "a@b,a@b,c@d"}) == ["a@b", "c@d"]
    end

    test "blank, comma-only and whitespace-only input mean all nodes" do
      assert Filter.parse_nodes(%{"node" => ""}) == []
      assert Filter.parse_nodes(%{"node" => " , , "}) == []
      assert Filter.parse_nodes(%{}) == []
    end
  end

  describe "nodes_to_param/1" do
    test "round-trips a parsed node list" do
      params = %{"node" => " a@b , c@d "}

      assert params
             |> Filter.parse_nodes()
             |> Filter.nodes_to_param() == "a@b,c@d"

      assert Filter.nodes_to_param([]) == ""
    end
  end

  describe "parse/1" do
    test "rejects from after to" do
      assert {:error, msg} =
               Filter.parse(%{
                 "from" => "2026-09-02T00:00:00Z",
                 "to" => "2026-09-01T00:00:00Z"
               })

      assert msg =~ "from"
    end

    test "rejects invalid level and datetime" do
      assert {:error, _} = Filter.parse(%{"level" => "fatal"})
      assert {:error, _} = Filter.parse(%{"from" => "not-a-date"})
    end

    test "composes nodes, level, range, search" do
      assert {:ok, f} =
               Filter.parse(%{
                 "node" => "my_app@10.0.0.5",
                 "level" => "error",
                 "search" => "*boom*",
                 "from" => "2026-09-01T00:00:00Z",
                 "to" => "2026-09-02T00:00:00Z",
                 "limit" => "25",
                 "offset" => "0"
               })

      assert f.nodes == ["my_app@10.0.0.5"]
      assert f.level == "error"
      assert f.search == "*boom*"
      assert f.limit == 25
    end

    test "parses several comma-separated nodes" do
      assert {:ok, f} = Filter.parse(%{"node" => "my_app@10.0.0.5, my_app@10.0.0.6"})

      assert f.nodes == ["my_app@10.0.0.5", "my_app@10.0.0.6"]
    end

    test "all-nodes has an empty node list and no level predicate" do
      assert {:ok, f} = Filter.parse(%{"level" => "all", "search" => ""})
      assert f.nodes == []
    end
  end

  describe "presets/1" do
    test "window family is a lookback that sets both bounds" do
      assert Filter.presets(:window) == [
               {"10m", {10, :minute}},
               {"1h", {1, :hour}},
               {"6h", {6, :hour}},
               {"24h", {24, :hour}},
               {"7d", {7, :day}}
             ]
    end

    test "age family is a retention cutoff that sets only the upper bound" do
      assert Filter.presets(:age) == [
               {"1d", {1, :day}},
               {"3d", {3, :day}},
               {"7d", {7, :day}},
               {"30d", {30, :day}},
               {"90d", {90, :day}}
             ]
    end

    test "the two families never share an id" do
      window_ids = for {id, _} <- Filter.presets(:window), do: id
      age_ids = for {id, _} <- Filter.presets(:age), do: id

      # "last 7 days" and "older than 7 days" are different ranges, so the
      # families must stay distinguishable by id.
      assert window_ids -- age_ids == ["10m", "1h", "6h", "24h"]
      assert age_ids -- window_ids == ["1d", "3d", "30d", "90d"]
    end

    test "preset_id/2 namespaces an id with its family" do
      assert Filter.preset_id(:window, "1h") == "window:1h"
      assert Filter.preset_id(:age, "7d") == "age:7d"
    end
  end

  describe "resolve_preset/2" do
    @now ~U[2026-09-02 12:00:00Z]

    test "a window preset anchors both bounds at now" do
      for {id, {amount, unit}} <- Filter.presets(:window) do
        preset = Filter.preset_id(:window, id)

        assert {:ok, {from, to}} = Filter.resolve_preset(preset, @now)
        assert to == @now
        assert from == DateTime.add(@now, -amount, unit)
      end
    end

    test "an age preset anchors only the upper bound and leaves the lower open" do
      for {id, {amount, unit}} <- Filter.presets(:age) do
        preset = Filter.preset_id(:age, id)

        assert {:ok, {nil, to}} = Filter.resolve_preset(preset, @now)
        assert to == DateTime.add(@now, -amount, unit)
      end
    end

    test "the same duration in different families resolves to different ranges" do
      assert {:ok, {from, to}} = Filter.resolve_preset("window:7d", @now)
      assert {:ok, {nil, cutoff}} = Filter.resolve_preset("age:7d", @now)

      assert from != nil
      assert to == @now
      assert cutoff == from
    end

    test "an absent or blank preset means no range" do
      assert {:ok, {nil, nil}} = Filter.resolve_preset(nil, @now)
      assert {:ok, {nil, nil}} = Filter.resolve_preset("", @now)
      assert {:ok, {nil, nil}} = Filter.resolve_preset("   ", @now)
    end

    test "an unrecognized preset is rejected and names the offered ids" do
      for bad <- ["1h", "window", "window:", "window:2h", "age:1h", "month:1m", "window:1h:x"] do
        assert {:error, message} = Filter.resolve_preset(bad, @now)
        assert message =~ "invalid preset"
        assert message =~ ~s("window:1h")
      end
    end
  end

  describe "parse/1 with a preset" do
    test "a window preset resolves both bounds against the request clock" do
      assert {:ok, f} = Filter.parse(%{"preset" => "window:1h"})

      assert f.preset == "window:1h"
      assert f.to
      assert f.from

      # Both bounds land inside the same one-hour window ending now.
      assert_in_delta DateTime.diff(f.to, f.from, :second), 3600, 1
      assert DateTime.diff(DateTime.utc_now(), f.to, :second) in 0..2
    end

    test "an age preset leaves the lower bound open" do
      assert {:ok, f} = Filter.parse(%{"preset" => "age:30d"})

      assert f.from == nil
      assert f.to
      assert DateTime.diff(DateTime.utc_now(), f.to, :day) in 30..31
    end

    test "a present preset overrides explicit bounds in the same request" do
      assert {:ok, f} =
               Filter.parse(%{
                 "preset" => "window:10m",
                 "from" => "2020-01-01T00:00:00Z",
                 "to" => "2020-01-02T00:00:00Z"
               })

      refute f.from == ~U[2020-01-01 00:00:00Z]
      refute f.to == ~U[2020-01-02 00:00:00Z]
      assert DateTime.diff(f.to, f.from, :second) == 600
    end

    test "a preset cannot smuggle an unparseable bound past validation" do
      # The preset supplies the bounds, so the malformed `from` is never read.
      # What must not happen is the malformed value reaching the query.
      assert {:ok, f} = Filter.parse(%{"preset" => "window:10m", "from" => "not-a-date"})
      assert %DateTime{} = f.from

      {sql, params} = Filter.predicates(f)
      assert sql == "timestamp >= ? AND timestamp <= ?"
      refute inspect(params) =~ "not-a-date"
    end

    test "an unrecognized preset is rejected before any bound is read" do
      assert {:error, message} =
               Filter.parse(%{"preset" => "window:2h", "from" => "2020-01-01T00:00:00Z"})

      assert message =~ "invalid preset"
    end

    test "no preset keeps the explicit range and the from-after-to rejection" do
      assert {:ok, f} =
               Filter.parse(%{"from" => "2026-09-01T00:00:00Z", "to" => "2026-09-02T00:00:00Z"})

      assert f.preset == nil
      assert f.from == ~U[2026-09-01 00:00:00Z]
      assert f.to == ~U[2026-09-02 00:00:00Z]

      assert {:error, message} =
               Filter.parse(%{"from" => "2026-09-02T00:00:00Z", "to" => "2026-09-01T00:00:00Z"})

      assert message =~ "from"
      assert {:error, _} = Filter.parse(%{"from" => "not-a-date"})
    end

    test "a preset-resolved filter builds the same predicates as an explicit one" do
      assert {:ok, preset_filter} =
               Filter.parse(%{
                 "preset" => "window:1h",
                 "node" => "a@b,c@d",
                 "level" => "error",
                 "search" => "*boom*"
               })

      {sql, [node_a, node_b, level, from, to, pattern]} =
        Filter.predicates(preset_filter)

      assert sql ==
               "node IN (?, ?) AND level = ? AND timestamp >= ? AND timestamp <= ? AND message LIKE ?"

      assert node_a == "a@b"
      assert node_b == "c@d"
      assert level == "error"
      assert %DateTime{} = from
      assert %DateTime{} = to
      assert pattern == "%boom%"
    end
  end

  describe "to_params/1" do
    test "round-trips through parse/1 for an explicitly bounded filter" do
      assert {:ok, filter} =
               Filter.parse(%{
                 "node" => " a@b , c@d ",
                 "level" => "error",
                 "search" => "*boom*",
                 "from" => "2026-09-01T00:00:00Z",
                 "to" => "2026-09-02T00:00:00Z",
                 "limit" => "25"
               })

      assert {:ok, reparsed} = Filter.parse(Filter.to_params(filter))

      assert reparsed.nodes == filter.nodes
      assert reparsed.level == filter.level
      assert reparsed.search == filter.search
      assert reparsed.from == filter.from
      assert reparsed.to == filter.to
      assert reparsed.limit == filter.limit
    end

    test "exposes the instants a preset resolved to" do
      assert {:ok, filter} = Filter.parse(%{"preset" => "window:1h"})

      params = Filter.to_params(filter)

      assert params["preset"] == "window:1h"
      assert {:ok, %DateTime{}, 0} = DateTime.from_iso8601(params["from"])
      assert {:ok, %DateTime{}, 0} = DateTime.from_iso8601(params["to"])
      assert params["from"] != ""
      assert params["to"] != ""

      # Second precision, matching what the picker can represent.
      assert params["from"] =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/
      assert params["to"] =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/
    end

    test "omits the preset key when none is active and blanks absent bounds" do
      params = Filter.to_params(%Filter{})

      refute Map.has_key?(params, "preset")
      assert params["from"] == ""
      assert params["to"] == ""
    end
  end

  describe "parse/1 pagination" do
    test "defaults to 100 when the URL carries no size" do
      assert {:ok, filter} = Filter.parse(%{})

      assert filter.limit == 100
      assert filter.offset == 0
    end

    test "a positive whole size is honoured even when it is no longer offered" do
      # The offered set changed from 25/50/100 to 100/500/3000. An existing
      # bookmark carrying an older size still has to render that page size
      # rather than being silently resized.
      assert {:ok, filter} = Filter.parse(%{"limit" => "25"})

      assert filter.limit == 25
    end

    test "a size above the maximum is capped rather than rejected" do
      assert {:ok, filter} = Filter.parse(%{"limit" => "5000"})

      assert filter.limit == 3000
    end

    test "an unreadable size falls back to the default rather than erroring" do
      assert {:ok, filter} = Filter.parse(%{"limit" => "abc"})

      assert filter.limit == 100
    end

    test "a size below one is raised to one and a negative offset to zero" do
      assert {:ok, filter} = Filter.parse(%{"limit" => "0", "offset" => "-5"})

      assert filter.limit == 1
      assert filter.offset == 0
    end
  end

  describe "page_sizes/0 and limit_options/1" do
    test "offers 100, 500 and 3000, and the default is one of them" do
      assert Filter.page_sizes() == ["100", "500", "3000"]
      assert Integer.to_string(Filter.default_limit()) in Filter.page_sizes()
    end

    test "an offered size adds no option, so the control offers exactly three" do
      assert Filter.limit_options(500) == ["100", "500", "3000"]
      assert Filter.limit_options(Filter.default_limit()) == ["100", "500", "3000"]
    end

    test "a size outside the offered set is appended so the control can show it" do
      # Rendering the options without the active value would leave the select
      # with nothing selected, which reads as "no page size" rather than "25".
      assert Filter.limit_options(25) == ["100", "500", "3000", "25"]
    end
  end
end
