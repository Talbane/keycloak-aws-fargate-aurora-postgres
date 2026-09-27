output "github_deploy_role_arn" {
  value       = aws_iam_role.github_deploy.arn
  description = "Store this ARN as AWS_DEPLOY_ROLE_ARN in the protected GitHub Environment."
}

output "github_oidc_provider_arn" {
  value = local.github_provider_arn
}

output "github_plan_role_arn" {
  description = "Read-only role ARN for pull-request Terraform plans."
  value       = aws_iam_role.github_plan.arn
}
