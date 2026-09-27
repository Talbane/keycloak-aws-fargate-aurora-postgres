locals {
  name = substr(replace(lower("${var.name_prefix}-${var.environment}"), "/[^a-z0-9-]/", "-"), 0, 24)

  common_tags = merge(
    {
      Name        = local.name
      Environment = var.environment
      Application = "keycloak"
      ManagedBy   = "terraform"
    },
    var.tags
  )

  internal_alb_subnets = length(var.internal_alb_subnet_ids) > 0 ? var.internal_alb_subnet_ids : var.private_subnet_ids

  external_alb_subnets = length(var.external_alb_subnet_ids) > 0 ? var.external_alb_subnet_ids : (
    var.external_alb_internal ? var.private_subnet_ids : var.public_subnet_ids
  )

  db_subnets = length(var.db_subnet_ids) > 0 ? var.db_subnet_ids : var.private_subnet_ids
  db_availability_zones = var.create_database ? sort(distinct([for subnet in data.aws_subnet.database : subnet.availability_zone])) : []

  db_host       = var.create_database ? aws_rds_cluster.keycloak[0].endpoint : var.external_db_host
  db_name       = var.create_database ? var.db_name : coalesce(var.external_db_name, var.db_name)
  db_secret_arn = var.create_database ? aws_rds_cluster.keycloak[0].master_user_secret[0].secret_arn : var.external_db_secret_arn

  bootstrap_secret_arn = var.bootstrap_secret_arn != null ? var.bootstrap_secret_arn : aws_secretsmanager_secret.bootstrap[0].arn

  proxy_trusted_cidrs = distinct(concat(
    [for s in data.aws_subnet.internal_alb : s.cidr_block],
    var.enable_external_alb ? [for s in data.aws_subnet.external_alb : s.cidr_block] : []
  ))

  customer_secret_kms_key_arns = distinct(compact(concat(
    [var.secrets_kms_key_arn],
    var.additional_secret_kms_key_arns
  )))

  base_environment = merge(
    {
      KC_DB_URL_HOST             = local.db_host
      KC_DB_URL_PORT             = tostring(var.db_port)
      KC_DB_URL_DATABASE         = local.db_name
      KC_DB_TLS_MODE             = var.create_database || var.external_db_tls_verify ? "verify-server" : "disabled"
      KC_DB_POOL_INITIAL_SIZE    = tostring(var.db_pool_size)
      KC_DB_POOL_MIN_SIZE        = tostring(var.db_pool_size)
      KC_DB_POOL_MAX_SIZE        = tostring(var.db_pool_size)
      KC_HOSTNAME                = "https://${var.keycloak_hostname}"
      KC_HOSTNAME_STRICT         = "true"
      KC_HTTP_ENABLED            = "true"
      KC_PROXY_HEADERS           = "xforwarded"
      KC_PROXY_TRUSTED_ADDRESSES = join(",", local.proxy_trusted_cidrs)
      KC_HTTP_MANAGEMENT_PORT    = "9000"
      KC_HTTP_MANAGEMENT_SCHEME  = "http"
      KC_CACHE                   = "ispn"
      KC_CACHE_STACK             = "jdbc-ping"
      KC_SHUTDOWN_DELAY          = "10s"
      KC_SHUTDOWN_TIMEOUT        = "20s"
      KC_LOG_LEVEL               = "INFO"
    },
    var.create_database ? {
      KC_DB_TLS_TRUST_STORE_FILE = "/opt/keycloak/conf/rds-global-bundle.pem"
      } : (var.external_db_tls_verify ? {
        KC_DB_TLS_TRUST_STORE_FILE = "/tmp/keycloak-db-ca.pem"
    } : {})
  )

  task_environment = merge(local.base_environment, var.additional_task_environment)

  bootstrap_secrets = var.inject_bootstrap_admin_secret ? [
    {
      name      = "KC_BOOTSTRAP_ADMIN_USERNAME"
      valueFrom = "${local.bootstrap_secret_arn}:username::"
    },
    {
      name      = "KC_BOOTSTRAP_ADMIN_PASSWORD"
      valueFrom = "${local.bootstrap_secret_arn}:password::"
    }
  ] : []

  db_secrets = concat([
    {
      name      = "KC_DB_USERNAME"
      valueFrom = "${local.db_secret_arn}:username::"
    },
    {
      name      = "KC_DB_PASSWORD"
      valueFrom = "${local.db_secret_arn}:password::"
    }
    ], (!var.create_database && var.external_db_tls_verify) ? [
    {
      name      = "DB_CA_PEM"
      valueFrom = "${local.db_secret_arn}:ca_pem::"
    }
  ] : [])

  ecr_repository_name = "${var.name_prefix}/${var.environment}/keycloak"
}
