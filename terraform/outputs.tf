output "region" {
  value = var.region
}

output "fsx_file_system_id" {
  value = module.fsx.file_system_id
}

output "fsx_svm_name" {
  value = module.fsx.svm_name
}

output "fsx_management_dns" {
  description = "ssh fsxadmin@<this> from the client instance for the ONTAP CLI."
  value       = module.fsx.management_dns
}

output "fsx_nfs_dns" {
  description = "NFS endpoint of the SVM. Mount the lab volumes from here."
  value       = module.fsx.svm_nfs_dns
}

output "fsx_volumes" {
  value = module.fsx.volumes
}

output "fsxadmin_secret_arn" {
  value = module.fsx.fsxadmin_secret_arn
}

output "vsadmin_secret_arn" {
  description = "Referenced by the Trident backend (k8s/backend-ontap-nas.yaml.tpl)."
  value       = module.fsx.vsadmin_secret_arn
}

output "client_instance_id" {
  description = "aws ssm start-session --target <this>"
  value       = var.enable_client ? aws_instance.client[0].id : null
}

output "eks_cluster_name" {
  value = var.enable_eks ? module.eks[0].cluster_name : null
}
