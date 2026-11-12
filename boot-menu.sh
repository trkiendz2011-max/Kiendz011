#!/usr/bin/env bash
# Interactive Vietnamese menu for the whole VM lifecycle.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "$ROOT_DIR/scripts/common.sh"

usage() {
  cat <<'EOF'
Dùng:
  bash scripts/boot-menu.sh

Menu VIP cho các máy ảo:
  win10        Windows 10 Pro
  win11        Windows 11 Pro
  win11-ltsc   Windows 11 Enterprise LTSC 2024 (eval)
  server2022   Windows Server 2022 (Desktop Experience)

Chức năng: Tạo máy ảo, Bật máy ảo, Tắt máy ảo, Trạng thái,
Snapshot, mở noVNC, tải ISO và cài dependency.

Chạy không tương tác:
  bash scripts/manage.sh <lệnh> <os>
EOF
}

CHOSEN_OS=""

choose_os() {
  local choice
  CHOSEN_OS=""
  printf '\nChọn Windows:\n'
  printf '  1) Windows 10 Pro\n'
  printf '  2) Windows 11 Pro\n'
  printf '  3) Windows 11 Enterprise LTSC 2024 (eval)\n'
  printf '  4) Windows Server 2022 (Desktop Experience)\n'
  read -rp 'Nhập số (1-4): ' choice || return 1
  case "$choice" in
    1) CHOSEN_OS="win10" ;;
    2) CHOSEN_OS="win11" ;;
    3) CHOSEN_OS="win11-ltsc" ;;
    4) CHOSEN_OS="server2022" ;;
    *) warn "Lựa chọn không hợp lệ: $choice"; return 1 ;;
  esac
  return 0
}

open_vnc() {
  local url
  url="$(codespaces_vnc_url "$VNC_PORT")"
  printf '\n  Mở màn hình Windows: %s\n' "$url"
  printf '  Trong Codespaces: tab Ports → cổng %s → Open in Browser.\n\n' "$VNC_PORT"
  if [[ -n "${CODESPACE_NAME:-}" ]] && command -v code >/dev/null 2>&1; then
    code --open-url "$url" >/dev/null 2>&1 || true
  fi
}

# A failed action must return to the menu, not kill it via set -e.
run_menu_cmd() {
  if ! "$@"; then
    warn "Lệnh thất bại; menu vẫn tiếp tục. Xem lỗi phía trên."
  fi
}

snapshot_menu() {
  local action name
  choose_os || return 0
  printf '\n  1) Tạo snapshot\n'
  printf '  2) Liệt kê snapshot\n'
  printf '  3) Khôi phục snapshot\n'
  read -rp 'Chọn (1-3): ' action || return 0
  case "$action" in
    1)
      read -rp 'Tên snapshot (Enter để tự đặt): ' name || return 0
      if [[ -n "$name" ]]; then
        run_menu_cmd bash "$ROOT_DIR/scripts/snapshot.sh" "$CHOSEN_OS" create "$name"
      else
        run_menu_cmd bash "$ROOT_DIR/scripts/snapshot.sh" "$CHOSEN_OS" create
      fi
      ;;
    2) run_menu_cmd bash "$ROOT_DIR/scripts/snapshot.sh" "$CHOSEN_OS" list ;;
    3)
      read -rp 'Tên snapshot cần khôi phục: ' name || return 0
      [[ -n "$name" ]] || { warn "Chưa nhập tên snapshot."; return 0; }
      run_menu_cmd bash "$ROOT_DIR/scripts/snapshot.sh" "$CHOSEN_OS" restore "$name"
      ;;
    *) warn "Lựa chọn không hợp lệ." ;;
  esac
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    usage >&2
    die "Tham số không hợp lệ: $1"
    ;;
esac

if [[ ! -t 0 ]]; then
  usage
  exit 1
fi

while true; do
  clear 2>/dev/null || true
  printf '%s╔══════════════════════════════════════════╗%s\n' "$C_CYAN" "$C_RESET"
  printf '%s║       WINVM CODESPACES VIP BOOT          ║%s\n' "$C_CYAN" "$C_RESET"
  printf '%s╚══════════════════════════════════════════╝%s\n' "$C_CYAN" "$C_RESET"
  printf '  1) Tạo máy ảo\n'
  printf '  2) Bật máy ảo + noVNC\n'
  printf '  3) Tắt máy ảo an toàn\n'
  printf '  4) Trạng thái các máy ảo\n'
  printf '  5) Snapshot (tạo / liệt kê / khôi phục)\n'
  printf '  6) Mở noVNC\n'
  printf '  7) Tải ISO Windows chính thức\n'
  printf '  8) Cài dependency cho Codespaces\n'
  printf '  0) Thoát\n\n'

  read -rp 'Chọn: ' choice || exit 0
  case "$choice" in
    1)
      choose_os || continue
      run_menu_cmd bash "$ROOT_DIR/scripts/create-vm.sh" "$CHOSEN_OS"
      ;;
    2)
      choose_os || continue
      run_menu_cmd bash "$ROOT_DIR/scripts/run-vm.sh" "$CHOSEN_OS"
      open_vnc
      ;;
    3)
      choose_os || continue
      run_menu_cmd bash "$ROOT_DIR/scripts/stop-vm.sh" "$CHOSEN_OS"
      ;;
    4)
      run_menu_cmd bash "$ROOT_DIR/scripts/status.sh"
      ;;
    5)
      snapshot_menu
      ;;
    6)
      open_vnc
      ;;
    7)
      choose_os || continue
      run_menu_cmd bash "$ROOT_DIR/scripts/fetch-iso.sh" "$CHOSEN_OS"
      ;;
    8)
      run_menu_cmd bash "$ROOT_DIR/scripts/setup.sh"
      ;;
    0)
      exit 0
      ;;
    *)
      warn "Lựa chọn không hợp lệ."
      ;;
  esac

  printf '\n'
  read -rp 'Nhấn Enter để tiếp tục...' _ || exit 0
done
