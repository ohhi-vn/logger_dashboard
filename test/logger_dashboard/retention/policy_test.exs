defmodule LoggerDashboard.Retention.PolicyTest do
  use ExUnit.Case, async: true

  alias LoggerDashboard.Logs.Filter
  alias LoggerDashboard.Retention.Policy

  describe "default/0" do
    test "is disabled" do
      # Nothing configured means nothing deletes. Retention is the one feature
      # here that destroys data unattended, so its out-of-the-box state is inert.
      refute Policy.default().enabled
    end
  end

  describe "build/1" do
    test "builds a policy from string-keyed params" do
      assert {:ok, policy} =
               Policy.build(%{
                 "enabled" => "true",
                 "run_at" => "03:30 UTC",
                 "keep" => "7d"
               })

      assert policy.enabled
      assert policy.run_at == {"03:30", "UTC"}
      assert policy.keep == "7d"
    end

    test "defaults an absent run time and keep" do
      assert {:ok, policy} = Policy.build(%{"enabled" => "true"})

      assert policy.run_at == Policy.default().run_at
      assert policy.keep == Policy.default().keep
    end

    test "treats an empty run time and keep as absent" do
      assert {:ok, policy} = Policy.build(%{"run_at" => "  ", "keep" => ""})

      assert policy.run_at == Policy.default().run_at
      assert policy.keep == Policy.default().keep
    end

    test "reads a bare HH:MM as UTC" do
      # Every other time in this project is UTC, so an unqualified clock means UTC
      # rather than a server-local zone.
      assert {:ok, policy} = Policy.build(%{"run_at" => "04:05"})

      assert policy.run_at == {"04:05", "UTC"}
    end

    test "accepts a zero-padded and an unpadded hour" do
      assert {:ok, _policy} = Policy.build(%{"run_at" => "04:05 UTC"})
      assert {:ok, policy} = Policy.build(%{"run_at" => "4:05 UTC"})

      assert policy.run_at == {"04:05", "UTC"}
    end

    test "uppercases a lower-case zone" do
      assert {:ok, policy} = Policy.build(%{"run_at" => "03:00 utc"})

      assert policy.run_at == {"03:00", "UTC"}
    end

    test "rejects an unparseable run time and names the remedy" do
      for bad <- ["25:00", "3:5", "0300", "noon", "03:60", "03:00:00"] do
        assert {:error, message} = Policy.build(%{"run_at" => bad})
        assert message =~ "invalid run time"
        assert message =~ "HH:MM UTC"
      end
    end

    test "rejects a non-binary run time" do
      assert {:error, message} = Policy.build(%{"run_at" => 300})
      assert message =~ "invalid run time"
    end

    test "accepts every age preset as a retained age" do
      for {id, _duration} <- Filter.presets(:age) do
        assert {:ok, policy} = Policy.build(%{"keep" => id})
        assert policy.keep == id
      end
    end

    test "rejects a retained age outside the age family" do
      assert {:error, message} = Policy.build(%{"keep" => "7 days"})

      assert message =~ "invalid retained age"
      # The message names the offered ids so the operator can pick one, and does
      # so from the family rather than a hand-written list.
      assert message =~ ~s("7d")
    end

    test "rejects a window preset id as a retained age" do
      # `window:1h` is a lookback that sets both bounds. A retention policy that
      # named one would delete the wrong range, so the family is enforced.
      assert {:error, _message} = Policy.build(%{"keep" => "window:1h"})
    end

    test "reads the enabled flag across the shapes a form and config produce" do
      for truthy <- [true, "true", "1", 1, "on", "yes"] do
        assert {:ok, policy} = Policy.build(%{"enabled" => truthy})
        assert policy.enabled
      end

      for falsy <- [false, "false", "0", 0, "off", "", nil, "maybe"] do
        assert {:ok, policy} = Policy.build(%{"enabled" => falsy})
        refute policy.enabled
      end
    end
  end

  describe "from_config/1" do
    test "reads a map retention config" do
      policy =
        Policy.from_config(
          retention: %{"enabled" => "true", "run_at" => "05:00 UTC", "keep" => "30d"}
        )

      assert policy.enabled
      assert policy.run_at == {"05:00", "UTC"}
      assert policy.keep == "30d"
    end

    test "reads a keyword-list retention config with atom keys" do
      # `config :logger_dashboard, retention: [enabled: true, keep: "12h"]` is
      # how this is written in config.exs, so it has to read the same as the map
      # form rather than silently disabling itself.
      policy = Policy.from_config(retention: [enabled: true, run_at: "06:00", keep: "12h"])

      assert policy.enabled
      assert policy.run_at == {"06:00", "UTC"}
      assert policy.keep == "12h"
    end

    test "yields the disabled default when unconfigured" do
      assert Policy.from_config([]) == Policy.default()
      assert Policy.from_config(other: "value") == Policy.default()
    end

    test "yields the disabled default for an unusable configuration" do
      # Boot must not fail over a retention setting. A malformed value disables
      # the feature instead of raising, because raising here would take down the
      # whole dashboard over a policy nobody was watching.
      for bad <- [
            [retention: "nonsense"],
            [retention: %{enabled: true, run_at: "not-a-time"}],
            [retention: %{enabled: true, keep: "7 days"}],
            [retention: 42]
          ] do
        assert Policy.from_config(bad) == Policy.default()
      end
    end

    test "partially-valid configuration does not raise and does not arm" do
      policy = Policy.from_config(retention: %{enabled: "true", run_at: "99:99"})

      # The valid field is kept but the policy cannot be built, so it is disabled.
      refute policy.enabled
    end
  end

  describe "resolve/1" do
    test "an absent stored policy resolves to the configured default" do
      Application.put_env(:logger_dashboard, :retention, %{
        "enabled" => "true",
        "run_at" => "07:00 UTC",
        "keep" => "30d"
      })

      on_exit(fn -> Application.delete_env(:logger_dashboard, :retention) end)

      assert {policy, :configured} = Policy.resolve(nil)

      assert policy.enabled
      assert policy.keep == "30d"
    end

    test "a stored policy wins over the configured default and reports its source" do
      Application.put_env(:logger_dashboard, :retention, %{"keep" => "90d"})

      on_exit(fn -> Application.delete_env(:logger_dashboard, :retention) end)

      stored = %Policy{enabled: true, run_at: {"09:00", "UTC"}, keep: "1h"}

      assert {policy, :stored} = Policy.resolve(stored)

      assert policy == stored
    end

    test "with nothing configured and nothing stored, the policy is disabled" do
      Application.delete_env(:logger_dashboard, :retention)

      assert {policy, :configured} = Policy.resolve(nil)

      refute policy.enabled
    end
  end

  describe "to_params/1" do
    test "renders the policy back into form values" do
      params = Policy.to_params(%Policy{enabled: true, run_at: {"03:30", "UTC"}, keep: "12h"})

      assert params == %{"enabled" => "true", "run_at" => "03:30 UTC", "keep" => "12h"}
    end
  end

  describe "describe/1" do
    test "names the scope, the age, and the time" do
      text = Policy.describe(%Policy{enabled: true, run_at: {"03:00", "UTC"}, keep: "7d"})

      assert text =~ "enabled"
      assert text =~ "7d"
      assert text =~ "03:00 UTC"
      # Every node is named explicitly, so a system-wide unattended delete is
      # never summarised as just a duration.
      assert text =~ "every node"
    end

    test "says so when the policy is disabled" do
      assert Policy.describe(Policy.default()) =~ "disabled"
    end
  end

  describe "keep_labels/1" do
    test "labels every age option from its duration" do
      labels = Policy.keep_labels()

      assert length(labels) == length(Filter.presets(:age))

      assert {"1h", "1h"} in labels
      assert {"7d", "7d"} in labels
    end
  end

  describe "preset_id/1" do
    test "resolves a retained age into the age family preset" do
      assert Policy.preset_id("7d") == Filter.preset_id(:age, "7d")
    end
  end
end
