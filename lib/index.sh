#!/usr/bin/env bash
# codex-switch index management
# Functions for managing the index.json metadata

# shellcheck disable=SC2155

# Read index.json
_cp_read_index() {
    local index_file="$CP_DATA_DIR/index.json"

    if [[ ! -f "$index_file" ]]; then
        echo '{"profiles":{}}'
        return 0
    fi

    cat "$index_file"
}

# Write index.json atomically
_cp_write_index() {
    local content="$1"
    local index_file="$CP_DATA_DIR/index.json"
    local temp_file="$index_file.tmp"

    echo "$content" > "$temp_file"
    mv "$temp_file" "$index_file"
}

# Get ISO 8601 timestamp
_cp_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Add or update a profile in the index
_cp_upsert_index() {
    local account_id="$1"
    local label="$2"
    local email="${3:-}"
    local plan="${4:-unknown}"

    local index="$(_cp_read_index)"
    local timestamp="$(_cp_timestamp)"

    local new_index
    new_index=$(echo "$index" | jq --arg id "$account_id" \
        --arg label "$label" \
        --arg email "$email" \
        --arg plan "$plan" \
        --arg timestamp "$timestamp" \
        '.profiles[$id] = {
            label: $label,
            email: $email,
            plan: $plan,
            last_seen: $timestamp
        }')

    _cp_write_index "$new_index"
}

# Update last_seen timestamp for a profile
_cp_update_last_seen() {
    local account_id="$1"
    local timestamp="$(_cp_timestamp)"

    local index="$(_cp_read_index)"

    local new_index
    new_index=$(echo "$index" | jq --arg id "$account_id" \
        --arg timestamp "$timestamp" \
        '.profiles[$id].last_seen = $timestamp')

    _cp_write_index "$new_index"
}

# Remove a profile from the index
_cp_remove_from_index() {
    local account_id="$1"

    local index="$(_cp_read_index)"

    local new_index
    new_index=$(echo "$index" | jq --arg id "$account_id" \
        'del(.profiles[$id])')

    _cp_write_index "$new_index"
}

# Get all profiles from index
_cp_get_all_profiles() {
    local index="$(_cp_read_index)"

    echo "$index" | jq -r '.profiles | to_entries[] | @json' 2>/dev/null
}

# Get profile by account_id
_cp_get_profile() {
    local account_id="$1"

    local index="$(_cp_read_index)"

    echo "$index" | jq -r ".profiles[\"$account_id\"] // empty" 2>/dev/null
}

# Get profile by label
_cp_get_profile_by_label() {
    local label="$1"

    local index="$(_cp_read_index)"

    echo "$index" | jq -r ".profiles | to_entries[] | select(.value.label == \"$label\") | .value" 2>/dev/null | head -1
}

# Get account_id by label
_cp_get_account_id_by_label() {
    local label="$1"

    local index="$(_cp_read_index)"

    echo "$index" | jq -r ".profiles | to_entries[] | select(.value.label == \"$label\") | .key" 2>/dev/null | head -1
}

# Check if index has any profiles
_cp_has_profiles() {
    local index="$(_cp_read_index)"

    local count
    count=$(echo "$index" | jq -r '.profiles | length' 2>/dev/null)

    [[ "$count" -gt 0 ]]
}

# Get profile count
_cp_profile_count() {
    local index="$(_cp_read_index)"

    echo "$index" | jq -r '.profiles | length' 2>/dev/null || echo "0"
}

# Get labels list for interactive selection
_cp_get_labels() {
    local index="$(_cp_read_index)"

    echo "$index" | jq -r '.profiles | to_entries[] | .value.label' 2>/dev/null | sort
}
