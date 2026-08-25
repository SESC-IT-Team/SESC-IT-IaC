#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: build-and-push-images.sh [--insecure] <registry-domain>

Examples:
  ./docs/build-and-push-images.sh reg.example.com
  ./docs/build-and-push-images.sh 212.113.98.188:5000
  ./docs/build-and-push-images.sh --insecure reg.example.com

Repository paths are configured directly in the projects list below.
Use --insecure only when Docker is configured to allow this registry without
certificate verification (Docker Desktop: Settings -> Docker Engine ->
insecure-registries).
EOF
}

insecure=false
if [[ "${1:-}" == "--insecure" ]]; then
  insecure=true
  shift
fi

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit $([[ $# -lt 1 ]] && echo 2 || echo 0)
fi

registry_domain="${1%/}"

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
command -v git >/dev/null || { echo "git is required" >&2; exit 1; }

declare -a skipped_projects=()

if [[ "$insecure" == true ]]; then
  if ! docker info --format '{{json .RegistryConfig.InsecureRegistryCIDRs}} {{json .RegistryConfig.IndexConfigs}}' 2>/dev/null | grep -Fq '"'"$registry_domain"'"'; then
    cat >&2 <<EOF
Docker is not configured to allow insecure registry: $registry_domain

On Docker Desktop for macOS, add this to Settings -> Docker Engine and restart Docker:
  "insecure-registries": ["$registry_domain"]
EOF
    exit 1
  fi
  echo "WARNING: TLS certificate verification is disabled for $registry_domain" >&2
fi

# Set each path to the corresponding repository on disk.
# The optional fourth field is a subdirectory containing the Dockerfile.
declare -a projects=(
  "document-renderer|/Users/reveek/PycharmProjects/SIT/Document-Renderer-Backend"
  "lyceum-auth-admin-frontend|/Users/reveek/WebstormProjects/Lyceum-Auth-Admin-Frontend"
  "lyceum-auth-admin-backend|/Users/reveek/Projects/SESC_IT/Lyceum-Auth-Admin-Backend"
  "lyceum-auth-backend|/Users/reveek/SESC_IT/Lyceum-Auth-Backend"
  "sesc-portal|/Users/reveek/SESC_IT/serv"
  "spravki-backend|/Users/reveek/SESC_IT/Spravki-Backend"
  "spravki-frontend|/Users/reveek/WebstormProjects/Spravki-Frontend"
  "technical-support-backend|/Users/reveek/Projects/Technical-Support-Backend"
)

build_and_push() {
  local image_name="$1"
  local repo_path="$2"
  local component="${3:-}"
  local context
  local dockerfile
  local tag

  if [[ ! -d "$repo_path/.git" ]]; then
    echo "Git repository does not exist for $image_name: $repo_path" >&2
    return 1
  fi

  echo "Updating $repo_path"
  git -C "$repo_path" pull
  tag="$(git -C "$repo_path" rev-parse --short HEAD)"

  if [[ -n "$component" ]]; then
    context="$repo_path/$component"
  else
    context="$repo_path"
  fi

  if [[ ! -d "$context" ]]; then
    echo "Build context does not exist for $image_name: $context" >&2
    return 1
  fi
  dockerfile="$context/Dockerfile"
  if [[ ! -f "$dockerfile" ]]; then
    echo "Dockerfile does not exist for $image_name: $dockerfile" >&2
    return 1
  fi

  local image="$registry_domain/$image_name:$tag"
  echo "Building $image from $context"
  docker build --platform linux/amd64 -t "$image" "$context"
  echo "Pushing $image"
  docker push "$image"
}

for project in "${projects[@]}"; do
  IFS='|' read -r image_name repo_path component <<< "$project"
  build_and_push "$image_name" "$repo_path" "${component:-}"
done

echo "All application images were built and pushed to $registry_domain"
if ((${#skipped_projects[@]} > 0)); then
  echo "Skipped images: ${skipped_projects[*]}" >&2
fi