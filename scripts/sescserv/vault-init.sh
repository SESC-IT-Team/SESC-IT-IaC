#!/bin/bash
# Initialise (once) and unseal Vault; store keys in /root/vault-init.json (root only).
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
V="kubectl -n vault exec vault-0 --"

for i in $(seq 1 60); do
  phase=$(kubectl -n vault get pod vault-0 -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [ "$phase" = Running ] && break
  sleep 10
done
[ "$phase" = Running ] || { echo "vault-0 not running"; kubectl -n vault get pods; exit 1; }

status=$($V vault status -format=json 2>/dev/null || true)
if [ "$(echo "$status" | jq -r .initialized)" != true ]; then
  umask 077
  if [ "$(echo "$status" | jq -r .type)" = transit ]; then
    # Transit auto-unseal (vault-transit.sh ran first): init yields recovery keys.
    $V vault operator init -recovery-shares=5 -recovery-threshold=3 -format=json > /root/vault-init.json
  else
    $V vault operator init -key-shares=5 -key-threshold=3 -format=json > /root/vault-init.json
  fi
  echo "vault initialised, keys saved to /root/vault-init.json"
fi

# Manual unseal is only needed for the Shamir seal; the transit seal unseals itself.
if [ "$($V vault status -format=json 2>/dev/null | jq -r .type)" = shamir ] &&    [ "$($V vault status -format=json 2>/dev/null | jq -r .sealed)" = true ]; then
  for k in $(jq -r '.unseal_keys_b64[0:3][]' /root/vault-init.json); do
    $V vault operator unseal "$k" >/dev/null
  done
fi
for i in $(seq 1 30); do
  [ "$($V vault status -format=json 2>/dev/null | jq -r .sealed)" = false ] && break
  sleep 3
done
$V vault status -format=json | jq -c '{type, initialized, sealed}'

if ! grep -q '^VAULT_ROOT_TOKEN=' /root/sescserv-secrets.env; then
  echo "VAULT_ROOT_TOKEN=$(jq -r .root_token /root/vault-init.json)" >> /root/sescserv-secrets.env
fi
