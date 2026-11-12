#!/usr/bin/env bash
# Download an official Windows ISO into iso/<os>.iso.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "$ROOT_DIR/scripts/common.sh"

usage() {
  cat <<'EOF'
Dùng:
  bash scripts/fetch-iso.sh <win10|win11|win11-ltsc|server2022> [--url URL] [--dry-run] [--force]

Ví dụ:
  bash scripts/fetch-iso.sh win11
  bash scripts/fetch-iso.sh win10 --url "https://.../Win10.iso"
  bash scripts/fetch-iso.sh win11-ltsc
  bash scripts/fetch-iso.sh server2022 --dry-run
EOF
}

os=""
custom_url=""
dry_run="false"
force="false"

while (( $# > 0 )); do
  case "$1" in
    win10|win11|win11-ltsc|server2022) os="$1"; shift ;;
    --url) custom_url="${2:-}"; [[ -n "$custom_url" ]] || die "--url cần một URL"; shift 2 ;;
    --dry-run) dry_run="true"; shift ;;
    --force) force="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Tham số không hợp lệ: $1" ;;
  esac
done

[[ -n "$os" ]] || { usage; exit 1; }
os_config "$os"
mkdir -p "$ISO_DIR"
dest="$ISO_DIR/$OS_ISO_NAME"

if [[ -s "$dest" && "$force" != "true" ]]; then
  log "ISO đã có: $dest ($(du -h "$dest" | cut -f1))"
  exit 0
fi

resolve_url() {
  if [[ -n "$custom_url" ]]; then
    printf '%s\n' "$custom_url"
    return 0
  fi

  case "$os" in
    server2022)
      # Microsoft Evaluation Center, Windows Server 2022, English x64 ISO.
      printf '%s\n' 'https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US'
      ;;
    win11-ltsc)
      # Microsoft Evaluation Center, Windows 11 Enterprise LTSC 2024, English x64 ISO.
      printf '%s\n' 'https://go.microsoft.com/fwlink/?linkid=2289029&clcid=0x409&culture=en-us&country=us'
      ;;
    win10|win11)
      local fido_out
      if ! fido_out="$(bash "$ROOT_DIR/scripts/fetch-fido.sh" "$os" 2>/dev/null)"; then
        if [[ "$os" == "win11" ]]; then
          die "Microsoft Sentinel đang chặn IP này nên không lấy được link Win11 Pro. Dùng bản dự phòng: bash scripts/fetch-iso.sh win11-ltsc — hoặc tải ISO Win11 trên PC rồi upload vào iso/ và dùng --url."
        fi
        die "Không lấy được link $OS_LABEL (Microsoft Sentinel chặn IP). Hãy tải ISO trên PC rồi upload vào iso/, hoặc dùng --url."
      fi
      printf '%s\n' "$fido_out"
      ;;
  esac
}

info "Đang lấy link ISO cho $OS_LABEL..."
url="$(resolve_url)"
[[ -n "$url" ]] || die "Không lấy được link ISO."

if [[ "$dry_run" == "true" ]]; then
  printf '%s\n' "$url"
  exit 0
fi

if (( $(free_disk_gb) < 10 )); then
  die "Chỉ còn $(free_disk_gb) GB trống. Cần ít nhất 10 GB để tải ISO."
fi

info "Tải ISO về $dest (có thể mất vài phút)..."
part="$dest.part"
if ! curl -fL --retry 3 --retry-delay 3 -C - \
  -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36" \
  -o "$part" "$url"; then
  warn "Không resume được, tải lại từ đầu..."
  rm -f "$part"
  curl -fL --retry 3 --retry-delay 3 \
    -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36" \
    -o "$part" "$url"
fi

size="$(stat -c%s "$part" 2>/dev/null || echo 0)"
if (( size < 2000000000 )); then
  rm -f "$part"
  die "File tải về quá nhỏ ($size bytes) — có thể Microsoft trả về trang HTML thay vì ISO. Hãy tải ISO trên PC rồi upload vào iso/, hoặc dùng --url."
fi

mv "$part" "$dest"
log "Đã tải: $dest ($(du -h "$dest" | cut -f1))"
