[
  import_deps: [:phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"],
  # AppleDouble sidecars (`._foo.ex`) match the inputs globs above and crash
  # the formatter with a UnicodeConversionError. Already covered by .gitignore;
  # the glob does not honour that, so exclude them here too.
  excludes: ["**/._*"]
]
