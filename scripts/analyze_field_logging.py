#!/usr/bin/env python3
"""Analyze an exported Meshtastic field logging session.

The input may be either the directory produced by SessionDataExporter or a ZIP
archive containing that directory. The script prints a compact summary and can
optionally write radio observations joined to their nearest GPS point as CSV.

Examples:

    python3 scripts/analyze_field_logging.py /path/to/field-session
    python3 scripts/analyze_field_logging.py session.zip \
        --tolerance 5 --output radio-with-location.csv
"""

from __future__ import annotations

import argparse
import csv
import json
import shutil
import sys
import tempfile
import zipfile
from bisect import bisect_left
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable, Iterator


REQUIRED_FILES = (
    "manifest.json",
    "gps_points.jsonl",
    "radio_observations.jsonl",
)


@dataclass(frozen=True)
class GPSPoint:
    """A GPS point with a parsed timestamp for efficient matching."""

    timestamp: datetime
    values: dict[str, Any]


def parse_timestamp(value: str) -> datetime:
    """Parse the ISO-8601 dates emitted by the Swift exporter."""

    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def read_json_lines(path: Path) -> Iterator[dict[str, Any]]:
    """Yield JSON objects from a JSON Lines file, skipping blank lines."""

    with path.open("r", encoding="utf-8") as input_file:
        for line_number, line in enumerate(input_file, start=1):
            if not line.strip():
                continue
            try:
                value = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(f"{path}:{line_number}: invalid JSON: {error}") from error
            if not isinstance(value, dict):
                raise ValueError(f"{path}:{line_number}: expected a JSON object")
            yield value


def resolve_bundle(path: Path) -> tuple[Path, Path | None]:
    """Return the bundle directory and an optional temporary extraction path."""

    if path.is_dir():
        bundle = path
        cleanup_path = None
    elif path.is_file() and zipfile.is_zipfile(path):
        cleanup_path = Path(tempfile.mkdtemp(prefix="meshtastic-field-session-"))
        with zipfile.ZipFile(path) as archive:
            archive.extractall(cleanup_path)
        bundle = cleanup_path
    else:
        raise ValueError(f"Input is not a session folder or ZIP archive: {path}")

    # ZIP tools commonly add one enclosing directory. Find the directory that
    # contains the exporter files without making assumptions about its name.
    for candidate in (bundle, *bundle.rglob("*")):
        if candidate.is_dir() and all((candidate / name).is_file() for name in REQUIRED_FILES):
            return candidate, cleanup_path

    if cleanup_path is not None:
        shutil.rmtree(cleanup_path, ignore_errors=True)
    raise ValueError("The bundle does not contain the required export files")


def load_gps_points(path: Path) -> tuple[list[datetime], list[GPSPoint]]:
    """Load and sort GPS points by timestamp for nearest-neighbor matching."""

    points = [
        GPSPoint(timestamp=parse_timestamp(str(values["recordedAt"])), values=values)
        for values in read_json_lines(path)
    ]
    points.sort(key=lambda point: point.timestamp)
    return [point.timestamp for point in points], points


def closest_gps_point(
    timestamp: datetime,
    timestamps: list[datetime],
    points: list[GPSPoint],
    tolerance_seconds: float,
) -> GPSPoint | None:
    """Return the closest GPS point when it falls inside the tolerance window."""

    if not points:
        return None

    insertion_index = bisect_left(timestamps, timestamp)
    candidates = []
    if insertion_index < len(points):
        candidates.append(points[insertion_index])
    if insertion_index > 0:
        candidates.append(points[insertion_index - 1])

    closest = min(candidates, key=lambda point: abs(point.timestamp - timestamp))
    if abs(closest.timestamp - timestamp).total_seconds() <= tolerance_seconds:
        return closest
    return None


def join_radio_to_gps(
    radio_path: Path,
    timestamps: list[datetime],
    points: list[GPSPoint],
    tolerance_seconds: float,
) -> Iterator[dict[str, Any]]:
    """Yield radio observations augmented with the nearest GPS coordinates."""

    for radio in read_json_lines(radio_path):
        received_at = parse_timestamp(str(radio["receivedAt"]))
        point = closest_gps_point(received_at, timestamps, points, tolerance_seconds)
        joined = dict(radio)
        joined["gpsRecordedAt"] = point.values["recordedAt"] if point else ""
        joined["latitude"] = point.values["latitude"] if point else ""
        joined["longitude"] = point.values["longitude"] if point else ""
        joined["altitude"] = point.values["altitude"] if point else ""
        joined["gpsMatchOffsetSeconds"] = (
            (received_at - point.timestamp).total_seconds() if point else ""
        )
        yield joined


def flatten_value(value: Any) -> Any:
    """Make optional values safe for CSV output."""

    if isinstance(value, (dict, list)):
        return json.dumps(value, separators=(",", ":"))
    return value


def write_joined_csv(rows: Iterable[dict[str, Any]], output_path: Path) -> int:
    """Write joined rows while keeping only one radio observation in memory."""

    row_count = 0
    fieldnames: list[str] | None = None
    with output_path.open("w", encoding="utf-8", newline="") as output_file:
        writer = None
        for row in rows:
            if fieldnames is None:
                fieldnames = list(row)
                writer = csv.DictWriter(output_file, fieldnames=fieldnames)
                writer.writeheader()
            writer.writerow({key: flatten_value(value) for key, value in row.items()})
            row_count += 1
    return row_count


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path, help="Exported session folder or ZIP archive")
    parser.add_argument(
        "--tolerance",
        type=float,
        default=2.0,
        metavar="SECONDS",
        help="Maximum absolute radio/GPS timestamp difference (default: 2)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        metavar="CSV",
        help="Write radio observations joined to GPS coordinates to this CSV file",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.tolerance < 0:
        print("--tolerance must not be negative", file=sys.stderr)
        return 2

    cleanup_path: Path | None = None
    try:
        bundle, cleanup_path = resolve_bundle(args.bundle)
        with (bundle / "manifest.json").open("r", encoding="utf-8") as manifest_file:
            manifest = json.load(manifest_file)

        timestamps, gps_points = load_gps_points(bundle / "gps_points.jsonl")
        joined_rows = join_radio_to_gps(
            bundle / "radio_observations.jsonl",
            timestamps,
            gps_points,
            args.tolerance,
        )

        matched_count = 0
        radio_count = 0
        if args.output:
            # Materialize only when needed for the summary count; CSV writing
            # itself remains streaming and does not retain all radio records.
            def counted_rows() -> Iterator[dict[str, Any]]:
                nonlocal matched_count, radio_count
                for row in joined_rows:
                    radio_count += 1
                    if row["gpsRecordedAt"]:
                        matched_count += 1
                    yield row

            radio_count = write_joined_csv(counted_rows(), args.output)
        else:
            for row in joined_rows:
                radio_count += 1
                matched_count += bool(row["gpsRecordedAt"])

        print(f"Session: {manifest.get('name', manifest.get('sessionId', 'unknown'))}")
        print(f"Activity: {manifest.get('activity', 'unknown')}")
        print(f"GPS points: {len(gps_points)}")
        print(f"Radio observations: {radio_count}")
        print(f"Radio observations matched to GPS: {matched_count}")
        print(f"Match tolerance: {args.tolerance:g} seconds")
        if args.output:
            print(f"Joined CSV: {args.output}")
        return 0
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError, zipfile.BadZipFile) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    finally:
        if cleanup_path is not None:
            shutil.rmtree(cleanup_path, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
