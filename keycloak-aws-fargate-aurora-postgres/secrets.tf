resource "aws_secretsmanager_secret" "bootstrap" {
  count = var.bootstrap_secret_arn == null ? 1 : 0

  name                    = "${local.name}/bootstrap-admin"
  description             = "Keycloak bootstrap admin credentials. Populate out-of-band; Terraform intentionally creates no secret version."
  kms_key_id              = var.secrets_kms_key_arn
  recovery_window_in_days = 14

  lifecycle {
    prevent_destroy = true
  }
}
