defmodule LoggerDashboardWeb.PageControllerTest do
  use LoggerDashboardWeb.ConnCase

  test "GET / lists links to every tool", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ ~p"/logs"
    assert html =~ ~p"/analysis"
    assert html =~ ~p"/prune"
  end

  test "GET / renders the tool cards", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "home-card-logs"
    assert html =~ "home-card-analysis"
    assert html =~ "home-card-prune"
  end

  test "GET / shows the dashboard shell and marks home as the active page", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "dashboard-nav"
    assert html =~ "dashboard-header"
    assert html =~ "Log Dashboard"
  end

  test "GET / no longer shows Phoenix marketing content", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    refute html =~ "Peace of mind from prototype to production"
    refute html =~ "phoenixframework.org"
  end
end
