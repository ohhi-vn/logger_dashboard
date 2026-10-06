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

      assert has_element?(lv, "#analysis-active-nodes[hidden]")
      assert has_element?(lv, "#analysis-clear-nodes[hidden]")
    end

    test "shows each selected node and offers a clear action", %{conn: conn} do
      # A bare path because a comma in the node value would be read as a query
      # separator by the verified-routes sigil.
      {:ok, lv, _html} = live(conn, "/analysis?node=a@h,b@h")

      assert has_element?(lv, "#analysis-active-nodes:not([hidden])")
      assert has_element?(lv, "#analysis-clear-nodes:not([hidden])")
      assert has_element?(lv, ~s(#analysis-active-nodes [data-node="a@h"]))
      assert has_element?(lv, ~s(#analysis-active-nodes [data-node="b@h"]))
    end

    test "blank and comma-only node input is all nodes", %{conn: conn} do
      for value <- ["", " , , "] do
        {:ok, lv, _html} = live(conn, "/analysis?node=" <> URI.encode_www_form(value))

        assert has_element?(lv, "#analysis-active-nodes[hidden]")
      end
    end

    test "clearing nodes returns to all nodes and keeps the other filters", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?node=a@h&level=error")

      assert has_element?(lv, "#analysis-clear-nodes:not([hidden])")

      lv |> element("#analysis-clear-nodes") |> render_click()

      assert has_element?(lv, "#analysis-active-nodes[hidden]")
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

      assert has_element?(lv, "#analysis-active-nodes[hidden]")
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
      assert has_element?(lv, ~s(#filters_level option[value="error"][selected]))
      assert has_element?(lv, ~s(#analysis-active-nodes [data-node="a@h"]))
    end

    test "toggling a node keeps the search keyword", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?search=*x*&level=error")

      render_click(lv, "toggle-node", %{"node" => "b@h"})

      assert input_value(lv, "filters_search") == "*x*"
      assert has_element?(lv, ~s(#analysis-active-nodes [data-node="b@h"]))
    end
  end

  describe "click-to-filter" do
    test "toggling a node adds it to the scope and keeps the other filters", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?node=a@h&level=error")

      render_click(lv, "toggle-node", %{"node" => "b@h"})

      assert has_element?(lv, ~s(#analysis-active-nodes [data-node="a@h"]))
      assert has_element?(lv, ~s(#analysis-active-nodes [data-node="b@h"]))
      assert has_element?(lv, ~s(#filters_level option[value="error"][selected]))
    end

    test "toggling a selected node removes it, and the last one returns to all nodes", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, "/analysis?node=" <> URI.encode_www_form("a@h,b@h"))

      render_click(lv, "toggle-node", %{"node" => "a@h"})

      refute has_element?(lv, ~s(#analysis-active-nodes [data-node="a@h"]))
      assert has_element?(lv, ~s(#analysis-active-nodes [data-node="b@h"]))

      render_click(lv, "toggle-node", %{"node" => "b@h"})

      assert has_element?(lv, "#analysis-active-nodes[hidden]")
    end

    test "toggling a blank node value changes nothing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?node=a@h")

      render_click(lv, "toggle-node", %{"node" => "  "})

      assert has_element?(lv, ~s(#analysis-active-nodes [data-node="a@h"]))
    end

    test "clicking a level selects it and clicking all clears it", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/analysis")

      render_click(lv, "select-level", %{"level" => "warning"})

      assert has_element?(lv, ~s(#filters_level option[value="warning"][selected]))

      assert has_element?(
               lv,
               ~s(#analysis-level-options [data-level="warning"][aria-pressed="true"])
             )

      render_click(lv, "select-level", %{"level" => "info"})

      assert has_element?(lv, ~s(#filters_level option[value="info"][selected]))

      render_click(lv, "select-level", %{"level" => "all"})

      assert has_element?(lv, ~s(#filters_level option[value="all"][selected]))
    end

    test "clicking an unknown level is ignored", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/analysis?level=error")

      render_click(lv, "select-level", %{"level" => "fatal"})

      assert has_element?(lv, ~s(#filters_level option[value="error"][selected]))
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
