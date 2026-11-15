#!/bin/bash
# Transit auto-unseal for the main Vault (same scheme as GitOps-IaC):
#   1. vault-unsealer (argocd/apps/vault-unsealer.yaml) holds transit/keys/autounseal;
#   2. this script writes the transit-unseal policy, mints an orphan periodic
#      token and stores it in Secret vault/vault-transit-token (vault-0 cannot
#      start without it);
#   3. if vault-0 still uses the Shamir seal, it is restarted with the transit
#      seal config and migrated with `vault operator unseal -migrate` using the
#      keys from /root/vault-init.json (they become recovery keys).
# Re-runnable: every step checks the current state first.
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
NS=vault
K="kubectl -n $NS"

echo "[transit] waiting for vault-unsealer-0"
for i in $(seq 1 60); do
  $K get pod vault-unsealer-0 >/dev/null 2>&1 && break
  sleep 5
done
$K wait --for=condition=ready pod/vault-unsealer-0 --timeout=300s >/dev/null

UNSEALER_ROOT=$($K exec vault-unsealer-0 -- cat /vault/data/init.json | jq -r .root_token)
U="$K exec -i vault-unsealer-0 -- env VAULT_TOKEN=$UNSEALER_ROOT"

$U vault policy write transit-unseal - >/dev/null <<'EOF'
path "transit/encrypt/autounseal" { capabilities = ["update"] }
path "transit/decrypt/autounseal" { capabilities = ["update"] }
path "transit/keys/autounseal"    { capabilities = ["read"] }
path "auth/token/renew-self"      { capabilities = ["update"] }
EOF
echo "[transit] policy transit-unseal ok"

if ! $K get secret vault-transit-token >/dev/null 2>&1; then
  # Orphan: survives revocation of the unsealer root token. Periodic: Vault
  # renews it while running; 720h lets the server stay off for up to 30 days.
  TOKEN=$($U vault token create -orphan -policy=transit-unseal -no-default-policy \
            -period=720h -format=json | jq -r .auth.client_token)
  $K create secret generic vault-transit-token --from-literal=token="$TOKEN" >/dev/null
  echo "[transit] secret vault-transit-token created"
else
  echo "[transit] secret vault-transit-token exists"
fi

status() { $K exec vault-0 -- vault status -format=json 2>/dev/null || true; }

S=$(status)
if [ -z "$S" ]; then
  echo "[transit] vault-0 not answering yet (greenfield: run vault-init.sh next)"; exit 0
fi
if [ "$(echo "$S" | jq -r .type)" = transit ]; then
  echo "[transit] vault-0 already on the transit seal: $(echo "$S" | jq -c '{type,initialized,sealed}')"
  exit 0
fi
if [ "$(echo "$S" | jq -r .initialized)" != true ]; then
  echo "[transit] vault-0 not initialised (greenfield: run vault-init.sh next)"; exit 0
fi

# Shamir -> transit migration. The StatefulSet uses OnDelete, so the pod must be
# recreated to load the seal "transit" config.
echo "[transit] restarting vault-0 with the transit seal config"
$K delete pod vault-0 --wait=true >/dev/null
for i in $(seq 1 60); do
  [ "$($K get pod vault-0 -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ] && \
    [ "$(status | jq -r '.initialized // empty')" = true ] && break
  sleep 5
done
S=$(status)
echo "[transit] before migration: $(echo "$S" | jq -c '{type,sealed,migration}')"

for k in $(jq -r '.unseal_keys_b64[0:3][]' /root/vault-init.json); do
  $K exec vault-0 -- vault operator unseal -migrate "$k" >/dev/null || true
done
for i in $(seq 1 20); do
  [ "$(status | jq -r .sealed)" = false ] && break
  sleep 3
done
echo "[transit] after migration: $(status | jq -c '{type,sealed,recovery_seal}')"
