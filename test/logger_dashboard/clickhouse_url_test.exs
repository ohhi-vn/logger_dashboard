defmodule LoggerDashboard.ClickhouseUrlTest do
  use ExUnit.Case, async: true

  alias LoggerDashboard.ClickhouseUrl

  test "leaves a bare URL unchanged when password is empty" do
    assert ClickhouseUrl.build("http://localhost:8123", "default", "") == "http://localhost:8123"
  end

  test "falls back to default user for nil or blank username" do
    assert ClickhouseUrl.build("http://localhost:8123", nil, "secret") ==
             "http://default:secret@localhost:8123"

    assert ClickhouseUrl.build("http://localhost:8123", "  ", "secret") ==
             "http://default:secret@localhost:8123"
  end

  test "injects a custom username" do
    assert ClickhouseUrl.build("http://localhost:8123", "cluser_dev", "b0123") ==
             "http://cluser_dev:b0123@localhost:8123"
  end

  test "preserves a URL that already carries userinfo" do
    assert ClickhouseUrl.build("http://custom:pass@clickhouse:8124", "other", "otherpass") ==
             "http://custom:pass@clickhouse:8124"
  end

  test "percent-encodes reserved characters in userinfo" do
    assert ClickhouseUrl.build("http://localhost:8123", "user", "p@ss/w:th?x#y&z%") ==
             "http://user:p%40ss%2Fw%3Ath%3Fx%23y%26z%25@localhost:8123"
  end
end
