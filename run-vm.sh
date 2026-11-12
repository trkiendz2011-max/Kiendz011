#!/usr/bin/env bash
# Start one VM with QEMU and expose its VNC display through noVNC.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "$ROOT_DIR/scripts/common.sh"

usage() {
  cat <<'EOF'
Dùng:
  bash scripts/run-vm.sh <win10|win11|win11-ltsc|server2022> [--dry-run]

--dry-run chỉ in lệnh QEMU, không khởi động gì.
EOF
}

os=""
dry_run="false"
while (( $# > 0 )); do
  case "$1" in
    win10|win11|win11-ltsc|server2022) os="$1"; shift ;;
    --dry-run) dry_run="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Tham số không hợp lệ: $1" ;;
  esac
done
[[ -n "$os" ]] || { usage; exit 1; }
os_config "$os"

dir="$VM_DIR/$os"
conf="$dir/vm.conf"
disk="$dir/disk.qcow2"
iso="$(find_iso "$os")" || true
tools="$dir/tools.iso"
vars="$dir/OVMF_VARS.fd"

env_accel="${ACCEL:-}"
if [[ -f "$conf" ]]; then
  # shellcheck disable=SC1090
  source "$conf"
fi
DISK_GB="${DISK_GB:-$OS_DISK_GB}"
RAM_MB="${RAM_MB:-$OS_RAM_MB}"
CPUS="${CPUS:-4}"
# Detect acceleration at run time; a value stored by create-vm.sh may be stale.
ACCEL="${env_accel:-$(detect_accel)}"
ISO_PATH="${ISO_PATH:-$iso}"

[[ -n "$ISO_PATH" ]] || die "Chưa có ISO cho $OS_LABEL. Đặt file vào $ISO_DIR/$OS_ISO_NAME hoặc chạy fetch-iso.sh."
validate_iso_for_os "$os" "$ISO_PATH"

if [[ "$dry_run" != "true" ]]; then
  [[ -f "$disk" ]] || die "Chưa có disk. Chạy trước: bash scripts/create-vm.sh $os"
  [[ -f "$vars" ]] || die "Không thấy OVMF_VARS: $vars. Chạy lại create-vm.sh."
  clear_stale_pid "$os"
  require_not_running "$os"
fi

qemu="$(qemu_bin)"
ovmf_code="$(ovmf_code_path)"
if [[ "$dry_run" != "true" ]]; then
  require_cmd websockify
fi

args=(
  -name "WinVM VIP - $OS_LABEL"
  # q35 exposes the ICH9 AHCI controller; Windows has an inbox AHCI driver.
  -machine q35
  -accel "$ACCEL"
  -cpu max
  -smp "$CPUS,sockets=1,cores=$CPUS,threads=1"
  -m "$RAM_MB"
  -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
  -drive "if=pflash,format=raw,file=$vars"
  -drive "file=$disk,if=none,id=disk0,format=qcow2,cache=writeback"
  -device "ide-hd,drive=disk0,bus=ide.0"
  -drive "file=$ISO_PATH,media=cdrom,readonly=on,if=none,id=cd0"
  -device "ide-cd,drive=cd0,bus=ide.1"
  -boot "order=c,menu=off"
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$RDP_PORT-:3389,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22"
  -device "e1000,netdev=net0"
  -device VGA
  -usb
  -device usb-tablet
  -rtc "base=localtime,clock=host"
  -vnc "127.0.0.1:$VNC_DISPLAY"
  -qmp "unix:$dir/qmp.sock,server=on,wait=off"
  -pidfile "$dir/qemu.pid"
  -daemonize
)

if [[ -f "$tools" || "$dry_run" == "true" ]]; then
  args+=(
    -drive "file=$tools,media=cdrom,readonly=on,if=none,id=cd1"
    -device "ide-cd,drive=cd1,bus=ide.2"
  )
fi

if [[ "$OS_TPM" == "true" ]]; then
  args+=(
    -chardev "socket,id=chrtpm,path=$dir/swtpm.sock"
    -tpmdev "emulator,id=tpm0,chardev=chrtpm"
    -device "tpm-tis,tpmdev=tpm0"
  )
fi

if [[ "$dry_run" == "true" ]]; then
  printf '%s ' "$qemu" "${args[@]}"
  printf '\n'
  exit 0
fi

# Any websockify from a previous run is stale here: no VM is running.
if [[ -f "$dir/websockify.pid" ]]; then
  old_ws="$(cat "$dir/websockify.pid" 2>/dev/null || true)"
  [[ -n "$old_ws" ]] && kill "$old_ws" 2>/dev/null || true
  rm -f "$dir/websockify.pid"
fi

port_in_use() {
  ss -ltn 2>/dev/null | awk 'NR > 1 { print $4 }' | grep -qE "[:.]$1$"
}
if port_in_use "$VNC_PORT"; then
  die "Cổng $VNC_PORT đang bận. Tắt tiến trình đang dùng cổng rồi thử lại."
fi

rm -f "$dir/qemu.pid" "$dir/qmp.sock"

if [[ "$OS_TPM" == "true" ]]; then
  require_cmd swtpm
  mkdir -p "$dir/tpm"
  rm -f "$dir/swtpm.sock" "$dir/swtpm.pid"
  info "Khởi động swtpm (TPM 2.0)..."
  swtpm socket --tpm2 \
    --tpmstate "dir=$dir/tpm" \
    --ctrl "type=unixio,path=$dir/swtpm.sock" \
    --pid "file=$dir/swtpm.pid" \
    --log "file=$dir/swtpm.log" \
    --daemon
fi

info "Khởi động QEMU ($ACCEL)..."
if ! "$qemu" "${args[@]}" 2>"$dir/qemu-launch.log"; then
  warn "QEMU không khởi động được. Log:"
  tail -n 20 "$dir/qemu-launch.log" >&2 || true
  [[ -f "$dir/swtpm.pid" ]] && kill "$(cat "$dir/swtpm.pid")" 2>/dev/null || true
  die "Khởi động QEMU thất bại."
fi

sleep 1
if ! is_running "$os"; then
  warn "QEMU thoát ngay sau khi khởi động. Log:"
  tail -n 20 "$dir/qemu-launch.log" >&2 || true
  die "Máy ảo không chạy."
fi

web_root=""
for p in /usr/share/novnc /usr/share/novnc/utils/../; do
  [[ -d "$p" ]] && { web_root="$p"; break; }
done
if [[ -z "$web_root" ]]; then
  warn "Không thấy thư mục web noVNC (/usr/share/novnc). Chạy: bash scripts/setup.sh"
fi

info "Khởi động noVNC trên cổng $VNC_PORT..."
ws_args=(--web "$web_root" "$VNC_PORT" "127.0.0.1:590$VNC_DISPLAY")
if [[ -z "$web_root" ]]; then
  ws_args=("$VNC_PORT" "127.0.0.1:590$VNC_DISPLAY")
fi
nohup websockify "${ws_args[@]}" >"$dir/websockify.log" 2>&1 &
echo $! > "$dir/websockify.pid"
sleep 1
if ! kill -0 "$(cat "$dir/websockify.pid")" 2>/dev/null; then
  warn "noVNC không chạy. Log: $dir/websockify.log"
  tail -n 10 "$dir/websockify.log" >&2 || true
fi

url="$(codespaces_vnc_url "$VNC_PORT")"
log "$OS_LABEL đang chạy."
printf '\n  Mở màn hình Windows: %s\n' "$url"
printf '  Trong Codespaces: tab Ports → cổng %s → Open in Browser.\n' "$VNC_PORT"
printf '  Tắt máy an toàn: bash scripts/stop-vm.sh %s\n\n' "$os"
