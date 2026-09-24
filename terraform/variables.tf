variable "name" {
  description = "Prefix for every resource in the lab."
  type        = string
  default     = "ontap-lab"
}

variable "region" {
  description = "AWS region. FSx for ONTAP and EKS must both be available in it."
  type        = string
  default     = "ca-central-1"
}

variable "vpc_cidr" {
  description = "CIDR for the lab VPC."
  type        = string
  default     = "10.42.0.0/16"
}

# --- FSx for ONTAP ----------------------------------------------------------

variable "fsx_storage_capacity_gib" {
  description = "SSD tier capacity. 1024 GiB is the minimum for SINGLE_AZ_1."
  type        = number
  default     = 1024
}

variable "fsx_throughput_mbps" {
  description = "Throughput capacity. 128 MBps is the smallest (cheapest) SINGLE_AZ_1 size."
  type        = number
  default     = 128

  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096], var.fsx_throughput_mbps)
    error_message = "SINGLE_AZ_1 throughput must be one of 128, 256, 512, 1024, 2048, 4096."
  }
}

variable "tiering_demo_cooling_days" {
  description = "Cooling period for the AUTO volume. 2 is the minimum, so tiering shows up within a lab week."
  type        = number
  default     = 2

  validation {
    condition     = var.tiering_demo_cooling_days >= 2 && var.tiering_demo_cooling_days <= 183
    error_message = "cooling_period must be between 2 and 183 days."
  }
}

# --- Optional pieces --------------------------------------------------------

variable "enable_client" {
  description = "Small EC2 instance, reachable only through SSM, for NFS mounts and the ONTAP CLI."
  type        = bool
  default     = true
}

variable "enable_eks" {
  description = "EKS cluster for the Trident part of the lab. Off by default: week 1 does not need it."
  type        = bool
  default     = false
}

variable "eks_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS API. Set to your own IP (x.x.x.x/32); there is deliberately no open default."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.enable_eks || length(var.eks_public_access_cidrs) > 0
    error_message = "Set eks_public_access_cidrs (for example your IP as x.x.x.x/32) when enable_eks is true."
  }
}

variable "kubernetes_version" {
  description = "EKS version. Check what is offered: aws eks describe-cluster-versions --region <region>."
  type        = string
  default     = "1.35"
}

# --- Cost guardrail ---------------------------------------------------------

variable "budget_limit_usd" {
  description = "Monthly budget for the account. An alert fires at 50%, 80% and 100% of it."
  type        = number
  default     = 150
}

variable "budget_alert_email" {
  description = "Where budget alerts go. Leave empty to skip creating the budget."
  type        = string
  default     = ""
}
