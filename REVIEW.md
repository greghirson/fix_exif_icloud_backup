# Code Review: fix_icloud_exif.sh

## Bugs / Correctness

1. **~~Timezone handling discards offset info~~** *(fixed)* — The date was parsed as GMT then converted to local time with `.astimezone()`, but `exif_date` used `strftime("%Y:%m:%d %H:%M:%S")` which drops the timezone offset. The EXIF tag was written with the local time value but no offset indicator. Running the script in a different timezone than where the photos were taken would silently produce wrong times. **Fix:** Keep the parsed time in UTC and write `OffsetTimeOriginal`, `OffsetTime`, and `OffsetTimeDigitized` EXIF tags set to `+00:00` for images.

2. **`os.utime` after exiftool may be overwritten** — `os.utime` sets the file's mtime, but exiftool with `-overwrite_original` writes a new file and renames it into place, which happens *before* this call — so it works. However, if exiftool is ever run *without* `-overwrite_original`, the utime would only affect the modified copy and not the backup. Fine as-is but fragile to future changes.

3. **`updated` count not incremented on dry run but `parsed` is** — The summary printed `updated if not dry_run else 0`, but since `updated` is never incremented during dry-run mode, the ternary was redundant. Simplified to just print `updated` directly.

## Robustness

4. **No handling of duplicate filenames in CSV** — If the CSV has duplicate `imgName` entries, the same file gets processed multiple times. Depending on intent, you might want to deduplicate or warn.

5. **Extension extraction was fragile** — `name.rsplit(".", 1)[-1]` works but `os.path.splitext(name)` is more idiomatic and handles edge cases (e.g., dotfiles like `.hidden`). Updated to use `os.path.splitext`.

6. **No progress indication for large sets** — For thousands of photos, there's no way to gauge progress. A simple counter (`Processing 1500/8000...`) every N files would help.

7. **~~CSV column names are hardcoded~~** *(fixed)* — If Apple changes the export format, the script would silently produce no results (every row would have empty `imgName`). **Fix:** Added validation that the required columns (`imgName`, `originalCreationDate`) exist in `reader.fieldnames` immediately after opening the CSV, failing fast with a clear error message.

## Style / Minor

8. **Inline Python heredoc** — The entire script logic is in an inline Python heredoc. This works but makes the Python code harder to lint, test, and debug independently. Extracting it to a `.py` file would allow proper IDE support, type checking, and unit testing.

9. **`-R` flag for dry-run is unconventional** — Typically `-n` or `--dry-run` is used for dry-run. `-R` suggests "recursive" to most CLI users.

10. **~~Error output goes to stdout~~** *(fixed)* — All error/warning messages went to stdout. **Fix:** Added a `warn()` helper that prints to `sys.stderr`, and routed all warnings and errors through it. Normal output (DRYRUN, UPDATED, Summary) still goes to stdout.
