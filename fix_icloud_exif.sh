#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  fix_icloud_exif.sh -d <directory> -f <csv_file> -R <true|false>

Required flags:
  -d   Directory containing the exported iCloud files
  -f   CSV manifest file
  -R   Dry-run mode: true or false

Examples:
  fix_icloud_exif.sh -d "/path/to/Photos" -f "/path/to/Photos/Photo Details.csv" -R true
  fix_icloud_exif.sh -d "/path/to/Photos" -f "/path/to/Photos/Photo Details.csv" -R false

Notes:
  - All three flags are required.
  - This is intentional so a real write cannot happen accidentally.
  - The script updates files in place.
EOF
}

if [[ $# -eq 0 ]]; then
  echo "Error: no arguments provided."
  echo
  usage
  exit 1
fi

TARGET_DIR=""
CSV_FILE=""
DRY_RUN=""

while getopts ":d:f:R:h" opt; do
  case "$opt" in
    d) TARGET_DIR="$OPTARG" ;;
    f) CSV_FILE="$OPTARG" ;;
    R) DRY_RUN="$OPTARG" ;;
    h)
      usage
      exit 0
      ;;
    \?)
      echo "Error: invalid option -$OPTARG"
      echo
      usage
      exit 1
      ;;
    :)
      echo "Error: option -$OPTARG requires an argument."
      echo
      usage
      exit 1
      ;;
  esac
done

shift $((OPTIND - 1))

if [[ -z "$TARGET_DIR" || -z "$CSV_FILE" || -z "$DRY_RUN" ]]; then
  echo "Error: -d, -f, and -R are all required."
  echo
  usage
  exit 1
fi

DRY_RUN_NORMALIZED="$(printf '%s' "$DRY_RUN" | tr '[:upper:]' '[:lower:]')"

case "$DRY_RUN_NORMALIZED" in
  true|false) ;;
  *)
    echo "Error: -R must be either true or false."
    echo
    usage
    exit 1
    ;;
esac

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Error: directory not found: $TARGET_DIR"
  exit 1
fi

if [[ ! -f "$CSV_FILE" ]]; then
  echo "Error: CSV file not found: $CSV_FILE"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required."
  exit 1
fi

if ! command -v exiftool >/dev/null 2>&1; then
  echo "Error: exiftool is required."
  exit 1
fi

echo "Running with:"
echo "  TARGET_DIR=$TARGET_DIR"
echo "  CSV_FILE=$CSV_FILE"
echo "  DRY_RUN=$DRY_RUN_NORMALIZED"

python3 - "$TARGET_DIR" "$CSV_FILE" "$DRY_RUN_NORMALIZED" <<'PY'
import csv
import os
import sys
import subprocess
from datetime import datetime, timezone

target_dir = os.path.abspath(sys.argv[1])
csv_path = os.path.abspath(sys.argv[2])
dry_run = sys.argv[3].lower() == "true"

image_exts = {"jpg", "jpeg", "png", "heic", "gif"}
video_exts = {"mov", "mp4", "m4v"}

REQUIRED_COLUMNS = {"imgName", "originalCreationDate"}

def parse_apple_date(s: str):
    s = (s or "").strip()
    if not s:
        return None
    try:
        dt = datetime.strptime(s, "%A %B %d,%Y %I:%M %p GMT")
        dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except ValueError:
        return None

def warn(msg: str):
    print(msg, file=sys.stderr)

def run(cmd):
    return subprocess.run(cmd, check=True, text=True, capture_output=True)

missing = 0
parsed = 0
updated = 0
unsupported = 0
bad_dates = 0
errors = 0

with open(csv_path, "r", encoding="utf-8-sig", newline="") as f:
    reader = csv.DictReader(f)

    if not reader.fieldnames:
        warn("Error: CSV file is empty or has no header row.")
        sys.exit(1)

    missing_cols = REQUIRED_COLUMNS - set(reader.fieldnames)
    if missing_cols:
        warn(f"Error: CSV is missing required columns: {', '.join(sorted(missing_cols))}")
        warn(f"  Found columns: {', '.join(reader.fieldnames)}")
        sys.exit(1)

    for row in reader:
        name = (row.get("imgName") or "").strip()
        created = (row.get("originalCreationDate") or "").strip()

        if not name:
            continue

        file_path = os.path.join(target_dir, name)

        if not os.path.isfile(file_path):
            warn(f"⚠️  Missing file: {file_path}")
            missing += 1
            continue

        dt = parse_apple_date(created)
        if not dt:
            warn(f"⚠️  Could not parse date for: {name} | raw={created!r}")
            bad_dates += 1
            continue

        exif_date = dt.strftime("%Y:%m:%d %H:%M:%S")
        parsed += 1

        ext = os.path.splitext(name)[1].lstrip(".").lower()

        if ext in image_exts:
            cmd = [
                "exiftool",
                "-overwrite_original",
                f"-DateTimeOriginal={exif_date}",
                f"-CreateDate={exif_date}",
                f"-ModifyDate={exif_date}",
                "-OffsetTimeOriginal=+00:00",
                "-OffsetTime=+00:00",
                "-OffsetTimeDigitized=+00:00",
                file_path,
            ]
        elif ext in video_exts:
            cmd = [
                "exiftool",
                "-overwrite_original",
                f"-CreateDate={exif_date}",
                f"-ModifyDate={exif_date}",
                f"-TrackCreateDate={exif_date}",
                f"-TrackModifyDate={exif_date}",
                f"-MediaCreateDate={exif_date}",
                f"-MediaModifyDate={exif_date}",
                file_path,
            ]
        else:
            warn(f"⚠️  Unsupported type: {file_path}")
            unsupported += 1
            continue

        if dry_run:
            print(f"DRYRUN  {file_path} -> {exif_date}")
            continue

        try:
            result = run(cmd)
            ts = dt.timestamp()
            os.utime(file_path, (ts, ts))
            print(f"UPDATED {file_path} -> {exif_date}")
            if result.stdout.strip():
                print(result.stdout.strip())
            updated += 1
        except subprocess.CalledProcessError as e:
            warn(f"⚠️  exiftool failed for {file_path}")
            if e.stdout:
                warn(e.stdout.strip())
            if e.stderr:
                warn(e.stderr.strip())
            errors += 1
        except Exception as e:
            warn(f"⚠️  Failed updating filesystem time for {file_path}: {e}")
            errors += 1

print("")
print("Summary")
print(f"  parsed dates:      {parsed}")
print(f"  updated files:     {updated}")
print(f"  missing files:     {missing}")
print(f"  bad dates:         {bad_dates}")
print(f"  unsupported types: {unsupported}")
print(f"  errors:            {errors}")
PY
