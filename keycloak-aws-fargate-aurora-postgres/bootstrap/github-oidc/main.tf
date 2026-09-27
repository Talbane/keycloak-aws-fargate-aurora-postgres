provider "aws" {
  region  = var.aws_region
  profile = "saml"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  name            = substr(replace(lower("${var.name_prefix}-${var.environment}"), "/[^a-z0-9-]/", "-"), 0, 24)
  account_id      = data.aws_caller_identity.current.account_id
  partition       = data.aws_partition.current.partition
  alb_logs_bucket = substr("${local.name}-alb-logs-${local.account_id}-${var.aws_region}", 0, 63)
  ecr_repo_name   = "${var.name_prefix}/${var.environment}/keycloak"

  github_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_github_oidc_provider_arn
}

# If your account already has this provider, reuse it instead of trying to create a duplicate.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

check "github_provider" {
  assert {
    condition     = var.create_github_oidc_provider || var.existing_github_oidc_provider_arn != null
    error_message = "Set existing_github_oidc_provider_arn or create_github_oidc_provider=true."
  }
}

data "aws_iam_policy_document" "github_deploy_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.github_deploy_oidc_subjects
    }
  }
}

data "aws_iam_policy_document" "github_plan_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.github_plan_oidc_subjects
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name                 = "${local.name}-github-deploy"
  assume_role_policy   = data.aws_iam_policy_document.github_deploy_assume.json
  permissions_boundary = var.permissions_boundary_arn

  max_session_duration = 3600
}

resource "aws_iam_role" "github_plan" {
  name                 = "${local.name}-github-plan"
  assume_role_policy   = data.aws_iam_policy_document.github_plan_assume.json
  permissions_boundary = var.permissions_boundary_arn

  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_plan" {
  # Read-only plan role: no resource mutations, no GetSecretValue, and no state writes.
  statement {
    sid    = "ReadAwsControlPlaneForTerraformPlan"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "elasticloadbalancing:Describe*",
      "ecs:Describe*",
      "ecs:List*",
      "ecr:Describe*",
      "ecr:List*",
      "ecr:GetLifecyclePolicy",
      "rds:Describe*",
      "rds:ListTagsForResource",
      "logs:Describe*",
      "logs:ListTagsForResource",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListTagsForResource",
      "application-autoscaling:Describe*",
      "application-autoscaling:ListTagsForResource",
      "wafv2:Get*",
      "wafv2:List*"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ReadOnlyKeycloakIamRoles"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:ListRoleTags"
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/${local.name}-*"]
  }

  statement {
    sid    = "ReadSecretMetadataOnly"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
      "secretsmanager:GetResourcePolicy"
    ]
    resources = concat(
      compact([
        "arn:${local.partition}:secretsmanager:${var.aws_region}:${local.account_id}:secret:${local.name}/bootstrap-admin-*",
        "arn:${local.partition}:secretsmanager:${var.aws_region}:${local.account_id}:secret:rds!db-*",
        "arn:${local.partition}:secretsmanager:${var.aws_region}:${local.account_id}:secret:rds!cluster-*",
        var.bootstrap_secret_arn_for_value_write
      ]),
      var.database_secret_arns_for_metadata_read
    )
  }

  statement {
    sid       = "ReadTerraformStateObject"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:${local.partition}:s3:::${var.terraform_state_bucket}/${var.terraform_state_key}"]
  }

  statement {
    sid       = "ListTerraformStatePrefix"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:${local.partition}:s3:::${var.terraform_state_bucket}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.terraform_state_key]
    }
  }

  statement {
    sid     = "ReadManagedS3BucketMetadata"
    effect  = "Allow"
    actions = ["s3:GetBucket*"]
    resources = [
      "arn:${local.partition}:s3:::${var.terraform_state_bucket}",
      "arn:${local.partition}:s3:::${local.alb_logs_bucket}"
    ]
  }

  dynamic "statement" {
    for_each = var.terraform_state_kms_key_arn != null ? [1] : []
    content {
      sid       = "DecryptTerraformStateOnly"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:DescribeKey"]
      resources = [var.terraform_state_kms_key_arn]
    }
  }

  statement {
    sid    = "ReadSecretRedeployLambdaAndRule"
    effect = "Allow"
    actions = [
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:GetPolicy",
      "lambda:ListTags",
      "lambda:ListVersionsByFunction",
      "lambda:GetFunctionCodeSigningConfig",
      "events:DescribeRule",
      "events:ListTargetsByRule",
      "events:ListTagsForResource"
    ]
    resources = [
      "arn:${local.partition}:lambda:${var.aws_region}:${local.account_id}:function:${local.name}-secret-redeploy",
      "arn:${local.partition}:events:${var.aws_region}:${local.account_id}:rule/${local.name}-db-secret-current"
    ]
  }

  statement {
    sid    = "ReadAlbLogBucketExtendedMetadata"
    effect = "Allow"
    actions = [
      "s3:GetAccelerateConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetEncryptionConfiguration",
      "s3:GetReplicationConfiguration"
    ]
    resources = [
      "arn:${local.partition}:s3:::${local.alb_logs_bucket}"
    ]
  }
}

resource "aws_iam_role_policy" "github_plan" {
  name   = "${local.name}-terraform-plan"
  role   = aws_iam_role.github_plan.id
  policy = data.aws_iam_policy_document.github_plan.json
}

data "aws_iam_policy_document" "github_deploy" {
  # Read/list operations Terraform needs to refresh state. Many AWS Describe/List APIs
  # do not support resource-level scoping, hence Resource="*" is unavoidable here.
  statement {
    sid    = "ReadControlPlaneState"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "elasticloadbalancing:Describe*",
      "ecs:Describe*",
      "ecs:List*",
      "ecr:Describe*",
      "ecr:List*",
      "rds:Describe*",
      "rds:ListTagsForResource",
      "logs:Describe*",
      "logs:ListTagsForResource",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListTagsForResource",
      "application-autoscaling:Describe*",
      "application-autoscaling:ListTagsForResource",
      "wafv2:Get*",
      "wafv2:List*"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ReadOnlyKeycloakIamRoles"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:ListRoleTags"
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/${local.name}-*"]
  }

  statement {
    sid    = "ReadBootstrapSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
      "secretsmanager:GetResourcePolicy"
    ]
    resources = compact(["arn:${local.partition}:secretsmanager:${var.aws_region}:${local.account_id}:secret:${local.name}/bootstrap-admin-*", var.bootstrap_secret_arn_for_value_write])
  }

  statement {
    sid    = "ReadDatabaseSecretMetadataOnly"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetResourcePolicy"
    ]
    resources = concat(
      [
        "arn:${local.partition}:secretsmanager:${var.aws_region}:${local.account_id}:secret:rds!db-*",
        "arn:${local.partition}:secretsmanager:${var.aws_region}:${local.account_id}:secret:rds!cluster-*"
      ],
      var.database_secret_arns_for_metadata_read
    )
  }

  statement {
    sid     = "ReadTerraformAndAlbLogBuckets"
    effect  = "Allow"
    actions = ["s3:GetBucket*"]
    resources = [
      "arn:${local.partition}:s3:::${var.terraform_state_bucket}",
      "arn:${local.partition}:s3:::${local.alb_logs_bucket}"
    ]
  }

  statement {
    sid    = "TerraformStateObject"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = [
      "arn:${local.partition}:s3:::${var.terraform_state_bucket}/${var.terraform_state_key}"
    ]
  }

  statement {
    sid    = "TerraformStateLock"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "arn:${local.partition}:s3:::${var.terraform_state_bucket}/${var.terraform_state_key}.tflock"
    ]
  }

  statement {
    sid       = "TerraformStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:${local.partition}:s3:::${var.terraform_state_bucket}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.terraform_state_key, "${var.terraform_state_key}.tflock"]
    }
  }

  dynamic "statement" {
    for_each = var.terraform_state_kms_key_arn != null ? [1] : []
    content {
      sid       = "TerraformStateKms"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
      resources = [var.terraform_state_kms_key_arn]
    }
  }

  statement {
    sid    = "ManageKeycloakEcrAndPushImages"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository",
      "ecr:DeleteRepository",
      "ecr:TagResource",
      "ecr:UntagResource",
      "ecr:PutLifecyclePolicy",
      "ecr:GetLifecyclePolicy",
      "ecr:DeleteLifecyclePolicy",
      "ecr:PutImageScanningConfiguration",
      "ecr:PutImageTagMutability",
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]
    resources = ["arn:${local.partition}:ecr:${var.aws_region}:${local.account_id}:repository/${local.ecr_repo_name}"]
  }

  statement {
    sid       = "EcrAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ManageKeycloakIamRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy"
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/${local.name}-ecs-exec",
      "arn:${local.partition}:iam::${local.account_id}:role/${local.name}-ecs-task",
      "arn:${local.partition}:iam::${local.account_id}:role/${local.name}-secret-redeploy"
    ]
  }

  statement {
    sid       = "PassOnlyKeycloakRuntimeRolesToEcs"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/${local.name}-ecs-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "PassOnlySecretRedeployRoleToLambda"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/${local.name}-secret-redeploy"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  # EC2 SG and endpoint APIs contain create/delete/authorize operations that frequently
  # require Resource="*". The action set is intentionally limited to the VPC network
  # constructs used by this stack; it does not grant instance, route, subnet or IGW creation.
  statement {
    sid    = "ManageKeycloakNetworkControls"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:CreateVpcEndpoint",
      "ec2:ModifyVpcEndpoint",
      "ec2:DeleteVpcEndpoints"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageKeycloakAlb"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:SetWebACL"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageKeycloakEcs"
    effect = "Allow"
    actions = [
      "ecs:CreateCluster",
      "ecs:DeleteCluster",
      "ecs:PutClusterCapacityProviders",
      "ecs:UpdateClusterSettings",
      "ecs:TagResource",
      "ecs:UntagResource",
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:CreateService",
      "ecs:UpdateService",
      "ecs:DeleteService"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DescribeKmsKeysForAwsManagedAndConfiguredEncryption"
    effect    = "Allow"
    actions   = ["kms:DescribeKey"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.deployment_kms_key_arns) > 0 ? [1] : []
    content {
      sid    = "UseOnlyConfiguredCustomerKmsKeys"
      effect = "Allow"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ]
      resources = var.deployment_kms_key_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.deployment_kms_key_arns) > 0 ? [1] : []
    content {
      sid       = "CreateAwsResourceGrantsOnlyOnConfiguredKeys"
      effect    = "Allow"
      actions   = ["kms:CreateGrant"]
      resources = var.deployment_kms_key_arns

      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
    }
  }

  statement {
    sid    = "ManageKeycloakRds"
    effect = "Allow"
    actions = [
      "rds:CreateDBSubnetGroup",
      "rds:ModifyDBSubnetGroup",
      "rds:DeleteDBSubnetGroup",
      "rds:CreateDBParameterGroup",
      "rds:ModifyDBParameterGroup",
      "rds:DeleteDBParameterGroup",
      "rds:ResetDBParameterGroup",
      "rds:CreateDBClusterParameterGroup",
      "rds:ModifyDBClusterParameterGroup",
      "rds:DeleteDBClusterParameterGroup",
      "rds:ResetDBClusterParameterGroup",
      "rds:CreateDBCluster",
      "rds:ModifyDBCluster",
      "rds:DeleteDBCluster",
      "rds:AddTagsToResource",
      "rds:RemoveTagsFromResource",
      "rds:CreateDBInstance",
      "rds:ModifyDBInstance",
      "rds:DeleteDBInstance"
    ]
    resources = ["*"]
  }

  # RDS needs the caller to permit creation/tagging of its service-managed master
  # secret when manage_master_user_password=true. Constrain creation to RDS's name prefix.
  statement {
    sid       = "CreateOnlyRdsManagedMasterSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:CreateSecret"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "secretsmanager:Name"
      values   = ["rds!db-*", "rds!cluster-*"]
    }
  }

  statement {
    sid       = "TagOnlyRdsManagedMasterSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:TagResource"]
    resources = [
      "arn:${local.partition}:secretsmanager:${var.aws_region}:${local.account_id}:secret:rds!db-*",
      "arn:${local.partition}:secretsmanager:${var.aws_region}:${local.account_id}:secret:rds!cluster-*"
    ]
  }

  # CreateSecret is one of the Secrets Manager actions that cannot be scoped to a
  # not-yet-existing secret ARN. Limit it by the exact secret name instead.
  statement {
    sid       = "CreateOnlyNamedBootstrapSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:CreateSecret"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "secretsmanager:Name"
      values   = ["${local.name}/bootstrap-admin"]
    }
  }

  statement {
    sid    = "ManageExistingBootstrapSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:DeleteSecret",
      "secretsmanager:RestoreSecret",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
      "secretsmanager:UpdateSecret",
      "secretsmanager:PutSecretValue"
    ]
    resources = compact(["arn:${local.partition}:secretsmanager:${var.aws_region}:${local.account_id}:secret:${local.name}/bootstrap-admin-*", var.bootstrap_secret_arn_for_value_write])
  }

  statement {
    sid    = "ManageKeycloakLogsAndAlarms"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:AssociateKmsKey",
      "logs:DisassociateKmsKey",
      "logs:TagResource",
      "logs:UntagResource",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageSecretRotationRedeployHook"
    effect = "Allow"
    actions = [
      "lambda:CreateFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:DeleteFunction",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:GetPolicy",
      "lambda:ListTags",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:GetFunctionCodeSigningConfig",
      "events:PutRule",
      "events:DeleteRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:DescribeRule",
      "events:ListTargetsByRule",
      "events:ListTagsForResource",
      "events:TagResource",
      "events:UntagResource",
      "lambda:ListVersionsByFunction"
    ]
    resources = [
      "arn:${local.partition}:lambda:${var.aws_region}:${local.account_id}:function:${local.name}-secret-redeploy",
      "arn:${local.partition}:events:${var.aws_region}:${local.account_id}:rule/${local.name}-db-secret-current"
    ]
  }

  statement {
    sid    = "ManageKeycloakAutoscaling"
    effect = "Allow"
    actions = [
      "application-autoscaling:RegisterScalableTarget",
      "application-autoscaling:DeregisterScalableTarget",
      "application-autoscaling:PutScalingPolicy",
      "application-autoscaling:DeleteScalingPolicy",
      "application-autoscaling:TagResource",
      "application-autoscaling:UntagResource"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageKeycloakWaf"
    effect = "Allow"
    actions = [
      "wafv2:CreateWebACL",
      "wafv2:UpdateWebACL",
      "wafv2:DeleteWebACL",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "wafv2:TagResource",
      "wafv2:UntagResource"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageAlbAccessLogBucket"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:ListBucket",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketOwnershipControls",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:GetBucketTagging",
      "s3:PutBucketTagging"
    ]
    resources = [
      "arn:${local.partition}:s3:::${local.alb_logs_bucket}",
      "arn:${local.partition}:s3:::${local.alb_logs_bucket}/*"
    ]
  }

  statement {
    sid    = "ReadAlbLogBucketExtendedMetadata"
    effect = "Allow"
    actions = [
      "s3:GetAccelerateConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetEncryptionConfiguration",
      "s3:GetReplicationConfiguration"
    ]
    resources = [
      "arn:${local.partition}:s3:::${local.alb_logs_bucket}"
    ]
  }

}


resource "aws_iam_role_policy" "github_deploy" {
  name   = "${local.name}-terraform-deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
