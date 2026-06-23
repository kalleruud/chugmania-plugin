#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_dir/.." && pwd)"
target="${1:-all}"
output_directory="${2:-$repository_root/dist}"

case "$target" in
  all|shared|unified) ;;
  *) echo "Error: target must be all, shared, or unified" >&2; exit 1 ;;
esac

if [[ ! -d "$repository_root/src" ]]; then
  echo "Error: Could not find $repository_root/src" >&2
  exit 1
fi
if ! command -v zip >/dev/null 2>&1; then
  echo "Error: zip is required to package the plugin" >&2
  exit 1
fi

mkdir -p "$output_directory"
output_directory="$(cd -- "$output_directory" && pwd)"
manifest="$repository_root/info.toml"
if [[ ! -f "$manifest" ]]; then
  echo "Error: Could not find $manifest" >&2
  exit 1
fi

artifact="$output_directory/tm-webhooks.op"
rm -f -- "$artifact"
(
  cd -- "$repository_root"
  zip -rq "$artifact" info.toml src
)
printf 'Created %s\n' "$artifact"
