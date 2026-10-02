defmodule Mix.Tasks.LoggerDashboard.SignTailwind do
  @shortdoc "Ad-hoc code-signs the downloaded Tailwind CLI on macOS"

  @moduledoc """
  Ad-hoc code-signs the downloaded Tailwind CLI binary.

  macOS refuses to execute the released Tailwind binary when its embedded code
  signature does not validate, terminating the process with
  `SIGKILL (Code Signature Invalid)` and exit status 137. `mix assets.build`
  surfaces that as ``mix tailwind logger_dashboard exited with 137`` without
  saying why. Re-signing ad-hoc replaces the invalid signature with one this
  machine accepts.

  The step is deliberately inert everywhere it is not needed: a no-op on
  non-macOS platforms, when `codesign` is unavailable, and when the binary has
  not been downloaded yet. Re-running it is safe.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    if darwin?() do
      case System.find_executable("codesign") do
        nil ->
          Mix.shell().info("[tailwind] codesign not found; skipping ad-hoc signature")

        codesign ->
          sign(codesign, Tailwind.bin_path())
      end
    end

    :ok
  end

  @doc """
  Ad-hoc signs `path` when it exists. Returns `:skipped` when there is nothing
  to sign and `:ok` once the binary is signed.
  """
  @spec sign(String.t(), Path.t()) :: :ok | :skipped
  def sign(codesign, path) do
    if File.regular?(path) do
      {output, status} =
        System.cmd(codesign, ["--force", "--sign", "-", path], stderr_to_stdout: true)

      case status do
        0 ->
          Mix.shell().info("[tailwind] ad-hoc signed #{Path.basename(path)}")
          :ok

        _ ->
          # A failed signature is not fatal here: the binary may still run on
          # this machine, and turning this into a hard error would block builds
          # that the previous code path completed.
          Mix.shell().info(
            "[tailwind] could not sign #{Path.basename(path)}: #{String.trim(output)}"
          )

          :skipped
      end
    else
      :skipped
    end
  end

  defp darwin?, do: match?({:unix, :darwin}, :os.type())
end
