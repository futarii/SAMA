# SAMA

This repository contains the code and datasets needed to reproduce the SAMA experiments for exact kernel density visualization (KDV).

## Repository Layout

- `cpp/sama/`: SAMA implementation.
- `cpp/baselines/exact/`: exact baseline source adapted from the SLAM SIGMOD 2022 artifact, including SCAN, RQS, and SLAM variants.
- `cpp/baselines/approximate/`: Z-order coreset approximate baseline source used by the experiments.
- `experiments/`: experiment scripts only. Generated results are intentionally ignored.
- `datasets/`: four standardized small datasets used by the paper experiments.
- `datasets/osm/`: scripts and instructions for downloading and processing the OSM datasets. Processed OSM point files are not included because they are too large for GitHub.

## Build

Install a C++ compiler with `g++` available on `PATH`, then run:

```powershell
Set-Location -LiteralPath <repo-root>
PowerShell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

If multiple `g++` installations are present, pass the compiler explicitly:

```powershell
PowerShell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 `
  -Cxx "C:\path\to\g++.exe"
```

The script builds SAMA, exact baselines, and Z-order executables in their source directories. These generated binaries are ignored by Git.

## Small Dataset Experiment Example

```powershell
Set-Location -LiteralPath <repo-root>
PowerShell -NoProfile -ExecutionPolicy Bypass -File .\experiments\run_kdv_experiments.ps1 `
  -Dataset .\datasets\crime.txt `
  -DatasetTag philadelphia_crime `
  -RunTag smoke `
  -Groups default `
  -MethodKeys @('m7','m8') `
  -CustomRows 320 `
  -CustomCols 240 `
  -ExecutionOrder expected_fast_first `
  -OutputRetention none `
  -TimeoutSeconds 600 `
  -NoZOrder
```

Generated results are written under `experiments/results/` and are not tracked.

## OSM Datasets

The large OSM datasets used for high-resolution experiments are generated from Geofabrik extracts. See `datasets/osm/README.md` for download URLs, bounding boxes, and processing commands.

## Third-party Code

The baseline code is included only for reproducibility and fair comparison. See `THIRD_PARTY_NOTICES.md`.
