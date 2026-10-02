defmodule LoggerDashboard.Tailwind do
  @moduledoc """
  Wrapper around `Tailwind.install_and_run/2` used as the dev asset watcher.

  `Tailwind.install_and_run/2` downloads the binary only when it is missing,
  so on this macOS the freshly downloaded Tailwind 4.3.0 binary is immediately
  killed for an invalid code signature. Signing it before the run keeps
  `mix phx.server` watchers working.
  """

  alias Mix.Tasks.LoggerDashboard.SignTailwind

  @doc """
  Signs the Tailwind binary when needed, then delegates to
  `Tailwind.install_and_run/2`.
  """
  @spec install_and_run(atom(), [String.t()]) :: integer()
  def install_and_run(profile, args) do
    if match?({:unix, :darwin}, :os.type()) do
      case System.find_executable("codesign") do
        nil -> :ok
        codesign -> SignTailwind.sign(codesign, Tailwind.bin_path())
      end
    end

    Tailwind.install_and_run(profile, args)
  end
end
