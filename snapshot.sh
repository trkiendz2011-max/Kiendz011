#!/usr/bin/env bash
# Manage qcow2 internal snapshots. The VM must be stopped.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "$ROOT_DIR/scripts/common.sh"

usage() {
  cat <<'EOF'
Dùng:
  bash scripts/snapshot.sh <os> create [tên]
  bash scripts/snapshot.sh <os> list
  bash scripts/snapshot.sh <os> restore <tên>

<os>: win10 | win11 | win11-ltsc | server2022
Phải tắt máy ảo trước khi tạo/khôi phục snapshot.
EOF
}

os="${1:-}"
action="${2:-}"
name="${3:-}"

if [[ -z "$os" || -z "$action" ]]; then
  usage
  exit 1
fi
os_config "$os"
require_cmd qemu-img

dir="$VM_DIR/$os"
disk="$dir/disk.qcow2"
[[ -f "$disk" ]] || die "Chưa có disk cho $OS_LABEL. Chạy create-vm.sh trước."

if is_running "$os"; then
  die "$OS_LABEL đang chạy. Tắt trước: bash scripts/stop-vm.sh $os"
fi

case "$action" in
  create)
    name="${name:-snap-$(date +%Y%m%d-%H%M%S)}"
    info "Tạo snapshot '$name'..."
    qemu-img snapshot -c "$name" "$disk"
    log "Đã tạo snapshot '$name'."
    ;;
  list)
    qemu-img snapshot -l "$disk"
    ;;
  restore)
    [[ -n "$name" ]] || die "Thiếu tên snapshot. Dùng: snapshot.sh $os list"
    info "Khôi phục snapshot '$name'..."
    qemu-img snapshot -a "$name" "$disk"
    log "Đã khôi phục '$name'."
    ;;
  *)
    usage
    exit 1
    ;;
esac
