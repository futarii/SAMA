# Third-party Notices

This repository includes third-party baseline code for reproducibility and fair comparison.

## Exact Baselines: SLAM / SCAN / RQS

Files under `cpp/baselines/exact/` are adapted from the released SLAM SIGMOD 2022 implementation. The same executable supports SCAN, RQS, and SLAM variants through different method IDs.

Method IDs used by the baseline executable:

- `0`: SCAN
- `3`: RQS-kd
- `4`: RQS-ball
- `5`: SLAM-SORT
- `6`: SLAM-BUCKET
- `7`: SLAM-SORT-RAO
- `8`: SLAM-BUCKET-RAO

## Z-order Baseline

Files under `cpp/baselines/approximate/` are adapted from the released Z-order coreset implementation used as an approximate baseline.

## SAMA

Files under `cpp/sama/` contain the SAMA implementation developed for this work.
