#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_dir/.." && pwd)"
target="${1:-all}"
output_directory="${2:-$repository_root/dist}"

case "$target" in
  all) targets=(next turbo) ;;
  next|turbo) targets=("$target") ;;
  *) echo "Error: target must be all, next, or turbo" >&2; exit 1 ;;
esac

if [[ ! -d "$repository_root/src" ]]; then
  echo "Error: Could not find $repository_root/src" >&2
  exit 1
fi
if ! command -v zip >/dev/null 2>&1; then
  echo "Error: zip is required to package the plugin" >&2
  exit 1
fi

read_meta_value() {
  local manifest="$1"
  local key="$2"
  awk -F '=' -v key="$key" '
    /^\[meta\]/ { in_meta = 1; next }
    /^\[/ { in_meta = 0 }
    in_meta && $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$manifest"
}

mkdir -p "$output_directory"
output_directory="$(cd -- "$output_directory" && pwd)"
staging_root="$(mktemp -d)"
trap 'rm -rf -- "$staging_root"' EXIT

for game in "${targets[@]}"; do
  if [[ "$game" == "next" ]]; then
    manifest="$repository_root/info.next.toml"
  else
    manifest="$repository_root/info.turbo.toml"
  fi
  if [[ ! -f "$manifest" ]]; then
    echo "Error: Could not find $manifest" >&2
    exit 1
  fi

  if [[ "$game" == "next" ]]; then
    artifact="$output_directory/chugmania-webhooks-next.op"
  else
    artifact="$output_directory/chugmania-webhooks-turbo.op"
  fi
  staging="$staging_root/$game"

  mkdir -p "$staging"
  cp "$manifest" "$staging/info.toml"
  cp -R "$repository_root/src" "$staging/src"
  rm -f -- "$artifact"
  (
    cd -- "$staging"
    zip -rq "$artifact" info.toml src
  )
  printf 'Created %s\n' "$artifact"
done
