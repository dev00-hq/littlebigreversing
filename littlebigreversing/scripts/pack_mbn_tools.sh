#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tools_dir="$repo_root/mbn_tools"
archive_path="$tools_dir/mbn_tools.tar.zst"

if ! command -v zstd >/dev/null 2>&1; then
  echo "Error: zstd is required but was not found in PATH." >&2
  exit 1
fi

if [[ ! -d "$tools_dir" ]]; then
  echo "Error: $tools_dir not found." >&2
  exit 1
fi

subdirs=()
while IFS= read -r subdir; do
  subdirs+=("$subdir")
done < <(find "$tools_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)

if [[ "${#subdirs[@]}" -eq 0 ]]; then
  echo "Error: no subfolders found in $tools_dir." >&2
  exit 1
fi

tmp_archive="$(mktemp "${archive_path}.tmp.XXXXXX")"

cleanup() {
  rm -f "$tmp_archive"
}
trap cleanup EXIT

tar \
  --use-compress-program="zstd -19 -T0" \
  -cf "$tmp_archive" \
  -C "$tools_dir" \
  "${subdirs[@]}"

mv -f "$tmp_archive" "$archive_path"
trap - EXIT

echo "Created $archive_path"
du -h "$archive_path"
