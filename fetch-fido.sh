#!/usr/bin/env bash
# Resolve official Microsoft Windows 10/11 ISO URLs with Fido.
# Fido refuses to run on Linux; we patch only that guard and use -GetUrl.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "$ROOT_DIR/scripts/common.sh"

os="${1:-}"
case "$os" in
  win10) win_name="Windows 10" ;;
  win11) win_name="Windows 11" ;;
  *) die "Dùng: bash scripts/fetch-fido.sh <win10|win11>" ;;
esac

require_cmd curl python3 sha256sum
if ! command -v pwsh >/dev/null 2>&1; then
  die "Chưa có pwsh. Chạy 'bash scripts/setup.sh' hoặc dùng: bash scripts/fetch-iso.sh $os --url <URL>"
fi

# Pin Fido to an immutable commit so upstream changes cannot alter what we run.
FIDO_COMMIT="266084e3765ab8bf96767bd55c51b0ee70934551"
FIDO_SHA256="89a26b4a8be2721e610ba3f563ec44024e6cf7975938ee5b61d624d2bfbf4643"
FIDO_URL="https://raw.githubusercontent.com/pbatard/Fido/$FIDO_COMMIT/Fido.ps1"

mkdir -p "$TOOLS_DIR"
fido="$TOOLS_DIR/Fido.ps1"
if [[ ! -s "$fido" ]] || ! printf '%s  %s\n' "$FIDO_SHA256" "$fido" | sha256sum -c - >/dev/null 2>&1; then
  info "Tải Fido (công cụ lấy link ISO chính thức của Microsoft)..."
  curl -fsSL --retry 3 -o "$fido" "$FIDO_URL"
  printf '%s  %s\n' "$FIDO_SHA256" "$fido" | sha256sum -c - >/dev/null 2>&1 \
    || { rm -f "$fido"; die "Fido tải về không khớp checksum. Không chạy file lạ."; }
fi

if ! grep -q "WINVM_PATCHED" "$fido"; then
  info "Patch Fido để chạy trên Linux..."
  python3 - "$fido" <<'PY'
import sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8-sig") as fh:
    text = fh.read()
text = text.replace(
    "if ($winver -le 6.1) {",
    "if ($false) { # WINVM_PATCHED",
)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(text)
PY
fi

url="$(pwsh -NoProfile -NonInteractive -File "$fido" \
  -Win "$win_name" -Ed Pro -Lang English -Arch x64 -PlatformArch x64 -GetUrl 2>/dev/null | tr -d '\r' | tail -n 1)"

if [[ ! "$url" =~ ^https?:// ]]; then
  die "Fido không trả về link ISO. Microsoft có thể đang chặn IP Codespaces. Hãy tải ISO trên PC rồi upload vào iso/, hoặc dùng --url."
fi

printf '%s\n' "$url"
