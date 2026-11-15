#!/bin/bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
P=$(kubectl -n minio get secret minio-secrets -o jsonpath='{.data.MINIO_ROOT_PASSWORD}' | base64 -d)
kubectl -n minio exec minio-0 -- env MP="$P" sh -c '
  export HOME=/tmp
  mc alias set local http://127.0.0.1:9000 minioadmin "$MP" >/dev/null &&
  mc mb --ignore-existing local/geometry-dash local/order-photos && mc ls local'
