#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

home_dir="$(make_temp_home)"
trap 'rm -rf "$home_dir"' EXIT

write_codex_auth "$home_dir" "account-current" "current@example.com" "refresh-current"
write_profile "$home_dir/.codex-switch" "account-current" "current" "current@example.com" "refresh-current"
write_profile "$home_dir/.codex-switch" "account-work" "work" "work@example.com" "refresh-work"
write_openclaw_store "$home_dir" "openclaw-refresh"

output="$(run_codex_switch "$home_dir" load --label work)"

assert_eq "refresh-work" "$(read_codex_refresh "$home_dir")" "load should switch Codex auth"
assert_eq "openclaw-refresh" "$(read_openclaw_refresh "$home_dir")" "load should not change OpenClaw by default"
assert_contains "$output" "OpenClaw was not changed." "load should explain OpenClaw is untouched"

echo "PASS: test_load_skips_openclaw"
