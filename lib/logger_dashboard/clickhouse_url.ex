defmodule LoggerDashboard.ClickhouseUrl do
  @moduledoc """
  Builds the effective ClickHouse HTTP URL.

  Only the URL authenticates: `AshClickhouse.Connection` forwards just `:url`
  to the `clickhouse` HTTP client (which derives basic auth from URL userinfo
  via hackney), so separate `:username`/`:password` repo config never reaches
  the wire. This helper injects percent-encoded userinfo when the base URL
  carries none.
  """

  @doc """
  Returns `base_url` unchanged when it already carries userinfo or when
  `password` is empty; otherwise injects `username` (default `"default"`) and
  `password` as percent-encoded userinfo.
  """
  @spec build(String.t(), String.t() | nil, String.t() | nil) :: String.t()
  def build(base_url, username, password) when is_binary(base_url) do
    uri = URI.parse(base_url)

    if uri.userinfo not in [nil, ""] do
      base_url
    else
      case password_to_string(password) do
        "" ->
          base_url

        pass ->
          %{uri | userinfo: "#{encode(normalize_user(username))}:#{encode(pass)}"}
          |> URI.to_string()
      end
    end
  end

  defp normalize_user(nil), do: "default"

  defp normalize_user(username) when is_binary(username) do
    case String.trim(username) do
      "" -> "default"
      trimmed -> trimmed
    end
  end

  defp normalize_user(_), do: "default"

  defp password_to_string(nil), do: ""
  defp password_to_string(password) when is_binary(password), do: password
  defp password_to_string(_), do: ""

  defp encode(value), do: URI.encode(value, &URI.char_unreserved?/1)
end
