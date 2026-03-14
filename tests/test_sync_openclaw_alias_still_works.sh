#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

home_dir="$(make_temp_home)"
trap 'rm -rf "$home_dir"' EXIT

write_codex_auth "$home_dir" "account-sync" "sync@example.com" "refresh-sync"
write_openclaw_store "$home_dir" "openclaw-old-refresh" "old-account"

output="$(run_codex_switch "$home_dir" sync-openclaw 2>&1)"

assert_eq "refresh-sync" "$(read_openclaw_refresh "$home_dir")" "sync-openclaw alias should still update OpenClaw auth store"
assert_contains "$output" "Prefer 'openclaw-use'" "sync-openclaw alias should warn about the preferred command"
assert_contains "$output" "OpenClaw now uses current Codex auth" "sync-openclaw alias should still complete the switch"

echo "PASS: test_sync_openclaw_alias_still_works"
