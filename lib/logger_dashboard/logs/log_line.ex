defmodule LoggerDashboard.Logs.LogLine do
  @moduledoc """
  Owns the log fields and their order, shared by the viewer's row and its
  raw-text export.

  Both surfaces carry the same five fields — UTC `timestamp`, `level`, `node`,
  `message`, and the source location — and a line from either has to be
  matchable back to the row it came from. Defining the order and the field
  formatting once here means the two surfaces cannot drift, and it keeps the
  level placeholder and the source-location rendering out of the template,
  where they were previously restated per surface.

  `fields/2` returns the ordered fields; `format/2` joins them into one
  exported line. The only difference between the two surfaces is the message:
  the row shortens an over-long message and the export must not, which is the
  `:shorten` option.

  ## Escaping

  A logger message can contain newlines — a stack trace is multi-line by
  nature — and emitting one verbatim would push the following record's fields
  onto continuation lines, so a downstream `grep` for a level or a node would
  match a line that is not a record boundary. Newline, carriage return, and
  tab therefore render as their two-character `\\n`, `\\r`, and `\\t` sequences,
  and every record occupies exactly one physical line. Only those three
  characters are escaped, so ordinary log text stays byte-identical to the
  stored message and the original remains reconstructible.

  Escaping is the message's canonical rendering here, so the row's hover text,
  the expanded panel, and the exported line all show the same bytes: what the
  panel shows is exactly what the file contains.
  """

  @node_placeholder "unknown"
  @ellipsis "…"

  # Character budget for a message shown on the row. The row is a single line
  # and CSS shortens it to the viewport regardless, so this is not the visible
  # width — it bounds the payload, which matters once a page holds 3000 rows
  # and one message can be a whole stack trace.
  @row_message_chars 500

  @escapes [{"\n", "\\n"}, {"\r", "\\r"}, {"\t", "\\t"}]

  @doc """
  The row's fields, in display order.

  `opts` supports `:shorten`, which bounds the message for display. The
  `:location` field is `nil` for a row with no source location, and callers
  omit a `nil` value rather than rendering an empty one.
  """
  @spec fields(map(), keyword()) :: [{atom(), String.t() | nil}]
  def fields(log, opts \\ []) do
    shorten? = Keyword.get(opts, :shorten, false)

    [
      {:timestamp, timestamp(log)},
      {:level, level(log)},
      {:node, node_name(log)},
      {:message, message(log, shorten: shorten?)},
      {:location, location(log)}
    ]
  end

  @doc """
  The export body for a page of rows: one `format/1` line per row, in the order
  the page shows them — newest first — joined by newlines.

  This is what the export carries, built from the rows already on the page
  rather than from a second query. An empty page yields an empty body, so
  exporting a page with no rows still downloads a file rather than failing.
  """
  @spec format_page([map()]) :: String.t()
  def format_page(rows) when is_list(rows), do: Enum.map_join(rows, "\n", &format/1)

  @doc """
  One record as a single line of text, in the same field order as `fields/2`.

  This is the export's line. `opts` are `fields/2`'s; the export passes no
  `:shorten`, so it carries the message as stored. A field with no value
  contributes nothing, so a row with no source location — or an empty message —
  does not leave a blank column or a trailing separator behind.
  """
  @spec format(map(), keyword()) :: String.t()
  def format(log, opts \\ []) do
    log
    |> fields(opts)
    |> Enum.reject(fn {_field, value} -> value in [nil, ""] end)
    |> Enum.map_join(" ", fn {_field, value} -> value end)
  end

  @doc """
  The row's `timestamp` as seconds with an explicit UTC marker.

  Second precision plus the marker: log timestamps are already second-scale, and
  a bare timestamp in a viewer whose controls are all UTC would be ambiguous.
  """
  @spec timestamp(map()) :: String.t()
  def timestamp(%{timestamp: %DateTime{} = timestamp}),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S UTC")

  def timestamp(%{timestamp: timestamp}), do: to_string(timestamp)

  @doc "The row's `level` as text, so a row is never distinguished by colour alone."
  @spec level(map()) :: String.t()
  def level(%{level: level}), do: to_string(level)

  @doc """
  The row's `node`, or an explicit placeholder when it has none.

  A node-less row is a real row in a no-node scope, so the field is named
  rather than left blank — an empty field reads as a missing value, and an
  exported line is matched by its fields.
  """
  @spec node_name(map()) :: String.t()
  def node_name(%{node: nil}), do: @node_placeholder
  def node_name(%{node: node}), do: to_string(node)

  @doc """
  The row's `message`, escaped, and shortened when `shorten: true`.

  `shorten: true` is for the row, where the message shares one line with the
  other fields. Omitting it leaves the message as stored apart from the
  control-character escapes, which is what the export carries.
  """
  @spec message(map(), keyword()) :: String.t()
  def message(log, opts \\ []) do
    log
    |> Map.fetch!(:message)
    |> to_string()
    |> escape()
    |> shorten(Keyword.get(opts, :shorten, false))
  end

  @doc """
  The row's source location as `module.function file:line`, or `nil`.

  Either half is optional: a row may carry a file with no module, or a module
  with no file. A row carrying neither has no location rather than a blank one.
  A file with no line renders as the file alone, never as a dangling colon.
  """
  @spec location(map()) :: String.t() | nil
  def location(log) do
    [
      location_module(log),
      location_file(log)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> case do
      "" -> nil
      location -> location
    end
  end

  defp location_file(%{file: nil}), do: nil
  defp location_file(%{file: file, line: nil}), do: file
  defp location_file(%{file: file, line: line}), do: "#{file}:#{line}"

  @doc "Whether a row carries any metadata, so no empty disclosure is offered."
  @spec metadata?(map()) :: boolean()
  def metadata?(%{metadata: metadata}) when is_map(metadata), do: map_size(metadata) > 0
  def metadata?(_log), do: false

  defp location_module(%{module: nil, function: nil}), do: nil
  defp location_module(%{module: nil, function: function}), do: ".#{function}"
  defp location_module(%{module: module, function: nil}), do: module
  defp location_module(%{module: module, function: function}), do: "#{module}.#{function}"

  defp escape(message) do
    Enum.reduce(@escapes, message, fn {control, escape}, acc ->
      String.replace(acc, control, escape)
    end)
  end

  defp shorten(message, false), do: message

  defp shorten(message, true) do
    if String.length(message) > @row_message_chars do
      String.slice(message, 0, @row_message_chars) <> @ellipsis
    else
      message
    end
  end
end
