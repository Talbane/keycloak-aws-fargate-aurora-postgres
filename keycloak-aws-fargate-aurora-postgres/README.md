Sandbox Deployment Configurations


# Keycloak 26.7.2 on AWS ECS/Fargate

Production-oriented Terraform for Keycloak on private ECS/Fargate tasks with an internal ALB by default and an optional second ALB for InfoBlox split DNS. The stack intentionally does **not** create a VPC, subnets, Route 53 zones, resolvers, NAT gateways, or an ACM certificate.

## Architecture

- **Keycloak 26.7.2**, built into an optimized immutable image and pushed to a private **Amazon ECR** repository. ECR encryption is AES-256 by default with an optional customer KMS key.
- **ECS on Fargate**, minimum two tasks, private subnets, no public IPs, Container Insights, rolling deployment circuit breaker, and target-tracking autoscaling.
- **Internal ALB** by default. Optional second ALB for split-DNS/external traffic.
- **ACM certificate** supplied by you and attached to the ALB listener(s).
- **ALB -> Keycloak HTTP/8080** for edge TLS termination. The ECS SG accepts 8080 only from the ALB SGs, which prevents direct client access and forwarded-header spoofing.
- **Health checks on private port 9000** using `/health/ready`; port 9000 is never exposed to end users.
- **PostgreSQL**: optional encrypted Multi-AZ RDS PostgreSQL. Keycloak uses TLS with full server-certificate verification against the AWS RDS CA bundle. When disabled, a DBA-managed PostgreSQL endpoint and Secrets Manager secret are used.
- **Clustering**: Keycloak production cache (`ispn`) with current default/recommended `jdbc-ping` database discovery. ECS task SG permits only peer-to-peer TCP/7800 and TCP/57800 for JGroups.
- **Sticky sessions**: ALB application-cookie stickiness using Keycloak `AUTH_SESSION_ID`.
- **Secrets Manager**: database credentials and bootstrap admin credentials are injected through the ECS `secrets` mechanism. Terraform never writes bootstrap username/password into state.
- **AWS WAFv2**: optional baseline managed rules and rate limiting on the external ALB. The external listener is default-deny and forwards only `/realms/*`, `/resources/*`, and `/.well-known/*`; `/admin/*` and `/realms/master/*` are explicitly blocked.
- **Logging**: Keycloak logs to CloudWatch Logs and ALB access logs to a private S3 bucket.
- **GitHub OIDC**: deployment workflow uses short-lived AWS credentials, not stored AWS access keys.
- **Pinned toolchain**: Terraform is pinned to 1.15.9 in CI and provider constraints are exact (`hashicorp/aws` 6.60.0, `hashicorp/archive` 2.8.0). Generate and commit `.terraform.lock.hcl` from a trusted workstation/runner after the first `terraform init`.

## DNS / InfoBlox

The safest split-DNS design is to keep a **single canonical Keycloak hostname** and resolve it differently by DNS view:

```text
Internal InfoBlox view
sso.example.edu  CNAME  <internal-alb>.elb.amazonaws.com

External InfoBlox view (only when enable_external_alb=true)
sso.example.edu  CNAME  <external-alb>.elb.amazonaws.com
```

Because both paths use the same user-facing hostname, Keycloak can keep `KC_HOSTNAME=https://sso.example.edu` and does not need dynamic hostname resolution. Your ACM certificate must cover that hostname.

## Database modes

### Terraform-managed database

`create_database=true` creates encrypted Multi-AZ RDS PostgreSQL, with:

- no public endpoint;
- security-group ingress only from the Keycloak task SG on 5432;
- RDS-managed master password in Secrets Manager;
- backups, deletion protection, storage autoscaling, and Performance Insights.

### DBA-managed database

Set `create_database=false` and provide:

- `external_db_host`;
- `external_db_secret_arn` containing JSON `{"username":"...","password":"...","ca_pem":"-----BEGIN CERTIFICATE-----..."}` when `external_db_tls_verify=true`;
- either `external_db_security_group_id` or narrow `external_db_cidrs`.

Give the DBA team the Terraform output `ecs_task_security_group_id`; their DB SG should allow TCP/5432 **from that SG**, not from the whole VPC.

If database-secret change redeployment is enabled, also add that exact external database secret ARN to `bootstrap/github-oidc` variable `database_secret_arns_for_metadata_read`; this grants the GitHub deployment role only `DescribeSecret` metadata access, never `GetSecretValue`.

## Outbound network / VPC endpoints

The ECS task SG deliberately has **no default 0.0.0.0/0 egress**. Choose one of these patterns:

1. Set `create_vpc_endpoints=true` and provide private route table IDs. Terraform creates ECR API, ECR DKR, CloudWatch Logs, Secrets Manager (and SSM Messages if ECS Exec is enabled) interface endpoints plus an S3 gateway endpoint for ECR layer downloads.
2. If your private subnets already route through a TGW/central firewall or proxy, add only the required destination CIDRs, prefix lists, or destination SGs with `https_egress_*` variables.
3. Add specific destinations needed by configured Keycloak identity providers, LDAP endpoints, SMTP APIs, webhooks, etc.

This is intentional: Keycloak integrations are environment-specific, so a production SG should not silently receive unrestricted outbound Internet access.

## Bootstrap admin secret

When Terraform manages the bootstrap secret, it creates **only the Secrets Manager secret container**, not a secret version. This avoids placing bootstrap credentials in Terraform state.

The GitHub workflow seeds it once from protected GitHub Environment secrets:

- `KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME`
- `KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD`

After Keycloak has been initialized and permanent administrative access is established, consider setting:

```hcl
inject_bootstrap_admin_secret = false
```

and redeploying so future ECS task definitions no longer inject bootstrap credentials. You can then retire the GitHub bootstrap secrets according to your organization process.

## GitHub repository configuration

Use a protected GitHub Environment (for example `keycloak-prod`) with required reviewers/branch restrictions. Configure:

### GitHub Environment secrets

- `AWS_DEPLOY_ROLE_ARN` — deployment IAM role, configured only in the protected `keycloak-prod` environment.
- `AWS_PLAN_ROLE_ARN` — read-only IAM role, configured only in the `keycloak-plan` environment.
- `KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME` — initial bootstrap only.
- `KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD` — initial bootstrap only.

### GitHub variables

- `AWS_REGION` — e.g. `us-east-1`.
- `TF_STATE_BUCKET` — pre-existing private/encrypted Terraform state bucket.
- `TF_STATE_KEY` — e.g. `identity/keycloak/prod.tfstate`.
- `TF_RUNNER_LABEL` — optional self-hosted runner label; otherwise the workflow uses `ubuntu-latest`.

Do **not** place AWS access keys, database passwords, client secrets, SMTP passwords, or IdP secrets in `terraform.tfvars`. Pull-request plans run with a separate read-only role and `-lock=false`, so PRs cannot mutate infrastructure or Terraform state. The workflow uses exact action release tags rather than floating major tags; if your enterprise policy requires full commit-SHA pinning, replace each `uses:` version with the approved full SHA and let Dependabot/Renovate manage updates.

The current action releases use Node.js 24. Keep self-hosted GitHub runners on a current Actions Runner build; alternatively use GitHub-hosted `ubuntu-latest`.

## First deployment

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in VPC/subnet/ACM/DNS/tag values. Run `terraform init` from a trusted environment once and commit the generated `.terraform.lock.hcl`.
2. Create the GitHub OIDC plan/deploy roles using `bootstrap/github-oidc` or your enterprise IAM pipeline.
3. Configure the GitHub Environment secrets/variables above.
4. Merge to `main` or use workflow dispatch.
5. The workflow bootstraps ECR and the empty Secrets Manager secret, seeds the bootstrap credential out-of-band, resolves the upstream Keycloak 26.7.2 image to a digest, builds the optimized image, pushes an immutable `<version>-<git-sha>` tag, then runs the full Terraform apply.
6. Register the returned internal ALB DNS name as the InfoBlox internal-view CNAME target.

The first-run workflow intentionally uses Terraform `-target` only to break the ECR/secret/image bootstrap dependency. Normal infrastructure convergence is performed by the final full `terraform apply`.

## Enabling split DNS later

Set:

```hcl
enable_external_alb = true
external_alb_internal = false
external_alb_ingress_cidrs = ["0.0.0.0/0"] # only if truly public
```

Leave `enable_external_waf=true` and `external_restrict_public_paths=true`. The external listener defaults to 404 and forwards only `/realms/*`, `/resources/*`, and `/.well-known/*`; a higher-priority rule returns 403 for `/admin`, `/admin/*`, `/realms/master`, and `/realms/master/*`. After apply, add the `external_alb_dns_name` output as the CNAME target in the external InfoBlox view while retaining the internal CNAME in the internal view.

For higher assurance, prefer a dedicated internal admin hostname/certificate and stronger edge controls rather than exposing administrative surfaces over the public path.

## Security notes

- Current AWS guidance recommends `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`; it supports TLS 1.3/1.2 plus hybrid ML-KEM post-quantum key exchange for capable clients.
- The Keycloak management interface on port 9000 is not proxied to users.
- `KC_PROXY_HEADERS=xforwarded` is paired with `KC_PROXY_TRUSTED_ADDRESSES` derived from the ALB subnet CIDRs, and network SGs further restrict direct access to the tasks.
- ALBs default to `xff_header_processing_mode="remove"` so user-supplied `X-Forwarded-For` chains are stripped before Keycloak. This deliberately means Keycloak itself sees the ALB as the network peer; original source IP remains in ALB access logs/WAF. Keycloak recommends proxies **overwrite**, not append, forwarded identity headers. Because ALB offers append/preserve/remove rather than an overwrite mode for XFF, switch to `append` only if an upstream trusted edge strips client-supplied forwarded headers before the ALB and you have validated the entire chain.
- ECS task role has no AWS permissions unless ECS Exec is enabled.
- ECS execution role can pull only this ECR repository, write only this CloudWatch log group, and read only the required Secrets Manager secrets.
- RDS master password is generated by RDS and stored in Secrets Manager, not Terraform state.
- When you use customer-managed KMS keys, put their exact ARNs in the bootstrap stack's `deployment_kms_key_arns`; the deploy role receives only the cryptographic/grant permissions AWS requires on those keys.
- The Terraform-managed RDS convenience path uses the RDS master login because Terraform cannot safely create a PostgreSQL application principal without handling database credentials. For stricter **database-level** least privilege, use `create_database=false` (or have the DBA team provision an app-specific Keycloak database user/secret) while keeping all AWS IAM/SG controls unchanged.
- PostgreSQL traffic uses Keycloak `db-tls-mode=verify-server`; managed RDS uses the AWS RDS CA bundle and external DBs can inject their private CA from the DB secret at runtime.
- The external WAF rules are a baseline. Test authentication flows and tune exclusions/rate limits before production cutover.
- The deploy role intentionally omits `iam:CreateServiceLinkedRole`; pre-create any first-use AWS service-linked roles through your platform/IAM process rather than giving GitHub that broad permission.

## Keycloak-specific assumptions

This stack follows current Keycloak 26.7.x guidance: production `start --optimized`, PostgreSQL, clustered `ispn` cache with `jdbc-ping`, reverse-proxy `xforwarded` headers, a fixed HTTPS hostname, health/metrics on management port 9000, restricted external paths, and session affinity via `AUTH_SESSION_ID`.

## Database transport security

For Terraform-managed RDS, the stack attaches a PostgreSQL parameter group with `rds.force_ssl=1` and Keycloak uses `db-tls-mode=verify-server` against the AWS RDS CA bundle. For a DBA-managed database, keep `external_db_tls_verify=true` and store the private/public CA PEM under `ca_pem` in the database Secrets Manager JSON secret.

## Database credential rotation

RDS-managed master credentials rotate every seven days by default. ECS resolves Secrets Manager values when a task starts, so this stack enables `enable_db_secret_change_redeploy=true` by default. A native Secrets Manager `Secret Label Updated` EventBridge rule watches only the configured database secret and invokes a small Lambda whose only application permission is `ecs:UpdateService` on this Keycloak service with `forceNewDeployment=true`. The normal ECS rolling-deployment settings keep healthy old tasks in service while new tasks start with the new credential.

## Database connection pool

The stack sets `KC_DB_POOL_INITIAL_SIZE`, `KC_DB_POOL_MIN_SIZE`, and `KC_DB_POOL_MAX_SIZE` to the same `db_pool_size` value (default `20`). Treat this as a starting point: the database must be sized for at least `db_pool_size × autoscaling_max_capacity`, plus administrative/system connections and any other clients. Load-test and tune before production cutover.

## Outbound dependencies

The ECS task security group intentionally has no catch-all Internet egress. AWS control-plane/runtime traffic can use the optional VPC endpoints. Add only the destinations Keycloak actually needs through `https_egress_*`, `additional_egress_cidr_rules`, or `additional_egress_security_group_rules` (for example LDAPS 636 or SMTP 587). If your TGW/Palo Alto or other centralized egress path is the required route, scope these rules to the firewall/proxy destination rather than `0.0.0.0/0` where possible.
