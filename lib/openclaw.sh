#!/usr/bin/env bash
# codex-switch OpenClaw integration
# Functions for syncing auth to OpenClaw

# shellcheck disable=SC2155

_CP_OPENCLAW_PROVIDER_ID="openai-codex"
_CP_OPENCLAW_PROFILE_ID="openai-codex:default"

_cp_openclaw_state_dir() {
    local state_dir="${OPENCLAW_STATE_DIR:-${CLAWDBOT_STATE_DIR:-$HOME/.openclaw}}"
    echo "$state_dir"
}

_cp_openclaw_agent_id() {
    local agent_id="${OPENCLAW_AGENT_ID:-${CLAWDBOT_AGENT_ID:-main}}"
    echo "$agent_id"
}

_cp_openclaw_agent_dir() {
    local override="${OPENCLAW_AGENT_DIR:-${PI_CODING_AGENT_DIR:-}}"
    if [[ -n "$override" ]]; then
        echo "$override"
    else
        echo "$(_cp_openclaw_state_dir)/agents/$(_cp_openclaw_agent_id)/agent"
    fi
}

_cp_openclaw_auth_store_path() {
    echo "$(_cp_openclaw_agent_dir)/auth-profiles.json"
}

_cp_openclaw_oauth_import_path() {
    echo "$(_cp_openclaw_state_dir)/credentials/oauth.json"
}

_cp_openclaw_is_installed() {
    [[ -d "$(_cp_openclaw_state_dir)" ]]
}

_cp_openclaw_agent_exists() {
    [[ -d "$(_cp_openclaw_agent_dir)" ]]
}

_cp_openclaw_gateway_running() {
    if ! command -v pgrep >/dev/null 2>&1; then
        return 1
    fi

    pgrep -x "openclaw-gateway" >/dev/null 2>&1
}

_cp_openclaw_restart_gateway() {
    if ! command -v openclaw >/dev/null 2>&1; then
        _cp_warn "openclaw CLI not found on PATH; cannot restart gateway automatically"
        return 1
    fi

    openclaw gateway restart >/dev/null 2>&1
}

_cp_decode_jwt_exp_ms() {
    local token="$1"
    if [[ -z "$token" ]]; then
        return 0
    fi

    local payload
    payload=$(echo "$token" | cut -d. -f2)
    if [[ -z "$payload" ]]; then
        return 0
    fi

    local mod=$(( ${#payload} % 4 ))
    if [[ $mod -ne 0 ]]; then
        payload="${payload}$(printf '=%.0s' $(seq 1 $(( 4 - mod ))))"
    fi

    local exp
    exp=$(echo "$payload" | base64 -d 2>/dev/null | jq -r '.exp // empty' 2>/dev/null)
    if [[ -n "$exp" ]]; then
        echo $((exp * 1000))
    fi
}

_cp_openclaw_extract_auth_payload() {
    local auth_file="${1:-$(_cp_get_codex_auth_path)}"

    jq -c '{
        access: (.tokens.access_token // empty),
        refresh: (.tokens.refresh_token // empty),
        accountId: (.tokens.account_id // empty),
        idToken: (.tokens.id_token // empty),
        email: (
            .email //
            .user.email //
            (
                .tokens.id_token
                | if . == null or . == "" then null
                  else (
                    split(".")[1]
                    | @base64d
                    | fromjson
                    | .email // ."https://api.openai.com/profile".email // null
                  )
                end
            ) //
            empty
        )
    }' "$auth_file" 2>/dev/null
}

_cp_openclaw_ensure_json_file() {
    local path="$1"
    local default_json="$2"
    local dir
    dir=$(dirname "$path")

    mkdir -p "$dir"

    if [[ ! -f "$path" ]]; then
        printf '%s\n' "$default_json" > "$path"
        return 0
    fi

    if ! jq -e '.' "$path" >/dev/null 2>&1; then
        _cp_warn "OpenClaw auth file is invalid JSON, recreating: $path"
        printf '%s\n' "$default_json" > "$path"
    fi
}

_cp_openclaw_update_auth_store() {
    local auth_store="$(_cp_openclaw_auth_store_path)"
    local access_token="$1"
    local refresh_token="$2"
    local account_id="$3"
    local expires="$4"
    local email="$5"

    _cp_openclaw_ensure_json_file "$auth_store" '{"version":1,"profiles":{}}'

    local temp_file
    temp_file="$(mktemp "${auth_store}.tmp.XXXXXX")"

    jq \
        --arg profile_id "$_CP_OPENCLAW_PROFILE_ID" \
        --arg provider_id "$_CP_OPENCLAW_PROVIDER_ID" \
        --arg access "$access_token" \
        --arg refresh "$refresh_token" \
        --arg account_id "$account_id" \
        --arg email "$email" \
        --argjson expires "$expires" \
        '
        .version = (.version // 1) |
        .profiles = (.profiles // {}) |
        .profiles[$profile_id] = ((.profiles[$profile_id] // {}) + {
            type: "oauth",
            provider: $provider_id,
            access: $access,
            refresh: $refresh,
            expires: $expires,
            accountId: $account_id
        }) |
        if $email != "" then
            .profiles[$profile_id].email = $email
        else
            .
        end |
        .lastGood = (.lastGood // {}) |
        .lastGood[$provider_id] = (.lastGood[$provider_id] // $profile_id)
        ' \
        "$auth_store" > "$temp_file" && mv "$temp_file" "$auth_store"
}

_cp_openclaw_update_oauth_import() {
    local oauth_import="$(_cp_openclaw_oauth_import_path)"
    local access_token="$1"
    local refresh_token="$2"
    local account_id="$3"
    local expires="$4"
    local email="$5"

    _cp_openclaw_ensure_json_file "$oauth_import" '{}'

    local temp_file
    temp_file="$(mktemp "${oauth_import}.tmp.XXXXXX")"

    jq \
        --arg provider_id "$_CP_OPENCLAW_PROVIDER_ID" \
        --arg access "$access_token" \
        --arg refresh "$refresh_token" \
        --arg account_id "$account_id" \
        --arg email "$email" \
        --argjson expires "$expires" \
        '
        .[$provider_id] = ((.[$provider_id] // {}) + {
            access: $access,
            refresh: $refresh,
            expires: $expires,
            accountId: $account_id
        }) |
        if $email != "" then
            .[$provider_id].email = $email
        else
            .
        end
        ' \
        "$oauth_import" > "$temp_file" && mv "$temp_file" "$oauth_import"
}

_cp_openclaw_sync_from_auth_file() {
    local auth_file="${1:-$(_cp_get_codex_auth_path)}"

    if [[ ! -f "$auth_file" ]]; then
        _cp_warn "Auth file not found, skipping OpenClaw sync: $auth_file"
        return 1
    fi

    if ! _cp_openclaw_is_installed; then
        _cp_debug "OpenClaw not installed, skipping sync"
        return 0
    fi

    local payload
    payload="$(_cp_openclaw_extract_auth_payload "$auth_file")"
    if [[ -z "$payload" ]]; then
        _cp_warn "Could not parse auth file, skipping OpenClaw sync: $auth_file"
        return 1
    fi

    local access_token refresh_token account_id id_token email expires
    access_token=$(echo "$payload" | jq -r '.access // empty')
    refresh_token=$(echo "$payload" | jq -r '.refresh // empty')
    account_id=$(echo "$payload" | jq -r '.accountId // empty')
    id_token=$(echo "$payload" | jq -r '.idToken // empty')
    email=$(echo "$payload" | jq -r '.email // empty')

    if [[ -z "$access_token" ]] || [[ -z "$refresh_token" ]] || [[ -z "$account_id" ]]; then
        _cp_warn "Incomplete auth data, skipping OpenClaw sync"
        return 1
    fi

    expires="$(_cp_decode_jwt_exp_ms "$access_token")"
    if [[ -z "$expires" ]] && [[ -n "$id_token" ]]; then
        expires="$(_cp_decode_jwt_exp_ms "$id_token")"
    fi
    if [[ -z "$expires" ]]; then
        expires=0
    fi

    _cp_openclaw_update_auth_store "$access_token" "$refresh_token" "$account_id" "$expires" "$email"
    _cp_openclaw_update_oauth_import "$access_token" "$refresh_token" "$account_id" "$expires" "$email"

    _cp_debug "Synced OpenClaw auth store: $(_cp_openclaw_auth_store_path)"
    _cp_debug "Synced OpenClaw oauth import: $(_cp_openclaw_oauth_import_path)"
    return 0
}

_cp_openclaw_sync() {
    _cp_openclaw_sync_from_auth_file "$(_cp_get_codex_auth_path)"
}

_cp_openclaw_read_record() {
    local path="$1"
    local jq_account_expr="$2"
    local jq_refresh_expr="$3"
    local jq_email_expr="$4"

    if [[ ! -f "$path" ]]; then
        echo '{"status":"missing"}'
        return 0
    fi

    if ! jq -e '.' "$path" >/dev/null 2>&1; then
        echo '{"status":"invalid"}'
        return 0
    fi

    local refresh_token account_id email
    refresh_token=$(jq -r "$jq_refresh_expr // empty" "$path" 2>/dev/null)
    account_id=$(jq -r "$jq_account_expr // empty" "$path" 2>/dev/null)
    email=$(jq -r "$jq_email_expr // empty" "$path" 2>/dev/null)

    if [[ -z "$refresh_token" ]] || [[ -z "$account_id" ]]; then
        echo '{"status":"invalid"}'
        return 0
    fi

    jq -nc \
        --arg status "ready" \
        --arg accountId "$account_id" \
        --arg refresh "$refresh_token" \
        --arg email "$email" \
        '{status:$status,accountId:$accountId,refresh:$refresh,email:$email}'
}

_cp_openclaw_auth_store_record() {
    _cp_openclaw_read_record \
        "$(_cp_openclaw_auth_store_path)" \
        '.profiles["openai-codex:default"].accountId' \
        '.profiles["openai-codex:default"].refresh' \
        '.profiles["openai-codex:default"].email'
}

_cp_openclaw_oauth_import_record() {
    _cp_openclaw_read_record \
        "$(_cp_openclaw_oauth_import_path)" \
        '.["openai-codex"].accountId' \
        '.["openai-codex"].refresh' \
        '.["openai-codex"].email'
}

_cp_openclaw_record_status() {
    local record="$1"
    echo "$record" | jq -r '.status // "invalid"' 2>/dev/null
}

_cp_openclaw_record_relation_to_current() {
    local record="$1"
    local record_status
    record_status="$(_cp_openclaw_record_status "$record")"

    if [[ "$record_status" != "ready" ]]; then
        echo "$record_status"
        return 0
    fi

    local codex_auth="$(_cp_get_codex_auth_path)"
    if [[ ! -f "$codex_auth" ]]; then
        echo "present"
        return 0
    fi

    local codex_account_id codex_refresh_token store_account_id refresh_token
    codex_account_id="$(_cp_extract_account_id "$codex_auth")"
    codex_refresh_token="$(_cp_extract_refresh_token "$codex_auth")"
    store_account_id=$(echo "$record" | jq -r '.accountId // empty' 2>/dev/null)
    refresh_token=$(echo "$record" | jq -r '.refresh // empty' 2>/dev/null)

    if [[ "$store_account_id" == "$codex_account_id" ]] && [[ "$refresh_token" == "$codex_refresh_token" ]]; then
        echo "matches_current"
    else
        echo "different_current"
    fi
}

_cp_openclaw_auth_store_status() {
    _cp_openclaw_record_relation_to_current "$(_cp_openclaw_auth_store_record)"
}

_cp_openclaw_oauth_import_status() {
    _cp_openclaw_record_relation_to_current "$(_cp_openclaw_oauth_import_record)"
}

_cp_openclaw_primary_record() {
    local auth_store_record oauth_import_record
    auth_store_record="$(_cp_openclaw_auth_store_record)"
    if [[ "$(_cp_openclaw_record_status "$auth_store_record")" == "ready" ]]; then
        echo "$auth_store_record"
        return 0
    fi

    oauth_import_record="$(_cp_openclaw_oauth_import_record)"
    echo "$oauth_import_record"
}

_cp_openclaw_primary_profile_info() {
    local record="$1"
    local record_status
    record_status="$(_cp_openclaw_record_status "$record")"

    if [[ "$record_status" != "ready" ]]; then
        jq -nc '{label:"",email:"",accountId:""}'
        return 0
    fi

    local account_id email label="" profile
    account_id=$(echo "$record" | jq -r '.accountId // empty' 2>/dev/null)
    email=$(echo "$record" | jq -r '.email // empty' 2>/dev/null)
    profile="$(_cp_get_profile "$account_id")"
    if [[ -n "$profile" ]]; then
        label=$(echo "$profile" | jq -r '.label // empty' 2>/dev/null)
        if [[ -z "$email" ]]; then
            email=$(echo "$profile" | jq -r '.email // empty' 2>/dev/null)
        fi
    fi

    jq -nc \
        --arg label "$label" \
        --arg email "$email" \
        --arg accountId "$account_id" \
        '{label:$label,email:$email,accountId:$accountId}'
}

_cp_openclaw_relation_to_current_text() {
    local record="$1"
    local relation
    relation="$(_cp_openclaw_record_relation_to_current "$record")"

    case "$relation" in
        matches_current)
            echo "matches current Codex"
            ;;
        different_current)
            local current_profile current_label
            current_profile="$(_cp_get_current_profile || true)"
            current_label=$(echo "$current_profile" | jq -r '.label // empty' 2>/dev/null)
            if [[ -n "$current_label" ]]; then
                echo "different from current Codex ($current_label)"
            else
                echo "different from current Codex"
            fi
            ;;
        present)
            echo "current Codex auth missing"
            ;;
        invalid)
            echo "OpenClaw auth is invalid"
            ;;
        missing)
            echo "OpenClaw auth is missing"
            ;;
        *)
            echo "$relation"
            ;;
    esac
}

_cp_openclaw_status_label() {
    local status="$1"
    local text=""
    local color=""

    case "$status" in
        matches_current)
            text="matches current Codex"
            color="$CP_COLOR_GREEN"
            ;;
        different_current)
            text="different from current Codex"
            color="$CP_COLOR_YELLOW"
            ;;
        invalid)
            text="invalid"
            color="$CP_COLOR_RED"
            ;;
        missing)
            text="missing"
            color="$CP_COLOR_YELLOW"
            ;;
        present)
            text="present"
            color="$CP_COLOR_DIM"
            ;;
        *)
            text="$status"
            color="$CP_COLOR_DIM"
            ;;
    esac

    if _cp_use_color; then
        printf "%b%s%b" "$color" "$text" "$CP_COLOR_RESET"
    else
        printf "%s" "$text"
    fi
}

_cp_openclaw_print_doctor_field() {
    local label="$1"
    local value="$2"

    if _cp_use_color; then
        printf "  ${CP_COLOR_BOLD}%s:${CP_COLOR_RESET} %s\n" "$label" "$value"
    else
        printf "  %s: %s\n" "$label" "$value"
    fi
}

_cp_openclaw_format_status() {
    if ! _cp_openclaw_is_installed; then
        if _cp_use_color; then
            printf "  %bOpenClaw:%b    not installed\n" "$CP_COLOR_DIM" "$CP_COLOR_RESET"
        else
            printf "  OpenClaw:    not installed\n"
        fi
        return 0
    fi

    local auth_store_status oauth_import_status
    auth_store_status="$(_cp_openclaw_auth_store_status)"
    oauth_import_status="$(_cp_openclaw_oauth_import_status)"

    if _cp_use_color; then
        printf "  %bOpenClaw auth store:%b  %s\n" "$CP_COLOR_DIM" "$CP_COLOR_RESET" "$(_cp_openclaw_status_label "$auth_store_status")"
        printf "  %bOpenClaw oauth import:%b %s\n" "$CP_COLOR_DIM" "$CP_COLOR_RESET" "$(_cp_openclaw_status_label "$oauth_import_status")"
    else
        printf "  OpenClaw auth store:  %s\n" "$(_cp_openclaw_status_label "$auth_store_status")"
        printf "  OpenClaw oauth import: %s\n" "$(_cp_openclaw_status_label "$oauth_import_status")"
    fi
}

_cp_openclaw_format_doctor() {
    if ! _cp_openclaw_is_installed; then
        _cp_warn "OpenClaw is not installed in $(_cp_openclaw_state_dir)"
        return 1
    fi

    echo ""
    _cp_subheader "OpenClaw Doctor"
    echo ""
    _cp_openclaw_print_doctor_field "State dir" "$(_cp_openclaw_state_dir)"
    _cp_openclaw_print_doctor_field "Agent dir" "$(_cp_openclaw_agent_dir)"
    _cp_openclaw_print_doctor_field "Auth store" "$(_cp_openclaw_auth_store_path)"
    _cp_openclaw_print_doctor_field "OAuth import" "$(_cp_openclaw_oauth_import_path)"
    echo ""

    local primary_record primary_profile openclaw_label openclaw_email openclaw_account_id
    primary_record="$(_cp_openclaw_primary_record)"
    primary_profile="$(_cp_openclaw_primary_profile_info "$primary_record")"
    openclaw_label=$(echo "$primary_profile" | jq -r '.label // empty' 2>/dev/null)
    openclaw_email=$(echo "$primary_profile" | jq -r '.email // empty' 2>/dev/null)
    openclaw_account_id=$(echo "$primary_profile" | jq -r '.accountId // empty' 2>/dev/null)

    _cp_openclaw_print_doctor_field "OpenClaw profile" "${openclaw_label:-<unknown>}"
    _cp_openclaw_print_doctor_field "OpenClaw email" "${openclaw_email:-<unknown>}"
    _cp_openclaw_print_doctor_field "OpenClaw account" "${openclaw_account_id:-<unknown>}"
    _cp_openclaw_print_doctor_field "Relation to Codex" "$(_cp_openclaw_relation_to_current_text "$primary_record")"
    echo ""

    _cp_openclaw_format_status
    echo ""
}
