# FSx for ONTAP + EKS lab. Run `make help` for the targets.

TF            := terraform -chdir=terraform
TRIDENT_CHART ?= 100.2606.1
out            = $(shell $(TF) output -raw $(1) 2>/dev/null)

.PHONY: help init check up client footprint kubeconfig trident backend demo snapshot k8s-clean down

help: ## Show targets
	@grep -E '^[a-z0-9-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

init: ## terraform init
	$(TF) init

check: ## fmt, validate and offline plan tests (no AWS credentials needed)
	$(TF) fmt -recursive -check
	$(TF) init -backend=false -input=false >/dev/null
	$(TF) validate
	$(TF) test

up: ## Create the lab (reads terraform/terraform.tfvars)
	$(TF) apply

client: ## Open a shell on the client instance through SSM
	aws ssm start-session --region $(call out,region) --target $(call out,client_instance_id)

footprint: ## SSD vs capacity-pool footprint of each tiering volume
	./scripts/footprint.sh

kubeconfig: ## Point kubectl at the lab cluster
	aws eks update-kubeconfig --region $(call out,region) --name $(call out,eks_cluster_name)

trident: kubeconfig ## Install Trident with Helm (supports AL2023 nodes)
	helm repo add netapp-trident https://netapp.github.io/trident-helm-chart --force-update
	helm upgrade --install trident-operator netapp-trident/trident-operator \
	  --version $(TRIDENT_CHART) --namespace trident --create-namespace --wait

backend: ## Register FSx for ONTAP with Trident and create the StorageClass
	@test -n "$(call out,fsx_file_system_id)" || { echo "No lab outputs found: run 'make up' first."; exit 1; }
	sed -e 's|$${SVM_NAME}|$(call out,fsx_svm_name)|' \
	    -e 's|$${FSX_ID}|$(call out,fsx_file_system_id)|' \
	    -e 's|$${AWS_REGION}|$(call out,region)|' \
	    -e 's|$${VSADMIN_SECRET_ARN}|$(call out,vsadmin_secret_arn)|' \
	    k8s/backend-ontap-nas.yaml.tpl | kubectl apply -f -
	kubectl apply -f k8s/storageclass-ontap-nas.yaml
	kubectl -n trident get tridentbackendconfig fsx-ontap-nas

demo: ## Two replicas sharing one ReadWriteMany volume
	kubectl apply -f k8s/demo/app.yaml

snapshot: ## Snapshot the demo volume and restore it into a new claim
	kubectl apply -f k8s/demo/snapshot-restore.yaml

# Trident-created volumes are not in Terraform state. Delete them through
# Kubernetes first, or the file system cannot be destroyed.
k8s-clean: ## Remove demo claims and the backend (run before `down`)
	-kubectl delete namespace ontap-demo --wait=true
	-kubectl -n trident delete tridentbackendconfig fsx-ontap-nas --wait=true

down: ## Tear everything down
	@if [ -n "$(call out,eks_cluster_name)" ]; then $(MAKE) k8s-clean; fi
	$(TF) destroy
