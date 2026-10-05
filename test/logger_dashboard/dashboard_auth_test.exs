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

  describe "digest/0" do
    test "is stable for an unchanged token" do
      first = DashboardAuth.digest()

      # Recomputed per request, so it has to be deterministic: this is the value a
      # session is checked against on every one of them.
      assert DashboardAuth.digest() == first
      assert DashboardAuth.digest_matches?(first)
    end

    test "is a fixed-width lowercase hex digest of the token" do
      digest = DashboardAuth.digest()

      # Fixed width is what lets `digest_matches?/1` compare in constant time.
      assert String.length(digest) == 64
      assert digest =~ ~r/\A[0-9a-f]{64}\z/
    end

    test "is not the token and does not contain it" do
      # The session cookie is signed, not encrypted, so whoever holds it can read it.
      # What a session stores must not be the secret itself.
      refute DashboardAuth.digest() =~ "unit-test-token"
      refute DashboardAuth.digest() == "unit-test-token"
    end

    test "changes when the token changes" do
      before = DashboardAuth.digest()

      Application.put_env(:logger_dashboard, :dashboard_auth_token, "rotated-token")
      after_rotation = DashboardAuth.digest()

      # The property that makes rotating the token a revocation: a session recorded
      # under the old token no longer matches.
      refute after_rotation == before
      refute DashboardAuth.digest_matches?(before)
      assert DashboardAuth.digest_matches?(after_rotation)
    end

    test "is nil when no token is configured" do
      Application.delete_env(:logger_dashboard, :dashboard_auth_token)

      assert DashboardAuth.digest() == nil
      # Same "nothing can authenticate" state `valid?/1` reports.
      refute DashboardAuth.digest_matches?("anything")
    end
  end

  describe "digest_matches?/1" do
    test "rejects anything that is not the current digest" do
      digest = DashboardAuth.digest()

      refute DashboardAuth.digest_matches?(nil)
      refute DashboardAuth.digest_matches?("")
      refute DashboardAuth.digest_matches?("unit-test-token")
      refute DashboardAuth.digest_matches?(String.upcase(digest))
      refute DashboardAuth.digest_matches?(binary_part(digest, 0, byte_size(digest) - 1))
      refute DashboardAuth.digest_matches?(digest <> "0")
      refute DashboardAuth.digest_matches?(123)
    end
  end
end
