# fix_icloud_exif

Restore original creation dates to photos and videos exported from iCloud.

When you export your iCloud Photo Library using Apple's data privacy tool, the exported files lose their original EXIF timestamps. Apple includes CSV manifest files (`Photo Details.csv`) with the original dates. This script reads all CSV files in the directory, merges them, and writes the correct dates back into each file's EXIF metadata and filesystem timestamps.

If a file has GPS coordinates in its EXIF data, the script automatically determines the correct timezone and converts the UTC date to local time. Files without GPS data fall back to UTC.

## Requirements

- **bash** (macOS/Linux)
- **[uv](https://docs.astral.sh/uv/)** — install via `curl -LsSf https://astral.sh/uv/install.sh | sh`
- **exiftool** — install via `brew install exiftool` on macOS

Python dependencies (`timezonefinder`) are managed automatically by `uv` at runtime — no manual install needed.

## Usage

```bash
fix_icloud_exif.sh -d <directory> -R <true|false>
```

### Flags

| Flag | Description |
|------|-------------|
| `-d` | Directory containing the exported iCloud files and CSV metadata files |
| `-R` | Dry-run mode: `true` to preview changes, `false` to apply them |

Both flags are required. This is intentional so a real write cannot happen accidentally.

### Examples

Preview what would be changed (dry run):

```bash
./fix_icloud_exif.sh -d "/path/to/Photos" -R true
```

Apply changes:

```bash
./fix_icloud_exif.sh -d "/path/to/Photos" -R false
```

## What it does

1. Discovers all CSV files in the target directory and merges them into a single metadata set
2. For each file listed in the CSV, reads GPS coordinates from existing EXIF data to determine the local timezone
3. Converts the UTC creation date to local time (falls back to UTC if no GPS data)
4. For **images** (jpg, jpeg, png, heic, gif): sets `DateTimeOriginal`, `CreateDate`, `ModifyDate`, and timezone offset tags
5. For **videos** (mov, mp4, m4v): sets `CreateDate`, `ModifyDate`, `TrackCreateDate`, `TrackModifyDate`, `MediaCreateDate`, `MediaModifyDate`
6. Updates each file's filesystem modification time to match
7. Prints a summary of results

## Supported formats

- **Images:** JPG, JPEG, PNG, HEIC, GIF
- **Videos:** MOV, MP4, M4V

## Notes

- Files are updated in place (`-overwrite_original`) — no backup copies are created by exiftool
- Dates are converted to local time using GPS coordinates when available, with proper timezone offset tags
- Warnings and errors are printed to stderr; normal output goes to stdout
- CSV files must contain `imgName` and `originalCreationDate` columns

## License

MIT
