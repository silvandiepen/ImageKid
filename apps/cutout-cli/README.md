# cutout

Command-line background removal, on this Mac, with the same engines as **Cutout**.

```bash
cutout photo.jpg cutouts/photo.png
cutout shots/*.jpg cutouts/ --quality=best
cutout watch inbox/ cutouts/ --quality=best
```

The last positional argument is the destination. It is treated as a folder when it already
exists as one, ends with `/`, or has no file extension; otherwise a single input may be given
an explicit output path. Output is always PNG, so transparency stays real.

| Option | Meaning |
|---|---|
| `-q`, `--quality <fast\|best>` | `fast` is Apple Vision, always available, no download. `best` is BiRefNet through Core ML. Default `fast`. |
| `-f`, `--force` | Overwrite an existing output file. |
| `-h`, `--help` / `-v`, `--version` | Usage / version. |

`--quality=best`, `--q=best` and `-q best` all work.

## Watch a folder

Keep Cutout running to process images as they arrive in a folder:

```bash
cutout watch ~/Desktop/Cutout-Inbox ~/Desktop/Cutouts --quality=best
```

Images already in the inbox are processed on startup. The watcher then handles each new or
changed supported image in that folder (not subfolders), after a short delay so a copy can finish.
Use a different destination folder; this avoids treating generated PNGs as new inputs. Stop it with
`Control-C`.

Exit code `0` on success, `1` for a usage error, `2` when one or more images failed.

## Install

```bash
npm run cutout:install     # builds release and copies to /usr/local/bin/cutout
npm run cutout:uninstall
```

## Best Quality models

`--quality=best` reads the model cache the apps already fill, so there is no second download and
no network access from the CLI:

1. `~/Library/Group Containers/group.com.hakobs.imagekid/Models` — the App Group the sandboxed
   apps share.
2. `~/Library/Application Support/ImageKid/Models` — the unsandboxed fallback.

A command-line tool is not sandboxed and holds no App Group entitlement, so it addresses that
container by path rather than through `containerURL(forSecurityApplicationGroupIdentifier:)`.
Install Best Quality once from Cutout and the CLI picks it up; until then `--quality=best`
exits with an error rather than silently downgrading.

BiRefNet runs on the CPU here, matching the app — that is where its output matches the reference
implementation.
