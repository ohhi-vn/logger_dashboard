defmodule LoggerDashboardWeb.ShellSessionControlTest do
  @moduledoc """
  The sign-out control's presence and placement, as the shell spec requires it.

  The behaviour of signing out is covered in `dashboard_auth_test.exs`; this is about
  the frame offering it at all, which is a different capability's requirement.
  """

  use LoggerDashboardWeb.ConnCase, async: false

  alias LoggerDashboard.DashboardAuth

  test "every dashboard page offers a way to end the session" do
    conn = sign_in(build_conn(), DashboardAuth.get_token())

    for path <- [~p"/", ~p"/logs", ~p"/analysis", ~p"/prune"] do
      html = conn |> get(path) |> html_response(200)

      assert html =~ ~s(id="logout-button"), "expected a sign-out control on #{path}"
    end
  end

  test "the control is a form posting to the logout route, not a socket event" do
    html = sign_in(build_conn(), DashboardAuth.get_token()) |> get(~p"/") |> html_response(200)

    # Signing out has to work in exactly the state where the session is no longer
    # trusted — which is also the state with no usable socket.
    assert html =~ ~s(action="/logout")
    assert html =~ ~s(name="_method" value="delete")
    refute html =~ ~s(phx-click="logout")
  end

  test "the control is named for assistive technology, not only drawn as an icon" do
    html = sign_in(build_conn(), DashboardAuth.get_token()) |> get(~p"/") |> html_response(200)

    assert html =~ "Sign out"
  end

  test "the control is absent from the token page" do
    html = get(build_conn(), ~p"/login") |> html_response(200)

    # There is no session to end, so offering to end one would be a lie.
    refute html =~ ~s(id="logout-button")
  end
end
