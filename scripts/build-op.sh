#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_dir/.." && pwd)"
target="${1:-all}"
output_directory="${2:-$repository_root/dist}"

case "$target" in
  trackmania|turbo) targets=("$target") ;;
  all) targets=(trackmania turbo) ;;
  *) echo "Error: target must be trackmania, turbo, or all" >&2; exit 1 ;;
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
  if [[ "$game" == "trackmania" ]]; then
    manifest="$repository_root/info.toml"
  else
    manifest="$repository_root/manifests/info.turbo.toml"
  fi
  if [[ ! -f "$manifest" ]]; then
    echo "Error: Could not find $manifest" >&2
    exit 1
  fi

  name="$(read_meta_value "$manifest" name)"
  version="$(read_meta_value "$manifest" version)"
  if [[ -z "$name" || -z "$version" ]]; then
    echo "Error: Could not read plugin name or version from $manifest" >&2
    exit 1
  fi
  slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
  artifact="$output_directory/$slug-$game-v$version.op"
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
