output "ecr_repository_url" {
  description = "ECR repository URL used by the GitHub image build."
  value       = aws_ecr_repository.keycloak.repository_url
}

output "bootstrap_secret_arn" {
  description = "Bootstrap admin secret ARN. Populate JSON keys username/password out-of-band."
  value       = local.bootstrap_secret_arn
}

output "database_secret_arn" {
  description = "Database secret ARN used by ECS."
  value       = local.db_secret_arn
  sensitive   = true
}


output "database_writer_endpoint" {
  description = "Aurora PostgreSQL writer endpoint used by Keycloak when create_database=true."
  value       = var.create_database ? aws_rds_cluster.keycloak[0].endpoint : var.external_db_host
}

output "database_reader_endpoint" {
  description = "Aurora PostgreSQL reader endpoint when create_database=true. Keycloak itself uses the writer endpoint."
  value       = var.create_database ? aws_rds_cluster.keycloak[0].reader_endpoint : null
}

output "database_cluster_identifier" {
  description = "Aurora PostgreSQL cluster identifier when create_database=true."
  value       = var.create_database ? aws_rds_cluster.keycloak[0].cluster_identifier : null
}

output "ecs_task_security_group_id" {
  description = "Security group to provide to the DBA team when using an external DB; they should allow PostgreSQL ingress from this SG."
  value       = aws_security_group.ecs.id
}

output "internal_alb_dns_name" {
  value       = aws_lb.internal.dns_name
  description = "InfoBlox internal-view CNAME target."
}

output "internal_alb_zone_id" {
  value       = aws_lb.internal.zone_id
  description = "Internal ALB canonical hosted zone ID (informational; Route53 is not required)."
}

output "external_alb_dns_name" {
  value       = var.enable_external_alb ? aws_lb.external[0].dns_name : null
  description = "InfoBlox external-view CNAME target when split DNS is enabled."
}

output "keycloak_url" {
  value       = "https://${var.keycloak_hostname}"
  description = "Canonical Keycloak URL."
}

output "infoblox_split_dns_summary" {
  description = "Suggested split-DNS mapping."
  value = {
    fqdn                  = var.keycloak_hostname
    internal_cname_target = aws_lb.internal.dns_name
    external_cname_target = var.enable_external_alb ? aws_lb.external[0].dns_name : null
  }
}
