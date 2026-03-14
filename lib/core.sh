#!/usr/bin/env bash
# codex-switch core functions
# Core functionality for profile management

# shellcheck disable=SC2155

# Ensure data directory structure exists
_cp_ensure_paths() {
    local dir="${CP_DATA_DIR:=$HOME/.codex-switch}"
    local profiles_dir="$dir/profiles"

    mkdir -p "$profiles_dir"

    # Create index.json if it doesn't exist
    local index_file="$dir/index.json"
    if [[ ! -f "$index_file" ]]; then
        echo '{"profiles":{}}' > "$index_file"
    fi
}

# Get the path to Codex auth.json
_cp_get_codex_auth_path() {
    echo "$HOME/.codex/auth.json"
}

_cp_get_profile_path() {
    local account_id="$1"
    echo "$CP_DATA_DIR/profiles/$account_id.json"
}

# Extract account_id from auth.json
_cp_extract_account_id() {
    local auth_file="$1"
    if [[ ! -f "$auth_file" ]]; then
        return 1
    fi

    # Try to extract account_id from the auth file
    # The format may vary, so try multiple approaches
    # Handle both flat and nested (tokens.*) structures
    local account_id
    account_id=$(jq -r '
        .account_id //                  # Direct account_id
        .user_id //                     # Legacy user_id
        .id //                          # Generic id
        .tokens.account_id //           # Nested in tokens
        .tokens.chatgpt_account_id //   # ChatGPT specific
        empty
    ' "$auth_file" 2>/dev/null)

    if [[ -z "$account_id" ]]; then
        # Generate a hash from the refresh_token as fallback
        local refresh_token
        refresh_token=$(jq -r '.refresh_token // .tokens.refresh_token // empty' "$auth_file" 2>/dev/null)
        if [[ -n "$refresh_token" ]]; then
            account_id=$(echo -n "$refresh_token" | md5sum | cut -c1-16)
        else
            account_id="unknown"
        fi
    fi

    echo "$account_id"
}

# Extract email from auth.json
_cp_extract_email() {
    local auth_file="$1"
    if [[ ! -f "$auth_file" ]]; then
        return 1
    fi

    # Try direct paths first
    local email
    email=$(jq -r '
        .email //                       # Direct email
        .user.email //                  # Nested in user
        empty
    ' "$auth_file" 2>/dev/null)

    if [[ -n "$email" && "$email" != "null" ]]; then
        echo "$email"
        return 0
    fi

    # Try decoding from JWT id_token
    local id_token
    id_token=$(jq -r '.tokens.id_token // .id_token // empty' "$auth_file" 2>/dev/null)

    if [[ -n "$id_token" ]]; then
        # Decode JWT payload (second part)
        local payload
        payload=$(echo "$id_token" | cut -d. -f2)

        # Add padding if needed
        local mod=$(( ${#payload} % 4 ))
        if [[ $mod -ne 0 ]]; then
            payload="${payload}$(printf '=%.0s' $(seq 1 $(( 4 - mod ))))"
        fi

        # Decode and extract email
        email=$(echo "$payload" | base64 -d 2>/dev/null | jq -r '.email // empty' 2>/dev/null)

        if [[ -n "$email" ]]; then
            echo "$email"
            return 0
        fi
    fi

    echo ""
}

# Extract plan from auth.json
_cp_extract_plan() {
    local auth_file="$1"
    if [[ ! -f "$auth_file" ]]; then
        return 1
    fi

    local plan
    plan=$(jq -r '
        .plan //                        # Direct plan
        .user.plan //                   # Nested in user
        .subscription.plan //           # Nested in subscription
        .tokens.plan_type //            # Nested in tokens
        .tokens.chatgpt_plan_type //    # ChatGPT specific
        empty
    ' "$auth_file" 2>/dev/null)

    if [[ -n "$plan" && "$plan" != "null" ]]; then
        echo "$plan"
        return 0
    fi

    # Try decoding from JWT id_token
    local id_token
    id_token=$(jq -r '.tokens.id_token // .id_token // empty' "$auth_file" 2>/dev/null)

    if [[ -n "$id_token" ]]; then
        # Decode JWT payload (second part)
        local payload
        payload=$(echo "$id_token" | cut -d. -f2)

        # Add padding if needed
        local mod=$(( ${#payload} % 4 ))
        if [[ $mod -ne 0 ]]; then
            payload="${payload}$(printf '=%.0s' $(seq 1 $(( 4 - mod ))))"
        fi

        # Decode and extract plan_type from nested auth object
        plan=$(echo "$payload" | base64 -d 2>/dev/null | jq -r '."https://api.openai.com/auth".chatgpt_plan_type // empty' 2>/dev/null)

        if [[ -n "$plan" ]]; then
            echo "$plan"
            return 0
        fi
    fi

    echo "unknown"
}

# Extract refresh_token from auth.json
_cp_extract_refresh_token() {
    local auth_file="$1"
    if [[ ! -f "$auth_file" ]]; then
        return 1
    fi

    jq -r '.refresh_token // .tokens.refresh_token // empty' "$auth_file" 2>/dev/null
}

# Check if auth.json is valid
_cp_is_valid_auth() {
    local auth_file="$1"
    if [[ ! -f "$auth_file" ]]; then
        return 1
    fi

    # Check if it has essential fields
    local refresh_token
    refresh_token=$(_cp_extract_refresh_token "$auth_file")

    [[ -n "$refresh_token" ]]
}

# Sync current auth.json back to its profile
# This is critical: when Codex refreshes tokens, we need to save them
_cp_sync_current() {
    local codex_auth="$(_cp_get_codex_auth_path)"

    if [[ ! -f "$codex_auth" ]]; then
        return 0
    fi

    local account_id
    account_id="$(_cp_extract_account_id "$codex_auth")"

    if [[ "$account_id" == "unknown" ]]; then
        _cp_warn "Could not identify current profile account_id"
        return 1
    fi

    # Find the profile by account_id in index
    local index="$CP_DATA_DIR/index.json"
    if [[ ! -f "$index" ]]; then
        return 0
    fi

    local profile_label
    profile_label=$(jq -r ".profiles[\"$account_id\"].label // empty" "$index" 2>/dev/null)

    if [[ -z "$profile_label" ]]; then
        # Profile doesn't exist, skip sync
        return 0
    fi

    # Copy current auth.json to profile
    local profile_file="$CP_DATA_DIR/profiles/$account_id.json"
    cp "$codex_auth" "$profile_file"

    _cp_debug "Synced current auth to profile: $profile_label"
}

# Copy profile to Codex auth location
_cp_load_profile() {
    local account_id="$1"
    local profile_file="$CP_DATA_DIR/profiles/$account_id.json"

    if [[ ! -f "$profile_file" ]]; then
        _cp_error "Profile file not found: $profile_file"
        return 1
    fi

    local codex_auth="$(_cp_get_codex_auth_path)"
    local codex_dir
    codex_dir=$(dirname "$codex_auth")

    mkdir -p "$codex_dir"
    cp "$profile_file" "$codex_auth"

    # Update last_seen timestamp
    _cp_update_last_seen "$account_id"

    return 0
}
# Get current profile info
_cp_get_current_profile() {
    local codex_auth="$(_cp_get_codex_auth_path)"

    if [[ ! -f "$codex_auth" ]]; then
        return 1
    fi

    local account_id
    account_id="$(_cp_extract_account_id "$codex_auth")"

    local index="$CP_DATA_DIR/index.json"
    if [[ ! -f "$index" ]]; then
        return 1
    fi

    jq -r ".profiles[\"$account_id\"] // empty" "$index" 2>/dev/null
}

# Check if a profile exists by label
_cp_profile_exists_by_label() {
    local label="$1"
    local index="$CP_DATA_DIR/index.json"

    if [[ ! -f "$index" ]]; then
        return 1
    fi

    local count
    count=$(jq -r ".profiles | to_entries[] | select(.value.label == \"$label\") | .key" "$index" 2>/dev/null | wc -l)

    [[ "$count" -gt 0 ]]
}

# Get account_id by label
_cp_get_account_id_by_label() {
    local label="$1"
    local index="$CP_DATA_DIR/index.json"

    if [[ ! -f "$index" ]]; then
        return 1
    fi

    jq -r ".profiles | to_entries[] | select(.value.label == \"$label\") | .key" "$index" 2>/dev/null | head -1
}

# Validate label format
_cp_validate_label() {
    local label="$1"

    # Label should be alphanumeric with dashes/underscores, not empty
    if [[ -z "$label" ]]; then
        _cp_error "Label cannot be empty"
        return 1
    fi

    if [[ ! "$label" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        _cp_error "Label must contain only letters, numbers, dashes, and underscores"
        return 1
    fi

    return 0
}

# Delete a profile
_cp_delete_profile() {
    local account_id="$1"

    local profile_file="$CP_DATA_DIR/profiles/$account_id.json"
    if [[ -f "$profile_file" ]]; then
        rm "$profile_file"
    fi

    # Remove from index
    _cp_remove_from_index "$account_id"
}
