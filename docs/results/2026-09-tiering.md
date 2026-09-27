# Tiering results, September 2026

Measured on a live lab, not taken from documentation. The experiment ran in two rounds. Round 1 kept the SSD tier almost empty and showed that `AUTO` and `SNAPSHOT_ONLY` do not tier at all below the 50% utilization threshold. Round 2 filled the SSD tier past 50% and is waiting for the cooling window to complete.

## Setup

| | |
| --- | --- |
| Region | `ca-central-1` (Canada Central) |
| File system | FSx for ONTAP `SINGLE_AZ_1`, 1024 GiB SSD, 128 MBps |
| Volumes | Four 10 GiB volumes on `svm1`, one per tiering policy, storage efficiency on. Round 2 adds `tier_filler`, a 480 GiB `NONE` volume used only to raise SSD utilization |
| Cooling period | 2 days (the minimum) for `AUTO` and `SNAPSHOT_ONLY` |
| Data | 2 GiB of random data per volume (`dd if=/dev/urandom`), so deduplication and compression cannot mask tiering |
| Measurement | ONTAP REST API, `space.performance_tier_footprint` (SSD) and `space.capacity_tier_footprint` (capacity pool), via `make footprint`. Cross-checked against the CloudWatch `StorageUsed` metric per volume and `StorageTier`, which agrees to within 0.1 GiB |

## Timeline (UTC)

| Time | Step |
| --- | --- |
| 2026-09-24 18:53 | `make up`: file system creation started (available after 15 min 12 s); all 56 resources done at 19:10, about 18 min in total |
| 19:11 | Mounted the four volumes over NFS 4.1 and wrote 2 GiB to each |
| 19:12:40 | Reading 1 |
| 19:13:06 | Snapshot `before-overwrite` on `tier_snapshot_only`, then its file overwritten with new random data |
| 19:14:02 | Reading 2 (`make footprint`) |
| 2026-09-26 19:11 | Two-day cooling period on the round-1 data expires |
| 20:25 | Reading 3 (round 1 final), SSD tier at 1.2% utilization |
| 20:29 | `tier_filler` created (`NONE`, 480 GiB) and about 456 GiB of random data written to it over NFS |
| 2026-09-27 ~02:00 | SSD tier crosses 50% utilization (CloudWatch hourly averages: 47.4% for the hour starting 01:00, 54.6% from 02:00) |
| 16:47 | Reading 4, SSD tier at 54.6%: no movement yet on `AUTO` or `SNAPSHOT_ONLY` |
| 2026-09-28 02:00 to 2026-09-29 02:00 | Window in which round-2 tiering is expected (24 to 48 hours after eligibility) |

## Readings (GiB, SSD / capacity pool)

| Volume | Policy | Reading 1 (write) | Reading 2 (+90 s) | Reading 3 (round 1 final, +2 days, SSD 1.2%) | Reading 4 (round 2, SSD 54.6%, before window) | Round 2 final |
| --- | --- | --- | --- | --- | --- | --- |
| `tier_none` | `NONE` | 2.04 / 0 | 2.04 / 0 | 2.12 / 0 | 2.07 / 0 | pending |
| `tier_all` | `ALL` | 2.04 / 0 | 0.05 / 2.00 | 0.14 / 2.00 | 0.08 / 2.00 | pending |
| `tier_auto` | `AUTO` | 2.05 / 0 | 2.05 / 0 | 2.13 / 0 | 2.07 / 0 | pending |
| `tier_snapshot_only` | `SNAPSHOT_ONLY` | 2.05 / 0 | 4.09 / 0 (2.03 snapshot) | 4.18 / 0 | 4.11 / 0 (2.03 snapshot) | pending |
| `tier_filler` | `NONE` | n/a | n/a | n/a | 456.70 / 0 | pending |

Reading 3 comes from CloudWatch (`StorageUsed` per volume and tier, five-minute average ending 2026-09-26 20:25 UTC); readings 1, 2 and 4 are from the ONTAP REST API. The small differences between sources (about 0.05 to 0.1 GiB) are metadata and rounding.

Aggregate at reading 4: 470.4 GiB used of 861.8 GiB usable = 54.6%. The 1024 GiB provisioned becomes about 862 GiB usable once ONTAP's overhead (up to 16%) is set aside, and the utilization thresholds are measured against the usable figure.

## Round 1 result: the 50% threshold

After the full two-day cooling period, `AUTO` and `SNAPSHOT_ONLY` had moved nothing. This is not a failure of the policies; it is documented behaviour that the policy descriptions do not mention. The [FSx for ONTAP tiering thresholds](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/volume-storage-capacity.html#storage-tiering-thresholds):

| SSD tier utilization | Behaviour |
| --- | --- |
| 50% or below | Only `ALL` volumes tier. `AUTO` and `SNAPSHOT_ONLY` move nothing. |
| Above 50% | `AUTO` and `SNAPSHOT_ONLY` tier data past its cooling period, 24 to 48 hours after eligibility, as a low-priority background job. |
| 90% or above | Reads from the capacity pool are no longer cached on SSD. |
| 98% or above | All tiering stops; reads continue, writes fail. |

With four 10 GiB volumes on a 1024 GiB tier, utilization was 1.2%, so the cooling period alone could never trigger a move. A fresh or over-provisioned file system behaves the same way in production: `AUTO` volumes stay entirely on SSD and the bill is identical to `NONE`.

## Round 2: filling the tier

To get past the threshold without changing the four test volumes, a fifth volume, `tier_filler` (`NONE`, 480 GiB), was created on 2026-09-26 at 20:29 UTC and filled with about 456 GiB of random data over NFS. Utilization rose from 1.2% to 54.6% over the following hours and crossed 50% at about 02:00 UTC on 2026-09-27. Because SSD is billed on the provisioned size, the filler adds nothing to the running cost.

The round-1 data has already been cold for longer than the cooling period, so the remaining wait is the tiering scanner's 24 to 48 hour lag from the moment the tier became eligible. Reading 4, taken about 15 hours after the crossing, shows no movement yet, as expected. The round-2 final reading will be taken after 2026-09-29 02:00 UTC at the latest.

## What it shows so far

- **`ALL` tiers in minutes, not days.** 2 GiB moved to the capacity pool between readings 1 and 2, about 90 seconds apart, leaving 0.05 GiB (metadata) on SSD.
- **`NONE` keeps everything on SSD**, as expected.
- **`AUTO` and `SNAPSHOT_ONLY` did not move after two days at 1.2% SSD utilization**, and will not until the tier is above 50%. The cooling period is necessary but not sufficient; see "Round 1 result" above.
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

- **Capacity-pool data costs about a sixth as much as SSD** in this region ($0.0238 against $0.138 per GB-month, a 5.8 to 1 ratio).
- **Throughput is a fixed cost that tiering does not touch.** At the minimum size (128 MBps) it is about $101 a month, against about $141 for the minimum 1024 GiB of SSD. Tiering lowers the storage line; right-sizing throughput is a separate decision that sizing on capacity alone misses.

Lab running cost at these prices: about $9.50 a day (file system about $7.96, NAT gateway $1.20, client instance $0.28, key and secrets about $0.06).
