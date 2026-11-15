#!/bin/bash
# Generate application secrets once and write them to Vault kv/apps/*.
# Existing Vault paths are left untouched (re-runnable).
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
set -a; . /root/sescserv-secrets.env; set +a
r() { openssl rand -hex "${1:-24}"; }

put() {  # put <path> KEY=VALUE...
  local path=$1; shift
  if kubectl -n vault exec vault-0 -- env VAULT_TOKEN="$VAULT_ROOT_TOKEN" vault kv get -mount=kv "$path" >/dev/null 2>&1; then
    echo "kv/$path exists, skipped"; return
  fi
  kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN="$VAULT_ROOT_TOKEN" vault kv put -mount=kv "$path" "$@" >/dev/null
  echo "kv/$path written ($# keys)"
}

API_TOKEN=$(r 32)
put apps/authentik \
  PG_PASS=$(r) AUTHENTIK_SECRET_KEY=$(r 40) AUTHENTIK_ADMIN_PASSWORD=$(r 12) \
  SPRAVKI_CLIENT_SECRET=$(r 32) TECHNICAL_SUPPORT_CLIENT_SECRET=$(r 32) \
  AUTH_ADMIN_APP_CLIENT_SECRET=$(r 32) OPENFGA_CLIENT_SECRET=$(r 32) \
  SA_SPRAVKI_APP_PASSWORD=$(r) SA_TECHNICAL_SUPPORT_APP_PASSWORD=$(r) \
  SA_AUTH_ADMIN_APP_APP_PASSWORD=$(r) SA_AUTH_ADMIN_APP_API_TOKEN=$API_TOKEN
# lyceum-auth must use the same service-account API token as authentik.
API_TOKEN=$(kubectl -n vault exec vault-0 -- env VAULT_TOKEN="$VAULT_ROOT_TOKEN" vault kv get -mount=kv -field=SA_AUTH_ADMIN_APP_API_TOKEN apps/authentik)
put apps/lyceum-auth POSTGRES_PASSWORD=$(r) ADMIN_PASSWORD=$(r 12) SA_AUTH_ADMIN_APP_API_TOKEN=$API_TOKEN
put apps/spravki-backend POSTGRES_PASSWORD=$(r)
put apps/technical-support-backend POSTGRES_PASSWORD=$(r)
put apps/rabbitmq RABBITMQ_PASSWORD=$(r) RABBITMQ_ERLANG_COOKIE=$(r 16)
put apps/redis REDIS_PASSWORD=$(r)
put apps/minio MINIO_ROOT_PASSWORD=$(r)
put apps/registry REGISTRY_USERNAME="$REGISTRY_USERNAME" REGISTRY_PASSWORD="$REGISTRY_PASSWORD" \
  HTPASSWD="$(htpasswd -Bbn "$REGISTRY_USERNAME" "$REGISTRY_PASSWORD")"
