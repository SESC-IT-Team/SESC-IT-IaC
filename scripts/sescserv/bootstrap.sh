#!/bin/bash
# Usage: bootstrap.sh <logname>
# Runs the k3s/ArgoCD playbook locally with secrets from /root/sescserv-secrets.env.
set -a
. /root/sescserv-secrets.env
set +a
export ANSIBLE_VAULT_PASSWORD_FILE=/root/.ansible-vault-dummy
export ANSIBLE_STDOUT_CALLBACK=default
export ANSIBLE_FORCE_COLOR=0
cd /opt/apps/SESC-IT-IaC && git pull -q --ff-only
cd ansible
ansible-playbook -i inventories/sescserv.yml playbooks/k3s-server.yml > "/root/$1.log" 2>&1
rc=$?
echo "exit=$rc"
grep -E "^(TASK|fatal|PLAY RECAP)|failed=|ok=" "/root/$1.log" | tail -15
