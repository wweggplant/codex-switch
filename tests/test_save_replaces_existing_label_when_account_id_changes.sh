#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

home_dir="$(make_temp_home)"
trap 'rm -rf "$home_dir"' EXIT

write_profile "$home_dir/.codex-switch" "account-old" "protonmail" "weiainijiujiu@protonmail.com" "refresh-old" "access-old" "team"
write_codex_auth "$home_dir" "account-new" "weiainijiujiu@protonmail.com" "refresh-new" "access-new" "team"

output="$(printf 'Y\n' | run_codex_switch "$home_dir" save protonmail 2>&1)"

assert_contains "$output" "will be updated to the current login" "save should warn before reassigning an existing label"
assert_contains "$output" "Profile saved: protonmail" "save should still succeed when reassigning a label"
assert_eq "refresh-new" "$(read_profile_refresh "$home_dir/.codex-switch" "account-new")" "save should write the current auth snapshot under the new account_id"

if [[ -f "$home_dir/.codex-switch/profiles/account-old.json" ]]; then
    fail "save should remove the old profile file when reassigning a label"
fi

assert_eq "account-new" "$(jq -r '.profiles | to_entries[] | select(.value.label == "protonmail") | .key' "$home_dir/.codex-switch/index.json")" "save should point the label at the new account_id"

run_codex_switch "$home_dir" use protonmail >/dev/null
assert_eq "refresh-new" "$(read_codex_refresh "$home_dir")" "use should load the refreshed profile after the label is reassigned"

echo "PASS: test_save_replaces_existing_label_when_account_id_changes"
