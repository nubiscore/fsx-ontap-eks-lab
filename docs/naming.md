# Product names

NetApp and AWS rename products often. These were checked in September 2026.

| Use this | Not this | Notes | Source |
| --- | --- | --- | --- |
| Amazon FSx for NetApp ONTAP (FSx for ONTAP) | "FSx" alone, "FSxN" in customer-facing copy | "FSx" also covers FSx for Windows File Server, Lustre, and OpenZFS. | [AWS](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/what-is-fsx-ontap.html) |
| NetApp Console | BlueXP | BlueXP was renamed in 2025, along with its services (tiering, replication, disaster recovery, copy and sync). | [NetApp KB](https://kb.netapp.com/Cloud/ncds/nc/ag/ag_kbs/Is_BlueXP__been_replaced_by_NetApp_Console) |
| NetApp Trident | Astra Trident | The CSI driver. EKS add-on name: `netapp_trident-operator`. | [NetApp](https://docs.netapp.com/us-en/trident/trident-use/trident-aws-addon.html) |
| NetApp Trident Protect | Astra Control | Free Kubernetes data protection, migration and DR. | [NetApp](https://docs.netapp.com/us-en/trident/trident-protect/trident-protect-requirements.html) |
| Cloud Volumes ONTAP | | ONTAP running in your own cloud VMs, on AWS, Azure, or Google Cloud. | [NetApp](https://docs.netapp.com/us-en/storage-management-cloud-volumes-ontap/) |
| Azure NetApp Files | | Microsoft's first-party ONTAP-based service. | [Microsoft](https://learn.microsoft.com/azure/azure-netapp-files/) |
| Google Cloud NetApp Volumes | | Google's first-party ONTAP-based service. | [Google Cloud](https://cloud.google.com/netapp/volumes/docs) |
| Amazon Elastic VMware Service (Amazon EVS) | | Integrates with FSx for ONTAP as an NFS or iSCSI datastore. Announced in public preview in June 2025; confirm current availability. | [AWS](https://aws.amazon.com/about-aws/whats-new/2025/06/amazon-elastic-vmware-service-fsx-netapp-ontap) |

## Versions used in this lab

| Component | Version |
| --- | --- |
| Terraform AWS provider | 6.66 |
| terraform-aws-modules/vpc | 6.7 |
| terraform-aws-modules/eks | 21.26 |
| Trident (Helm chart `100.2606.1`) | 26.06.1 |
