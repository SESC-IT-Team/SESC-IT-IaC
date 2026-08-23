#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: build-and-push-images.sh [--insecure] <registry-domain> [projects-root]

Examples:
  ./docs/build-and-push-images.sh reg.example.com
  ./docs/build-and-push-images.sh 212.113.98.188:5000 /Users/me/Projects
  ./docs/build-and-push-images.sh --insecure reg.example.com

The optional projects-root defaults to the parent directory of this repository.
Missing repositories are cloned into <projects-root>/SESC_IT.
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
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
projects_root="${2:-$(dirname "$repo_root")}"
clone_root="$projects_root/SESC_IT"

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

# Values correspond to the custom images referenced by Argo CD applications.
declare -a projects=(
  "document-renderer|Document-Renderer-Backend|https://github.com/SESC-IT-Team/Document-Renderer-Backend.git"
  "lyceum-auth-admin-frontend|Lyceum-Auth-Admin-Frontend|https://github.com/SESC-IT-Team/Lyceum-Auth-Admin-Frontend.git"
  "lyceum-auth-admin-backend|Lyceum-Auth-Admin-Backend|https://github.com/SESC-IT-Team/Lyceum-Auth-Admin-Backend.git"
  "sesc-portal|sesc-portal|https://github.com/SESC-IT-Team/sesc-portal.git"
  "spravki-backend|Spravki-Backend|https://github.com/SESC-IT-Team/Spravki-Backend.git"
  "spravki-frontend|Spravki-Frontend|https://github.com/SESC-IT-Team/Spravki-Frontend.git"
  "technical-support-backend|Technical-Support-Backend|https://github.com/SESC-IT-Team/Technical-Support-Backend.git"
)

find_local_repo() {
  local repo_name="$1"
  local candidate
  for candidate in "$projects_root/$repo_name" "$projects_root/${repo_name//-/_}" "$projects_root/${repo_name//-/}"; do
    if [[ -d "$candidate/.git" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

ensure_repo() {
  local repo_name="$1"
  local repo_url="$2"
  local repo_path

  if [[ -z "$repo_url" ]]; then
    echo "Skipping $repo_name: repository URL is not configured" >&2
    return 2
  fi

  if repo_path="$(find_local_repo "$repo_name")"; then
    printf '%s\n' "$repo_path"
    return 0
  fi

  mkdir -p "$clone_root"
  repo_path="$clone_root/$repo_name"
  if [[ -e "$repo_path" ]]; then
    echo "Cannot clone $repo_name: $repo_path already exists and is not a Git repository" >&2
    return 1
  fi
  echo "Cloning $repo_url into $repo_path" >&2
  git clone "$repo_url" "$repo_path" >&2
  printf '%s\n' "$repo_path"
}

build_and_push() {
  local image_name="$1"
  local repo_name="$2"
  local repo_url="$3"
  local component="${4:-}"
  local repo_path
  local context
  local dockerfile
  local tag

  if [[ -z "$repo_url" ]]; then
    echo "Skipping $image_name: repository URL is not configured" >&2
    skipped_projects+=("$image_name")
    return 0
  fi

  if repo_path="$(ensure_repo "$repo_name" "$repo_url")"; then
    :
  else
    local ensure_repo_exit_code=$?
    if [[ "$ensure_repo_exit_code" -eq 2 ]]; then
      skipped_projects+=("$image_name")
      return 0
    fi
    return "$ensure_repo_exit_code"
  fi
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
  IFS='|' read -r image_name repo_name repo_url component <<< "$project"
  build_and_push "$image_name" "$repo_name" "$repo_url" "${component:-}"
done

echo "All application images were built and pushed to $registry_domain"
if ((${#skipped_projects[@]} > 0)); then
  echo "Skipped images: ${skipped_projects[*]}" >&2
fi