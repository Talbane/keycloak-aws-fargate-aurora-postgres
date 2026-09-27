data "aws_caller_identity" "current" {}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_subnet" "internal_alb" {
  for_each = toset(local.internal_alb_subnets)
  id       = each.value
}

data "aws_subnet" "external_alb" {
  for_each = var.enable_external_alb ? toset(local.external_alb_subnets) : toset([])
  id       = each.value
}

data "aws_subnet" "database" {
  for_each = var.create_database ? toset(local.db_subnets) : toset([])
  id       = each.value
}

data "aws_prefix_list" "s3" {
  count = var.create_vpc_endpoints ? 1 : 0
  name  = "com.amazonaws.${var.aws_region}.s3"
}

check "keycloak_image_version" {
  assert {
    condition     = startswith(var.keycloak_image_tag, "${var.keycloak_version}-")
    error_message = "keycloak_image_tag must start with <keycloak_version>- (for example 26.7.2-<git-sha>)."
  }
}
check "aurora_database_subnets" {
  assert {
    condition     = !var.create_database || length(local.db_availability_zones) >= 2
    error_message = "Aurora PostgreSQL requires database subnets spanning at least two Availability Zones."
  }
}

