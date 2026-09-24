# Offline plan tests: the AWS provider is mocked, so no credentials or cost.

# terraform test also loads a local terraform.tfvars. Pin every input it could
# set, so the tests mean the same thing on a laptop with a live lab and in CI.
variables {
  region                  = "ca-central-1"
  enable_client           = true
  enable_eks              = false
  eks_public_access_cidrs = []
  budget_alert_email      = ""
  budget_limit_usd        = 150
}

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["ca-central-1a", "ca-central-1b"] }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_iam_session_context" {
    defaults = { issuer_arn = "arn:aws:iam::123456789012:role/lab-admin" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:user/test" }
  }
}

run "week1_defaults_plan_fsx_without_eks" {
  command = plan

  assert {
    condition     = length(module.eks) == 0
    error_message = "EKS must be off by default."
  }
  assert {
    condition     = length(module.fsx.volumes) == 4
    error_message = "Expected one volume per tiering policy."
  }
  assert {
    condition     = length(aws_budgets_budget.lab) == 0
    error_message = "No budget without an alert email."
  }
}

run "eks_requires_locked_down_api_access" {
  command = plan

  variables {
    enable_eks = true
  }

  expect_failures = [var.eks_public_access_cidrs]
}

run "eks_plans_with_trident_identity" {
  command = plan

  variables {
    enable_eks              = true
    eks_public_access_cidrs = ["203.0.113.10/32"]
    budget_alert_email      = "lab@example.com"
  }

  assert {
    condition     = aws_eks_pod_identity_association.trident[0].service_account == "trident-controller" && aws_eks_pod_identity_association.trident[0].namespace == "trident"
    error_message = "Trident's pod identity must bind trident/trident-controller."
  }
  assert {
    condition     = length(aws_budgets_budget.lab) == 1
    error_message = "Budget expected when an alert email is set."
  }
}

run "rejects_invalid_throughput" {
  command = plan

  variables {
    fsx_throughput_mbps = 100
  }

  expect_failures = [var.fsx_throughput_mbps]
}
