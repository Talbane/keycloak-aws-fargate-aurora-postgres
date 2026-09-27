# Reference sources

This implementation was designed against the following authoritative references as checked on 2026-08-25.

## Keycloak

- Latest stable release / upgrading notes: https://www.keycloak.org/docs/26.7.2/upgrading/
- Containers: https://www.keycloak.org/server/containers
- Production configuration: https://www.keycloak.org/server/configuration-production
- Reverse proxy: https://www.keycloak.org/server/reverseproxy
- Hostname configuration: https://www.keycloak.org/server/hostname
- Health checks: https://www.keycloak.org/observability/health
- Distributed caches: https://www.keycloak.org/server/caching
- Database configuration: https://www.keycloak.org/server/db

## AWS / GitHub / Terraform

- Amazon ECS Secrets Manager injection: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/secrets-envvar-secrets-manager.html
- RDS password management with Secrets Manager: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html
- RDS PostgreSQL SSL: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.SSL.html
- ALB target health checks: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html
- ALB X-Forwarded-For behavior: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/x-forwarded-headers.html
- GitHub OIDC in AWS: https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
- Terraform AWS provider: https://registry.terraform.io/providers/hashicorp/aws/latest
- Terraform Archive provider: https://registry.terraform.io/providers/hashicorp/archive/latest
