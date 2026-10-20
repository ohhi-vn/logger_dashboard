defmodule LoggerDashboardWeb.AnalysisLiveTest do
  use LoggerDashboardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders controls, charts, tables and limit badge", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      assert has_element?(lv, "#analysis-filter-form")
      assert has_element?(lv, "#analysis-chart-level")
      assert has_element?(lv, "#analysis-chart-volume")
      assert has_element?(lv, "#analysis-levels")
      assert has_element?(lv, "#analysis-volume")
      assert has_element?(lv, "#analysis-nodes")
      assert has_element?(lv, "#analysis-limit")
    end

    test "invalid datetime shows filter error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis?from=bad-date")

      assert has_element?(lv, "#analysis-filter-error")
    end

    test "renders navigation with analysis marked as the active page", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      assert has_element?(lv, "#dashboard-nav")
      assert has_element?(lv, ~s(#dashboard-nav a[aria-current="page"][href="/analysis"]))

      refute has_element?(lv, ~s(#dashboard-nav a[aria-current="page"][href="/logs"]))
    end

    test "shows no active nodes and hides the clear action by default", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      refute has_element?(lv, ~s(#analysis-node-options [aria-pressed="true"]))
      assert has_element?(lv, "#analysis-clear-nodes[hidden]")
    end

    test "shows each selected node and offers a clear action", %{conn: conn} do
      # A bare path because a comma in the node value would be read as a query
      # separator by the verified-routes sigil.
      {:ok, lv, _html} = live(conn, "/analysis?node=a@h,b@h")

      assert has_element?(lv, "#analysis-clear-nodes:not([hidden])")
      assert has_element?(lv, ~s(#analysis-node-options [data-node="a@h"][aria-pressed="true"]))
      assert has_element?(lv, ~s(#analysis-node-options [data-node="b@h"][aria-pressed="true"]))
    end

    test "states the node scope through the node options alone", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?node=a@h")

      # The summary list that repeated the scope beside the control is gone:
      # the options are the one place the scope is stated, so its two
      # renderings can never disagree.
      refute has_element?(lv, "#analysis-active-nodes")
      assert has_element?(lv, ~s(#analysis-node-options [data-node="a@h"][aria-pressed="true"]))
    end

    test "blank and comma-only node input is all nodes", %{conn: conn} do
      for value <- ["", " , , "] do
        {:ok, lv, _html} = live(conn, "/analysis?node=" <> URI.encode_www_form(value))

        refute has_element?(lv, ~s(#analysis-node-options [aria-pressed="true"]))
      end
    end

    test "clearing nodes returns to all nodes and keeps the other filters", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?node=a@h&level=error")

      assert has_element?(lv, "#analysis-clear-nodes:not([hidden])")

      lv |> element("#analysis-clear-nodes") |> render_click()

      refute has_element?(lv, ~s(#analysis-node-options [aria-pressed="true"]))
      assert lv |> element("#analysis-filter-form") |> render() =~ "error"
    end

    test "shares the viewer's datetime controls", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      assert has_element?(lv, "#analysis-from-picker")
      assert has_element?(lv, "#analysis-to-picker")
      refute has_element?(lv, "#analysis-from-picker[name]")

      for preset <- ~w(window:10m window:1h window:6h window:24h window:7d) do
        assert has_element?(lv, ~s(#analysis-shortcuts [data-preset="#{preset}"]))
      end

      refute has_element?(lv, ~s(#analysis-shortcuts [data-preset="age:7d"]))
      assert has_element?(lv, "#analysis-shortcuts-all-time")
    end

    test "a shortcut resolves the range and a hand-entered bound replaces it", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      lv |> element("#analysis-shortcuts [data-preset='window:6h']") |> render_click()

      assert has_element?(lv, "#analysis-shortcuts [data-preset='window:6h'][aria-pressed=true]")
      assert has_element?(lv, "#analysis-shortcuts-all-time[aria-pressed=false]")

      from = input_value(lv, "filters_from")
      to = input_value(lv, "filters_to")
      assert from != "" and to != ""
      assert_in_delta seconds_between(from, to), 6 * 3600, 1

      lv
      |> form("#analysis-filter-form", filters: %{from: "2026-01-01T00:00:00Z"})
      |> render_submit()

      assert input_value(lv, "filters_from") == "2026-01-01T00:00:00Z"
      assert has_element?(lv, "#analysis-shortcuts-all-time[aria-pressed=true]")
    end

    test "clearing nodes keeps the active shortcut", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?node=a@h&preset=window:1h")

      lv |> element("#analysis-clear-nodes") |> render_click()

      refute has_element?(lv, ~s(#analysis-node-options [aria-pressed="true"]))
      assert has_element?(lv, "#analysis-shortcuts [data-preset='window:1h'][aria-pressed=true]")
    end

    test "offers a search input that round-trips a keyword", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?search=*timeout*")

      assert input_value(lv, "filters_search") == "*timeout*"

      lv
      |> form("#analysis-filter-form", filters: %{search: "*boom*"})
      |> render_submit()

      assert input_value(lv, "filters_search") == "*boom*"
    end

    test "a handoff from the logs page applies the same filters", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?node=a@h&search=*boom*&level=error")

      assert input_value(lv, "filters_search") == "*boom*"

      assert has_element?(
               lv,
               ~s(#analysis-level-options [data-level="error"][aria-pressed="true"])
             )

      assert has_element?(lv, ~s(#analysis-node-options [data-node="a@h"][aria-pressed="true"]))
    end

    test "toggling a node keeps the search keyword", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?search=*x*&level=error")

      render_click(lv, "toggle-node", %{"node" => "b@h"})

      assert input_value(lv, "filters_search") == "*x*"
      assert has_element?(lv, ~s(#analysis-node-options [data-node="b@h"][aria-pressed="true"]))
    end

    test "the shared filter controls are the only node, level and search controls", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      # One node control, one level control, one search control: the page
      # offers no second, page-specific variant of any of them.
      assert has_element?(lv, "#analysis-node-options")
      assert has_element?(lv, "#analysis-level-options")
      assert has_element?(lv, "#filters_search")

      refute has_element?(lv, ~s(#analysis-filter-form input[name="filters[node]"]))
      refute has_element?(lv, "#filters_level")
    end

    test "the search control states the shared syntax", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      assert has_element?(lv, "#analysis-search-help")
      assert lv |> element("#analysis-search-help") |> render() =~ "ignores case"
      assert lv |> element("#analysis-search-help") |> render() =~ "combined with AND"
    end

    test "toggling a node keeps the bucket and the other filters", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?node=a@h&bucket=day&level=error")

      render_click(lv, "toggle-node", %{"node" => "b@h"})

      # The scope grew; the bucket and the level the operator chose stayed.
      assert has_element?(lv, ~s(#analysis-node-options [data-node="a@h"][aria-pressed="true"]))
      assert has_element?(lv, ~s(#analysis-node-options [data-node="b@h"][aria-pressed="true"]))
      assert has_element?(lv, "#filters_bucket option[value=day][selected]")

      assert has_element?(
               lv,
               ~s(#analysis-level-options [data-level="error"][aria-pressed="true"])
             )
    end
  end

  describe "click-to-filter" do
    test "toggling a node adds it to the scope and keeps the other filters", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?node=a@h&level=error")

      render_click(lv, "toggle-node", %{"node" => "b@h"})

      assert has_element?(lv, ~s(#analysis-node-options [data-node="a@h"][aria-pressed="true"]))
      assert has_element?(lv, ~s(#analysis-node-options [data-node="b@h"][aria-pressed="true"]))

      assert has_element?(
               lv,
               ~s(#analysis-level-options [data-level="error"][aria-pressed="true"])
             )
    end

    test "toggling a selected node removes it, and the last one returns to all nodes", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, "/analysis?node=" <> URI.encode_www_form("a@h,b@h"))

      render_click(lv, "toggle-node", %{"node" => "a@h"})

      refute has_element?(lv, ~s(#analysis-node-options [data-node="a@h"][aria-pressed="true"]))
      assert has_element?(lv, ~s(#analysis-node-options [data-node="b@h"][aria-pressed="true"]))

      render_click(lv, "toggle-node", %{"node" => "b@h"})

      refute has_element?(lv, ~s(#analysis-node-options [aria-pressed="true"]))
    end

    test "toggling a blank node value changes nothing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?node=a@h")

      render_click(lv, "toggle-node", %{"node" => "  "})

      assert has_element?(lv, ~s(#analysis-node-options [data-node="a@h"][aria-pressed="true"]))
    end

    test "clicking levels toggles them and clicking all clears the set", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      render_click(lv, "select-level", %{"level" => "warning"})

      assert has_element?(
               lv,
               ~s(#analysis-level-options [data-level="warning"][aria-pressed="true"])
             )

      # Clicking a second level adds it instead of replacing the first.
      render_click(lv, "select-level", %{"level" => "info"})

      assert has_element?(
               lv,
               ~s(#analysis-level-options [data-level="warning"][aria-pressed="true"])
             )

      assert has_element?(
               lv,
               ~s(#analysis-level-options [data-level="info"][aria-pressed="true"])
             )

      # Clicking a selected level removes it again.
      render_click(lv, "select-level", %{"level" => "warning"})

      assert has_element?(
               lv,
               ~s(#analysis-level-options [data-level="warning"][aria-pressed="false"])
             )

      assert has_element?(
               lv,
               ~s(#analysis-level-options [data-level="info"][aria-pressed="true"])
             )

      render_click(lv, "select-level", %{"level" => "all"})

      assert has_element?(
               lv,
               ~s(#analysis-level-options [data-level="all"][aria-pressed="true"])
             )
    end

    test "a multi-level scope marks every selected level", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?level=" <> URI.encode_www_form("error,warning"))

      assert has_element?(
               lv,
               ~s(#analysis-level-options [data-level="error"][aria-pressed="true"])
             )

      assert has_element?(
               lv,
               ~s(#analysis-level-options [data-level="warning"][aria-pressed="true"])
             )

      assert has_element?(
               lv,
               ~s(#analysis-level-options [data-level="info"][aria-pressed="false"])
             )
    end

    test "clicking an unknown level is ignored", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?level=error")

      render_click(lv, "select-level", %{"level" => "fatal"})

      assert has_element?(
               lv,
               ~s(#analysis-level-options [data-level="error"][aria-pressed="true"])
             )
    end

    test "level selector is a single badge group inside the filter card", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      assert has_element?(lv, "#analysis-filter-form #analysis-level-options")
      refute has_element?(lv, "#filters_level")

      for level <- ~w(error warning info debug all) do
        assert has_element?(lv, ~s(#analysis-level-options [data-level="#{level}"]))
      end
    end
  end

  describe "redesigned filter" do
    test "badges are the only node selector with select-all and Refresh, no Run or Reset", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      assert has_element?(lv, "#analysis-node-options")
      assert has_element?(lv, "#analysis-select-all-nodes")
      assert has_element?(lv, "#analysis-refresh")

      refute has_element?(lv, ~s(#analysis-filter-form input[name="filters[node]"]))
      refute lv |> element("#analysis-filter-form") |> render() =~ "Run analysis"
      refute has_element?(lv, "#analysis-filter-form a", "Reset")
    end

    test "select-all returns to whole-system scope and keeps the level", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?node=a@h&level=error")

      assert has_element?(lv, "#analysis-select-all-nodes:not([hidden])")

      lv |> element("#analysis-select-all-nodes") |> render_click()

      refute has_element?(lv, ~s(#analysis-node-options [aria-pressed="true"]))

      assert has_element?(
               lv,
               ~s(#analysis-level-options [data-level="error"][aria-pressed="true"])
             )
    end

    test "committing the form keeps the badge-selected node scope", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?node=a@h")

      lv
      |> form("#analysis-filter-form", filters: %{search: "*boom*"})
      |> render_submit()

      assert has_element?(lv, ~s(#analysis-node-options [data-node="a@h"][aria-pressed="true"]))
      assert input_value(lv, "filters_search") == "*boom*"
    end

    test "refresh recomputes the current URL scope without changing it", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?node=a@h&level=error")

      lv |> element("#analysis-refresh") |> render_click()

      assert has_element?(lv, ~s(#analysis-node-options [data-node="a@h"][aria-pressed="true"]))

      assert has_element?(
               lv,
               ~s(#analysis-level-options [data-level="error"][aria-pressed="true"])
             )

      refute has_element?(lv, "#analysis-filter-error")
    end
  end

  describe "chart styles" do
    test "every charted breakdown offers a style control", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      assert has_element?(lv, "#analysis-chart-level-style")
      assert has_element?(lv, "#analysis-chart-volume-style")
      assert has_element?(lv, "#analysis-chart-node-style")
    end

    test "the styles offered fit the breakdown", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      # A level or node breakdown is one series of counts, so a pie and a
      # donut can represent it. A volume breakdown is a series over time, and
      # a pie of it could not.
      for style <- ~w(bar pie donut) do
        assert has_element?(
                 lv,
                 "#analysis-chart-level-style [id='analysis-chart-level-style-#{style}']"
               )

        assert has_element?(
                 lv,
                 "#analysis-chart-node-style [id='analysis-chart-node-style-#{style}']"
               )
      end

      for style <- ~w(bar line area) do
        assert has_element?(
                 lv,
                 "#analysis-chart-volume-style [id='analysis-chart-volume-style-#{style}']"
               )
      end

      refute has_element?(
               lv,
               "#analysis-chart-volume-style [id='analysis-chart-volume-style-pie']"
             )
    end

    test "each style is labelled with a readable name", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      # The button face reads a name an operator recognises, not the machine
      # name the URL carries.
      assert lv
             |> element("#analysis-chart-level-style [id='analysis-chart-level-style-pie']")
             |> render() =~ "Pie"

      assert lv
             |> element("#analysis-chart-level-style [id='analysis-chart-level-style-bar']")
             |> render() =~ "Bar"

      assert lv
             |> element("#analysis-chart-volume-style [id='analysis-chart-volume-style-area']")
             |> render() =~ "Area"

      # The control's id still carries the machine name, so the styles stay
      # addressable by it.
      assert has_element?(
               lv,
               "#analysis-chart-level-style [id='analysis-chart-level-style-pie']"
             )
    end

    test "an unknown style falls back to the default and the control shows it", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?level_chart=nonsense")

      assert has_element?(
               lv,
               "#analysis-chart-level-style [id='analysis-chart-level-style-bar'][aria-pressed=\"true\"]"
             )
    end

    test "a style the data cannot represent falls back visibly", %{conn: conn} do
      # A pie cannot represent the multi-series volume breakdown, so the
      # request falls back to the recommended style and the control shows the
      # style actually in use.
      {:ok, lv, _html} = live(conn, "/analysis?volume_chart=pie")

      assert has_element?(
               lv,
               "#analysis-chart-volume-style [id='analysis-chart-volume-style-line'][aria-pressed=\"true\"]"
             )
    end

    test "the by-node breakdown is charted beside its table", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      assert has_element?(lv, "#analysis-chart-node")
      assert has_element?(lv, "#analysis-nodes")
    end

    test "choosing a style changes the chart and needs no run action", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      before = chart_config(lv, "analysis-chart-level")

      lv |> element("#analysis-chart-level-style-pie") |> render_click()

      after_click = chart_config(lv, "analysis-chart-level")

      # The chart config changed, so the chart is drawn differently.
      refute before == after_click
      assert after_click =~ ~s("type":"pie")

      assert has_element?(
               lv,
               "#analysis-chart-level-style [id='analysis-chart-level-style-pie'][aria-pressed=\"true\"]"
             )
    end

    test "the chosen style travels in the URL", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      lv |> element("#analysis-chart-volume-style-area") |> render_click()

      # An area chart is a filled line, so the style shows up as the fill the
      # datasets carry rather than as a different chart type.
      assert chart_config(lv, "analysis-chart-volume") =~ ~s("fill":true)

      assert has_element?(
               lv,
               "#analysis-chart-volume-style [id='analysis-chart-volume-style-area'][aria-pressed=\"true\"]"
             )
    end

    test "the chosen style survives a reload", %{conn: conn} do
      # The style travels in the URL, so a shared link reproduces the same
      # charts without re-choosing the style.
      {:ok, _lv, _html} = live(conn, "/analysis?level_chart=pie")

      {:ok, reloaded, _html} = live(conn, "/analysis?level_chart=pie")

      assert has_element?(
               reloaded,
               "#analysis-chart-level-style [id='analysis-chart-level-style-pie'][aria-pressed=\"true\"]"
             )
    end

    test "picking a label sends the machine name in the URL", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      lv |> element("#analysis-chart-level-style-pie") |> render_click()

      # The button reads "Pie" but the param carries "pie", so the link the
      # operator copies selects the same chart on a shared page.
      assert_patched(lv, "/analysis?level_chart=pie")

      assert chart_config(lv, "analysis-chart-level") =~ ~s("type":"pie")
    end

    test "the chart config is re-rendered when the scope changes", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      before = chart_config(lv, "analysis-chart-volume")

      # A day bucket labels the volume differently from an hour bucket, so
      # the chart is drawn from different data.
      render_change(lv, "filter", %{"filters" => %{"bucket" => "day"}})

      refute before == chart_config(lv, "analysis-chart-volume")
    end

    test "every chart is drawn in a frame it cannot outgrow", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      # The option rides in the config the hook receives, so it is merged in
      # the one place every breakdown's config is assembled: all three charts
      # measure a definite height rather than deriving one from the width of
      # the column they sit in.
      for id <- ~w(analysis-chart-level analysis-chart-node analysis-chart-volume) do
        assert chart_config(lv, id) =~ ~s("maintainAspectRatio":false)
      end
    end
  end

  describe "breakdown layout" do
    test "the three breakdowns are siblings of one grid, ordered by level, by node, volume over time",
         %{
           conn: conn
         } do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      # One grid element holds all three cards. DOM order is the reading order
      # — so tab order matches what is on screen — and the by-node card takes
      # a column of the row rather than spanning the page as its own block.
      cards =
        lv
        |> element("#analysis-breakdowns")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("div#analysis-breakdowns > div")

      assert Enum.map(cards, &(&1 |> LazyHTML.attribute("id") |> to_string())) == [
               "analysis-breakdown-level",
               "analysis-breakdown-node",
               "analysis-breakdown-volume"
             ]

      # The frequency breakdowns take three of the grid's columns each and the
      # time series six, so the time series is twice the width of either
      # frequency breakdown wherever it matters.
      by_node = Enum.at(cards, 1) |> LazyHTML.attribute("class") |> to_string()
      assert by_node =~ "md:col-span-3"
      refute by_node =~ "md:col-span-6"

      assert Enum.at(cards, 2) |> LazyHTML.attribute("class") |> to_string() =~ "md:col-span-6"
    end

    test "the breakdowns read in the visual order", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      headings =
        lv
        |> element("#analysis-breakdowns")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("div#analysis-breakdowns h2")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      assert headings == ["By level", "By node", "Volume over time"]
    end

    test "each chart sits in a frame of definite height", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      for id <- ~w(analysis-chart-level analysis-chart-node analysis-chart-volume) do
        # The canvas is a child of the fixed-height frame, and it fills the
        # frame — a canvas is inline by default, so `block` is what makes it
        # take the height at all.
        assert has_element?(lv, ~s(#analysis-breakdowns .h-56 > ##{id}))
        assert has_element?(lv, ~s(##{id}.block.h-full.w-full))
      end
    end

    test "the result tables share one compact density inside a bounded region", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      # The same treatment from the one component all three share: compact
      # rows, in a region that scrolls, with the header row pinned there.
      for id <- ~w(analysis-levels analysis-volume analysis-nodes) do
        assert has_element?(lv, ~s(div.max-h-64.overflow-auto > ##{id}.table-xs.table-pin-rows))
      end
    end

    test "the filter card's rows are filled through to the bucket", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      rows =
        lv
        |> element("#analysis-filter-form")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("form#analysis-filter-form > div")
        |> Enum.map(&(&1 |> LazyHTML.attribute("class") |> to_string()))

      # In order: search, the two bounds, the bucket, the level options, then
      # the actions. Each row sums to the card's six columns — 3 + 1 + 1 + 1,
      # then 6, then 6 — so no row of the card is left partly empty on a wide
      # viewport, and the bucket sits with the controls it qualifies.
      assert rows == [
               "md:col-span-3",
               "flex flex-col gap-1 md:col-span-1",
               "flex flex-col gap-1 md:col-span-1",
               "md:col-span-1",
               "flex flex-wrap items-center gap-2 text-sm md:col-span-6",
               "md:col-span-6 flex flex-wrap items-center justify-between gap-2"
             ]
    end

    test "the limit disclosure names the bound and nothing else", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      limit = lv |> element("#analysis-limit") |> render()

      # The bound is disclosed; the sentence that asked the reader to raise a
      # limit the page does not offer is gone.
      assert limit =~ "rows per query"
      refute limit =~ "Increase"
    end
  end

  # The chart config a canvas carries, unescaped. The config travels in an
  # attribute, so it arrives HTML-escaped.
  defp chart_config(lv, id) do
    lv
    |> element("##{id}")
    |> render()
    |> then(&Regex.run(~r/data-chart="([^"]*)"/, &1))
    |> case do
      [_, config] -> config |> String.replace("&quot;", "\"") |> String.replace("&amp;", "&")
      nil -> ""
    end
  end

  defp input_value(lv, id) do
    case lv |> element("##{id}") |> render() |> then(&Regex.run(~r/\bvalue="([^"]*)"/, &1)) do
      [_, value] -> value
      nil -> ""
    end
  end

  defp seconds_between(from, to) do
    {:ok, from_dt, 0} = DateTime.from_iso8601(from)
    {:ok, to_dt, 0} = DateTime.from_iso8601(to)
    DateTime.diff(to_dt, from_dt, :second)
  end
end
