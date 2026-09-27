data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# --- Network ----------------------------------------------------------------
# Two AZs because EKS requires subnets in at least two. FSx for ONTAP is
# SINGLE_AZ_1 in the first private subnet. One NAT gateway keeps cost down.

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [cidrsubnet(var.vpc_cidr, 4, 0), cidrsubnet(var.vpc_cidr, 4, 1)]
  public_subnets  = [cidrsubnet(var.vpc_cidr, 8, 64), cidrsubnet(var.vpc_cidr, 8, 65)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# --- FSx for ONTAP ----------------------------------------------------------

module "fsx" {
  source = "./modules/fsx-ontap"

  name                 = var.name
  vpc_id               = module.vpc.vpc_id
  vpc_cidr             = module.vpc.vpc_cidr_block
  subnet_id            = module.vpc.private_subnets[0]
  storage_capacity_gib = var.fsx_storage_capacity_gib
  throughput_mbps      = var.fsx_throughput_mbps
  cooling_days         = var.tiering_demo_cooling_days
  filler_gib           = var.tiering_filler_gib
}

# --- Client instance --------------------------------------------------------
# No SSH key, no public IP: reach it with `aws ssm start-session`. From it you
# mount the lab volumes over NFS and log in to the ONTAP CLI as fsxadmin.

data "aws_ssm_parameter" "al2023" {
  count = var.enable_client ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_iam_role" "client" {
  count = var.enable_client ? 1 : 0
  name  = "${var.name}-client"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "client_ssm" {
  count      = var.enable_client ? 1 : 0
  role       = aws_iam_role.client[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "client_fsxadmin_secret" {
  count = var.enable_client ? 1 : 0
  name  = "read-fsxadmin-secret"
  role  = aws_iam_role.client[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = "secretsmanager:GetSecretValue", Resource = module.fsx.fsxadmin_secret_arn },
      { Effect = "Allow", Action = "kms:Decrypt", Resource = module.fsx.kms_key_arn },
    ]
  })
}

resource "aws_iam_instance_profile" "client" {
  count = var.enable_client ? 1 : 0
  name  = "${var.name}-client"
  role  = aws_iam_role.client[0].name
}

resource "aws_security_group" "client" {
  count       = var.enable_client ? 1 : 0
  name_prefix = "${var.name}-client-"
  description = "Lab client: outbound only (SSM, package installs, FSx)"
  vpc_id      = module.vpc.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "client" {
  count             = var.enable_client ? 1 : 0
  security_group_id = aws_security_group.client[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "client" {
  count                  = var.enable_client ? 1 : 0
  ami                    = data.aws_ssm_parameter.al2023[0].value
  instance_type          = "t3.micro"
  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [aws_security_group.client[0].id]
  iam_instance_profile   = aws_iam_instance_profile.client[0].name

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    encrypted = true
  }

  user_data = <<-EOT
    #!/bin/bash
    dnf install -y nfs-utils jq
    for v in tier_none tier_snapshot_only tier_auto tier_all; do mkdir -p /mnt/$v; done
  EOT

  tags = { Name = "${var.name}-client" }
}

# --- EKS (optional) ---------------------------------------------------------
# AL2023 nodes; Trident is installed with Helm (see Makefile), which supports
# AL2023. The pod identity agent lets the trident-controller service account
# assume the role below without static credentials.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.26"
  count   = var.enable_eks ? 1 : 0

  name               = "${var.name}-eks"
  kubernetes_version = var.kubernetes_version

  endpoint_public_access                   = true
  endpoint_public_access_cidrs             = var.eks_public_access_cidrs
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  addons = {
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    coredns                = {}
    snapshot-controller    = {}
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.large"]
      min_size       = 1
      max_size       = 2
      desired_size   = 2
    }
  }
}

# Permissions from NetApp's Trident documentation for FSx for ONTAP, plus
# kms:Decrypt because the vsadmin secret is encrypted with the lab's own key.
resource "aws_iam_role" "trident" {
  count = var.enable_eks ? 1 : 0
  name  = "${var.name}-trident"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "trident" {
  count = var.enable_eks ? 1 : 0
  name  = "trident-fsx-ontap"
  role  = aws_iam_role.trident[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "fsx:DescribeFileSystems",
          "fsx:DescribeVolumes",
          "fsx:CreateVolume",
          "fsx:RestoreVolumeFromSnapshot",
          "fsx:DescribeStorageVirtualMachines",
          "fsx:UntagResource",
          "fsx:UpdateVolume",
          "fsx:TagResource",
          "fsx:DeleteVolume",
        ]
        Resource = "*"
      },
      { Effect = "Allow", Action = "secretsmanager:GetSecretValue", Resource = module.fsx.vsadmin_secret_arn },
      { Effect = "Allow", Action = "kms:Decrypt", Resource = module.fsx.kms_key_arn },
    ]
  })
}

resource "aws_eks_pod_identity_association" "trident" {
  count           = var.enable_eks ? 1 : 0
  cluster_name    = module.eks[0].cluster_name
  namespace       = "trident"
  service_account = "trident-controller"
  role_arn        = aws_iam_role.trident[0].arn
}

# --- Cost guardrail ---------------------------------------------------------

resource "aws_budgets_budget" "lab" {
  count        = var.budget_alert_email == "" ? 0 : 1
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = [
      { threshold = 50, type = "ACTUAL" },
      { threshold = 80, type = "ACTUAL" },
      { threshold = 100, type = "FORECASTED" },
    ]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.type
      subscriber_email_addresses = [var.budget_alert_email]
    }
  }
}
