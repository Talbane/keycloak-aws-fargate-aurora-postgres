data "aws_secretsmanager_secret" "database" {
  count = var.enable_db_secret_change_redeploy ? 1 : 0
  arn   = local.db_secret_arn
}

data "archive_file" "secret_redeploy" {
  count = var.enable_db_secret_change_redeploy ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/lambda/redeploy_on_secret_change.py"
  output_path = "${path.module}/.terraform/secret-redeploy.zip"
}

data "aws_iam_policy_document" "secret_redeploy_assume" {
  count = var.enable_db_secret_change_redeploy ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "secret_redeploy" {
  count = var.enable_db_secret_change_redeploy ? 1 : 0

  name               = "${local.name}-secret-redeploy"
  assume_role_policy = data.aws_iam_policy_document.secret_redeploy_assume[0].json
}

resource "aws_cloudwatch_log_group" "secret_redeploy" {
  count = var.enable_db_secret_change_redeploy ? 1 : 0

  name              = "/aws/lambda/${local.name}-secret-redeploy"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.cloudwatch_logs_kms_key_arn
}

data "aws_iam_policy_document" "secret_redeploy" {
  count = var.enable_db_secret_change_redeploy ? 1 : 0

  statement {
    sid       = "ForceOnlyThisEcsServiceDeployment"
    effect    = "Allow"
    actions   = ["ecs:UpdateService"]
    resources = [aws_ecs_service.keycloak.id]
  }

  statement {
    sid    = "WriteOnlyOwnLambdaLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.secret_redeploy[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "secret_redeploy" {
  count = var.enable_db_secret_change_redeploy ? 1 : 0

  name   = "${local.name}-secret-redeploy"
  role   = aws_iam_role.secret_redeploy[0].id
  policy = data.aws_iam_policy_document.secret_redeploy[0].json
}

resource "aws_lambda_function" "secret_redeploy" {
  count = var.enable_db_secret_change_redeploy ? 1 : 0

  function_name = "${local.name}-secret-redeploy"
  role          = aws_iam_role.secret_redeploy[0].arn
  runtime       = "python3.13"
  handler       = "redeploy_on_secret_change.handler"

  filename         = data.archive_file.secret_redeploy[0].output_path
  source_code_hash = data.archive_file.secret_redeploy[0].output_base64sha256

  timeout     = 30
  memory_size = 128

  environment {
    variables = {
      ECS_CLUSTER = aws_ecs_cluster.keycloak.name
      ECS_SERVICE = aws_ecs_service.keycloak.name
    }
  }

  depends_on = [aws_iam_role_policy.secret_redeploy]
}

resource "aws_cloudwatch_event_rule" "database_secret_changed" {
  count = var.enable_db_secret_change_redeploy ? 1 : 0

  name        = "${local.name}-db-secret-current"
  description = "Redeploy Keycloak when the database secret AWSCURRENT value changes."

  event_pattern = jsonencode({
    source        = ["aws.secretsmanager"]
    "detail-type" = ["Secret Label Updated"]
    detail = {
      name         = [data.aws_secretsmanager_secret.database[0].name]
      labelUpdated = ["AWSCURRENT"]
    }
  })
}

resource "aws_cloudwatch_event_target" "database_secret_changed" {
  count = var.enable_db_secret_change_redeploy ? 1 : 0

  rule = aws_cloudwatch_event_rule.database_secret_changed[0].name
  arn  = aws_lambda_function.secret_redeploy[0].arn
}

resource "aws_lambda_permission" "eventbridge_secret_redeploy" {
  count = var.enable_db_secret_change_redeploy ? 1 : 0

  statement_id  = "AllowEventBridgeDatabaseSecretChange"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secret_redeploy[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.database_secret_changed[0].arn
}
