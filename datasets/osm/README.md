# OSM Dataset Preparation

Large OSM point datasets are not stored in this repository. They can be reproduced from Geofabrik extracts with the scripts in this directory.

## Australia

- Source URL: `https://download.geofabrik.de/australia-oceania/australia-latest.osm.pbf`
- Observed source size on 2026-09-23: about 964 MB
- Bounding box used by the experiments:
  - longitude: `[112, 154]`
  - latitude: `[-44, -10]`
- Processed point count: `134,281,802`

Example:

```powershell
Set-Location -LiteralPath <repo-root>
PowerShell -NoProfile -ExecutionPolicy Bypass -File .\datasets\osm\prepare_osm_dataset.ps1 `
  -Url https://download.geofabrik.de/australia-oceania/australia-latest.osm.pbf `
  -DatasetTag osm_australia_nodes_mainland_tas_full `
  -Stage full `
  -MinX 112 -MaxX 154 -MinY -44 -MaxY -10
```

## Japan

- Source URL: `https://download.geofabrik.de/asia/japan-latest.osm.pbf`
- Observed source size on 2026-09-23: about 2.53 GB
- Bounding box used by the experiments:
  - longitude: `[122, 154]`
  - latitude: `[24, 46]`
- Processed point count: `317,795,304`

Example:

```powershell
Set-Location -LiteralPath <repo-root>
PowerShell -NoProfile -ExecutionPolicy Bypass -File .\datasets\osm\prepare_osm_dataset.ps1 `
  -Url https://download.geofabrik.de/asia/japan-latest.osm.pbf `
  -DatasetTag osm_japan_main `
  -Stage full `
  -MinX 122 -MaxX 154 -MinY 24 -MaxY 46
```

The generated `.pbf` and processed OSM `.txt` files are intentionally ignored by Git.
