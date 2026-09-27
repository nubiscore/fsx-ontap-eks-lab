# Lab plan

Two weeks, a few hours at a time. Each exercise ends with a result you can measure or demonstrate.

## Week 1: FSx for ONTAP and tiering

### 1. Build it

```bash
make up
make client
```

On the client (commands run as `ssm-user`; the region comes from instance metadata):

```bash
export AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" http://169.254.169.254/latest/meta-data/placement/region)
NFS=<fsx_nfs_dns output>
for v in tier_none tier_snapshot_only tier_auto tier_all; do sudo mount -t nfs $NFS:/$v /mnt/$v; done
df -h /mnt/tier_*
```

### 2. Write the same data to every volume

Random data, so deduplication and compression do not hide the tiering effect:

```bash
for v in tier_none tier_snapshot_only tier_auto tier_all; do
  sudo dd if=/dev/urandom of=/mnt/$v/data.bin bs=1M count=2048 status=none
done
```

### 3. Watch where it lands

From your own machine, `make footprint` prints each volume's SSD and capacity-pool footprint through SSM and the ONTAP REST API; the password never leaves AWS. Run it now, after a few hours, and after the cooling period.

### 4. Push the SSD tier past 50%, or AUTO never moves

FSx for ONTAP does not tier `AUTO` or `SNAPSHOT_ONLY` volumes while the SSD tier is at or below 50% utilization, however long the data has been cold ([tiering thresholds](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/volume-storage-capacity.html#storage-tiering-thresholds)). Four 10 GiB volumes on a 1024 GiB tier sit at about 1%, so after step 3's cooling period only `ALL` will have moved. That is a real result, and the reason a generously sized production file system can run `AUTO` for months and save nothing.

To see the policies actually tier, add a filler volume and fill it. In `terraform.tfvars`:

```hcl
tiering_filler_gib = 480
```

Then `make up`, and on the client:

```bash
sudo mkdir -p /mnt/tier_filler
sudo mount -t nfs4 "$SVM_NFS_DNS":/tier_filler /mnt/tier_filler
# about 456 GiB, roughly an hour at 128 MBps; utilization is measured against
# the ~862 GiB usable after ONTAP's overhead, so this lands near 55%
sudo dd if=/dev/urandom of=/mnt/tier_filler/fill.bin bs=1M count=466944 status=progress
```

The filler adds nothing to the bill: SSD is charged on the provisioned size. Once the tier is above 50%, data already past its cooling period is tiered by a background job 24 to 48 hours later. Run `make footprint` again after that window.

To look at the same thing interactively, log in to the ONTAP CLI as `fsxadmin` (password from Secrets Manager):

```bash
aws secretsmanager get-secret-value --secret-id <fsxadmin_secret_arn output> --query SecretString --output text | jq -r .password
ssh fsxadmin@<fsx_management_dns output>
```

```
volume show -vserver svm1 -fields tiering-policy
volume show-footprint -vserver svm1 -volume tier_*
```

`show-footprint` splits each volume between the performance tier (SSD) and the capacity pool. Record it now, again after a day, and again after the two-day cooling period:

| Volume | Expected |
| --- | --- |
| `tier_none` | Stays on SSD. |
| `tier_all` | Moves to the capacity pool almost immediately. |
| `tier_auto` | Stays on SSD until the data has been cold for the cooling period (2 days in this lab), then moves. |
| `tier_snapshot_only` | Active data stays on SSD. Take a snapshot, overwrite the file, and the old blocks held only by the snapshot tier after the cooling period. |

For the snapshot case:

```
volume snapshot create -vserver svm1 -volume tier_snapshot_only -snapshot before-overwrite
```

then rerun the `dd` for `tier_snapshot_only` on the client.

### 4. Turn it into numbers

With the footprints and the SSD and capacity-pool prices for your region, work out what the same data costs under each policy. That table is the practical answer to "which tiering policy should we use?"

## Week 2: Kubernetes, then replication

### 5. EKS and Trident

Set `enable_eks = true` and `eks_public_access_cidrs` in `terraform.tfvars`, then:

```bash
make up && make trident && make backend
kubectl -n trident get tridentbackendconfig fsx-ontap-nas   # PHASE Bound, STATUS Success
make demo
kubectl -n ontap-demo exec deploy/writer -- tail /data/log.txt   # lines from both pods
make snapshot
kubectl -n ontap-demo get volumesnapshot,pvc
```

Each PersistentVolume is its own FSx for ONTAP volume (`ontap-nas` driver). Look at it from the ONTAP side with `volume show -vserver svm1` and `volume snapshot show -vserver svm1`: the Kubernetes snapshot is an ONTAP snapshot, which is what makes restores near-instant.

Next step here: [Trident Protect](https://docs.netapp.com/us-en/trident/trident-protect/trident-protect-requirements.html), NetApp's free Kubernetes backup and DR tool, for application-level backup to S3 and cross-cluster recovery.

### 6. SnapMirror (to build next)

The migration and disaster-recovery exercise: replicate an "on-premises" ONTAP system into FSx for ONTAP and fail over. Two ways to stand in for on-premises:

- **A second FSx for ONTAP file system** in the same VPC as the source. Simplest, no extra accounts, doubles the file system cost while it runs.
- **The ONTAP simulator**, which is closer to a real migration. It needs a NetApp Support Site account (guest accounts cannot download it), ships as a vSphere OVA, and needs a network path into the VPC.

Either way the work is the same: intercluster endpoints on both sides (the lab's security group already allows TCP 11104-11105), cluster and SVM peering, a `DP` volume as the destination, then `snapmirror create`, `initialize`, `update`, and a `break` for failover. Document the network path and the cutover: in real migrations, that is where most of the risk sits.

## Teardown

`make down` deletes the Kubernetes demo (so Trident removes the volumes it created), then destroys everything Terraform built. Check the FSx console afterwards if a destroy was interrupted: volumes Trident created are not in Terraform state.
