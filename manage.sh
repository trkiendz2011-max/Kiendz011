#!/usr/bin/env bash
# Small command dispatcher and interactive menu around the VM scripts.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "$ROOT_DIR/scripts/common.sh"

usage() {
  cat <<'EOF'
Dùng:
  bash scripts/manage.sh <lệnh> <os> [tham số...]
  bash scripts/manage.sh            # menu tương tác

Lệnh: create | start | stop | status | snapshot | url | list

Ví dụ:
  bash scripts/manage.sh create win11
  bash scripts/manage.sh start win11
  bash scripts/manage.sh stop win11
  bash scripts/manage.sh snapshot win11 create truoc-khi-cai-game
EOF
}

choose_os() {
  local choice
  # Menu text goes to stderr so command substitution captures only the OS id.
  printf 'Chọn Windows:\n' >&2
  printf '  1) Windows 10 Pro\n' >&2
  printf '  2) Windows 11 Pro\n' >&2
  printf '  3) Windows 11 Enterprise LTSC 2024 (eval)\n' >&2
  printf '  4) Windows Server 2022\n' >&2
  read -rp 'Nhập số (1-4): ' choice || exit 0
  case "$choice" in
    1) printf 'win10' ;;
    2) printf 'win11' ;;
    3) printf 'win11-ltsc' ;;
    4) printf 'server2022' ;;
    *) die "Lựa chọn không hợp lệ: $choice" ;;
  esac
}

# Interactive actions should return to the menu instead of killing it.
run_child() {
  if ! "$@"; then
    warn "Lệnh thất bại; menu vẫn tiếp tục. Xem lỗi phía trên."
  fi
}

dispatch() {
  local action="$1"
  shift
  case "$action" in
    create|start|run|stop|snapshot|snap)
      local os="${1:-}"
      [[ -n "$os" ]] || os="$(choose_os)"
      [[ -n "${1:-}" ]] && shift
      case "$action" in
        create) bash "$ROOT_DIR/scripts/create-vm.sh" "$os" "$@" ;;
        start|run) bash "$ROOT_DIR/scripts/run-vm.sh" "$os" "$@" ;;
        stop) bash "$ROOT_DIR/scripts/stop-vm.sh" "$os" "$@" ;;
        snapshot|snap) bash "$ROOT_DIR/scripts/snapshot.sh" "$os" "$@" ;;
      esac
      ;;
    status)
      bash "$ROOT_DIR/scripts/status.sh" "$@"
      ;;
    url)
      printf '%s\n' "$(codespaces_vnc_url "$VNC_PORT")"
      ;;
    list|ls)
      for id in $(list_os); do
        os_config "$id"
        if [[ -d "$VM_DIR/$id" ]]; then
          if is_running "$id"; then
            printf '%-12s %s\n' "$id" "đang chạy"
          else
            printf '%-12s %s\n' "$id" "đã tắt"
          fi
        else
          printf '%-12s %s\n' "$id" "chưa tạo"
        fi
      done
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

if (( $# > 0 )); then
  dispatch "$@"
  exit 0
fi

if [[ ! -t 0 ]]; then
  usage
  exit 1
fi

while true; do
  printf '\n%s╔══════════════════════════════════════╗%s\n' "$C_CYAN" "$C_RESET"
  printf '%s║      WinVM Codespaces VIP Menu       ║%s\n' "$C_CYAN" "$C_RESET"
  printf '%s╚══════════════════════════════════════╝%s\n' "$C_CYAN" "$C_RESET"
  printf '  1) Tạo máy ảo\n'
  printf '  2) Bật máy ảo + noVNC\n'
  printf '  3) Tắt máy ảo\n'
  printf '  4) Xem trạng thái\n'
  printf '  5) Snapshot\n'
  printf '  6) In link noVNC\n'
  printf '  0) Thoát\n'
  read -rp 'Chọn: ' choice || exit 0
  case "$choice" in
    1) os="$(choose_os)"; run_child bash "$ROOT_DIR/scripts/create-vm.sh" "$os" ;;
    2) os="$(choose_os)"; run_child bash "$ROOT_DIR/scripts/run-vm.sh" "$os" ;;
    3) os="$(choose_os)"; run_child bash "$ROOT_DIR/scripts/stop-vm.sh" "$os" ;;
    4) run_child bash "$ROOT_DIR/scripts/status.sh" ;;
    5)
      os="$(choose_os)"
      read -rp 'Thao tác (create/list/restore): ' snap_action || exit 0
      if [[ "$snap_action" == "restore" ]]; then
        read -rp 'Tên snapshot: ' snap_name || exit 0
        run_child bash "$ROOT_DIR/scripts/snapshot.sh" "$os" restore "$snap_name"
      else
        run_child bash "$ROOT_DIR/scripts/snapshot.sh" "$os" "$snap_action"
      fi
      ;;
    6) codespaces_vnc_url "$VNC_PORT" ;;
    0) exit 0 ;;
    *) warn "Lựa chọn không hợp lệ." ;;
  esac
done
