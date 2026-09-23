# Experiment Scripts

This directory contains scripts for running experiments. It does not contain generated figures or results.

## Main Runner

`run_kdv_experiments.ps1` runs SAMA and selected baseline methods on a dataset.

Example:

```powershell
PowerShell -NoProfile -ExecutionPolicy Bypass -File .\experiments\run_kdv_experiments.ps1 `
  -Dataset .\datasets\crime.txt `
  -DatasetTag philadelphia_crime `
  -RunTag example `
  -Groups default `
  -MethodKeys @('m7','m8') `
  -CustomRows 1280 `
  -CustomCols 960 `
  -ExecutionOrder expected_fast_first `
  -OutputRetention none `
  -TimeoutSeconds 14400 `
  -NoZOrder `
  -Resume
```

## OSM High-resolution Sweep

`run_osm_highres_sweep.ps1` wraps the main runner for multiple resolutions.

## Dataset Standardization

`standardize_datasets.py` converts raw point data into the standardized two-dimensional text format used by the runners. It is not required when using the prepared datasets already included under `datasets/`.
