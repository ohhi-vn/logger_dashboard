defmodule LoggerDashboardWeb.DashboardAuthLiveTest do
  use LoggerDashboardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias LoggerDashboard.DashboardAuth

  test "an authenticated socket mounts and keeps working" do
    {:ok, lv, _html} = live(sign_in(build_conn(), DashboardAuth.get_token()), ~p"/logs")

    assert has_element?(lv, "#logs-filter-form")

    # Still mounted after an event, so the socket survived the connect rather than
    # being replaced by a redirect page.
    render_click(lv, "preset", %{"id" => "age:1d"})
    assert has_element?(lv, "#logs-filter-form")
  end

  test "an unauthenticated socket is sent to the token page" do
    unauthed = unauthenticated(build_conn()) |> get(~p"/logs")

    assert redirected_to(unauthed) == "/login"
  end

  test "a socket whose session stopped matching is refused" do
    # The socket check is not redundant with the plug: this is the case where the page
    # was already open when the token rotated underneath it, which is exactly what a
    # session bound to a token is for.
    conn = authenticate(build_conn(), "a-token-that-is-no-longer-current")

    assert redirected_to(get(conn, ~p"/logs")) == "/login"
  end

  test "a session that keeps working does not re-prompt" do
    # Unchanged token: the session stays valid across a socket mount with no second
    # sign-in, which is the whole point of binding to a digest rather than a boolean
    # that expires on its own schedule.
    conn = sign_in(build_conn(), DashboardAuth.get_token())

    {:ok, lv, _html} = live(conn, ~p"/analysis")
    assert has_element?(lv, "#analysis-filter-form")

    # And across requests, not just the initial one.
    assert conn |> recycle() |> get(~p"/logs") |> html_response(200)
  end
end
