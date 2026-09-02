# Focused app command-line tools

## Decision

ImageKid AppIcons, ImageKid Sheet, and ImageKid Compress each ship with a
command-line tool:

- `imagekid-appicons`
- `imagekid-sheet`
- `imagekid-compress`

The CLI is part of the product. It is not a separate service or a thin
automation of the graphical interface. The app and CLI call the same shared
engine and must produce equivalent output from equivalent settings.

## Shared principles

- Every operation runs locally.
- No account, subscription, credits, telemetry, or network fallback.
- Commands are non-interactive by default and suitable for scripts and CI.
- Source files are never overwritten unless `--overwrite` or a more specific
  replacement option is explicit.
- Output is staged and moved into place only after validation succeeds.
- Existing output causes a clear failure by default.
- Warnings go to standard error.
- Normal results go to standard output.
- Progress is shown only when standard error is attached to a terminal.
- `--quiet` suppresses progress and non-essential output.
- `--json` produces a stable machine-readable result on standard output.
- `--dry-run` validates and prints the output plan without writing files.
- Paths containing spaces, Unicode, and non-ASCII filenames are supported.
- Cancellation removes incomplete temporary output and leaves previous
  successful output untouched.

## Common options

```text
--output <path>       Output file or directory
--overwrite           Replace existing planned output explicitly
--dry-run             Validate and print the output plan
--json                Emit a machine-readable result
--quiet               Suppress progress and non-essential messages
--preset <name>       Use a saved or built-in preset
--config <path>       Read an explicit configuration file
--help                Show command help
--version             Show the installed version
```

Configuration precedence is deterministic:

1. Explicit command-line option.
2. Explicit `--config` file.
3. Named `--preset`.
4. Tool default.

`--dry-run --json` prints the resolved configuration so automation can verify
what will happen.

## JSON result

All three tools use the same top-level shape:

```json
{
  "schemaVersion": 1,
  "tool": "imagekid-compress",
  "toolVersion": "1.0.0",
  "status": "completed",
  "outputs": [],
  "warnings": [],
  "errors": []
}
```

Human-readable progress must never be mixed into JSON standard output.
Tool-specific output objects are documented on each product page.

## Exit codes

| Code | Meaning |
| ---: | --- |
| 0 | Operation completed successfully |
| 1 | One or more inputs failed |
| 2 | Invalid arguments or configuration |
| 3 | Unsupported or malformed input |
| 4 | Output conflict without explicit overwrite |
| 5 | Permission or sandbox access failure |
| 6 | Operation cancelled or interrupted |
| 7 | Internal processing or validation failure |

For a batch operation, any failed item returns exit code `1`, even when other
items completed. JSON output contains per-item results.

## Presets and configuration

GUI presets and CLI presets use the same Codable configuration models. A preset
exported from the app can be passed to `--config`. Configuration files include
a `schemaVersion`. New versions may add optional fields, but must not silently
reinterpret existing fields.

## Installation and discovery

The signed CLI executable should be included with its macOS app distribution.
The final release path depends on the distribution method, but setup must:

- never require a shell download script;
- avoid administrator access when a user-local installation is sufficient;
- show the executable and link destination before changing shell paths;
- offer a copyable direct path when the user does not want an installed command;
- remove only links created by ImageKid when uninstalling CLI integration.

The app includes a **Command Line Tool** settings section with installation
status, the resolved command path, Install/Remove actions where distribution
allows them, and a copyable test command.

## Engine boundary

The GUI and CLI contain presentation and argument parsing only:

```text
AppIcons app ─┐
AppIcons CLI ─┴─> ImageKidAppIcons

Sheet app ────┐
Sheet CLI ────┴─> ImageKidSheet

Compress app ─┐
Compress CLI ─┴─> ImageKidCompression
```

Shared engines do not import SwiftUI or AppKit presentation types.

## CLI release gates

- GUI and CLI golden tests produce equivalent output.
- Every documented option has argument-parser tests.
- JSON fixtures cover success, partial failure, invalid input, output conflict,
  cancellation, and permission failure.
- No command writes outside its resolved output plan.
- `--dry-run` performs no write.
- Cancellation removes incomplete temporary output.
- Commands work from Terminal, scripts, and CI without launching the GUI.
