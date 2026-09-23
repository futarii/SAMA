#!/usr/bin/env python3
"""Extract OSM PBF nodes into the KDV two-column point format.

The script streams an .osm.pbf file with pyosmium/osmium and can either keep all
nodes or deterministically sample by node id. It also optionally emits a scatter
plot from the extracted points.
"""

from __future__ import annotations

import argparse
import math
import time
from pathlib import Path

import osmium


class NodeExtractor(osmium.SimpleHandler):
    def __init__(
        self,
        output_path: Path,
        sample_mod: int,
        sample_rem: int,
        max_points: int,
        min_x: float | None,
        max_x: float | None,
        min_y: float | None,
        max_y: float | None,
        log_every: int,
    ) -> None:
        super().__init__()
        self.output_path = output_path
        self.sample_mod = sample_mod
        self.sample_rem = sample_rem
        self.max_points = max_points
        self.min_x_filter = min_x
        self.max_x_filter = max_x
        self.min_y_filter = min_y
        self.max_y_filter = max_y
        self.log_every = log_every
        self.scanned = 0
        self.written = 0
        self.skipped_invalid = 0
        self.skipped_bbox = 0
        self.min_x = math.inf
        self.max_x = -math.inf
        self.min_y = math.inf
        self.max_y = -math.inf
        self.start = time.perf_counter()
        self._fh = None

    def __enter__(self) -> "NodeExtractor":
        self.output_path.parent.mkdir(parents=True, exist_ok=True)
        self._fh = self.output_path.open("w", encoding="utf-8", newline="\n")
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        if self._fh is not None:
            self._fh.close()
            self._fh = None

    def node(self, n) -> None:
        self.scanned += 1
        if self.max_points > 0 and self.written >= self.max_points:
            return
        if self.sample_mod > 1 and (int(n.id) % self.sample_mod) != self.sample_rem:
            return
        loc = n.location
        if not loc.valid():
            self.skipped_invalid += 1
            return
        x = float(loc.lon)
        y = float(loc.lat)
        if self.min_x_filter is not None and x < self.min_x_filter:
            self.skipped_bbox += 1
            return
        if self.max_x_filter is not None and x > self.max_x_filter:
            self.skipped_bbox += 1
            return
        if self.min_y_filter is not None and y < self.min_y_filter:
            self.skipped_bbox += 1
            return
        if self.max_y_filter is not None and y > self.max_y_filter:
            self.skipped_bbox += 1
            return
        self.min_x = min(self.min_x, x)
        self.max_x = max(self.max_x, x)
        self.min_y = min(self.min_y, y)
        self.max_y = max(self.max_y, y)
        assert self._fh is not None
        self._fh.write(f"{x:.7f} {y:.7f}\n")
        self.written += 1
        if self.written % self.log_every == 0:
            elapsed = time.perf_counter() - self.start
            rate = self.scanned / elapsed if elapsed else 0.0
            print(
                f"scanned={self.scanned} written={self.written} "
                f"elapsed={elapsed:.1f}s scan_rate={rate:.0f}/s",
                flush=True,
            )


def write_summary(path: Path, extractor: NodeExtractor, pbf: Path) -> None:
    elapsed = time.perf_counter() - extractor.start
    lines = [
        f"source={pbf}",
        f"output={extractor.output_path}",
        f"seconds={elapsed:.3f}",
        f"scanned_nodes={extractor.scanned}",
        f"written_points={extractor.written}",
        f"skipped_invalid={extractor.skipped_invalid}",
        f"skipped_bbox={extractor.skipped_bbox}",
        f"sample_mod={extractor.sample_mod}",
        f"sample_rem={extractor.sample_rem}",
        f"min_x={extractor.min_x}",
        f"max_x={extractor.max_x}",
        f"min_y={extractor.min_y}",
        f"max_y={extractor.max_y}",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def make_scatter(points_path: Path, image_path: Path, max_plot_points: int) -> None:
    import matplotlib.pyplot as plt

    xs: list[float] = []
    ys: list[float] = []
    with points_path.open("r", encoding="utf-8") as f:
        for i, line in enumerate(f):
            if i >= max_plot_points:
                break
            parts = line.strip().split()
            if len(parts) < 2:
                continue
            xs.append(float(parts[0]))
            ys.append(float(parts[1]))

    image_path.parent.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(8, 6), dpi=180)
    ax.scatter(xs, ys, s=0.08, c="#2f5f8f", alpha=0.18, linewidths=0)
    ax.set_aspect("equal", adjustable="box")
    ax.set_xlabel("Longitude")
    ax.set_ylabel("Latitude")
    title = points_path.stem.replace("_", " ").title()
    ax.set_title(f"{title} ({len(xs):,} plotted)")
    ax.grid(True, color="#d8d8d8", linewidth=0.35)
    fig.tight_layout()
    fig.savefig(image_path)
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pbf", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--summary", required=True, type=Path)
    parser.add_argument("--scatter", type=Path)
    parser.add_argument("--sample-mod", type=int, default=1)
    parser.add_argument("--sample-rem", type=int, default=0)
    parser.add_argument("--max-points", type=int, default=0)
    parser.add_argument("--min-x", type=float)
    parser.add_argument("--max-x", type=float)
    parser.add_argument("--min-y", type=float)
    parser.add_argument("--max-y", type=float)
    parser.add_argument("--max-plot-points", type=int, default=1_000_000)
    parser.add_argument("--log-every", type=int, default=100_000)
    args = parser.parse_args()

    with NodeExtractor(
        args.output,
        max(1, args.sample_mod),
        args.sample_rem,
        max(0, args.max_points),
        args.min_x,
        args.max_x,
        args.min_y,
        args.max_y,
        max(1, args.log_every),
    ) as extractor:
        extractor.apply_file(str(args.pbf), locations=False)
        write_summary(args.summary, extractor, args.pbf)

    if args.scatter:
        make_scatter(args.output, args.scatter, args.max_plot_points)


if __name__ == "__main__":
    main()
