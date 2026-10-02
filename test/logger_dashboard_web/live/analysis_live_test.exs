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
  end
end
