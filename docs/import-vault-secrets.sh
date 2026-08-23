#!/usr/bin/env bash
set -euo pipefail

manifest="${1:-docs/vault-secrets.import.json}"
mount="${VAULT_KV_MOUNT:-kv}"

command -v vault >/dev/null || { echo "vault CLI is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
jq empty "$manifest"

if jq -e '.. | strings | select(test("<[^>]+>"))' "$manifest" >/dev/null; then
  echo "Manifest still contains placeholders. Replace them before importing." >&2
  exit 1
fi

jq -c '.[]' "$manifest" | while IFS= read -r record; do
  path=$(jq -r '.path' <<<"$record")
  echo "Writing $mount/$path"
  if ! vault kv put -tls-skip-verify "$mount/$path" $(jq -r '.data | to_entries[] | "\(.key)=\(.value)"' <<<"$record"); then
    cat >&2 <<EOF
Vault denied the write to $mount/$path.
The token must include the policy in docs/vault-importer-policy.hcl,
including read access to $mount/metadata/apps/* for the Vault CLI preflight check.
EOF
    exit 1
  fi
done