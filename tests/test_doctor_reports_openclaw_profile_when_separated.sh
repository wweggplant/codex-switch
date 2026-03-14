#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

home_dir="$(make_temp_home)"
trap 'rm -rf "$home_dir"' EXIT

write_codex_auth "$home_dir" "account-current" "current@example.com" "refresh-current"
write_profile "$home_dir/.codex-switch" "account-current" "current" "current@example.com" "refresh-current"
write_profile "$home_dir/.codex-switch" "account-proton" "protonmail" "proton@example.com" "refresh-proton"
write_openclaw_store "$home_dir" "openclaw-old-refresh" "old-account"

run_codex_switch "$home_dir" openclaw-use protonmail >/dev/null
output="$(run_codex_switch "$home_dir" doctor)"

assert_contains "$output" "OpenClaw profile: protonmail" "doctor should identify the OpenClaw profile when it differs from current Codex"
assert_contains "$output" "OpenClaw email: proton@example.com" "doctor should show the OpenClaw profile email"
assert_contains "$output" "Relation to Codex: different from current Codex (current)" "doctor should explain that OpenClaw is intentionally different from current Codex"
assert_contains "$output" "OpenClaw auth store:  different from current Codex" "doctor should avoid calling a separated OpenClaw profile a sync error"

echo "PASS: test_doctor_reports_openclaw_profile_when_separated"
