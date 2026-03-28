#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  fix_icloud_exif.sh -d <directory> [-n]

Required flags:
  -d   Directory containing the exported iCloud files and CSV metadata files

Options:
  -n   Dry-run mode: preview changes without modifying files

Examples:
  fix_icloud_exif.sh -d "/path/to/Photos" -n
  fix_icloud_exif.sh -d "/path/to/Photos"

Notes:
  - The script updates files in place when run without -n.
  - All CSV files in the directory are automatically merged as the metadata source.
EOF
}

if [[ $# -eq 0 ]]; then
  echo "Error: no arguments provided."
  echo
  usage
  exit 1
fi

TARGET_DIR=""
DRY_RUN=false

while getopts ":d:nh" opt; do
  case "$opt" in
    d) TARGET_DIR="$OPTARG" ;;
    n) DRY_RUN=true ;;
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

if [[ -z "$TARGET_DIR" ]]; then
  echo "Error: -d is required."
  echo
  usage
  exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Error: directory not found: $TARGET_DIR"
  exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "Error: uv is required. Install via: curl -LsSf https://astral.sh/uv/install.sh | sh"
  exit 1
fi

if ! command -v exiftool >/dev/null 2>&1; then
  echo "Error: exiftool is required."
  exit 1
fi

echo "Running with:"
echo "  TARGET_DIR=$TARGET_DIR"
echo "  DRY_RUN=$DRY_RUN"

uv run --with timezonefinder python3 - "$TARGET_DIR" "$DRY_RUN" <<'PY'
import csv
import glob
import json
import os
import sys
import subprocess
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo
from timezonefinder import TimezoneFinder

target_dir = os.path.abspath(sys.argv[1])
dry_run = sys.argv[2].lower() == "true"

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

tf = TimezoneFinder()

def warn(msg: str):
    print(msg, file=sys.stderr)

def run(cmd):
    return subprocess.run(cmd, check=True, text=True, capture_output=True)

def get_timezone_for_file(file_path):
    """Read GPS coordinates from EXIF and return a ZoneInfo, or None."""
    try:
        result = subprocess.run(
            ["exiftool", "-json", "-GPSLatitude", "-GPSLongitude", "-n", file_path],
            check=True, text=True, capture_output=True,
        )
        data = json.loads(result.stdout)
        if not data:
            return None
        entry = data[0]
        lat = entry.get("GPSLatitude")
        lng = entry.get("GPSLongitude")
        if lat is None or lng is None:
            return None
        tz_name = tf.timezone_at(lat=float(lat), lng=float(lng))
        if tz_name:
            return ZoneInfo(tz_name)
    except Exception as e:
        warn(f"⚠️  Could not determine timezone for {file_path}: {e}")
    return None

missing = 0
parsed = 0
updated = 0
unsupported = 0
bad_dates = 0
errors = 0

csv_files = sorted(glob.glob(os.path.join(target_dir, "*.csv")))
if not csv_files:
    warn(f"Error: no CSV files found in {target_dir}")
    sys.exit(1)

print(f"Found {len(csv_files)} CSV file(s):")
for cf in csv_files:
    print(f"  {os.path.basename(cf)}")

rows = []
header = None
for csv_file in csv_files:
    with open(csv_file, "r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)

        if not reader.fieldnames:
            warn(f"Error: CSV file is empty or has no header row: {csv_file}")
            sys.exit(1)

        if header is None:
            header = reader.fieldnames
            missing_cols = REQUIRED_COLUMNS - set(header)
            if missing_cols:
                warn(f"Error: CSV is missing required columns: {', '.join(sorted(missing_cols))}")
                warn(f"  Found columns: {', '.join(header)}")
                sys.exit(1)

        for row in reader:
            rows.append(row)

total = len(rows)
print(f"Merged {total} rows from CSV files.\n")

for i, row in enumerate(rows, 1):
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

    parsed += 1
    ext = os.path.splitext(name)[1].lstrip(".").lower()

    tz = get_timezone_for_file(file_path)
    if tz:
        local_dt = dt.astimezone(tz)
        offset = local_dt.strftime("%z")
        offset_str = f"{offset[:3]}:{offset[3:]}"
        tz_label = str(tz)
    else:
        local_dt = dt
        offset_str = "+00:00"
        tz_label = "UTC (no GPS)"

    exif_date = local_dt.strftime("%Y:%m:%d %H:%M:%S")

    if ext in image_exts:
        cmd = [
            "exiftool",
            "-overwrite_original",
            f"-DateTimeOriginal={exif_date}",
            f"-CreateDate={exif_date}",
            f"-ModifyDate={exif_date}",
            f"-OffsetTimeOriginal={offset_str}",
            f"-OffsetTime={offset_str}",
            f"-OffsetTimeDigitized={offset_str}",
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

    progress = f"[{i}/{total}]"

    if dry_run:
        print(f"{progress} DRYRUN  {file_path} -> {exif_date} {offset_str} ({tz_label})")
        continue

    try:
        result = run(cmd)
        ts = local_dt.timestamp()
        os.utime(file_path, (ts, ts))
        print(f"{progress} UPDATED {file_path} -> {exif_date} {offset_str} ({tz_label})")
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
