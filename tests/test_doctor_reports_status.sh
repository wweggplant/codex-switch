#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

home_dir="$(make_temp_home)"
trap 'rm -rf "$home_dir"' EXIT

write_codex_auth "$home_dir" "account-sync" "sync@example.com" "refresh-sync"
write_openclaw_store "$home_dir" "openclaw-old-refresh" "old-account"

before="$(run_codex_switch "$home_dir" doctor)"
assert_contains "$before" "OpenClaw auth store:  different from current Codex" "doctor should report a deliberate difference from current Codex before openclaw-use"

run_codex_switch "$home_dir" openclaw-use >/dev/null
after="$(run_codex_switch "$home_dir" doctor)"
assert_contains "$after" "OpenClaw auth store:  matches current Codex" "doctor should report auth store alignment after openclaw-use"
assert_contains "$after" "OpenClaw oauth import: matches current Codex" "doctor should report oauth import alignment after openclaw-use"
assert_contains "$after" "Relation to Codex:" "doctor should explain the OpenClaw-to-Codex relationship"

echo "PASS: test_doctor_reports_status"
