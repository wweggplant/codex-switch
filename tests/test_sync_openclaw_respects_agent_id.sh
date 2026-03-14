#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

home_dir="$(make_temp_home)"
trap 'rm -rf "$home_dir"' EXIT

write_codex_auth "$home_dir" "account-sync" "sync@example.com" "refresh-sync"
write_openclaw_store "$home_dir" "openclaw-old-refresh" "old-account" "ops"

output="$(OPENCLAW_AGENT_ID=ops run_codex_switch "$home_dir" openclaw-use)"

assert_eq "refresh-sync" "$(read_openclaw_refresh "$home_dir" "ops")" "openclaw-use should write to agents/<agentId>/agent/auth-profiles.json"
assert_contains "$output" "OpenClaw now uses current Codex auth" "openclaw-use should still report success for non-default agents"

echo "PASS: test_sync_openclaw_respects_agent_id"
