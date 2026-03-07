#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

home_dir="$(make_temp_home)"
path_dir="$(make_temp_home)"
trap 'rm -rf "$home_dir" "$path_dir"' EXIT

ln -s "$(command -v bash)" "$path_dir/bash"
ln -s "$(command -v jq)" "$path_dir/jq"

write_codex_auth "$home_dir" "account-current" "current@example.com" "refresh-current"
write_profile "$home_dir/.codex-switch" "account-current" "current" "current@example.com" "refresh-current"
write_profile "$home_dir/.codex-switch" "account-work" "work" "work@example.com" "refresh-work"

output="$(printf '2\n' | PATH="$path_dir:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$home_dir" CP_DATA_DIR="$home_dir/.codex-switch" CP_NO_COLOR=1 "$BIN" use 2>&1)"

assert_eq "refresh-work" "$(read_codex_refresh "$home_dir")" "interactive use should switch to the selected profile"
assert_contains "$output" "Select number:" "interactive use should show the fallback selection prompt"
assert_contains "$output" "[2] work" "interactive use should show visible numbered options"

echo "PASS: test_use_interactive_menu_visible"
