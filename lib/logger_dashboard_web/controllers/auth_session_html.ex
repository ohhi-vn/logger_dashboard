defmodule LoggerDashboardWeb.AuthSessionHTML do
  @moduledoc """
  Renders the token page.

  A standalone shell rather than `Layouts.app/1`: this page has no session, so the nav
  links in that layout would all bounce straight back here, and the flash group would
  have nothing to report. The theme toggle is kept, because the shell's own spec says
  it is available on any page.
  """

  use LoggerDashboardWeb, :html

  alias LoggerDashboardWeb.Layouts

  embed_templates "auth_session_html/*"
end
