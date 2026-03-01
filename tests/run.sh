#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for test_file in "$ROOT_DIR"/test_*.sh; do
    [[ "$(basename "$test_file")" == "test_helper.sh" ]] && continue
    bash "$test_file"
done
