# Rendered by `make backend` from Terraform outputs. Trident reads the SVM's
# management endpoint from AWS (fsxFilesystemID) and the vsadmin credentials
# from Secrets Manager, using the pod identity set up in terraform/main.tf.
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: fsx-ontap-nas
  namespace: trident
spec:
  version: 1
  storageDriverName: ontap-nas
  backendName: fsx-ontap-nas
  svm: ${SVM_NAME}
  aws:
    fsxFilesystemID: ${FSX_ID}
    apiRegion: ${AWS_REGION}
  credentials:
    name: "${VSADMIN_SECRET_ARN}"
    type: awsarn
