#!/usr/bin/env bash
# Build the second CD-ROM ISO that carries autounattend.xml and guest scripts.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "$ROOT_DIR/scripts/common.sh"

usage() {
  cat <<'EOF'
Dùng:
  bash scripts/build-tools-iso.sh <win10|win11|win11-ltsc|server2022> <output.iso>

ISO chứa:
  /autounattend.xml
  /$OEM$/$$/Setup/Scripts/*   (Windows Setup chép vào C:\Windows\Setup\Scripts)
  /scripts/*                  (bản sao để chạy tay)
EOF
}

os="${1:-}"
output="${2:-}"
[[ -n "$os" && -n "$output" ]] || { usage; exit 1; }
os_config "$os"

xml="$GUEST_DIR/autounattend/$OS_UNATTEND"
scripts_dir="$GUEST_DIR/scripts"

[[ -f "$xml" ]] || die "Không thấy autounattend: $xml"
[[ -d "$scripts_dir" ]] || die "Không thấy thư mục script guest: $scripts_dir"
[[ -f "$scripts_dir/setup-win.ps1" ]] || die "Thiếu $scripts_dir/setup-win.ps1"
require_cmd genisoimage

mkdir -p "$(dirname "$output")"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp "$xml" "$stage/autounattend.xml"

oem_scripts="$stage/\$OEM\$/\$\$/Setup/Scripts"
mkdir -p "$oem_scripts"
cp -a "$scripts_dir/." "$oem_scripts/"

mkdir -p "$stage/scripts"
cp -a "$scripts_dir/." "$stage/scripts/"

if [[ -f "$GUEST_DIR/README.txt" ]]; then
  cp "$GUEST_DIR/README.txt" "$stage/README.txt"
fi

genisoimage -quiet -input-charset utf-8 -joliet-long -J -R \
  -V "VIPTOOLS" -o "$output" "$stage"

log "Đã tạo tools ISO: $output ($(du -h "$output" | cut -f1))"
