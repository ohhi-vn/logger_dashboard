defmodule Mix.Tasks.LoggerDashboard.SignTailwindTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.LoggerDashboard.SignTailwind

  describe "run/1" do
    test "completes without raising" do
      assert :ok = SignTailwind.run([])
    end

    test "completes when run twice" do
      assert :ok = SignTailwind.run([])
      assert :ok = SignTailwind.run([])
    end
  end

  describe "sign/2" do
    test "skips a path that does not exist" do
      assert :skipped =
               SignTailwind.sign(
                 "codesign",
                 Path.join(System.tmp_dir!(), "nope-#{System.unique_integer([:positive])}")
               )
    end

    test "signs an existing binary so it becomes runnable" do
      # Copy the real Tailwind binary when it is present so the test exercises
      # the actual signing path rather than a stub.
      case File.regular?(Tailwind.bin_path()) do
        false ->
          # Nothing downloaded yet: the step must be a no-op, not an error.
          assert :skipped = SignTailwind.sign("codesign", Tailwind.bin_path())

        true ->
          path = Path.join(System.tmp_dir!(), "tw-#{System.unique_integer([:positive])}")
          File.cp!(Tailwind.bin_path(), path)
          on_exit(fn -> File.rm(path) end)
          File.chmod!(path, 0o755)

          codesign = System.find_executable("codesign")

          case codesign do
            nil -> assert :skipped = SignTailwind.sign(codesign, path)
            exe -> assert :ok = SignTailwind.sign(exe, path)
          end
      end
    end
  end
end
