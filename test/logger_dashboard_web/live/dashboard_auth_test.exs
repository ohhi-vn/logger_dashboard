defmodule LoggerDashboardWeb.DashboardAuthLiveTest do
  use LoggerDashboardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "authenticated socket mounts while unauthenticated is denied", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/logs")
    assert has_element?(lv, "#logs-filter-form")

    unauthed = Phoenix.ConnTest.build_conn() |> get(~p"/logs")
    assert unauthed.status == 401
  end
end
