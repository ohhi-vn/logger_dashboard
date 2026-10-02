defmodule LoggerDashboard.DashboardAuth do
  @moduledoc """
  Shared-token gate for the dashboard.

  Token sources (in priority order):

    * Predefined via `DASHBOARD_AUTH_TOKEN` (read in `config/runtime.exs`).
    * Boot-generated ephemeral token using `:crypto` + `Base` only.

  Verification uses `Plug.Crypto.secure_compare/2` and never logs tokens.
  """

  @default_bytes 32
  @boot_bytes 24

  require Logger

  @doc """
  Generates a URL-safe token with at least 128 bits of entropy.

  Defaults to 32 random bytes (256 bits). The boot path uses 24 bytes
  (192 bits). Minimum is 16 bytes (128 bits).
  """
  @spec generate_token(pos_integer()) :: String.t()
  def generate_token(bytes \\ @default_bytes) when is_integer(bytes) and bytes >= 16 do
    bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @doc "Returns the current valid token from app env, or `nil` when unset."
  @spec get_token() :: String.t() | nil
  def get_token do
    case Application.get_env(:logger_dashboard, :dashboard_auth_token) do
      token when is_binary(token) ->
        token = String.trim(token)
        if token == "", do: nil, else: token

      _ ->
        nil
    end
  end

  @doc """
  Logs the boot token when it was generated at runtime.

  A release evaluates `config/runtime.exs` before `:logger` is started, so the
  notice is emitted here instead, where it reaches the console. This is the only
  place the token is ever logged, and only on the run that generated it.
  """
  @spec announce_boot_token() :: :ok
  def announce_boot_token do
    if generated?() do
      Logger.info("""

      [dashboard_auth] DASHBOARD_AUTH_TOKEN is unset; generated an ephemeral token.
      token: #{get_token()}
      Set DASHBOARD_AUTH_TOKEN to pin a known token; this one changes on every restart.\
      """)

      :ok
    end
  end

  @doc "True when the active token was generated at boot rather than predefined."
  @spec generated?() :: boolean()
  def generated? do
    Application.get_env(:logger_dashboard, :dashboard_auth_token_generated, false) == true
  end

  @doc """
  Resolves an env value into `{:predefined, token}` or `{:generated, token}`.

  Empty/nil env falls back to a boot-generated token. Trims whitespace so
  `DASHBOARD_AUTH_TOKEN=" secret "` does not create a mismatch trap.
  """
  @spec resolve_token(String.t() | nil) :: {:predefined, String.t()} | {:generated, String.t()}
  def resolve_token(env_value) do
    case env_value do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:generated, generate_token(@boot_bytes)}
          trimmed -> {:predefined, trimmed}
        end

      _ ->
        {:generated, generate_token(@boot_bytes)}
    end
  end

  @doc "Returns true when `provided` matches the current token (constant-time)."
  @spec valid?(String.t() | nil) :: boolean()
  def valid?(nil), do: false
  def valid?(""), do: false

  def valid?(provided) when is_binary(provided) do
    case get_token() do
      nil -> false
      "" -> false
      expected when is_binary(expected) -> secure_compare(expected, provided)
    end
  end

  def valid?(_), do: false

  @doc "Extracts the presented token from `Authorization: Bearer` or `Basic`."
  @spec extract_token(Plug.Conn.t()) :: String.t() | nil
  def extract_token(conn) do
    conn
    |> Plug.Conn.get_req_header("authorization")
    |> List.first()
    |> parse_authorization()
  end

  @doc "Returns true when the conn carries the current valid token."
  @spec authenticated?(Plug.Conn.t()) :: boolean()
  def authenticated?(conn), do: conn |> extract_token() |> valid?()

  defp parse_authorization(nil), do: nil
  defp parse_authorization(""), do: nil

  defp parse_authorization("Bearer " <> token) do
    token = String.trim(token)
    if token == "", do: nil, else: token
  end

  defp parse_authorization("Basic " <> encoded) do
    case Base.decode64(String.trim(encoded)) do
      {:ok, decoded} -> basic_password(decoded)
      :error -> nil
    end
  end

  defp parse_authorization(_), do: nil

  defp basic_password(decoded) do
    case String.split(decoded, ":", parts: 2) do
      [_user, password] ->
        password = String.trim(password)
        if password == "", do: nil, else: password

      _ ->
        nil
    end
  end

  defp secure_compare(expected, provided) when is_binary(expected) and is_binary(provided) do
    if byte_size(expected) == byte_size(provided) do
      Plug.Crypto.secure_compare(expected, provided)
    else
      false
    end
  end
end
