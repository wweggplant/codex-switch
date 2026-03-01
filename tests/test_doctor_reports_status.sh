#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

home_dir="$(make_temp_home)"
trap 'rm -rf "$home_dir"' EXIT

write_codex_auth "$home_dir" "account-sync" "sync@example.com" "refresh-sync"
write_openclaw_store "$home_dir" "openclaw-old-refresh" "old-account"

before="$(run_codex_switch "$home_dir" doctor)"
assert_contains "$before" "OpenClaw auth store:  out of sync" "doctor should report out-of-sync state before sync"

run_codex_switch "$home_dir" sync-openclaw >/dev/null
after="$(run_codex_switch "$home_dir" doctor)"
assert_contains "$after" "OpenClaw auth store:  synced" "doctor should report synced state after sync"
assert_contains "$after" "OpenClaw oauth import: synced" "doctor should report oauth import state"

echo "PASS: test_doctor_reports_status"
