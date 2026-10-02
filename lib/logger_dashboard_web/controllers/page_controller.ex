defmodule LoggerDashboardWeb.PageController do
  use LoggerDashboardWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
