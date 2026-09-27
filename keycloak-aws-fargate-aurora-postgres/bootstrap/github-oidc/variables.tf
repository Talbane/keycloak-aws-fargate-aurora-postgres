variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "keycloak"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "github_deploy_oidc_subjects" {
  description = "Exact GitHub OIDC sub claims allowed to assume the deployment role. Normally only the protected production environment subject."
  type        = list(string)

  validation {
    condition     = length(var.github_deploy_oidc_subjects) > 0 && alltrue([for s in var.github_deploy_oidc_subjects : startswith(s, "repo:") && !strcontains(s, "*") && !strcontains(s, "?")])
    error_message = "Provide at least one exact GitHub OIDC subject beginning with repo: and containing no wildcard characters."
  }
}

variable "github_plan_oidc_subjects" {
  description = "Exact GitHub OIDC sub claims allowed to assume the read-only Terraform plan role. Normally only the protected plan environment subject."
  type        = list(string)

  validation {
    condition     = length(var.github_plan_oidc_subjects) > 0 && alltrue([for s in var.github_plan_oidc_subjects : startswith(s, "repo:") && !strcontains(s, "*") && !strcontains(s, "?")])
    error_message = "Provide at least one exact GitHub plan OIDC subject beginning with repo: and containing no wildcard characters."
  }
}

variable "create_github_oidc_provider" {
  description = "Create the account-level GitHub OIDC provider. Set false if your AWS account already has it."
  type        = bool
  default     = false
}

variable "existing_github_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN when create_github_oidc_provider=false."
  type        = string
  default     = null
}

variable "terraform_state_bucket" {
  description = "Existing S3 bucket that stores the main stack Terraform state."
  type        = string
}

variable "terraform_state_key" {
  description = "Exact main-stack state object key."
  type        = string
}

variable "terraform_state_kms_key_arn" {
  description = "Optional KMS key ARN protecting the Terraform state object."
  type        = string
  default     = null
}

variable "permissions_boundary_arn" {
  description = "Optional enterprise permissions boundary for the GitHub deployment role."
  type        = string
  default     = null
}

variable "bootstrap_secret_arn_for_value_write" {
  description = "Optional exact existing bootstrap secret ARN when the main stack uses bootstrap_secret_arn instead of creating <name>/bootstrap-admin. Grants the deploy role metadata/value-write access only to this secret."
  type        = string
  default     = null
}

variable "database_secret_arns_for_metadata_read" {
  description = "Optional exact DBA-managed database secret ARNs the deployment role may Describe when database secret change redeploy is enabled. Managed RDS instance secrets are covered by rds!db-* and managed DB-cluster/Aurora secrets by rds!cluster-* metadata-only patterns."
  type        = list(string)
  default     = []
}

variable "deployment_kms_key_arns" {
  description = "Exact customer-managed KMS key ARNs used by the main stack (Aurora/RDS storage, managed DB master secret, CloudWatch Logs, Performance Insights). Leave empty when using AWS-managed keys."
  type        = list(string)
  default     = []
}
