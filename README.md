# fix_icloud_exif

Restore original creation dates to photos and videos exported from iCloud.

When you export your iCloud Photo Library using Apple's data privacy tool, the exported files lose their original EXIF timestamps. Apple includes a CSV manifest (`Photo Details.csv`) with the original dates. This script reads that CSV and writes the correct dates back into each file's EXIF metadata and filesystem timestamps.

## Requirements

- **bash** (macOS/Linux)
- **python3** (3.6+)
- **exiftool** — install via `brew install exiftool` on macOS

## Usage

```bash
fix_icloud_exif.sh -d <directory> -f <csv_file> -R <true|false>
```

### Flags

| Flag | Description |
|------|-------------|
| `-d` | Directory containing the exported iCloud files |
| `-f` | Path to the CSV manifest file (e.g., `Photo Details.csv`) |
| `-R` | Dry-run mode: `true` to preview changes, `false` to apply them |

All three flags are required. This is intentional so a real write cannot happen accidentally.

### Examples

Preview what would be changed (dry run):

```bash
./fix_icloud_exif.sh -d "/path/to/Photos" -f "/path/to/Photos/Photo Details.csv" -R true
```

Apply changes:

```bash
./fix_icloud_exif.sh -d "/path/to/Photos" -f "/path/to/Photos/Photo Details.csv" -R false
```

## What it does

1. Parses the iCloud CSV manifest for filenames and original creation dates
2. For **images** (jpg, jpeg, png, heic, gif): sets `DateTimeOriginal`, `CreateDate`, `ModifyDate`, and UTC offset tags
3. For **videos** (mov, mp4, m4v): sets `CreateDate`, `ModifyDate`, `TrackCreateDate`, `TrackModifyDate`, `MediaCreateDate`, `MediaModifyDate`
4. Updates each file's filesystem modification time to match
5. Prints a summary of results

## Supported formats

- **Images:** JPG, JPEG, PNG, HEIC, GIF
- **Videos:** MOV, MP4, M4V

## Notes

- Files are updated in place (`-overwrite_original`) — no backup copies are created by exiftool
- Dates are stored in UTC with proper timezone offset tags
- Warnings and errors are printed to stderr; normal output goes to stdout
- The CSV must contain `imgName` and `originalCreationDate` columns

## License

MIT
