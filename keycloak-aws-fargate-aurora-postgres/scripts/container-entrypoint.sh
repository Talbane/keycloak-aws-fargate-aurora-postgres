#!/usr/bin/env bash
set -euo pipefail

# For DBA-managed PostgreSQL, Terraform can inject a PEM CA from Secrets Manager
# without ever storing it in Terraform state or baking an organization-private CA
# into the Git repository/image.
if [[ -n "${DB_CA_PEM:-}" ]]; then
  umask 077
  printf '%s\n' "$DB_CA_PEM" > /tmp/keycloak-db-ca.pem
fi

exec /opt/keycloak/bin/kc.sh "$@"
