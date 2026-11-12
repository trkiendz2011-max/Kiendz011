#!/usr/bin/env bash
# Install host dependencies inside GitHub Codespaces (Ubuntu).
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "$ROOT_DIR/scripts/common.sh"

SUDO=""
if (( EUID != 0 )); then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    die "Cần quyền root hoặc sudo để cài gói."
  fi
fi

install_pwsh() {
  if command -v pwsh >/dev/null 2>&1 \
    && pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' >/dev/null 2>&1; then
    log "PowerShell 7 đã có: $(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null)"
    return 0
  fi

  info "Cài PowerShell 7 (dùng để lấy link ISO chính thức)..."
  local version url tmp arch
  version="$(curl -fsSL --retry 3 https://api.github.com/repos/PowerShell/PowerShell/releases/latest \
    | jq -r '.tag_name // empty' | sed 's/^v//')" || true
  if [[ -z "$version" ]]; then
    warn "Không lấy được phiên bản PowerShell. Bỏ qua; có thể dùng fetch-iso.sh --url."
    return 1
  fi

  case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      warn "Kiến trúc $(uname -m) chưa hỗ trợ PowerShell; dùng fetch-iso.sh --url."
      return 1
      ;;
  esac

  url="https://github.com/PowerShell/PowerShell/releases/download/v${version}/powershell-${version}-linux-${arch}.tar.gz"
  tmp="$(mktemp -d)"
  if ! curl -fL --retry 3 --retry-delay 2 -o "$tmp/pwsh.tar.gz" "$url"; then
    warn "Tải PowerShell thất bại. Bỏ qua; có thể dùng fetch-iso.sh --url."
    rm -rf "$tmp"
    return 1
  fi

  $SUDO mkdir -p /opt/microsoft/powershell/7
  $SUDO tar -xzf "$tmp/pwsh.tar.gz" -C /opt/microsoft/powershell/7
  $SUDO chmod +x /opt/microsoft/powershell/7/pwsh
  $SUDO ln -sf /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh
  rm -rf "$tmp"

  if command -v pwsh >/dev/null 2>&1; then
    log "Đã cài PowerShell $(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null || echo 7)"
  else
    warn "Cài PowerShell chưa thành công; có thể dùng fetch-iso.sh --url."
    return 1
  fi
}

info "Cập nhật apt..."
$SUDO apt-get update -y

info "Cài QEMU, OVMF, swtpm, noVNC, công cụ ISO..."
$SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  qemu-system-x86 \
  qemu-utils \
  ovmf \
  swtpm \
  swtpm-tools \
  genisoimage \
  xorriso \
  curl \
  wget \
  ca-certificates \
  jq \
  unzip \
  zip \
  p7zip-full \
  shellcheck \
  socat \
  novnc \
  websockify \
  python3-websockify \
  net-tools \
  iproute2 \
  libxml2-utils \
  libicu-dev

mkdir -p "$ISO_DIR" "$VM_DIR" "$TOOLS_DIR"

require_cmd qemu-system-x86_64 qemu-img genisoimage swtpm websockify

install_pwsh || true

log "Dependency đã sẵn sàng."
log "QEMU: $(qemu-system-x86_64 --version | head -n 1)"
log "OVMF: $(ovmf_code_path)"
log "noVNC: $(command -v novnc || true) / websockify: $(command -v websockify || true)"

accel="$(detect_accel)"
if [[ "$accel" == "kvm" ]]; then
  log "Tăng tốc: KVM (nhanh)."
else
  warn "Không có /dev/kvm: dùng TCG giả lập CPU. Windows sẽ chậm; xem README."
fi

info "Xong. Tiếp theo: bash scripts/fetch-iso.sh win11"
