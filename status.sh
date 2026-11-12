#!/usr/bin/env bash
# Show VM state, resources and connection details.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "$ROOT_DIR/scripts/common.sh"

usage() {
  cat <<'EOF'
Dùng:
  bash scripts/status.sh [win10|win11|win11-ltsc|server2022]

Không truyền OS: hiển thị tất cả máy ảo đã tạo.
EOF
}

os="${1:-}"
if [[ -n "$os" ]]; then
  os_config "$os"
  targets=("$os")
else
  mapfile -t targets < <(list_os)
fi

printf '\n%s=== WinVM Codespaces VIP ===%s\n\n' "$C_BOLD" "$C_RESET"

found="false"
for id in "${targets[@]}"; do
  os_config "$id"
  dir="$VM_DIR/$id"
  [[ -d "$dir" ]] || continue
  found="true"

  disk="$dir/disk.qcow2"
  conf="$dir/vm.conf"
  ram="$OS_RAM_MB"
  cpus="4"
  # Always show the accelerator QEMU would use now, not a stale stored value.
  accel="${ACCEL:-$(detect_accel)}"
  if [[ -f "$conf" ]]; then
    # shellcheck disable=SC1090
    source "$conf"
    ram="${RAM_MB:-$ram}"
    cpus="${CPUS:-$cpus}"
  fi

  if is_running "$id"; then
    state="${C_GREEN}đang chạy${C_RESET}"
    pid="$(cat "$dir/qemu.pid" 2>/dev/null || echo '?')"
  else
    state="${C_YELLOW}đã tắt${C_RESET}"
    pid="-"
  fi

  printf '%s%s%s\n' "$C_BOLD" "$OS_LABEL" "$C_RESET"
  printf '  Trạng thái : %b (pid %s)\n' "$state" "$pid"
  printf '  RAM / vCPU : %s MB / %s\n' "$ram" "$cpus"
  printf '  Tăng tốc   : %s\n' "$accel"
  if [[ -f "$disk" ]]; then
    apparent="$(du -h --apparent-size "$disk" 2>/dev/null | cut -f1)"
    actual="$(du -h "$disk" 2>/dev/null | cut -f1)"
    printf '  Disk       : %s (thực tế %s / danh nghĩa %s)\n' "$disk" "$actual" "$apparent"
  else
    printf '  Disk       : chưa tạo\n'
  fi
  if [[ -f "$dir/tools.iso" ]]; then
    printf '  Tools ISO  : có\n'
  else
    printf '  Tools ISO  : thiếu (chạy lại create-vm.sh)\n'
  fi
  if is_running "$id"; then
    printf '  noVNC      : %s\n' "$(codespaces_vnc_url "$VNC_PORT")"
    printf '  RDP        : localhost:%s → Windows:3389\n' "$RDP_PORT"
  fi
  printf '\n'
done

if [[ "$found" == "false" ]]; then
  info "Chưa có máy ảo nào. Tạo trước: bash scripts/create-vm.sh win11"
  exit 0
fi
