#!/usr/bin/env bash
# Shared helpers for the WinVM Codespaces VIP toolkit.
# This file is meant to be sourced, not executed directly.

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_DIR="${ISO_DIR:-$ROOT_DIR/iso}"
VM_DIR="${VM_DIR:-$ROOT_DIR/vm}"
GUEST_DIR="${GUEST_DIR:-$ROOT_DIR/guest}"
TOOLS_DIR="${TOOLS_DIR:-$ROOT_DIR/.tools}"
export GUEST_DIR

VNC_PORT="${VNC_PORT:-6080}"
VNC_DISPLAY="${VNC_DISPLAY:-0}"
RDP_PORT="${RDP_PORT:-3389}"
SSH_PORT="${SSH_PORT:-2222}"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'; C_MAGENTA=$'\033[35m'
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""
  C_BLUE=""; C_CYAN=""; C_MAGENTA=""
fi
export C_RESET C_BOLD C_RED C_GREEN C_YELLOW C_BLUE C_CYAN C_MAGENTA

log()  { printf '%s[OK]%s %s\n'   "$C_GREEN"  "$C_RESET" "$*"; }
info() { printf '%s[..]%s %s\n'   "$C_CYAN"   "$C_RESET" "$*" >&2; }
warn() { printf '%s[!]%s %s\n'    "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%s[X]%s %s\n'    "$C_RED"    "$C_RESET" "$*" >&2; exit 1; }

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "Thiếu lệnh '$cmd'. Chạy: bash scripts/setup.sh"
  done
}

list_os() {
  printf '%s\n' win10 win11 win11-ltsc server2022
}

codespaces_vnc_url() {
  local port="${1:-$VNC_PORT}"
  if [[ -n "${CODESPACE_NAME:-}" && -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]]; then
    printf 'https://%s-%s.%s/vnc.html?autoconnect=true&resize=scale\n' \
      "$CODESPACE_NAME" "$port" "$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN"
  else
    printf 'http://localhost:%s/vnc.html?autoconnect=true&resize=scale\n' "$port"
  fi
}

host_cpus() {
  nproc 2>/dev/null || echo 2
}

host_mem_mb() {
  awk '/^MemTotal:/ { printf "%d\n", $2 / 1024 }' /proc/meminfo
}

free_disk_gb() {
  df -Pk "$ROOT_DIR" | awk 'NR==2 { printf "%d\n", $4 / 1024 / 1024 }'
}

detect_accel() {
  if [[ -r /dev/kvm && -w /dev/kvm ]] && command -v qemu-system-x86_64 >/dev/null 2>&1; then
    if qemu-system-x86_64 -accel help 2>/dev/null | grep -qx 'kvm'; then
      printf 'kvm\n'
      return 0
    fi
  fi
  printf 'tcg,thread=multi\n'
}

os_config() {
  local os="${1:-}"
  case "$os" in
    win10)
      OS_ID="win10"
      OS_LABEL="Windows 10 Pro"
      OS_EDITION_INDEX="6"
      OS_DISK_GB="40"
      OS_RAM_MB="4096"
      OS_TPM="false"
      OS_ISO_NAME="win10.iso"
      OS_UNATTEND="win10.xml"
      OS_COLOR="$C_BLUE"
      ;;
    win11)
      OS_ID="win11"
      OS_LABEL="Windows 11 Pro"
      OS_EDITION_INDEX="6"
      OS_DISK_GB="40"
      OS_RAM_MB="4096"
      OS_TPM="true"
      OS_ISO_NAME="win11.iso"
      OS_UNATTEND="win11.xml"
      OS_COLOR="$C_CYAN"
      ;;
    win11-ltsc)
      OS_ID="win11-ltsc"
      OS_LABEL="Windows 11 Enterprise LTSC 2024 (eval)"
      OS_EDITION_INDEX="1"
      OS_DISK_GB="40"
      OS_RAM_MB="4096"
      OS_TPM="true"
      OS_ISO_NAME="win11-ltsc.iso"
      OS_UNATTEND="win11-ltsc.xml"
      OS_COLOR="$C_CYAN"
      ;;
    server2022)
      OS_ID="server2022"
      OS_LABEL="Windows Server 2022 (Desktop Experience)"
      OS_EDITION_INDEX="4"
      OS_DISK_GB="32"
      OS_RAM_MB="4096"
      OS_TPM="false"
      OS_ISO_NAME="server2022.iso"
      OS_UNATTEND="server2022.xml"
      OS_COLOR="$C_MAGENTA"
      ;;
    *)
      die "Hệ điều hành không hợp lệ: '${os}'. Dùng: win10 | win11 | win11-ltsc | server2022"
      ;;
  esac

  # Give the VM more RAM on a 16 GB Codespaces machine.
  if (( $(host_mem_mb) >= 15000 )) && (( OS_RAM_MB < 6144 )); then
    OS_RAM_MB="6144"
  fi

  export OS_ID OS_LABEL OS_EDITION_INDEX OS_DISK_GB OS_RAM_MB OS_TPM
  export OS_ISO_NAME OS_UNATTEND OS_COLOR
}

find_iso() {
  local os="$1" f
  os_config "$os"

  local candidates=("$ISO_DIR/$OS_ISO_NAME")
  case "$os" in
    win10)
      candidates+=("$ISO_DIR"/Win10*.iso "$ISO_DIR"/win10*.iso "$ISO_DIR"/*Win10*.iso)
      ;;
    win11)
      candidates+=("$ISO_DIR"/Win11*.iso "$ISO_DIR"/win11*.iso)
      ;;
    win11-ltsc)
      # Never fall back to a generic Win11 ISO: its image index 1 is not LTSC.
      candidates+=("$ISO_DIR"/*LTSC*.iso "$ISO_DIR"/*ltsc*.iso)
      ;;
    server2022)
      candidates+=("$ISO_DIR"/*Server*2022*.iso "$ISO_DIR"/*server*2022*.iso)
      ;;
  esac

  for f in "${candidates[@]}"; do
    if [[ -f "$f" && -s "$f" ]]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

iso_volume_id() {
  local iso="$1"
  isoinfo -d -i "$iso" 2>/dev/null \
    | sed -n 's/^Volume id: *//p' \
    | head -n 1 \
    | tr -d '\r'
}

iso_has_windows_image() {
  local iso="$1" listing
  # Official Microsoft ISOs store the payload in UDF, where isoinfo only sees
  # the ISO9660 bridge (README.TXT). 7z reads UDF, so try it first.
  if command -v 7z >/dev/null 2>&1; then
    listing="$(7z l -ba "$iso" 2>/dev/null || true)"
    if grep -qiE 'sources[\\/]install\.(wim|esd)' <<<"$listing"; then
      return 0
    fi
  fi
  listing="$(isoinfo -J -f -i "$iso" 2>/dev/null || isoinfo -f -i "$iso" 2>/dev/null || true)"
  grep -qiE 'sources/install\.(wim|esd)' <<<"$listing"
}

# Fail closed when the ISO does not match the requested Windows edition.
# Set VIP_SKIP_ISO_CHECK=1 only for unusual media you trust.
validate_iso_for_os() {
  local os="$1" iso="$2" volume label
  ISO_VOLUME_ID=""

  [[ -f "$iso" ]] || die "Không thấy ISO: $iso"
  [[ -s "$iso" ]] || die "ISO rỗng: $iso"

  if [[ "${VIP_SKIP_ISO_CHECK:-0}" == "1" ]]; then
    warn "Bỏ qua kiểm tra edition ISO (VIP_SKIP_ISO_CHECK=1)."
    return 0
  fi

  command -v isoinfo >/dev/null 2>&1 \
    || die "Thiếu isoinfo (gói genisoimage). Chạy: bash scripts/setup.sh"

  iso_has_windows_image "$iso" \
    || die "File không giống ISO cài Windows (thiếu sources/install.wim hoặc install.esd): $iso. Nếu là ISO Microsoft chính thức, cài p7zip-full để đọc UDF: sudo apt-get install -y p7zip-full"

  volume="$(iso_volume_id "$iso")"
  ISO_VOLUME_ID="$volume"
  export ISO_VOLUME_ID
  label="${volume^^}"

  # Official Microsoft eval labels verified 2026-11-12:
  #   Win11 Enterprise LTSC 2024 eval -> CESE_X64FREE_EN-US_DV9
  #   Windows Server 2022 eval       -> SSS_X64FREE_EN-US_DV9
  # Older/manual media may use LTSC, ENTERPRISEEVAL or SERVER labels instead.
  case "$os" in
    win11-ltsc)
      [[ "$label" == *LTSC* || "$label" == *ENTERPRISEEVAL* || "$label" == CESE_* ]] \
        || die "ISO không phải $OS_LABEL (volume: '${volume:-không rõ}'). Dùng ISO LTSC eval chính thức hoặc đặt đúng file $OS_ISO_NAME."
      ;;
    server2022)
      [[ "$label" == *SERVER* || "$label" == SSS_* ]] \
        || die "ISO không phải $OS_LABEL (volume: '${volume:-không rõ}'). Dùng ISO Server eval chính thức hoặc đặt đúng file $OS_ISO_NAME."
      ;;
    win10|win11)
      if [[ "$label" == *SERVER* || "$label" == *LTSC* || "$label" == *ENTERPRISEEVAL* || "$label" == CESE_* || "$label" == SSS_* ]]; then
        die "ISO là bản Server/LTSC/eval, không phù hợp với $OS_LABEL (volume: '${volume:-không rõ}')."
      fi
      ;;
  esac
}

vm_dir() {
  local os="$1"
  local dir="$VM_DIR/$os"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

is_running() {
  local os="$1"
  local pidfile="$VM_DIR/$os/qemu.pid"
  local pid
  [[ -f "$pidfile" ]] || return 1
  pid="$(cat "$pidfile" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# A pidfile left by a killed QEMU must not block the next start.
clear_stale_pid() {
  local os="$1"
  local pidfile="$VM_DIR/$os/qemu.pid"
  if [[ -f "$pidfile" ]] && ! is_running "$os"; then
    rm -f "$pidfile"
  fi
}

require_not_running() {
  local os="$1"
  if is_running "$os"; then
    die "$OS_LABEL đang chạy. Dùng: bash scripts/stop-vm.sh $os"
  fi
}

qemu_bin() {
  if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    printf 'qemu-system-x86_64\n'
  else
    die "Chưa cài QEMU. Chạy: bash scripts/setup.sh"
  fi
}

ovmf_code_path() {
  local p
  for p in \
    /usr/share/OVMF/OVMF_CODE_4M.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/edk2/ovmf/OVMF_CODE.fd \
    /usr/share/qemu/OVMF_CODE.fd; do
    [[ -f "$p" ]] && { printf '%s\n' "$p"; return 0; }
  done
  die "Không tìm thấy OVMF. Chạy: bash scripts/setup.sh"
}

ovmf_vars_template() {
  local p
  for p in \
    /usr/share/OVMF/OVMF_VARS_4M.fd \
    /usr/share/OVMF/OVMF_VARS.fd \
    /usr/share/edk2/ovmf/OVMF_VARS.fd \
    /usr/share/qemu/OVMF_VARS.fd; do
    [[ -f "$p" ]] && { printf '%s\n' "$p"; return 0; }
  done
  die "Không tìm thấy OVMF_VARS. Chạy: bash scripts/setup.sh"
}

now_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

human_gb() {
  printf '%s GB\n' "$1"
}
