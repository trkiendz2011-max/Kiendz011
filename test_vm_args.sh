#!/usr/bin/env bash
# Tests for VM lifecycle argument generation and safety checks.
# Nothing is downloaded, launched or written to the real iso/ and vm/ dirs.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; failures=$((failures + 1)); }

contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label (missing: $needle)"
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export ISO_DIR="$tmp/iso"
export VM_DIR="$tmp/vm"
export ACCEL="tcg,thread=multi"
mkdir -p "$ISO_DIR" "$tmp/bin"

# Fake isoinfo: lets us exercise edition validation without real ISO files.
cat > "$tmp/bin/isoinfo" <<'EOF'
#!/usr/bin/env bash
mode=""
file=""
for arg in "$@"; do
  case "$arg" in
    -d) mode="d" ;;
    -f) mode="f" ;;
    -i|-J|-R) ;;
    *) file="$arg" ;;
  esac
done
base="$(basename "$file")"
if [[ "$mode" == "f" ]]; then
  printf '/sources/install.wim\n'
  exit 0
fi
case "$base" in
  # Real Microsoft eval volume labels, verified 2026-11-12.
  win11-ltsc.iso) label="${FAKE_LTSC_LABEL:-CESE_X64FREE_EN-US_DV9}" ;;
  server2022.iso) label="${FAKE_SERVER_LABEL:-SSS_X64FREE_EN-US_DV9}" ;;
  win10.iso|win11.iso) label="${FAKE_CLIENT_LABEL:-CCCOMA_X64FRE_EN-US_DV9}" ;;
  *) label="UNKNOWN" ;;
esac
printf 'Volume id: %s\n' "$label"
EOF
chmod +x "$tmp/bin/isoinfo"

# Fake QEMU so runtime accelerator detection is deterministic on KVM hosts too.
cat > "$tmp/bin/qemu-system-x86_64" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-accel" && "${2:-}" == "help" ]]; then
  printf 'tcg\n'
  exit 0
fi
exit 1
EOF
chmod +x "$tmp/bin/qemu-system-x86_64"
export PATH="$tmp/bin:$PATH"

printf 'dummy' > "$ISO_DIR/win11.iso"
printf 'dummy' > "$ISO_DIR/win10.iso"
printf 'dummy' > "$ISO_DIR/server2022.iso"
printf 'dummy' > "$ISO_DIR/win11-ltsc.iso"

# create-vm --dry-run must describe the plan without writing a disk.
if out="$(bash "$ROOT_DIR/scripts/create-vm.sh" win11 --dry-run 2>&1)"; then
  pass "create-vm win11 --dry-run exits 0"
else
  fail "create-vm win11 --dry-run failed: $out"
fi
contains "$out" "Windows 11 Pro" "create-vm names the OS"
contains "$out" "disk.qcow2" "create-vm plans disk.qcow2"
contains "$out" "tools.iso" "create-vm plans tools.iso"
if [[ ! -e "$VM_DIR/win11/disk.qcow2" ]]; then
  pass "create-vm --dry-run writes no disk"
else
  fail "create-vm --dry-run wrote a disk"
fi

# Wrong edition: a normal Windows 11 ISO must not be accepted as LTSC.
export FAKE_LTSC_LABEL='CCCOMA_X64FRE_EN-US_DV9'
if out="$(bash "$ROOT_DIR/scripts/create-vm.sh" win11-ltsc --dry-run 2>&1)"; then
  fail "create-vm accepts a non-LTSC ISO for win11-ltsc"
else
  contains "$out" "LTSC" "create-vm rejects wrong LTSC edition"
fi
if out="$(bash "$ROOT_DIR/scripts/run-vm.sh" win11-ltsc --dry-run 2>&1)"; then
  fail "run-vm accepts a non-LTSC ISO for win11-ltsc"
else
  contains "$out" "LTSC" "run-vm rejects wrong LTSC edition"
fi
unset FAKE_LTSC_LABEL
if out="$(bash "$ROOT_DIR/scripts/create-vm.sh" win11-ltsc --dry-run 2>&1)"; then
  contains "$out" "Windows 11 Enterprise LTSC 2024 (eval)" "create-vm accepts the official CESE LTSC ISO"
else
  fail "create-vm rejects a valid LTSC ISO: $out"
fi

# The official Server 2022 eval ISO uses the SSS label, not SERVER.
if out="$(bash "$ROOT_DIR/scripts/create-vm.sh" server2022 --dry-run 2>&1)"; then
  contains "$out" "Windows Server 2022 (Desktop Experience)" "create-vm accepts the official SSS Server ISO"
else
  fail "create-vm rejects a valid Server 2022 ISO: $out"
fi

# Consumer Windows must reject the official LTSC/Server eval labels.
for eval_label in 'CESE_X64FREE_EN-US_DV9' 'SSS_X64FREE_EN-US_DV9'; do
  export FAKE_CLIENT_LABEL="$eval_label"
  if out="$(bash "$ROOT_DIR/scripts/create-vm.sh" win11 --dry-run 2>&1)"; then
    fail "create-vm win11 accepts eval label $eval_label"
  else
    contains "$out" "Server/LTSC/eval" "create-vm win11 rejects eval label $eval_label"
  fi
done
unset FAKE_CLIENT_LABEL

# Missing ISO must fail with a clear message and write nothing.
rm -f "$ISO_DIR/win10.iso"
if out="$(bash "$ROOT_DIR/scripts/create-vm.sh" win10 --dry-run 2>&1)"; then
  fail "create-vm without ISO should fail"
else
  if [[ "$out" == *"ISO"* ]]; then
    pass "create-vm missing ISO reports ISO"
  else
    fail "create-vm missing ISO message: $out"
  fi
fi
if [[ ! -e "$VM_DIR/win10/disk.qcow2" ]]; then
  pass "create-vm missing ISO writes no disk"
else
  fail "create-vm missing ISO wrote a disk"
fi
printf 'dummy' > "$ISO_DIR/win10.iso"

# QEMU args for Windows 11: TCG, q35/AHCI, e1000, noVNC loopback, TPM.
if out="$(bash "$ROOT_DIR/scripts/run-vm.sh" win11 --dry-run 2>&1)"; then
  pass "run-vm win11 --dry-run exits 0"
else
  fail "run-vm win11 --dry-run failed: $out"
fi
contains "$out" "-accel tcg" "run-vm uses TCG accel"
contains "$out" "-machine q35" "run-vm uses q35/AHCI machine"
contains "$out" "e1000" "run-vm uses Intel e1000 NIC"
contains "$out" "ide-hd" "run-vm uses AHCI/IDE disk device"
contains "$out" "bus=ide.2" "run-vm puts tools ISO on its own AHCI port"
contains "$out" "-vnc 127.0.0.1:0" "run-vm binds VNC to loopback"
contains "$out" "tpm-tis" "run-vm adds TPM for Windows 11"
contains "$out" "win11.iso" "run-vm attaches the Windows ISO"
contains "$out" "tools.iso" "run-vm attaches the tools ISO"
contains "$out" "hostfwd=tcp:127.0.0.1:3389-:3389" "run-vm forwards RDP on loopback"
contains "$out" "hostfwd=tcp:127.0.0.1:2222-:22" "run-vm forwards SSH on loopback"
if [[ ! -e "$VM_DIR/win11/qemu.pid" && ! -e "$VM_DIR/win11/websockify.pid" ]]; then
  pass "run-vm --dry-run starts nothing"
else
  fail "run-vm --dry-run wrote pidfiles"
fi

# Windows 10 has no TPM.
if out="$(bash "$ROOT_DIR/scripts/run-vm.sh" win10 --dry-run 2>&1)"; then
  if [[ "$out" == *"tpm-tis"* ]]; then
    fail "run-vm win10 should not add TPM"
  else
    pass "run-vm win10 has no TPM"
  fi
else
  fail "run-vm win10 --dry-run failed: $out"
fi

# Server 2022 uses the same AHCI/e1000 path.
if out="$(bash "$ROOT_DIR/scripts/run-vm.sh" server2022 --dry-run 2>&1)"; then
  contains "$out" "e1000" "run-vm server2022 uses e1000"
  contains "$out" "ide-hd" "run-vm server2022 uses AHCI/IDE disk"
else
  fail "run-vm server2022 --dry-run failed: $out"
fi

# A dead pidfile is stale and must be cleared, not treated as a running VM.
mkdir -p "$VM_DIR/win11"
echo 999999 > "$VM_DIR/win11/qemu.pid"
if ( source "$ROOT_DIR/scripts/common.sh"; is_running win11 ); then
  fail "is_running treats a dead pid as running"
else
  pass "is_running ignores a dead pid"
fi
if ( source "$ROOT_DIR/scripts/common.sh"; clear_stale_pid win11; [[ ! -f "$VM_DIR/win11/qemu.pid" ]] ); then
  pass "clear_stale_pid removes a dead pidfile"
else
  fail "clear_stale_pid left a dead pidfile"
fi

# Runtime acceleration detection wins over a stale stored ACCEL value.
cat > "$VM_DIR/win11/vm.conf" <<EOF
ACCEL=kvm
DISK_GB=40
RAM_MB=4096
CPUS=2
ISO_PATH="$ISO_DIR/win11.iso"
EOF
if out="$(env -u ACCEL bash "$ROOT_DIR/scripts/run-vm.sh" win11 --dry-run 2>&1)"; then
  contains "$out" "-accel tcg" "run-vm detects accel at runtime"
else
  fail "run-vm runtime accel test failed: $out"
fi
if out="$(ACCEL=kvm bash "$ROOT_DIR/scripts/run-vm.sh" win11 --dry-run 2>&1)"; then
  contains "$out" "-accel kvm" "run-vm honors explicit ACCEL override"
else
  fail "run-vm explicit ACCEL test failed: $out"
fi
rm -f "$VM_DIR/win11/vm.conf"

# create-vm must refuse to touch a running VM.
mkdir -p "$VM_DIR/win10"
sleep 60 &
live_pid=$!
echo "$live_pid" > "$VM_DIR/win10/qemu.pid"
if out="$(bash "$ROOT_DIR/scripts/create-vm.sh" win10 2>&1)"; then
  fail "create-vm rewrites a running VM"
else
  contains "$out" "đang chạy" "create-vm refuses a running VM"
fi
kill "$live_pid" 2>/dev/null || true
wait "$live_pid" 2>/dev/null || true
rm -f "$VM_DIR/win10/qemu.pid"

# Less than 8 GB free must refuse before creating the VM directory/disk.
mkdir -p "$tmp/lowbin"
cat > "$tmp/lowbin/df" <<'EOF'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf 'fakefs 1000000 500000 4194304 50%% /\n'
EOF
chmod +x "$tmp/lowbin/df"
if out="$(PATH="$tmp/lowbin:$PATH" bash "$ROOT_DIR/scripts/create-vm.sh" win11 2>&1)"; then
  fail "create-vm ignores low disk space"
else
  contains "$out" "8 GB" "create-vm refuses when free disk is below 8 GB"
fi
if [[ ! -e "$VM_DIR/win11/disk.qcow2" ]]; then
  pass "create-vm low disk writes no disk"
else
  fail "create-vm low disk wrote a disk"
fi

# Invalid OS is rejected everywhere.
for script in create-vm run-vm stop-vm; do
  if bash "$ROOT_DIR/scripts/$script.sh" nonsense >/dev/null 2>&1; then
    fail "$script accepts invalid OS"
  else
    pass "$script rejects invalid OS"
  fi
done

if (( failures > 0 )); then
  printf '\n%d test(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nAll VM arg tests passed\n'
