# SAMA

SAMA is a support-aware moment aggregation method for exact kernel density visualization (KDV). It changes the computation unit from isolated pixels to on-demand raster tiles, certifies empty and full-cover node-tile interactions, evaluates full-cover regions by moment aggregation, and leaves only unresolved boundary interactions for direct evaluation.

This repository contains the code and datasets needed to reproduce the SAMA experiments.

## Repository Layout

- `cpp/sama/`: SAMA implementation.
- `cpp/baselines/exact/`: exact baseline methods, including SCAN, RQS-kd, RQS-ball, and SLAM variants.
- `cpp/baselines/approximate/`: Z-order coreset approximate baseline source used by the experiments.
- `experiments/`: experiment scripts.
- `datasets/`: four standardized real-world geospatial datasets used by the paper experiments.
- `datasets/osm/`: scripts and instructions for reproducing the OSM datasets from public Geofabrik extracts.

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

The script builds SAMA, exact baselines, and Z-order executables in their source directories.

## Experiment Example

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

## OSM Datasets

The large OSM datasets used for high-resolution experiments are generated from Geofabrik extracts. See `datasets/osm/README.md` for download URLs, bounding boxes, and processing commands.

## Third-party Code

The baseline code is included only for reproducibility and fair comparison. See `THIRD_PARTY_NOTICES.md`.
