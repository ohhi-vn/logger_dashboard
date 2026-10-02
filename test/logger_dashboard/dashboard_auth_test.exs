defmodule LoggerDashboard.DashboardAuthTest do
  use ExUnit.Case, async: false

  alias LoggerDashboard.DashboardAuth

  setup do
    previous = Application.get_env(:logger_dashboard, :dashboard_auth_token)
    Application.put_env(:logger_dashboard, :dashboard_auth_token, "unit-test-token")

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:logger_dashboard, :dashboard_auth_token)
      else
        Application.put_env(:logger_dashboard, :dashboard_auth_token, previous)
      end
    end)

    :ok
  end

  test "generate_token returns URL-safe tokens with enough entropy" do
    first = DashboardAuth.generate_token()
    second = DashboardAuth.generate_token()

    refute first == second
    assert String.length(first) >= 43
    assert first =~ ~r/\A[A-Za-z0-9_-]+\z/
    refute first =~ ~r/[+\/=]/

    # 32 bytes -> 256 bits; 16 bytes -> 128 bits minimum
    assert byte_size(Base.url_decode64!(first, padding: false)) == 32

    short = DashboardAuth.generate_token(16)
    assert byte_size(Base.url_decode64!(short, padding: false)) == 16
  end

  test "get_token trims and treats empty as absent" do
    Application.put_env(:logger_dashboard, :dashboard_auth_token, "  spaced  ")
    assert DashboardAuth.get_token() == "spaced"

    Application.put_env(:logger_dashboard, :dashboard_auth_token, "   ")
    assert DashboardAuth.get_token() == nil

    Application.delete_env(:logger_dashboard, :dashboard_auth_token)
    assert DashboardAuth.get_token() == nil
  end

  test "resolve_token prefers predefined env and generates otherwise" do
    assert {:predefined, "secret"} = DashboardAuth.resolve_token("secret")
    assert {:predefined, "secret"} = DashboardAuth.resolve_token("  secret  ")

    assert {:generated, generated} = DashboardAuth.resolve_token(nil)
    assert byte_size(Base.url_decode64!(generated, padding: false)) == 24

    assert {:generated, _} = DashboardAuth.resolve_token("")
    assert {:generated, _} = DashboardAuth.resolve_token("   ")
  end

  test "valid? accepts only the current token" do
    assert DashboardAuth.valid?("unit-test-token")
    refute DashboardAuth.valid?("wrong-token")
    refute DashboardAuth.valid?("")
    refute DashboardAuth.valid?(nil)
    refute DashboardAuth.valid?(123)

    # Different length never matches (and never raises)
    refute DashboardAuth.valid?("short")
    refute DashboardAuth.valid?(String.duplicate("x", 200))
  end

  test "valid? fails closed when no token is configured" do
    Application.delete_env(:logger_dashboard, :dashboard_auth_token)
    refute DashboardAuth.valid?("anything")
  end
end
