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
