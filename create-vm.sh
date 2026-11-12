#!/usr/bin/env bash
# Create a VM disk, OVMF vars, tools ISO and vm.conf for one OS.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "$ROOT_DIR/scripts/common.sh"

usage() {
  cat <<'EOF'
Dùng:
  bash scripts/create-vm.sh <win10|win11|win11-ltsc|server2022> [tùy chọn]

Tùy chọn:
  --disk-gb N   Dung lượng disk qcow2 (mặc định theo OS, thường 40)
  --ram-mb N    RAM cho VM (mặc định 4096, tự tăng 6144 nếu host >= 16 GB)
  --cpus N      Số vCPU (mặc định tối đa 4)
  --dry-run     Chỉ in kế hoạch, không ghi file
  -h, --help    Hiển thị trợ giúp
EOF
}

os=""
disk_gb=""
ram_mb=""
cpus=""
dry_run="false"

while (( $# > 0 )); do
  case "$1" in
    win10|win11|win11-ltsc|server2022) os="$1"; shift ;;
    --disk-gb) disk_gb="${2:-}"; [[ -n "$disk_gb" ]] || die "--disk-gb cần một số"; shift 2 ;;
    --ram-mb) ram_mb="${2:-}"; [[ -n "$ram_mb" ]] || die "--ram-mb cần một số"; shift 2 ;;
    --cpus) cpus="${2:-}"; [[ -n "$cpus" ]] || die "--cpus cần một số"; shift 2 ;;
    --dry-run) dry_run="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Tham số không hợp lệ: $1" ;;
  esac
done

[[ -n "$os" ]] || { usage; exit 1; }
os_config "$os"

iso="$(find_iso "$os")" || true
if [[ -z "$iso" ]]; then
  die "Chưa có ISO cho $OS_LABEL. Đặt file vào $ISO_DIR/$OS_ISO_NAME (hoặc chạy: bash scripts/fetch-iso.sh $os)."
fi
validate_iso_for_os "$os" "$iso"

disk_gb="${disk_gb:-$OS_DISK_GB}"
ram_mb="${ram_mb:-$OS_RAM_MB}"
if [[ -z "$cpus" ]]; then
  cpus="$(host_cpus)"
  (( cpus > 4 )) && cpus=4
  (( cpus < 2 )) && cpus=2
fi

[[ "$disk_gb" =~ ^[0-9]+$ ]] || die "--disk-gb phải là số nguyên"
[[ "$ram_mb" =~ ^[0-9]+$ ]] || die "--ram-mb phải là số nguyên"
[[ "$cpus" =~ ^[0-9]+$ ]] || die "--cpus phải là số nguyên"
(( disk_gb >= 20 && disk_gb <= 200 )) || die "--disk-gb phải trong khoảng 20..200"
(( ram_mb >= 2048 && ram_mb <= 16384 )) || die "--ram-mb phải trong khoảng 2048..16384"
(( cpus >= 1 && cpus <= $(host_cpus) )) || die "--cpus phải trong khoảng 1..$(host_cpus)"

accel="${ACCEL:-$(detect_accel)}"
dir="$VM_DIR/$os"
disk="$dir/disk.qcow2"
vars="$dir/OVMF_VARS.fd"
tools="$dir/tools.iso"
conf="$dir/vm.conf"

info "Kế hoạch tạo máy ảo:"
printf '  Hệ điều hành : %s\n' "$OS_LABEL"
printf '  ISO          : %s\n' "$iso"
printf '  Disk         : %s (%s GB, qcow2)\n' "$disk" "$disk_gb"
printf '  RAM / vCPU   : %s MB / %s\n' "$ram_mb" "$cpus"
printf '  Tăng tốc     : %s\n' "$accel"
printf '  UEFI vars    : %s\n' "$vars"
printf '  Tools ISO    : %s\n' "$tools"

if [[ "$dry_run" == "true" ]]; then
  printf '\n[dry-run] Không ghi file nào.\n'
  exit 0
fi

require_not_running "$os"
require_cmd qemu-img
free="$(free_disk_gb)"
if (( free < 8 )); then
  die "Chỉ còn ${free} GB trống trên host. Cần ít nhất 8 GB trước khi tạo disk."
fi

mkdir -p "$dir"

if [[ -f "$disk" ]]; then
  warn "Disk đã tồn tại, giữ nguyên: $disk"
else
  info "Tạo disk qcow2 ${disk_gb} GB..."
  qemu-img create -f qcow2 "$disk" "${disk_gb}G" >/dev/null
  log "Đã tạo $disk"
fi

if [[ -f "$vars" ]]; then
  info "OVMF_VARS đã có, giữ nguyên."
else
  cp "$(ovmf_vars_template)" "$vars"
  log "Đã tạo $vars"
fi

if [[ -f "$ROOT_DIR/scripts/build-tools-iso.sh" ]]; then
  info "Đóng gói tools ISO (autounattend + script tiếng Việt)..."
  if bash "$ROOT_DIR/scripts/build-tools-iso.sh" "$os" "$tools"; then
    log "Đã tạo $tools"
  else
    warn "Không tạo được tools ISO. Windows sẽ cài tay; xem log phía trên."
  fi
else
  warn "Chưa có scripts/build-tools-iso.sh — bỏ qua tools ISO."
fi

cat > "$conf" <<EOF
# WinVM Codespaces VIP — cấu hình máy ảo $OS_ID
OS_ID=$OS_ID
OS_LABEL="$OS_LABEL"
DISK_GB=$disk_gb
RAM_MB=$ram_mb
CPUS=$cpus
ACCEL=$accel
ISO_PATH="$iso"
ISO_LABEL="${ISO_VOLUME_ID:-unknown}"
CREATED="$(now_utc)"
EOF

log "Xong. Bật máy ảo: bash scripts/run-vm.sh $os"
