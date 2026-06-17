#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_dir/.." && pwd)"
output_directory="${1:-$repository_root/dist}"

if [[ ! -f "$repository_root/info.toml" ]]; then
  echo "Error: Could not find $repository_root/info.toml" >&2
  exit 1
fi
if [[ ! -d "$repository_root/src" ]]; then
  echo "Error: Could not find $repository_root/src" >&2
  exit 1
fi
if ! command -v zip >/dev/null 2>&1; then
  echo "Error: zip is required to package the plugin" >&2
  exit 1
fi

read_meta_value() {
  local key="$1"
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
  ' "$repository_root/info.toml"
}

name="$(read_meta_value name)"
version="$(read_meta_value version)"

if [[ -z "$name" ]]; then
  echo "Error: Could not read [meta].name from info.toml" >&2
  exit 1
fi
if [[ -z "$version" ]]; then
  echo "Error: Could not read [meta].version from info.toml" >&2
  exit 1
fi

slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
if [[ -z "$slug" ]]; then
  echo "Error: Plugin name does not produce a valid artifact slug" >&2
  exit 1
fi

mkdir -p "$output_directory"
output_directory="$(cd -- "$output_directory" && pwd)"
artifact="$output_directory/$slug-v$version.op"

rm -f -- "$artifact"
(
  cd -- "$repository_root"
  zip -rq "$artifact" info.toml src
)

printf 'Created %s\n' "$artifact"
