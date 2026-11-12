#!/usr/bin/env bash
# Run every host test suite in order.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

suites=(
  test_common.sh
  test_fetch_iso.sh
  test_vm_args.sh
  test_unattend.sh
  test_ps_syntax.sh
  test_boot_menu.sh
  test_manage.sh
  test_pack.sh
)

for suite in "${suites[@]}"; do
  printf '\n===== %s =====\n' "$suite"
  bash "$ROOT_DIR/tests/$suite"
done

printf '\nAll test suites passed\n'
