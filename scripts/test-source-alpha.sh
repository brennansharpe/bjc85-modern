#!/bin/sh
# Offline only: C tests use fake transports or committed status/calibration fixtures.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
export BJC85_OFFLINE_TEST=1
python3 tests/repository_privacy_test.py
cmake -S . -B build-source-alpha -DCMAKE_BUILD_TYPE=Debug
cmake --build build-source-alpha --parallel 4
ctest --test-dir build-source-alpha --output-on-failure
sh scripts/test-swift.sh build-source-alpha/swift-tests
sh scripts/test-hardening.sh
