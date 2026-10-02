defmodule Mix.Tasks.LoggerDashboard.Gen.Token do
  @shortdoc "Generate a URL-safe dashboard auth token"

  @moduledoc """
  Prints a single URL-safe token for `DASHBOARD_AUTH_TOKEN`.

  Uses only Elixir/OTP built-ins (`:crypto` + `Base`), matching the
  boot-generated token path in `LoggerDashboard.DashboardAuth`.

  ## Options

    * `--length N` - random bytes before Base64 encoding (default 32,
      minimum 16; 16 bytes = 128 bits of entropy)

  ## Examples

      mix logger_dashboard.gen.token
      mix logger_dashboard.gen.token --length 24
      DASHBOARD_AUTH_TOKEN=$(mix logger_dashboard.gen.token) mix phx.server
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [length: :integer])
    length = opts[:length] || 32

    if length < 16 do
      Mix.raise("--length must be at least 16 (128 bits of entropy)")
    end

    Mix.shell().info(LoggerDashboard.DashboardAuth.generate_token(length))
  end
end
