defmodule LoggerDashboardWeb.AnalysisLiveDataTest do
  @moduledoc """
  Behaviour of the analysis page against real rows.

  Split out from `analysis_live_test.exs` because these cases need seeded rows,
  which means a running ClickHouse and a module that cannot run concurrently
  with itself. The other file stays async and asserts structure only.

  The cases here are the regressions: each one fails against the page as it was
  before the results it checks were reported accurately.
  """

  use LoggerDashboardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias LoggerDashboard.Logs.Analysis

  @moduletag :clickhouse

  setup do
    node = unique_node("rich")
    quieter = unique_node("aaa-quieter")
    empty = unique_node("empty")

    now = DateTime.truncate(DateTime.utc_now(), :microsecond)

    rows = [
      # Two levels on `node`, across two hours, so the volume result pivots into
      # one series per level and spans more than one bucket.
      %{node: node, level: "error", minutes_ago: 10, message: "rich error one"},
      %{node: node, level: "error", minutes_ago: 70, message: "rich error two"},
      %{node: node, level: "info", minutes_ago: 20, message: "rich info"},
      # One row on a second node, named so it sorts before `node`
      # alphabetically while holding fewer rows.
      %{node: quieter, level: "info", minutes_ago: 30, message: "quieter info"}
    ]

    assert {:ok, _} =
             ClickhouseExLogger.Insert.insert(
               Enum.map(rows, fn row ->
                 %{
                   id: Ash.UUID.generate(),
                   timestamp: DateTime.add(now, -row.minutes_ago * 60, :second),
                   level: row.level,
                   message: row.message,
                   module: "Test",
                   file: nil,
                   line: nil,
                   function: nil,
                   metadata: %{},
                   node: row.node
                 }
               end)
             )

    # async_insert needs a moment to become queryable
    Process.sleep(2_000)

    on_exit(fn ->
      ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE node IN (?, ?, ?)", [
        node,
        quieter,
        empty
      ])
    end)

    {:ok, node: node, quieter: quieter, empty: empty}
  end

  describe "volume over time" do
    test "renders a named value for every series the analysis produced", %{
      conn: conn,
      node: node
    } do
      {:ok, lv, _html} = live(conn, "/analysis?node=#{node}&bucket=hour")

      {:ok, filter} = LoggerDashboard.Logs.Filter.parse(%{"node" => node})
      {:ok, result} = Analysis.volume_over_time(filter, :hour, limit: 1_000, split_by_level: true)

      # Splitting by level means the analysis produced one series per level, so
      # the table needs a column per series. Before the fix it rendered only the
      # first, showing one level's counts with no column saying which level.
      assert length(result.series) >= 2

      rows = rendered_rows(lv, "#analysis-volume")

      for series <- result.series do
        assert Enum.any?(rows, fn {_label, values} ->
                 Enum.any?(values, fn {name, _value} -> name == series.name end)
               end),
               "expected a rendered value for series #{series.name}, got #{inspect(rows)}"
      end

      # Every value cell is attributed, and the set of series rendered is exactly
      # the set the analysis produced.
      rendered_series =
        rows
        |> Enum.flat_map(fn {_label, values} -> Enum.map(values, &elem(&1, 0)) end)
        |> Enum.uniq()
        |> Enum.sort()

      assert rendered_series == result.series |> Enum.map(& &1.name) |> Enum.sort()
    end

    test "labels its first column Bucket", %{conn: conn, node: node} do
      {:ok, lv, _html} = live(conn, "/analysis?node=#{node}&bucket=hour")

      assert has_element?(lv, "#analysis-volume thead th[scope=col]", "Bucket")
    end

    test "a scope matching no rows renders headers and no rows", %{
      conn: conn,
      empty: empty
    } do
      {:ok, lv, _html} = live(conn, "/analysis?node=#{empty}")

      assert has_element?(lv, "#analysis-volume thead th[scope=col]")
      refute has_element?(lv, "#analysis-volume tbody tr")
      refute has_element?(lv, "#analysis-levels tbody tr")
      refute has_element?(lv, "#analysis-nodes tbody tr")
    end
  end

  describe "by level" do
    test "lists the dominant level first and names the single series", %{
      conn: conn,
      node: node
    } do
      {:ok, lv, _html} = live(conn, "/analysis?node=#{node}")

      {:ok, filter} = LoggerDashboard.Logs.Filter.parse(%{"node" => node})
      {:ok, result} = Analysis.level_frequency(filter, limit: 1_000)

      # `error` holds 2 rows and `info` holds 1, so descending-by-count and
      # alphabetical ordering cannot both produce this.
      assert result.labels == ["error", "info"]

      assert [{"error", [{"level", "2"}]}, {"info", [{"level", "1"}]}] =
               rendered_rows(lv, "#analysis-levels")
    end
  end

  describe "by node" do
    test "lists the busiest node first", %{conn: conn, node: node, quieter: quieter} do
      {:ok, lv, _html} = live(conn, "/analysis?node=#{node},#{quieter}")

      # `quieter` sorts before `node` alphabetically while holding fewer rows, so
      # this only holds for a descending-by-count ordering.
      assert [{^node, [{"node", "3"}]}, {^quieter, [{"node", "1"}]}] =
               rendered_rows(lv, "#analysis-nodes")
    end

    test "names its single series", %{conn: conn, node: node} do
      {:ok, lv, _html} = live(conn, "/analysis?node=#{node}")

      assert has_element?(lv, "#analysis-nodes thead th[data-series=node]")
      assert has_element?(lv, "#analysis-nodes thead th[scope=col]", "Node")
    end
  end

  describe "bucket control" do
    test "marks the applied bucket as selected", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?bucket=day")

      assert has_element?(lv, "#filters_bucket option[value=day][selected]")
      refute has_element?(lv, "#filters_bucket option[value=hour][selected]")
    end

    test "falls back visibly on an unsupported bucket", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?bucket=nope")

      assert has_element?(lv, "#filters_bucket option[value=hour][selected]")
    end

    test "offers exactly the buckets the page supports", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      assert offered_buckets(lv, "#filters_bucket") == ["hour", "day"]
    end

    test "keeps the chosen bucket when the form is submitted", %{conn: conn, node: node} do
      {:ok, lv, _html} = live(conn, "/analysis?node=#{node}&bucket=day")

      lv
      |> form("#analysis-filter-form", filters: %{level: "error"})
      |> render_submit()

      assert has_element?(lv, "#filters_bucket option[value=day][selected]")
    end
  end

  describe "rejected filter" do
    test "leaves no previous results on screen", %{conn: conn, node: node} do
      {:ok, lv, _html} = live(conn, "/analysis?node=#{node}")

      # The page is showing results before the rejection.
      assert has_element?(lv, "#analysis-levels tbody tr")
      assert has_element?(lv, "#analysis-volume tbody tr")
      assert has_element?(lv, "#analysis-nodes tbody tr")

      lv |> render_patch("/analysis?node=#{node}&from=bad-date")

      assert has_element?(lv, "#analysis-filter-error")
      refute has_element?(lv, "#analysis-levels tbody tr")
      refute has_element?(lv, "#analysis-volume tbody tr")
      refute has_element?(lv, "#analysis-nodes tbody tr")
    end
  end

  describe "keyword" do
    test "narrows every breakdown to the keyword scope", %{conn: conn, node: node} do
      {:ok, lv, _html} = live(conn, "/analysis?node=#{node}&search=*rich%20error*")

      assert rendered_rows(lv, "#analysis-levels") == [{"error", [{"level", "2"}]}]
      assert rendered_rows(lv, "#analysis-nodes") == [{node, [{"node", "2"}]}]
    end

    test "a keyword scope matching no rows renders empty tables", %{conn: conn, empty: empty} do
      {:ok, lv, _html} = live(conn, "/analysis?node=#{empty}&search=*rich*")

      refute has_element?(lv, "#analysis-levels tbody tr")
      refute has_element?(lv, "#analysis-volume tbody tr")
      refute has_element?(lv, "#analysis-nodes tbody tr")
    end

    test "keeps the limit disclosure with a keyword active", %{conn: conn, node: node} do
      {:ok, lv, _html} = live(conn, "/analysis?node=#{node}&search=*rich*")

      applied = Analysis.applied_limit(limit: 1_000)
      assert lv |> element("#analysis-limit") |> render() =~ to_string(applied)
    end
  end

  describe "limit disclosure" do
    test "reports the applied limit after a query runs", %{conn: conn, node: node} do
      {:ok, lv, _html} = live(conn, "/analysis?node=#{node}")

      applied = Analysis.applied_limit(limit: 1_000)
      max = AshDyan.Info.max_limit(LoggerDashboard.Logs.LogView)

      assert lv |> element("#analysis-limit") |> render() =~ to_string(applied)
      assert applied == min(1_000, max)
    end
  end

  describe "node options" do
    test "offers known nodes independent of the current scope", %{
      conn: conn,
      node: node,
      quieter: quieter
    } do
      # The page itself matches nothing, yet the options still list the table's
      # nodes rather than the page's scope.
      {:ok, lv, _html} =
        live(conn, "/analysis?node=no-such-node-#{System.unique_integer([:positive])}")

      assert has_element?(lv, ~s(#analysis-node-options [data-node="#{node}"]))
      assert has_element?(lv, ~s(#analysis-node-options [data-node="#{quieter}"]))
    end

    test "clicking a node option toggles it through the URL scope", %{conn: conn, node: node} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      assert has_element?(
               lv,
               ~s(#analysis-node-options [data-node="#{node}"][aria-pressed="false"])
             )

      lv |> element(~s(#analysis-node-options [data-node="#{node}"])) |> render_click()

      assert has_element?(
               lv,
               ~s(#analysis-node-options [data-node="#{node}"][aria-pressed="true"])
             )

      assert has_element?(lv, ~s(#analysis-active-nodes [data-node="#{node}"]))

      lv |> element(~s(#analysis-node-options [data-node="#{node}"])) |> render_click()

      assert has_element?(lv, "#analysis-active-nodes[hidden]")
    end
  end

  # The rendered table as `[{row_label, [{series_name, value_text}]}]`, read
  # through LazyHTML so an assertion names the structure it depends on rather
  # than the markup around it.
  defp rendered_rows(lv, selector) do
    lv
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("tbody tr")
    |> Enum.map(fn row ->
      label = row |> LazyHTML.query(~s(th[scope="row"])) |> LazyHTML.text() |> String.trim()

      values =
        row
        |> LazyHTML.query("td[data-series]")
        |> Enum.map(fn cell ->
          {cell |> LazyHTML.attribute("data-series") |> to_string(),
           cell |> LazyHTML.text() |> String.trim()}
        end)

      {label, values}
    end)
  end

  defp offered_buckets(lv, selector) do
    lv
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("option")
    |> Enum.map(&(&1 |> LazyHTML.attribute("value") |> to_string()))
  end

  defp unique_node(tag) do
    "#{tag}-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}-#{:rand.uniform(1_000_000)}@host"
  end
end
