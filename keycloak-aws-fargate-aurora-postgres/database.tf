resource "aws_db_subnet_group" "keycloak" {
  count = var.create_database ? 1 : 0

  name       = "${local.name}-db"
  subnet_ids = local.db_subnets
}

resource "aws_security_group" "database" {
  count = var.create_database ? 1 : 0

  name        = "${local.name}-db"
  description = "Managed Keycloak Aurora PostgreSQL; only Keycloak tasks may connect."
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "database_from_keycloak" {
  count = var.create_database ? 1 : 0

  security_group_id            = aws_security_group.database[0].id
  description                  = "PostgreSQL only from Keycloak ECS tasks"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.ecs.id
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_managed_database" {
  count = var.create_database ? 1 : 0

  security_group_id            = aws_security_group.ecs.id
  description                  = "Keycloak to managed Aurora PostgreSQL"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.database[0].id
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_external_database_sg" {
  count = !var.create_database && var.external_db_security_group_id != null ? 1 : 0

  security_group_id            = aws_security_group.ecs.id
  description                  = "Keycloak to DBA-managed PostgreSQL security group"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = var.external_db_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_external_database_cidr" {
  for_each = !var.create_database ? toset(var.external_db_cidrs) : toset([])

  security_group_id = aws_security_group.ecs.id
  description       = "Keycloak to DBA-managed PostgreSQL CIDR"
  ip_protocol       = "tcp"
  from_port         = var.db_port
  to_port           = var.db_port
  cidr_ipv4         = each.value
}

resource "aws_rds_cluster_parameter_group" "keycloak" {
  count = var.create_database ? 1 : 0

  name   = "${local.name}-aurora-postgres"
  family = "aurora-postgresql${split(".", var.db_engine_version)[0]}"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}

resource "aws_rds_cluster" "keycloak" {
  count = var.create_database ? 1 : 0

  cluster_identifier = "${local.name}-aurora-postgres"

  engine         = "aurora-postgresql"
  engine_version = var.db_engine_version

  database_name   = var.db_name
  master_username = var.db_master_username
  port            = var.db_port

  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.secrets_kms_key_arn

  storage_encrypted = true
  kms_key_id        = var.db_kms_key_arn

  db_subnet_group_name            = aws_db_subnet_group.keycloak[0].name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.keycloak[0].name
  vpc_security_group_ids           = [aws_security_group.database[0].id]

  backup_retention_period      = var.db_backup_retention_days
  preferred_backup_window      = "05:00-06:00"
  preferred_maintenance_window = "Sun:06:30-Sun:07:30"

  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = var.db_skip_final_snapshot
  final_snapshot_identifier = var.db_skip_final_snapshot ? null : "${local.name}-aurora-final"
  copy_tags_to_snapshot     = true
}

resource "aws_rds_cluster_instance" "keycloak" {
  count = var.create_database ? var.db_cluster_instance_count : 0

  identifier         = format("%s-aurora-%02d", local.name, count.index + 1)
  cluster_identifier = aws_rds_cluster.keycloak[0].id

  engine         = aws_rds_cluster.keycloak[0].engine
  engine_version = aws_rds_cluster.keycloak[0].engine_version
  instance_class = var.db_instance_class

  db_subnet_group_name = aws_db_subnet_group.keycloak[0].name
  availability_zone    = local.db_availability_zones[count.index % length(local.db_availability_zones)]
  publicly_accessible  = false

  # Keep the cluster on the Aurora PostgreSQL 17.7 LTS minor line; AWS still applies required LTS security/stability patches.
  auto_minor_version_upgrade = false
  apply_immediately          = false

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  performance_insights_kms_key_id       = var.db_performance_insights_kms_key_arn

  promotion_tier        = count.index
  copy_tags_to_snapshot = true
}

check "external_database_inputs" {
  assert {
    condition = var.create_database || (
      var.external_db_host != null &&
      var.external_db_secret_arn != null &&
      (var.external_db_security_group_id != null || length(var.external_db_cidrs) > 0)
    )
    error_message = "When create_database=false, set external_db_host, external_db_secret_arn, and either external_db_security_group_id or external_db_cidrs."
  }
}
