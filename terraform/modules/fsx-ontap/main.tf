terraform {
  required_providers {
    aws    = { source = "hashicorp/aws" }
    random = { source = "hashicorp/random" }
  }
}

# --- Encryption -------------------------------------------------------------

resource "aws_kms_key" "fsx" {
  description             = "${var.name} FSx for ONTAP encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "fsx" {
  name          = "alias/${var.name}-fsx"
  target_key_id = aws_kms_key.fsx.key_id
}

# --- Network access ---------------------------------------------------------
# Only the VPC can reach the file system. Ports follow the FSx for ONTAP
# guide: management (SSH, HTTPS/ONTAP REST), NFS, iSCSI, and SnapMirror
# intercluster replication for the week 2 exercise.

resource "aws_security_group" "fsx" {
  name_prefix = "${var.name}-fsx-"
  description = "FSx for ONTAP endpoints, reachable from the lab VPC only"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  ingress = {
    ssh_ontap_cli  = { protocol = "tcp", from = 22, to = 22 }
    rpcbind_tcp    = { protocol = "tcp", from = 111, to = 111 }
    rpcbind_udp    = { protocol = "udp", from = 111, to = 111 }
    ontap_rest     = { protocol = "tcp", from = 443, to = 443 }
    nfs_mount_tcp  = { protocol = "tcp", from = 635, to = 635 }
    nfs_mount_udp  = { protocol = "udp", from = 635, to = 635 }
    nfs_tcp        = { protocol = "tcp", from = 2049, to = 2049 }
    nfs_udp        = { protocol = "udp", from = 2049, to = 2049 }
    iscsi          = { protocol = "tcp", from = 3260, to = 3260 }
    nfs_lock_tcp   = { protocol = "tcp", from = 4045, to = 4046 }
    nfs_lock_udp   = { protocol = "udp", from = 4045, to = 4046 }
    snapmirror     = { protocol = "tcp", from = 11104, to = 11105 }
    icmp_reachable = { protocol = "icmp", from = -1, to = -1 }
  }
}

resource "aws_vpc_security_group_ingress_rule" "fsx" {
  for_each = local.ingress

  security_group_id = aws_security_group.fsx.id
  description       = each.key
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = each.value.protocol
  from_port         = each.value.from
  to_port           = each.value.to
}

resource "aws_vpc_security_group_egress_rule" "fsx" {
  security_group_id = aws_security_group.fsx.id
  description       = "Replies and SnapMirror to peers inside the VPC"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
}

# --- Credentials ------------------------------------------------------------
# fsxadmin is the cluster administrator; vsadmin administers the SVM. Trident
# only ever gets vsadmin, read from Secrets Manager, never fsxadmin.

resource "random_password" "fsxadmin" {
  length           = 24
  special          = true
  override_special = "_-"
}

resource "random_password" "vsadmin" {
  length           = 24
  special          = true
  override_special = "_-"
}

resource "aws_secretsmanager_secret" "fsxadmin" {
  name_prefix             = "${var.name}-fsxadmin-"
  description             = "FSx for ONTAP cluster admin (fsxadmin)"
  kms_key_id              = aws_kms_key.fsx.arn
  recovery_window_in_days = 0 # lab: allow immediate re-create after destroy
}

resource "aws_secretsmanager_secret_version" "fsxadmin" {
  secret_id     = aws_secretsmanager_secret.fsxadmin.id
  secret_string = jsonencode({ username = "fsxadmin", password = random_password.fsxadmin.result })
}

resource "aws_secretsmanager_secret" "vsadmin" {
  name_prefix             = "${var.name}-vsadmin-"
  description             = "SVM admin (vsadmin), used by Trident"
  kms_key_id              = aws_kms_key.fsx.arn
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "vsadmin" {
  secret_id     = aws_secretsmanager_secret.vsadmin.id
  secret_string = jsonencode({ username = "vsadmin", password = random_password.vsadmin.result })
}

# --- File system and SVM ----------------------------------------------------

resource "aws_fsx_ontap_file_system" "this" {
  deployment_type     = "SINGLE_AZ_1"
  storage_capacity    = var.storage_capacity_gib
  throughput_capacity = var.throughput_mbps
  subnet_ids          = [var.subnet_id]
  preferred_subnet_id = var.subnet_id
  security_group_ids  = [aws_security_group.fsx.id]
  kms_key_id          = aws_kms_key.fsx.arn
  fsx_admin_password  = random_password.fsxadmin.result

  # Lab: no automatic backups, so teardown is clean and nothing lingers.
  automatic_backup_retention_days = 0

  tags = { Name = "${var.name}-fsx" }
}

resource "aws_fsx_ontap_storage_virtual_machine" "this" {
  file_system_id             = aws_fsx_ontap_file_system.this.id
  name                       = "svm1"
  root_volume_security_style = "UNIX"
  svm_admin_password         = random_password.vsadmin.result
}

# --- One volume per tiering policy ------------------------------------------
# Write the same data set to each and compare where it lands with
# `volume show-footprint` on the ONTAP CLI (see docs/lab-plan.md).

locals {
  tiering_volumes = {
    tier_none          = { policy = "NONE", cooling = null }
    tier_snapshot_only = { policy = "SNAPSHOT_ONLY", cooling = var.cooling_days }
    tier_auto          = { policy = "AUTO", cooling = var.cooling_days }
    tier_all           = { policy = "ALL", cooling = null }
  }
}

resource "aws_fsx_ontap_volume" "tiering" {
  for_each = local.tiering_volumes

  name                       = each.key
  junction_path              = "/${each.key}"
  size_in_megabytes          = 10240
  storage_virtual_machine_id = aws_fsx_ontap_storage_virtual_machine.this.id
  storage_efficiency_enabled = true
  security_style             = "UNIX"
  skip_final_backup          = true

  tiering_policy {
    name           = each.value.policy
    cooling_period = each.value.cooling
  }
}

output "file_system_id" {
  value = aws_fsx_ontap_file_system.this.id
}

output "svm_name" {
  value = aws_fsx_ontap_storage_virtual_machine.this.name
}

output "management_dns" {
  description = "File system management endpoint (fsxadmin, ONTAP CLI over SSH)."
  value       = aws_fsx_ontap_file_system.this.endpoints[0].management[0].dns_name
}

output "svm_nfs_dns" {
  value = aws_fsx_ontap_storage_virtual_machine.this.endpoints[0].nfs[0].dns_name
}

output "security_group_id" {
  value = aws_security_group.fsx.id
}

output "fsxadmin_secret_arn" {
  value = aws_secretsmanager_secret.fsxadmin.arn
}

output "vsadmin_secret_arn" {
  value = aws_secretsmanager_secret.vsadmin.arn
}

output "kms_key_arn" {
  value = aws_kms_key.fsx.arn
}

# --- Filler volume (round 2 of the tiering experiment) -----------------------
# AUTO and SNAPSHOT_ONLY only tier once the SSD tier is above 50% utilization
# (see docs/results/2026-09-tiering.md). Four 10 GiB volumes on a 1024 GiB tier
# sit at about 1%, so this NONE volume exists purely to be filled with random
# data until the tier crosses the threshold. Storage efficiency is off: random
# data does not compress and the point is to consume SSD.

resource "aws_fsx_ontap_volume" "filler" {
  count = var.filler_gib > 0 ? 1 : 0

  name                       = "tier_filler"
  junction_path              = "/tier_filler"
  size_in_megabytes          = var.filler_gib * 1024
  storage_virtual_machine_id = aws_fsx_ontap_storage_virtual_machine.this.id
  storage_efficiency_enabled = false
  security_style             = "UNIX"
  skip_final_backup          = true

  tiering_policy {
    name = "NONE"
  }
}

output "volumes" {
  value = merge(
    { for k, v in aws_fsx_ontap_volume.tiering : k => { id = v.id, junction_path = v.junction_path, tiering = v.tiering_policy[0].name } },
    { for v in aws_fsx_ontap_volume.filler : "tier_filler" => { id = v.id, junction_path = v.junction_path, tiering = v.tiering_policy[0].name } },
  )
}
