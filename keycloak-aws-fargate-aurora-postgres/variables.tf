variable "aws_region" {
  description = "AWS region for the deployment."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Optional local AWS CLI profile. Leave null in GitHub Actions/OIDC."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Short naming prefix used for resources."
  type        = string
  default     = "keycloak"
}

variable "environment" {
  description = "Environment name, for example poc, dev, qa, prod."
  type        = string
  default     = "prod"
}

variable "tags" {
  description = "Additional tags applied to supported resources."
  type        = map(string)
  default = {
    Application = "keycloak"
    ManagedBy   = "terraform"
    Owner       = "CHANGE_ME"
    CostCenter  = "CHANGE_ME"
  }
}

variable "vpc_id" {
  description = "Existing VPC ID."
  type        = string
}

variable "private_subnet_ids" {
  description = "Existing private subnet IDs for ECS tasks and, by default, the database. Use at least two AZs for production."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "Provide at least two private subnet IDs in different Availability Zones for production HA."
  }
}

variable "public_subnet_ids" {
  description = "Existing public subnet IDs used only when the optional external ALB is internet-facing."
  type        = list(string)
  default     = []
}

variable "internal_alb_subnet_ids" {
  description = "Subnets for the internal ALB. Empty means private_subnet_ids."
  type        = list(string)
  default     = []
}

variable "external_alb_subnet_ids" {
  description = "Subnets for the optional external ALB. Empty means public_subnet_ids when internet-facing, otherwise private_subnet_ids."
  type        = list(string)
  default     = []
}

variable "private_route_table_ids" {
  description = "Private route table IDs. Required only if create_vpc_endpoints=true and you want the S3 gateway endpoint for private ECR image pulls."
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "Existing ACM certificate ARN covering keycloak_hostname."
  type        = string
}

variable "keycloak_hostname" {
  description = "Canonical Keycloak FQDN, without scheme. For split DNS, point the same FQDN to the internal or external ALB in the corresponding InfoBlox view."
  type        = string
}

variable "keycloak_image_tag" {
  description = "Immutable ECR image tag to deploy. GitHub Actions should set this to a version+commit tag."
  type        = string
}

variable "keycloak_version" {
  description = "Upstream Keycloak release used by the Containerfile/GitHub build."
  type        = string
  default     = "26.7.2"
}

variable "ecr_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for ECR image encryption. Null uses ECR AES-256 server-side encryption."
  type        = string
  default     = null
}

variable "ecs_cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 1024
}

variable "ecs_memory" {
  description = "Fargate task memory in MiB. Keycloak recommends setting a container memory limit; 2048 MiB is a sensible small production starting point."
  type        = number
  default     = 2048
}

variable "desired_count" {
  description = "Desired number of Keycloak tasks."
  type        = number
  default     = 2

  validation {
    condition     = var.desired_count >= 2
    error_message = "Production Keycloak should run at least two tasks."
  }
}

variable "autoscaling_min_capacity" {
  type        = number
  description = "Minimum ECS service task count."
  default     = 2
}

variable "autoscaling_max_capacity" {
  type        = number
  description = "Maximum ECS service task count."
  default     = 6
}

variable "autoscaling_cpu_target" {
  type        = number
  description = "Target average ECS service CPU utilization percentage."
  default     = 65
}

variable "autoscaling_memory_target" {
  type        = number
  description = "Target average ECS service memory utilization percentage."
  default     = 70
}

variable "enable_ecs_exec" {
  description = "Enable ECS Exec. Keep false unless operationally required. Enabling also grants the task the minimum SSM Messages permissions."
  type        = bool
  default     = false
}

variable "inject_bootstrap_admin_secret" {
  description = "Inject KC_BOOTSTRAP_ADMIN_USERNAME/PASSWORD into the task. Set false after initial bootstrap/hardening if you no longer need bootstrap credentials."
  type        = bool
  default     = true
}

variable "bootstrap_secret_arn" {
  description = "Optional existing Secrets Manager secret ARN with JSON keys username and password. If null, Terraform creates the secret container but never stores the secret value in Terraform state."
  type        = string
  default     = null
}

variable "secrets_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for the Terraform-managed bootstrap secret and Aurora/RDS-managed master secret. Ensure its key policy permits the required AWS services/roles."
  type        = string
  default     = null
}

variable "additional_secret_kms_key_arns" {
  description = "Additional customer KMS key ARNs needed to decrypt externally managed Secrets Manager secrets."
  type        = list(string)
  default     = []
}

variable "create_database" {
  description = "Create an encrypted Aurora PostgreSQL cluster. Set false when the DBA team supplies PostgreSQL."
  type        = bool
  default     = true
}

variable "db_subnet_ids" {
  description = "Subnets for managed Aurora PostgreSQL. Empty means private_subnet_ids. Aurora requires subnets spanning at least two Availability Zones."
  type        = list(string)
  default     = []
}

variable "db_name" {
  type        = string
  description = "Keycloak database name."
  default     = "keycloak"
}

variable "db_master_username" {
  type        = string
  description = "Managed Aurora PostgreSQL master username. Password is generated/managed by RDS Secrets Manager integration and is never placed in Terraform variables."
  default     = "keycloak_admin"
}

variable "db_port" {
  type        = number
  description = "PostgreSQL port."
  default     = 5432
}

variable "db_engine_version" {
  type        = string
  description = "Aurora PostgreSQL engine version. Keycloak supports Aurora PostgreSQL 17.x, 16.x, and 15.x. Default is the Aurora PostgreSQL 17.7 LTS release."
  default     = "17.7"
}

variable "db_instance_class" {
  type        = string
  description = "Aurora PostgreSQL cluster instance class."
  default     = "db.r7g.large"
}

variable "db_cluster_instance_count" {
  type        = number
  description = "Number of Aurora PostgreSQL cluster instances. Use at least 2 for database-instance HA; 1 is acceptable for a cost-focused POC."
  default     = 2

  validation {
    condition = (
      var.db_cluster_instance_count >= 1 &&
      var.db_cluster_instance_count <= 16 &&
      floor(var.db_cluster_instance_count) == var.db_cluster_instance_count
    )
    error_message = "db_cluster_instance_count must be a whole number from 1 through 16."
  }
}

variable "db_backup_retention_days" {
  type        = number
  description = "Aurora automated backup retention days."
  default     = 35
}

variable "db_deletion_protection" {
  type        = bool
  description = "Enable Aurora cluster deletion protection."
  default     = true
}

variable "db_skip_final_snapshot" {
  type        = bool
  description = "Skip final Aurora cluster snapshot on destroy. Keep false in production."
  default     = false
}

variable "db_kms_key_arn" {
  type        = string
  description = "Optional KMS key ARN for Aurora cluster storage encryption. Null uses the AWS-managed RDS key."
  default     = null
}

variable "db_performance_insights_kms_key_arn" {
  type        = string
  description = "Optional KMS key ARN for Aurora PostgreSQL Performance Insights."
  default     = null
}

variable "external_db_host" {
  type        = string
  description = "DBA-managed PostgreSQL hostname. Required when create_database=false."
  default     = null
}

variable "external_db_name" {
  type        = string
  description = "DBA-managed PostgreSQL database name. Null uses db_name."
  default     = null
}

variable "external_db_secret_arn" {
  type        = string
  description = "DBA-managed Secrets Manager secret ARN with JSON keys username and password. Required when create_database=false."
  default     = null
}

variable "external_db_security_group_id" {
  type        = string
  description = "Optional security group ID attached to the DBA-managed database. If provided, an ECS egress rule is scoped to that SG on db_port. The DBA must separately allow ingress from the ECS task SG."
  default     = null
}

variable "external_db_cidrs" {
  type        = list(string)
  description = "Optional DBA-managed DB CIDRs if a destination security group cannot be referenced."
  default     = []
}

variable "internal_alb_ingress_cidrs" {
  description = "Explicit IPv4 CIDRs allowed to reach the internal ALB on 443 (for example enterprise/on-prem networks routed over TGW)."
  type        = list(string)

  validation {
    condition     = length(var.internal_alb_ingress_cidrs) > 0
    error_message = "Specify at least one explicit trusted CIDR for the internal ALB."
  }
}

variable "internal_alb_ingress_ipv6_cidrs" {
  description = "Optional IPv6 CIDRs allowed to reach the internal ALB on 443."
  type        = list(string)
  default     = []
}

variable "enable_external_alb" {
  description = "Enable a second ALB for split-DNS/public access."
  type        = bool
  default     = false
}

variable "external_alb_internal" {
  description = "If true, the optional 'external' ALB is also internal (useful when an upstream enterprise edge/firewall provides public ingress). If false it is internet-facing."
  type        = bool
  default     = false
}

variable "external_alb_ingress_cidrs" {
  description = "Explicit IPv4 CIDRs allowed to reach the optional external ALB. Use 0.0.0.0/0 only when intentionally providing Internet access and preferably with WAF enabled."
  type        = list(string)
  default     = []
}

variable "external_alb_ingress_ipv6_cidrs" {
  description = "Optional IPv6 CIDRs allowed to reach the external ALB."
  type        = list(string)
  default     = []
}

variable "external_block_admin_paths" {
  description = "Return 403 for Keycloak administration paths and the master administrative realm on the external ALB."
  type        = bool
  default     = true
}


variable "external_restrict_public_paths" {
  description = "On the external ALB, default-deny paths and forward only /realms/*, /resources/* and /.well-known/* as recommended by Keycloak. Keep true for Internet exposure."
  type        = bool
  default     = true
}

variable "alb_xff_header_processing_mode" {
  description = "ALB X-Forwarded-For processing mode. Default remove prevents clients from supplying a spoofable XFF chain; ALB access logs/WAF retain source-IP visibility."
  type        = string
  default     = "remove"

  validation {
    condition     = contains(["append", "preserve", "remove"], var.alb_xff_header_processing_mode)
    error_message = "alb_xff_header_processing_mode must be append, preserve, or remove."
  }
}

variable "alb_ssl_policy" {
  description = "ALB TLS security policy. AWS currently recommends the resilient TLS 1.3/1.2 post-quantum policy for broad compatibility."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
}

variable "alb_deletion_protection" {
  description = "Enable ALB deletion protection."
  type        = bool
  default     = true
}

variable "alb_stickiness_seconds" {
  description = "Application-cookie stickiness duration for Keycloak AUTH_SESSION_ID."
  type        = number
  default     = 3600
}

variable "enable_alb_access_logs" {
  description = "Create a private S3 bucket and enable ALB access logging."
  type        = bool
  default     = true
}

variable "alb_log_retention_days" {
  description = "S3 lifecycle retention for ALB access logs."
  type        = number
  default     = 90
}

variable "enable_external_waf" {
  description = "Attach an AWS WAFv2 Web ACL with managed baseline rules to the external ALB."
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "WAF rate-based request limit per 5-minute evaluation window, per source IP. Tune for your authentication traffic."
  type        = number
  default     = 5000
}

variable "cloudwatch_log_retention_days" {
  type        = number
  description = "ECS/Keycloak CloudWatch Logs retention."
  default     = 90
}

variable "cloudwatch_logs_kms_key_arn" {
  type        = string
  description = "Optional KMS key ARN for the Keycloak CloudWatch log group. Key policy must permit the regional CloudWatch Logs service."
  default     = null
}

variable "alarm_actions" {
  type        = list(string)
  description = "SNS topic ARNs or other CloudWatch alarm actions."
  default     = []
}

variable "create_vpc_endpoints" {
  type        = bool
  description = "Create private interface endpoints for ECR API/DKR, CloudWatch Logs and Secrets Manager. Also creates SSM Messages when ECS Exec is enabled."
  default     = false
}

variable "https_egress_cidrs" {
  description = "Additional IPv4 HTTPS destinations that Keycloak tasks may reach (for external IdPs, SMTP APIs, enterprise proxies, etc.). Empty by default to avoid unrestricted egress."
  type        = list(string)
  default     = []
}

variable "https_egress_ipv6_cidrs" {
  description = "Additional IPv6 HTTPS destinations that Keycloak tasks may reach."
  type        = list(string)
  default     = []
}

variable "https_egress_prefix_list_ids" {
  description = "Additional AWS-managed/customer prefix list IDs permitted over HTTPS."
  type        = list(string)
  default     = []
}

variable "https_egress_security_group_ids" {
  description = "Additional destination security group IDs permitted over HTTPS, for example existing interface endpoints or enterprise proxies."
  type        = list(string)
  default     = []
}

variable "additional_task_environment" {
  description = "Optional non-secret Keycloak environment variables. Do not put passwords/tokens here."
  type        = map(string)
  default     = {}
}

variable "enable_db_secret_change_redeploy" {
  description = "Force a rolling ECS deployment when the database Secrets Manager AWSCURRENT label changes, so ECS refreshes injected credentials after rotation."
  type        = bool
  default     = true
}

variable "db_pool_size" {
  description = "Fixed Keycloak JDBC pool size per ECS task. Initial/min/max are set equal per Keycloak production guidance. Size this against database max_connections and autoscaling_max_capacity."
  type        = number
  default     = 20

  validation {
    condition     = var.db_pool_size >= 5
    error_message = "db_pool_size must be at least 5."
  }
}

variable "additional_egress_cidr_rules" {
  description = "Optional least-privilege task egress rules for non-HTTPS dependencies such as LDAP or SMTP. Each rule is scoped to one IPv4 CIDR and port range."
  type = list(object({
    description = string
    protocol    = string
    from_port   = number
    to_port     = number
    cidr_ipv4   = string
  }))
  default = []
}

variable "additional_egress_security_group_rules" {
  description = "Optional least-privilege task egress rules to destination security groups, for example private LDAP/SMTP services."
  type = list(object({
    description       = string
    protocol          = string
    from_port         = number
    to_port           = number
    security_group_id = string
  }))
  default = []
}

variable "external_db_tls_verify" {
  description = "Require TLS with full server certificate verification for a DBA-managed PostgreSQL database. Recommended for production. If true, the external DB secret must also contain a PEM CA in the ca_pem JSON key."
  type        = bool
  default     = true
}
