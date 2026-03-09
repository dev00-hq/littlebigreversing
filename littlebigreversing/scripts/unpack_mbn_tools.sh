#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tools_dir="$repo_root/mbn_tools"
archive_path="$tools_dir/mbn_tools.tar.zst"
target_dir="${1:-$tools_dir}"

if [[ ! -f "$archive_path" ]]; then
  echo "Error: $archive_path not found." >&2
  exit 1
fi

if ! command -v zstd >/dev/null 2>&1; then
  echo "Error: zstd is required but was not found in PATH." >&2
  exit 1
fi

mkdir -p "$target_dir"

tar \
  --use-compress-program="zstd -d -T0" \
  -xf "$archive_path" \
  -C "$target_dir"

echo "Extracted subfolders into $target_dir"
