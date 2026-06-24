#!/bin/sh

set -e

# Load environment variables
export RESOLVER_TYPE=${RESOLVER_TYPE:-selfsigned}
export CERT_PATH=${CERT_PATH}
export CERT_KEY=${CERT_KEY}
export CERT_CRT=${CERT_CRT}
export LE_EMAIL=${LE_EMAIL}

# Generate traefik.yml from template
envsubst < /etc/traefik/traefik.yml.template > /etc/traefik/traefik.yml

# Remove unnecessary resolver based on RESOLVER_TYPE
if [ "$RESOLVER_TYPE" = "selfsigned" ]; then
  # Remove letsencrypt block
  sed -i '/^  letsencrypt:/,/^  selfsigned:/{ /^  selfsigned:/!d; }' /etc/traefik/traefik.yml
elif [ "$RESOLVER_TYPE" = "letsencrypt" ]; then
  # Remove selfsigned block
  sed -i '/^  selfsigned:/,/^$/d' /etc/traefik/traefik.yml
fi

# Generate dynamic configs from templates
if [ -f /etc/traefik/dynamic/auth.yml.template ]; then
  envsubst < /etc/traefik/dynamic/auth.yml.template > /etc/traefik/dynamic/auth.yml
fi

# Execute traefik
exec /entrypoint.sh "$@"