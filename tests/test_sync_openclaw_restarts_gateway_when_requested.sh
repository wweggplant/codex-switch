#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

home_dir="$(make_temp_home)"
trap 'rm -rf "$home_dir"' EXIT

write_codex_auth "$home_dir" "account-sync" "sync@example.com" "refresh-sync"
write_openclaw_store "$home_dir" "openclaw-old-refresh" "old-account"
write_fake_pgrep_running "$home_dir"
write_fake_openclaw_cli "$home_dir"

output="$(run_codex_switch "$home_dir" sync-openclaw --restart-gateway 2>&1)"

assert_contains "$output" "OpenClaw auth synced" "sync-openclaw should still report a successful sync before restarting"
assert_contains "$output" "OpenClaw gateway restarted" "sync-openclaw --restart-gateway should restart the gateway when it is running"
assert_contains "$(cat "$home_dir/openclaw.log")" "gateway restart" "sync-openclaw --restart-gateway should invoke the OpenClaw CLI restart command"

echo "PASS: test_sync_openclaw_restarts_gateway_when_requested"
