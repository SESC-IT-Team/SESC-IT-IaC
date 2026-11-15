#!/bin/bash
# Smoke-test public endpoints through Traefik on this node.
# Usage: smoke.sh           -> resolve hosts to 127.0.0.1, skip TLS verify (before DNS)
#        smoke.sh public    -> real DNS + TLS verification
D=$(awk '/baseDomain:/ {print $2; exit}' /opt/apps/SESC-IT-IaC/charts/cluster/values.yaml)
check() {  # check <host> <path>
  local opts=(-s -o /dev/null -w '%{http_code}' --max-time 15)
  [ "${MODE:-}" = public ] || opts+=(-k --resolve "$1:443:127.0.0.1")
  printf '%-48s %s\n' "https://$1$2" "$(curl "${opts[@]}" "https://$1$2")"
}
MODE=${1:-}
check "auth.$D" /-/health/ready/
check "auth.$D" /application/o/spravki-app/.well-known/openid-configuration
check "auth.$D" /application/o/technical-support-app/.well-known/openid-configuration
check "spravki.$D" /
check "api.spravki.$D" /docs
check "api.support.$D" /docs
check "api.users.$D" /docs
check "reg.$D" /v2/
check "s3.$D" /minio/health/live
check "minio.$D" /
check "vault.$D" /v1/sys/health
check "argocd.$D" /
