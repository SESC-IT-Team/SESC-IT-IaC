#!/bin/bash
# Prepare a fresh Debian server: tools, repo clone (env/sescserv), secrets file.
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq ansible-core git jq curl python3-kubernetes apache2-utils openssl >/dev/null

if [ ! -d /opt/apps/SESC-IT-IaC/.git ]; then
  git clone -q -b env/sescserv https://github.com/SESC-IT-Team/SESC-IT-IaC.git /opt/apps/SESC-IT-IaC
fi
(cd /opt/apps/SESC-IT-IaC/ansible && ansible-galaxy collection install -r requirements.yml >/dev/null)

# ansible.cfg points at ../.ansible-vault-password; the sescserv inventory has
# no encrypted values, so any password file will do.
[ -f /root/.ansible-vault-dummy ] || (openssl rand -hex 16 > /root/.ansible-vault-dummy; chmod 600 /root/.ansible-vault-dummy)

# Bootstrap secrets live only on the server (root, 0600). vault-init.sh later
# appends VAULT_ROOT_TOKEN here.
if [ ! -f /root/sescserv-secrets.env ]; then
  umask 077
  cat > /root/sescserv-secrets.env <<EOF
REGISTRY_USERNAME=sesc
REGISTRY_PASSWORD=$(openssl rand -hex 24)
EOF
fi
ls -l /root/sescserv-secrets.env
