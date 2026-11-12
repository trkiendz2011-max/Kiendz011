#!/usr/bin/env bash
# Stop a VM gracefully (ACPI via QMP), then clean up noVNC/swtpm.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "$ROOT_DIR/scripts/common.sh"

usage() {
  cat <<'EOF'
Dùng:
  bash scripts/stop-vm.sh <win10|win11|win11-ltsc|server2022> [--timeout GIÂY]

Mặc định chờ 120 giây để Windows tắt an toàn, sau đó mới kill.
EOF
}

os=""
timeout="120"
while (( $# > 0 )); do
  case "$1" in
    win10|win11|win11-ltsc|server2022) os="$1"; shift ;;
    --timeout) timeout="${2:-}"; [[ "$timeout" =~ ^[0-9]+$ ]] || die "--timeout cần số giây"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Tham số không hợp lệ: $1" ;;
  esac
done
[[ -n "$os" ]] || { usage; exit 1; }
os_config "$os"

dir="$VM_DIR/$os"
qmp="$dir/qmp.sock"

stop_pidfile() {
  local file="$1" label="$2" pid
  [[ -f "$file" ]] || return 0
  pid="$(cat "$file" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.25
    done
    kill -9 "$pid" 2>/dev/null || true
    info "Đã dừng $label."
  fi
  rm -f "$file"
}

if ! is_running "$os"; then
  info "$OS_LABEL không chạy."
  stop_pidfile "$dir/websockify.pid" "noVNC"
  stop_pidfile "$dir/swtpm.pid" "swtpm"
  rm -f "$dir/qemu.pid" "$qmp" "$dir/swtpm.sock"
  exit 0
fi

info "Gửi lệnh tắt ACPI tới $OS_LABEL..."
if [[ -S "$qmp" ]] && command -v python3 >/dev/null 2>&1; then
  python3 - "$qmp" <<'PY' || true
import json
import socket
import sys

path = sys.argv[1]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(5)
s.connect(path)
f = s.makefile("rwb", buffering=0)
f.readline()  # QMP greeting
for command in ("qmp_capabilities", "system_powerdown"):
    f.write((json.dumps({"execute": command}) + "\n").encode())
    f.readline()
PY
else
  warn "Không thấy QMP socket; sẽ gửi tín hiệu TERM."
fi

pid="$(cat "$dir/qemu.pid" 2>/dev/null || true)"
deadline=$((SECONDS + timeout))
while (( SECONDS < deadline )); do
  if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
    break
  fi
  sleep 1
done

if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
  warn "Windows chưa tắt sau ${timeout}s. Gửi TERM..."
  kill "$pid" 2>/dev/null || true
  sleep 5
  kill -9 "$pid" 2>/dev/null || true
fi

stop_pidfile "$dir/websockify.pid" "noVNC"
stop_pidfile "$dir/swtpm.pid" "swtpm"
rm -f "$dir/qemu.pid" "$qmp" "$dir/swtpm.sock" "$dir/qemu-launch.log"
log "Đã tắt $OS_LABEL."
