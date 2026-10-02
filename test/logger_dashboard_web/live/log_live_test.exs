defmodule LoggerDashboardWeb.LogLiveTest do
  use LoggerDashboardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders filter form, list, pagination and empty state", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs")

      assert has_element?(lv, "#logs-filter-form")
      assert has_element?(lv, "#logs-list")
      assert has_element?(lv, "#logs-pagination")
      assert has_element?(lv, "#logs-empty")
    end

    test "invalid datetime shows filter error and no crash", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs?from=not-a-date")

      assert has_element?(lv, "#logs-filter-error")
    end

    test "filter preserves params across pagination", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs?level=error&limit=25")

      lv
      |> element("#logs-pagination button", "Next")
      |> render_click()

      assert_patch(lv, ~p"/logs?level=error&limit=25&offset=25")
    end
  end
end
