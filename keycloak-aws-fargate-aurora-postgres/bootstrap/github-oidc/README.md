# GitHub OIDC bootstrap

Run this small stack once from an authorized administrative workstation or your enterprise IAM pipeline. It creates two GitHub roles used by the main workflow: a read-only Terraform plan role and a separate deployment role. It does **not** use long-lived AWS access keys in GitHub.

The trust policy requires exact GitHub OIDC `sub` values plus audience `sts.amazonaws.com`. Because the main workflow uses GitHub Environments, the subject should normally identify the environment rather than a branch. GitHub introduced immutable owner/repository IDs in OIDC subjects for newly created/opted-in repositories in July 2026, so copy the exact subject format used by your repository instead of assuming the legacy `ORG/REPO` form.

The plan role can only read state/control-plane metadata and never gets `GetSecretValue` or infrastructure mutation permissions. The deployment policy is action-scoped to the AWS services/resources the Terraform stack manages. Some AWS create/describe APIs (notably EC2 security-group/VPC-endpoint operations, ECS task-definition registration, and several ELB/RDS control-plane actions) do not allow useful resource-level restriction at creation time, so those statements necessarily use `Resource="*"` while keeping the permitted **actions** narrow. Apply your enterprise permissions boundary/SCPs as an additional guardrail where available.


## Enterprise prerequisites

The deploy role intentionally does not grant `iam:CreateServiceLinkedRole`. If the account has never used ECS, Elastic Load Balancing, or Application Auto Scaling, have the platform/IAM team pre-create the AWS service-linked roles those services require. This keeps the GitHub deployment principal from having a generic service-linked-role creation permission.

If the main stack uses an existing bootstrap secret whose name is outside the Terraform-managed `${name_prefix}-${environment}/bootstrap-admin` pattern, set `bootstrap_secret_arn_for_value_write` to that exact ARN.
