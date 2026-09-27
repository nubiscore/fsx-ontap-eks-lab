variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  description = "Only this CIDR may reach the file system."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for the SINGLE_AZ_1 file system."
  type        = string
}

variable "storage_capacity_gib" {
  type = number
}

variable "throughput_mbps" {
  type = number
}

variable "cooling_days" {
  type = number
}

variable "filler_gib" {
  description = <<-EOT
    Size of an extra NONE volume, tier_filler, used only to raise SSD tier
    utilization above 50%. Below that threshold FSx for ONTAP does not tier
    AUTO or SNAPSHOT_ONLY volumes at all, whatever their cooling period. 0
    (the default) creates no filler volume.
  EOT
  type        = number
  default     = 0

  validation {
    condition     = var.filler_gib == 0 || (var.filler_gib >= 1 && var.filler_gib <= 100000)
    error_message = "filler_gib must be 0 (disabled) or a size in GiB."
  }
}
