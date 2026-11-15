#!/bin/bash
# Build the application images at the commits pinned in apps/*/values.yaml.
# Usage: build-images.sh            -> build only
#        build-images.sh push       -> build and push to reg.<baseDomain>
set -u
export DEBIAN_FRONTEND=noninteractive
command -v docker >/dev/null || apt-get install -y -qq docker.io docker-buildx >/dev/null
systemctl enable --now docker >/dev/null 2>&1

IAC=/opt/apps/SESC-IT-IaC
DOMAIN=$(awk '/baseDomain:/ {print $2; exit}' $IAC/charts/cluster/values.yaml)
REG="reg.$DOMAIN"
SRC=/opt/src
mkdir -p $SRC

# image name | github repo | values.yaml with the pinned tag
APPS="
spravki-frontend|Spravki-Frontend|apps/spravki-frontend/values.yaml
spravki-backend|Spravki-Backend|apps/spravki-backend/values.yaml
technical-support-backend|Technical-Support-Backend|apps/technical-support-backend/values.yaml
document-renderer|Document-Renderer-Backend|apps/document-renderer/values.yaml
lyceum-auth-backend|Lyceum-Auth-Backend|apps/lyceum-auth/values.yaml
"

if [ "${1:-}" = push ]; then
  set -a; . /root/sescserv-secrets.env; set +a
  echo "$REGISTRY_PASSWORD" | docker login "$REG" -u "$REGISTRY_USERNAME" --password-stdin >/dev/null || { echo "login to $REG failed"; exit 1; }
fi

fail=0
for line in $APPS; do
  IFS='|' read -r image repo values <<<"$line"
  tag=$(awk '/^image:/ {f=1} f && /tag:/ {gsub(/"/,"",$2); print $2; exit}' "$IAC/$values")
  dir="$SRC/$repo"
  [ -d "$dir/.git" ] || git clone -q "https://github.com/SESC-IT-Team/$repo.git" "$dir"
  commit=${tag%%-*}   # "<sha>-<patch>" tags build <sha> plus a local patch
  git -C "$dir" fetch -q origin && git -C "$dir" checkout -q --force "$commit" || { echo "$image: checkout $commit failed"; fail=1; continue; }
  if [ "$image" = technical-support-backend ] && [ "$tag" != "$commit" ]; then
    # Upstream src/config.py builds Settings(postgres_host='', ...): init kwargs
    # override env vars, so the DB/S3 settings are always empty. Read env instead.
    python3 - "$dir/src/config.py" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"\nsettings = Settings\([^)]*\)", "\nsettings = Settings()", s, flags=re.S)
open(p, "w").write(s)
PY
    grep -n "^settings = " "$dir/src/config.py"
  fi
  if docker build -q -t "$REG/$image:$tag" "$dir" > "/root/build-$image.log" 2>&1; then
    echo "$image:$tag built"
    if [ "${1:-}" = push ]; then
      docker push -q "$REG/$image:$tag" >/dev/null && echo "$image:$tag pushed" || { echo "$image push failed"; fail=1; }
    fi
  else
    echo "$image:$tag BUILD FAILED (see /root/build-$image.log)"; tail -15 "/root/build-$image.log"; fail=1
  fi
done
exit $fail
