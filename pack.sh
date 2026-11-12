#!/usr/bin/env bash
# Package the toolkit into /sdcard/Download as a zip + sha256 checksum.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$ROOT_DIR/scripts/common.sh"

DEST_DIR="${DEST_DIR:-/sdcard/Download}"
NAME="winvm-codespaces-vip"

usage() {
  cat <<'EOF'
Dùng:
  bash pack.sh

Tạo:
  /sdcard/Download/winvm-codespaces-vip.zip
  /sdcard/Download/winvm-codespaces-vip.zip.sha256.txt

Không đóng gói: .git/, iso/, vm/, .tools/, .superpowers/, docs/superpowers/,
log, pid và socket.
Đổi thư mục đích: DEST_DIR=/duong/dan bash pack.sh
EOF
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

require_cmd zip unzip sha256sum tar

mkdir -p "$DEST_DIR"
DEST_DIR="$(cd -- "$DEST_DIR" && pwd)"
zip_path="$DEST_DIR/$NAME.zip"
sha_path="$zip_path.sha256.txt"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/$NAME"

info "Đang gom mã nguồn..."
tar -C "$ROOT_DIR" \
  --exclude='./.git' --exclude='./.git/*' \
  --exclude='./iso' --exclude='./iso/*' \
  --exclude='./vm' --exclude='./vm/*' \
  --exclude='./.tools' --exclude='./.tools/*' \
  --exclude='./.superpowers' --exclude='./.superpowers/*' \
  --exclude='./docs/superpowers' --exclude='./docs/superpowers/*' \
  --exclude='*.log' --exclude='*.pid' --exclude='*.sock' \
  -cf - . | tar -C "$stage/$NAME" -xf -

for required in \
  README.md \
  pack.sh \
  scripts/boot-menu.sh \
  scripts/run-vm.sh \
  guest/autounattend/win11.xml \
  guest/scripts/setup-win.ps1 \
  docs/huong-dan.md \
  docs/iso.md \
  docs/loi-thuong-gap.md; do
  [[ -e "$stage/$NAME/$required" ]] || die "Thiếu file khi đóng gói: $required"
done

rm -f "$zip_path" "$sha_path"
info "Đang nén $NAME.zip..."
(
  cd "$stage"
  zip -qr9 "$zip_path" "$NAME"
)

unzip -tqq "$zip_path" >/dev/null || die "File zip tạo ra bị hỏng."
(
  cd "$DEST_DIR"
  sha256sum "$NAME.zip" > "$NAME.zip.sha256.txt"
  sha256sum -c "$NAME.zip.sha256.txt" >/dev/null
)

size="$(du -h "$zip_path" | cut -f1)"
log "Đã đóng gói: $zip_path ($size)"
log "Checksum   : $sha_path"
printf '\nKiểm tra lại trên máy khác:\n  sha256sum -c %s\n' "$(basename "$sha_path")"
