#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

home_dir="$(make_temp_home)"
trap 'rm -rf "$home_dir"' EXIT

write_codex_auth "$home_dir" "account-current" "current@example.com" "refresh-current"
write_profile "$home_dir/.codex-switch" "account-current" "current" "current@example.com" "refresh-current"
write_profile "$home_dir/.codex-switch" "account-work" "work" "work@example.com" "refresh-work"
write_openclaw_store "$home_dir" "openclaw-old-refresh" "old-account"

output="$(run_codex_switch "$home_dir" openclaw-use work)"

assert_eq "refresh-current" "$(read_codex_refresh "$home_dir")" "openclaw-use <label> should not switch Codex auth"
assert_eq "refresh-work" "$(read_openclaw_refresh "$home_dir")" "openclaw-use <label> should update OpenClaw auth store from the named profile"
assert_eq "refresh-work" "$(read_oauth_import_refresh "$home_dir")" "openclaw-use <label> should update oauth import from the named profile"
assert_contains "$output" "OpenClaw now uses profile: work" "openclaw-use <label> should report the profile source"

echo "PASS: test_sync_openclaw_uses_named_profile"
