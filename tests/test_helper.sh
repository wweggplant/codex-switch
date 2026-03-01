#!/usr/bin/env bash

set -euo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$TEST_ROOT/bin/codex-switch"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    if [[ "$expected" != "$actual" ]]; then
        fail "$message (expected='$expected' actual='$actual')"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        fail "$message (missing '$needle')"
    fi
}

make_temp_home() {
    mktemp -d "${TMPDIR:-/tmp}/codex-switch-test.XXXXXX"
}

write_codex_auth() {
    local home_dir="$1"
    local account_id="$2"
    local email="$3"
    local refresh_token="$4"
    local access_token="${5:-access-${account_id}}"
    local plan="${6:-plus}"

    mkdir -p "$home_dir/.codex"
    cat > "$home_dir/.codex/auth.json" <<EOF
{
  "auth_mode": "chatgpt",
  "email": "$email",
  "plan": "$plan",
  "last_refresh": "2026-03-01T08:10:15.918682Z",
  "tokens": {
    "access_token": "$access_token",
    "refresh_token": "$refresh_token",
    "account_id": "$account_id",
    "id_token": ""
  }
}
EOF
}

write_profile() {
    local data_dir="$1"
    local account_id="$2"
    local label="$3"
    local email="$4"
    local refresh_token="$5"
    local access_token="${6:-access-${account_id}}"
    local plan="${7:-plus}"

    mkdir -p "$data_dir/profiles"
    cat > "$data_dir/profiles/$account_id.json" <<EOF
{
  "auth_mode": "chatgpt",
  "email": "$email",
  "plan": "$plan",
  "last_refresh": "2026-03-01T08:10:15.918682Z",
  "tokens": {
    "access_token": "$access_token",
    "refresh_token": "$refresh_token",
    "account_id": "$account_id",
    "id_token": ""
  }
}
EOF

    mkdir -p "$data_dir"
    if [[ ! -f "$data_dir/index.json" ]]; then
        echo '{"profiles":{}}' > "$data_dir/index.json"
    fi

    local tmp_file
    tmp_file="$(mktemp "${TMPDIR:-/tmp}/codex-switch-index.XXXXXX")"
    jq \
        --arg account_id "$account_id" \
        --arg label "$label" \
        --arg email "$email" \
        --arg plan "$plan" \
        '.profiles[$account_id] = {
            label: $label,
            email: $email,
            plan: $plan,
            last_seen: "2026-03-01T10:00:00Z"
        }' \
        "$data_dir/index.json" > "$tmp_file"
    mv "$tmp_file" "$data_dir/index.json"
}

write_openclaw_store() {
    local home_dir="$1"
    local refresh_token="$2"
    local account_id="${3:-openclaw-account}"

    mkdir -p "$home_dir/.openclaw/agents/main/agent"
    cat > "$home_dir/.openclaw/agents/main/agent/auth-profiles.json" <<EOF
{
  "version": 1,
  "profiles": {
    "openai-codex:default": {
      "type": "oauth",
      "provider": "openai-codex",
      "access": "openclaw-access",
      "refresh": "$refresh_token",
      "expires": 1772356215000,
      "accountId": "$account_id"
    }
  }
}
EOF
}

read_codex_refresh() {
    local home_dir="$1"
    jq -r '.tokens.refresh_token' "$home_dir/.codex/auth.json"
}

read_openclaw_refresh() {
    local home_dir="$1"
    jq -r '.profiles["openai-codex:default"].refresh' "$home_dir/.openclaw/agents/main/agent/auth-profiles.json"
}

read_oauth_import_refresh() {
    local home_dir="$1"
    jq -r '.["openai-codex"].refresh' "$home_dir/.openclaw/credentials/oauth.json"
}

run_codex_switch() {
    local home_dir="$1"
    shift
    HOME="$home_dir" CP_DATA_DIR="$home_dir/.codex-switch" CP_NO_COLOR=1 "$BIN" "$@"
}
