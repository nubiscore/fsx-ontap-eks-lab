# Tiering results, September 2026

Measured on a live lab, not taken from documentation. Final readings are due after the two-day cooling period ends (2026-09-26 19:15 UTC).

## Setup

| | |
| --- | --- |
| Region | `ca-central-1` (Canada Central) |
| File system | FSx for ONTAP `SINGLE_AZ_1`, 1024 GiB SSD, 128 MBps |
| Volumes | Four 10 GiB volumes on `svm1`, one per tiering policy, storage efficiency on |
| Cooling period | 2 days (the minimum) for `AUTO` and `SNAPSHOT_ONLY` |
| Data | 2 GiB of random data per volume (`dd if=/dev/urandom`), so deduplication and compression cannot mask tiering |
| Measurement | ONTAP REST API, `space.performance_tier_footprint` (SSD) and `space.capacity_tier_footprint` (capacity pool), via `make footprint` |

## Timeline (UTC)

| Time | Step |
| --- | --- |
| 2026-09-24 18:53 | `make up`: file system creation started (available after 15 min 12 s); all 56 resources done at 19:10, about 18 min in total |
| 19:11 | Mounted the four volumes over NFS 4.1 and wrote 2 GiB to each |
| 19:12:40 | Reading 1 |
| 19:13:06 | Snapshot `before-overwrite` on `tier_snapshot_only`, then its file overwritten with new random data |
| 19:14:02 | Reading 2 (`make footprint`) |

## Readings (GiB)

| Volume | Policy | Reading 1: SSD / pool | Reading 2: SSD / pool | Snapshot | Final (after 2026-09-26 19:15) |
| --- | --- | --- | --- | --- | --- |
| `tier_none` | `NONE` | 2.04 / 0 | 2.04 / 0 | 0 | pending |
| `tier_all` | `ALL` | 2.04 / 0 | 0.05 / 2.00 | 0 | pending |
| `tier_auto` | `AUTO` | 2.05 / 0 | 2.05 / 0 | 0 | pending |
| `tier_snapshot_only` | `SNAPSHOT_ONLY` | 2.05 / 0 | 4.09 / 0 | 2.03 | pending |

## What it shows so far

- **`ALL` tiers in minutes, not days.** 2 GiB moved to the capacity pool between readings 1 and 2, about 90 seconds apart, leaving 0.05 GiB (metadata) on SSD.
- **`NONE` keeps everything on SSD**, as expected.
- **`AUTO` and `SNAPSHOT_ONLY` have not moved yet**, which is correct: their data has not been cold for the cooling period.
- **Snapshots cost SSD until they tier.** After the overwrite, `tier_snapshot_only` holds 4.09 GiB on SSD: the new data plus 2.03 GiB of old blocks kept only by the snapshot. Those old blocks are what `SNAPSHOT_ONLY` should move after two days.

## Prices used

AWS Price List API, `ca-central-1`, on-demand, retrieved 2026-09-24 (USD):

| Item | Price |
| --- | --- |
| SSD storage, Single-AZ | $0.138 per GB-month |
| Capacity pool (standard) | $0.0238 per GB-month |
| Throughput capacity, Single-AZ | $0.788 per MBps-month |
| Capacity pool requests | $0.0055 per 1,000 writes, $0.00044 per 1,000 reads |
| NAT gateway | $0.05 per hour, plus $0.05 per GB processed |

What the prices mean:

- **Capacity-pool data costs about 5.8x less than SSD** in this region ($0.0238 against $0.138 per GB-month).
- **Throughput is a fixed cost that tiering does not touch.** At the minimum size (128 MBps) it is about $101 a month, against about $141 for the minimum 1024 GiB of SSD. Tiering lowers the storage line; right-sizing throughput is a separate decision that sizing on capacity alone misses.

Lab running cost at these prices: about $9.50 a day (file system about $7.96, NAT gateway $1.20, client instance $0.28, key and secrets about $0.06).
