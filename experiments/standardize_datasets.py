#!/usr/bin/env python3
"""Convert raw 2D datasets to the experiment input format.

Output format:
    x y
    x y
    ...

Only the first two columns are used. Extra labels/classes are intentionally
discarded because the KDE/KDV algorithms consume only coordinates.
"""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


DATASETS = [
    {"name": "crime", "raw": "crime.txt", "out": "crime.txt"},
    {"name": "nyc_taxis", "raw": "NYC_taxis.csv", "out": "nyc_taxis.txt"},
    {"name": "us_census", "raw": "US_census.csv", "out": "us_census.txt"},
    {"name": "arxiv_articles_umap", "raw": "arxiv_articles_UMAP.csv", "out": "arxiv_articles_umap.txt"},
    {
        "name": "sf_311_cases",
        "raw": "311_Cases_20260711.csv",
        "out": "sf_311_cases.txt",
        "x_col": "Longitude",
        "y_col": "Latitude",
        "bounds": (-123.0, -122.0, 37.705, 38.0),
    },
    {
        "name": "la_crime_2010_2019",
        "raw": "Crime_Data_from_2010_to_2019_20260720.csv",
        "out": "la_crime_2010_2019.txt",
        "x_col": "LON",
        "y_col": "LAT",
        "bounds": (-119.0, -117.0, 33.0, 35.0),
    },
    {
        "name": "la_arrests_2010_2019_p001_p999_pad20",
        "raw": "Arrest_Data_from_2010_to_2019_20260724.csv",
        "out": "la_arrests_2010_2019_p001_p999_pad20.txt",
        "x_col": "LON",
        "y_col": "LAT",
        "bounds": (-119.0, -117.0, 33.0, 35.0),
        "quantile_crop": (0.001, 0.999, 0.20),
    },
]


def parse_xy(line: str):
    line = line.strip()
    if not line:
        return None
    parts = line.split(",") if "," in line else line.split()
    if len(parts) < 2:
        return None
    try:
        x = float(parts[0])
        y = float(parts[1])
    except ValueError:
        return None
    if not (math.isfinite(x) and math.isfinite(y)):
        return None
    return x, y


def parse_xy_from_row(row: dict[str, str], x_col: str, y_col: str):
    try:
        x = float(row.get(x_col, ""))
        y = float(row.get(y_col, ""))
    except ValueError:
        return None
    if not (math.isfinite(x) and math.isfinite(y)):
        return None
    return x, y


def quantile(sorted_values: list[float], p: float) -> float:
    return sorted_values[int(p * (len(sorted_values) - 1))]


def convert_one(src: Path, dst: Path, config: dict):
    count = 0
    skipped = 0
    min_x = math.inf
    max_x = -math.inf
    min_y = math.inf
    max_y = -math.inf

    dst.parent.mkdir(parents=True, exist_ok=True)
    x_col = config.get("x_col")
    y_col = config.get("y_col")
    quantile_crop = config.get("quantile_crop")
    retained_points = []
    with src.open("r", encoding="utf-8", errors="replace", newline="") as fin, dst.open(
        "w", encoding="utf-8", newline="\n"
    ) as fout:
        if x_col and y_col:
            iterator = (parse_xy_from_row(row, x_col, y_col) for row in csv.DictReader(fin))
        else:
            iterator = (parse_xy(line) for line in fin)
        for parsed in iterator:
            if parsed is None:
                skipped += 1
                continue
            x, y = parsed
            bounds = config.get("bounds")
            if bounds:
                xmin, xmax, ymin, ymax = bounds
                if x < xmin or x > xmax or y < ymin or y > ymax:
                    skipped += 1
                    continue
            if quantile_crop:
                retained_points.append((x, y))
                continue
            count += 1
            min_x = min(min_x, x)
            max_x = max(max_x, x)
            min_y = min(min_y, y)
            max_y = max(max_y, y)
            fout.write(f"{x:.17g} {y:.17g}\n")

        if quantile_crop:
            if not retained_points:
                raise ValueError(f"no points remain after coarse bounds for {config['name']}")
            lo_q, hi_q, padding = quantile_crop
            xs = sorted(p[0] for p in retained_points)
            ys = sorted(p[1] for p in retained_points)
            qx0 = quantile(xs, lo_q)
            qx1 = quantile(xs, hi_q)
            qy0 = quantile(ys, lo_q)
            qy1 = quantile(ys, hi_q)
            pad_x = (qx1 - qx0) * padding
            pad_y = (qy1 - qy0) * padding
            crop_x0 = max(xs[0], qx0 - pad_x)
            crop_x1 = min(xs[-1], qx1 + pad_x)
            crop_y0 = max(ys[0], qy0 - pad_y)
            crop_y1 = min(ys[-1], qy1 + pad_y)
            for x, y in retained_points:
                if crop_x0 <= x <= crop_x1 and crop_y0 <= y <= crop_y1:
                    count += 1
                    min_x = min(min_x, x)
                    max_x = max(max_x, x)
                    min_y = min(min_y, y)
                    max_y = max(max_y, y)
                    fout.write(f"{x:.17g} {y:.17g}\n")
                else:
                    skipped += 1

    if count == 0:
        min_x = max_x = min_y = max_y = 0.0
    return {
        "dataset": dst.stem,
        "source": src.as_posix(),
        "output": dst.as_posix(),
        "points": count,
        "skipped": skipped,
        "min_x": min_x,
        "max_x": max_x,
        "min_y": min_y,
        "max_y": max_y,
        "width": max_x - min_x,
        "height": max_y - min_y,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-dir", default="datasets")
    parser.add_argument("--out-dir", default="datasets/standardized")
    parser.add_argument(
        "--only",
        nargs="*",
        default=[],
        help="Convert only the named datasets, e.g. --only sf_311_cases",
    )
    args = parser.parse_args()

    raw_dir = Path(args.raw_dir)
    out_dir = Path(args.out_dir)
    selected_names = set(args.only)
    selected = [cfg for cfg in DATASETS if not selected_names or cfg["name"] in selected_names]
    missing = selected_names - {cfg["name"] for cfg in DATASETS}
    if missing:
        raise ValueError(f"unknown dataset(s): {', '.join(sorted(missing))}")

    rows_by_name = {}
    summary_path = out_dir / "summary.csv"
    if summary_path.exists():
        with summary_path.open(newline="", encoding="utf-8-sig") as f:
            for row in csv.DictReader(f):
                rows_by_name[row["dataset"]] = row

    for config in selected:
        src = raw_dir / config["raw"]
        dst = out_dir / config["out"]
        if not src.exists():
            raise FileNotFoundError(src)
        row = convert_one(src, dst, config)
        rows_by_name[row["dataset"]] = row
        print(
            f"{row['dataset']}: {row['points']} points, skipped={row['skipped']}, "
            f"x=[{row['min_x']:.12g},{row['max_x']:.12g}], "
            f"y=[{row['min_y']:.12g},{row['max_y']:.12g}]"
        )

    ordered_names = [cfg["out"].rsplit(".", 1)[0] for cfg in DATASETS if cfg["out"].rsplit(".", 1)[0] in rows_by_name]
    rows = [rows_by_name[name] for name in ordered_names]
    with summary_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "dataset",
                "source",
                "output",
                "points",
                "skipped",
                "min_x",
                "max_x",
                "min_y",
                "max_y",
                "width",
                "height",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {summary_path}")


if __name__ == "__main__":
    main()
