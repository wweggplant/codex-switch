#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

home_dir="$(make_temp_home)"
trap 'rm -rf "$home_dir"' EXIT

write_codex_auth "$home_dir" "account-current" "current@example.com" "refresh-live"
write_profile "$home_dir/.codex-switch" "account-current" "current" "current@example.com" "refresh-stale"
write_openclaw_store "$home_dir" "openclaw-old-refresh" "old-account"

output="$(run_codex_switch "$home_dir" openclaw-use --label current)"

assert_eq "refresh-live" "$(read_profile_refresh "$home_dir/.codex-switch" "account-current")" "openclaw-use --label should refresh the current profile snapshot before switching OpenClaw"
assert_eq "refresh-live" "$(read_openclaw_refresh "$home_dir")" "openclaw-use --label should use the refreshed current profile token"
assert_eq "refresh-live" "$(read_oauth_import_refresh "$home_dir")" "openclaw-use --label should update the oauth import with the refreshed current profile token"
assert_contains "$output" "OpenClaw now uses profile: current" "openclaw-use --label should report the profile source"

echo "PASS: test_sync_openclaw_named_profile_refreshes_current_snapshot"
