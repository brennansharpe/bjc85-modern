#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
helper_dir=${BJC85_TEST_HELPERS:-"$project_dir/dist/BJC-85 Utility.app/Contents/Helpers"}
test_root=$(mktemp -d /tmp/bjc85-services-test.XXXXXX)
trap 'rm -rf "$test_root"' EXIT
export BJC85_OFFLINE_TEST=1
export BJC85_ADMISSION_PATH="$test_root/admission.lock"
export BJC85_USB_LEASE_PATH="$test_root/usb.lock"
python3 "$project_dir/tests/escl_recovery_state_test.py" "$helper_dir/is12-escl-bridge"
python3 "$project_dir/tests/escl_recovery_test.py" "$helper_dir/is12-escl-bridge"
python3 "$project_dir/tests/isolated_http_runner.py" "$helper_dir/is12-escl-bridge"
export BJC85_TEST_FIXTURE_DIR="$test_root"
xcrun clang -Wall -Wextra -Werror "$project_dir/tests/make_urf_fixture.c" -lcups -o "$test_root/make-urf"
"$test_root/make-urf" "$test_root/letter.urf" letter
"$test_root/make-urf" "$test_root/a4.urf" a4
python3 "$project_dir/tests/ipp_dry_run_test.py" "$helper_dir/bjc85-ipp"
