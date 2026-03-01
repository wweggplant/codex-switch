#!/usr/bin/env bash
# codex-switch - Codex profile manager (source version)
# Source this file in your shell to get the codex-switch function
# Add to ~/.zshrc: source ~/path/to/codex-switch.sh

# Script directory
CP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CP_DATA_DIR="${CP_DATA_DIR:-$HOME/.codex-switch}"

# Source library files
source "$CP_SCRIPT_DIR/lib/format.sh"
source "$CP_SCRIPT_DIR/lib/core.sh"
source "$CP_SCRIPT_DIR/lib/index.sh"
source "$CP_SCRIPT_DIR/lib/openclaw.sh"

# Main codex-switch function
codex-switch() {
    # Parse arguments
    local command=""
    local label=""
    local yes_flag=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            save|load|list|status|delete|sync-openclaw|doctor)
                command="$1"
                shift
                ;;
            --label|-l)
                label="$2"
                shift 2
                ;;
            --yes|-y)
                yes_flag=1
                shift
                ;;
            --debug)
                export CP_DEBUG=1
                shift
                ;;
            --help|-h)
                _cp_usage
                return 0
                ;;
            *)
                if [[ -z "$command" ]]; then
                    _cp_error "Unknown command: $1"
                    _cp_usage
                    return 1
                else
                    _cp_error "Unknown option: $1"
                    return 1
                fi
                ;;
        esac
    done

    # Ensure data paths exist
    _cp_ensure_paths

    # Execute command
    case "$command" in
        save)
            _cp_cmd_save "$label"
            ;;
        load)
            _cp_cmd_load "$label"
            ;;
        list)
            _cp_cmd_list
            ;;
        status)
            _cp_cmd_status
            ;;
        sync-openclaw)
            _cp_cmd_sync_openclaw
            ;;
        doctor)
            _cp_cmd_doctor
            ;;
        delete)
            _cp_cmd_delete "$label" "$yes_flag"
            ;;
        "")
            _cp_error "No command specified"
            _cp_usage
            return 1
            ;;
        *)
            _cp_error "Unknown command: $command"
            _cp_usage
            return 1
            ;;
    esac
}

# Command: save current auth as profile
_cp_cmd_save() {
    local label="$1"

    local codex_auth="$(_cp_get_codex_auth_path)"

    if [[ ! -f "$codex_auth" ]]; then
        _cp_error "Codex auth.json not found at: $codex_auth"
        _cp_info "Please login to Codex first to create an auth.json file"
        return 1
    fi

    if ! _cp_is_valid_auth "$codex_auth"; then
        _cp_error "Invalid auth.json file (missing refresh_token)"
        return 1
    fi

    # Extract info
    local account_id email plan
    account_id="$(_cp_extract_account_id "$codex_auth")"
    email="$(_cp_extract_email "$codex_auth")"
    plan="$(_cp_extract_plan "$codex_auth")"

    # Prompt for label if not provided
    if [[ -z "$label" ]]; then
        echo ""
        echo -n "Enter label for this profile: "
        read -r label
        echo ""

        if [[ -z "$label" ]]; then
            _cp_error "Label cannot be empty"
            return 1
        fi
    fi

    # Validate label
    if ! _cp_validate_label "$label"; then
        return 1
    fi

    # Check if label already exists
    if _cp_profile_exists_by_label "$label"; then
        local existing_id
        existing_id="$(_cp_get_account_id_by_label "$label")"

        if [[ "$existing_id" != "$account_id" ]]; then
            _cp_error "Label '$label' is already used by another profile"
            return 1
        fi
    fi

    # Show confirmation
    _cp_format_save_confirm "$label" "${email:-unknown}" "${plan:-unknown}"

    local confirm=0
    if [[ "$yes_flag" -eq 0 ]]; then
        echo -n "Save profile? [Y/n] "
        read -r answer
        [[ "${answer,,}" != "n" ]] && confirm=1
    else
        confirm=1
    fi

    if [[ "$confirm" -eq 0 ]]; then
        _cp_info "Cancelled"
        return 0
    fi

    # Copy auth to profile directory
    local profile_file="$CP_DATA_DIR/profiles/$account_id.json"
    cp "$codex_auth" "$profile_file"

    # Update index
    _cp_upsert_index "$account_id" "$label" "$email" "$plan"

    _cp_success "Profile saved: $label"

    return 0
}

# Command: load a profile
_cp_cmd_load() {
    local label="$1"

    # First, sync current auth back to its profile (critical for token refresh!)
    _cp_sync_current

    # Check if profiles exist
    if ! _cp_has_profiles; then
        _cp_error "No profiles found. Save a profile first with: codex-switch save"
        return 1
    fi

    # Get label interactively if not provided
    if [[ -z "$label" ]]; then
        label="$(_cp_select_profile "Select profile to load")"

        if [[ -z "$label" ]]; then
            _cp_info "Cancelled"
            return 0
        fi
    fi

    # Validate label exists
    if ! _cp_profile_exists_by_label "$label"; then
        _cp_error "Profile not found: $label"
        _cp_info "Available profiles:"
        _cp_get_labels | while read -r l; do
            echo "  - $l"
        done
        return 1
    fi

    # Get account_id
    local account_id
    account_id="$(_cp_get_account_id_by_label "$label")"

    if [[ -z "$account_id" ]]; then
        _cp_error "Could not find account_id for label: $label"
        return 1
    fi

    # Load profile
    if ! _cp_load_profile "$account_id"; then
        return 1
    fi

    # OpenClaw sync is explicit on purpose.
    if _cp_openclaw_is_installed; then
        _cp_info "OpenClaw was not changed. Run 'codex-switch sync-openclaw' if you want to update OpenClaw too."
    fi

    # Get profile info for confirmation
    local profile_info
    profile_info="$(_cp_get_profile "$account_id")"
    local email
    email=$(echo "$profile_info" | jq -r '.email // empty')

    _cp_format_load_confirm "$label" "${email:-unknown}"

    return 0
}

# Command: list all profiles
_cp_cmd_list() {
    if ! _cp_has_profiles; then
        echo ""
        _cp_info "No profiles found"
        _cp_info "Save a profile first with: codex-switch save"
        echo ""
        return 0
    fi

    _cp_format_list
}

# Command: show current status
_cp_cmd_status() {
    _cp_format_status

    # Also show OpenClaw status
    if _cp_openclaw_is_installed; then
        _cp_openclaw_format_status
        echo ""
    fi
}

# Command: sync current Codex auth into OpenClaw stores
_cp_cmd_sync_openclaw() {
    if ! _cp_openclaw_is_installed; then
        _cp_error "OpenClaw is not installed at $(_cp_openclaw_state_dir)"
        return 1
    fi

    if ! _cp_openclaw_sync; then
        return 1
    fi

    _cp_success "OpenClaw auth synced"
    _cp_info "Restart OpenClaw gateway if it is already running to clear cached OAuth tokens"
    echo ""
    _cp_openclaw_format_status
    echo ""
}

# Command: inspect Codex/OpenClaw auth alignment
_cp_cmd_doctor() {
    _cp_format_status

    if _cp_openclaw_is_installed; then
        _cp_openclaw_format_doctor
    fi
}

# Command: delete a profile
_cp_cmd_delete() {
    local label="$1"
    local yes_flag="$2"

    if ! _cp_has_profiles; then
        _cp_error "No profiles found"
        return 1
    fi

    # Get label interactively if not provided
    if [[ -z "$label" ]]; then
        label="$(_cp_select_profile "Select profile to delete")"

        if [[ -z "$label" ]]; then
            _cp_info "Cancelled"
            return 0
        fi
    fi

    # Validate label exists
    if ! _cp_profile_exists_by_label "$label"; then
        _cp_error "Profile not found: $label"
        return 1
    fi

    # Get account_id and profile info
    local account_id profile_info email
    account_id="$(_cp_get_account_id_by_label "$label")"
    profile_info="$(_cp_get_profile "$account_id")"
    email=$(echo "$profile_info" | jq -r '.email // empty')

    # Show confirmation
    _cp_format_delete_confirm "$label" "${email:-unknown}"

    local confirm=0
    if [[ "$yes_flag" -eq 0 ]]; then
        echo -n "Delete this profile? [y/N] "
        read -r answer
        [[ "${answer,,}" == "y" ]] && confirm=1
    else
        confirm=1
    fi

    if [[ "$confirm" -eq 0 ]]; then
        _cp_info "Cancelled"
        return 0
    fi

    # Delete profile
    _cp_delete_profile "$account_id"

    _cp_success "Profile deleted: $label"

    return 0
}

# Aliases for convenience
alias codex-switch-load='codex-switch load'
alias codex-switch-save='codex-switch save'
alias codex-switch-list='codex-switch list'
alias codex-switch-status='codex-switch status'
alias codex-switch-delete='codex-switch delete'
