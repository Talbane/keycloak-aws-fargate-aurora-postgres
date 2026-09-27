#!/usr/bin/env bash
set -euo pipefail

: "${BOOTSTRAP_SECRET_ARN:?BOOTSTRAP_SECRET_ARN is required}"

if aws secretsmanager list-secret-version-ids \
  --secret-id "$BOOTSTRAP_SECRET_ARN" \
  --query 'Versions[?contains(VersionStages, `AWSCURRENT`)] | length(@)' \
  --output text 2>/dev/null | grep -qx '1'; then
  echo "Bootstrap secret already has an AWSCURRENT version; leaving it unchanged."
  exit 0
fi

: "${KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME:?GitHub protected secret KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME is required for first deployment}"
: "${KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD:?GitHub protected secret KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD is required for first deployment}"

payload="$(jq -cn \
  --arg username "$KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME" \
  --arg password "$KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD" \
  '{username:$username,password:$password}')"

aws secretsmanager put-secret-value \
  --secret-id "$BOOTSTRAP_SECRET_ARN" \
  --secret-string "$payload" >/dev/null

echo "Bootstrap secret populated in AWS Secrets Manager."
