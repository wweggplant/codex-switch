#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

home_dir="$(make_temp_home)"
trap 'rm -rf "$home_dir"' EXIT

write_codex_auth "$home_dir" "account-sync" "sync@example.com" "refresh-sync"
write_openclaw_store "$home_dir" "openclaw-old-refresh" "old-account"
write_fake_pgrep_running "$home_dir"

output="$(run_codex_switch "$home_dir" sync-openclaw 2>&1)"

assert_contains "$output" "OpenClaw auth synced" "sync-openclaw should still succeed when gateway is running"
assert_contains "$output" "Run: openclaw gateway restart" "sync-openclaw should instruct the user to restart a running gateway"
assert_contains "$output" "OpenClaw auth store:  synced" "sync-openclaw should still update the auth store before warning"

echo "PASS: test_sync_openclaw_warns_about_running_gateway"
