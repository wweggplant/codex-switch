#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

home_dir="$(make_temp_home)"
trap 'rm -rf "$home_dir"' EXIT

write_codex_auth "$home_dir" "account-sync" "sync@example.com" "refresh-sync"
write_openclaw_store "$home_dir" "openclaw-old-refresh" "old-account"

output="$(run_codex_switch "$home_dir" sync-openclaw)"

assert_eq "refresh-sync" "$(read_openclaw_refresh "$home_dir")" "sync-openclaw should update OpenClaw auth store"
assert_eq "refresh-sync" "$(read_oauth_import_refresh "$home_dir")" "sync-openclaw should update oauth import file"
assert_contains "$output" "OpenClaw auth synced" "sync-openclaw should report success"

echo "PASS: test_sync_openclaw_updates_files"
