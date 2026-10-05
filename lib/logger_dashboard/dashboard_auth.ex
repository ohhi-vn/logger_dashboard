defmodule LoggerDashboard.DashboardAuth do
  @moduledoc """
  Shared-token gate for the dashboard.

  Token sources (in priority order):

    * Predefined via `DASHBOARD_AUTH_TOKEN` (read in `config/runtime.exs`).
    * Boot-generated ephemeral token using `:crypto` + `Base` only.

  The token itself reaches this module in exactly one way: `valid?/1`, called by the
  token page when a token is submitted. Everything after that is a session, and a
  session records `digest/0` rather than the token — see that function for why.

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

  @doc """
  A digest of the current token, for an authenticated session to record.

  What a session stores instead of the token itself. Two reasons, and both matter:

    * The session cookie is signed, not encrypted, so anyone holding it can read it.
      A digest is not the token, and recovering the token from one means guessing a
      256-bit secret.
    * Recomputed per request from `get_token/0`, so replacing the token stops every
      session established under the previous one — which is what makes rotating the
      token a revocation rather than a cosmetic change.

  Fixed-width hex, so a comparison against it can stay constant-time. `nil` when no
  token is configured, which is the same "nothing can authenticate" state `valid?/1`
  reports.
  """
  @spec digest() :: String.t() | nil
  def digest do
    case get_token() do
      nil -> nil
      token -> :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
    end
  end

  @doc """
  Whether `recorded` is the digest of the current token.

  The session's half of the comparison. False for anything that is not a byte-for-byte
  match against the current digest, including a digest of a since-replaced token.
  """
  @spec digest_matches?(String.t() | nil) :: boolean()
  def digest_matches?(nil), do: false

  def digest_matches?(recorded) when is_binary(recorded) do
    case digest() do
      nil -> false
      current -> Plug.Crypto.secure_compare(current, recorded)
    end
  end

  def digest_matches?(_recorded), do: false

  defp secure_compare(expected, provided) when is_binary(expected) and is_binary(provided) do
    if byte_size(expected) == byte_size(provided) do
      Plug.Crypto.secure_compare(expected, provided)
    else
      false
    end
  end
end
