#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

home_dir="$(make_temp_home)"
trap 'rm -rf "$home_dir"' EXIT

write_codex_auth "$home_dir" "account-current" "current@example.com" "refresh-current"
write_profile "$home_dir/.codex-switch" "account-current" "current" "current@example.com" "refresh-current"
write_profile "$home_dir/.codex-switch" "account-proton" "proton" "proton@example.com" "refresh-proton"

output="$(run_codex_switch "$home_dir" use proton)"

assert_eq "refresh-proton" "$(read_codex_refresh "$home_dir")" "use should accept a positional label"
assert_contains "$output" "Loaded profile: proton" "use with a positional label should still confirm the switch"

echo "PASS: test_use_positional_label"
