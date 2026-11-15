#!/bin/bash
# Force ArgoCD refresh, wait, then print a cluster health summary.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
for a in $(kubectl -n argocd get applications -o name); do
  kubectl -n argocd annotate "$a" argocd.argoproj.io/refresh=hard --overwrite >/dev/null
done
sleep "${1:-120}"
echo "== applications"
kubectl -n argocd get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision | cut -c1-80
echo "== pods not ready"
kubectl get pods -A --no-headers | grep -vE 'Completed|1/1 +Running|2/2 +Running' || echo none
echo "== certificates"
kubectl get certificate -A --no-headers | awk '{print $1, $2, "ready=" $3}'
echo "== memory"
free -h | head -2
