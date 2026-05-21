#!/bin/bash
set -e
REPO_DIR="/opt/ssh_keys_repo"
AUTH_KEYS="/root/.ssh/authorized_keys"

cd "$REPO_DIR"
git pull origin main 2>/dev/null || { echo "Pull failed"; exit 1; }

mkdir -p /root/.ssh
> "$AUTH_KEYS"

for keyfile in users/*.pub; do
  [ -f "$keyfile" ] && cat "$keyfile" >> "$AUTH_KEYS"
done

chmod 600 "$AUTH_KEYS"
