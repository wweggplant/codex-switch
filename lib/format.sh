#!/usr/bin/env bash
# codex-switch format utilities
# Formatted output with colors and tables

# shellcheck disable=SC2155,SC2034

# Color definitions
CP_COLOR_RESET="\033[0m"
CP_COLOR_GREEN="\033[32m"
CP_COLOR_YELLOW="\033[33m"
CP_COLOR_RED="\033[31m"
CP_COLOR_CYAN="\033[36m"
CP_COLOR_BLUE="\033[34m"
CP_COLOR_DIM="\033[2m"
CP_COLOR_BOLD="\033[1m"

# Check if colors should be used
_cp_use_color() {
    [[ -t 1 ]] && [[ "${CP_NO_COLOR:-}" != "1" ]]
}

# Print colored message if colors are enabled
_cp_color() {
    local color="$1"
    shift

    if _cp_use_color; then
        echo -e "${color}$*${CP_COLOR_RESET}"
    else
        echo "$*"
    fi
}

# Print info message
_cp_info() {
    _cp_color "$CP_COLOR_CYAN" "$@"
}

# Print success message
_cp_success() {
    _cp_color "$CP_COLOR_GREEN" "✓ $*"
}

# Print warning message
_cp_warn() {
    _cp_color "$CP_COLOR_YELLOW" "⚠ $*" >&2
}

# Print error message
_cp_error() {
    _cp_color "$CP_COLOR_RED" "✗ $*" >&2
}

# Print debug message (only if CP_DEBUG is set)
_cp_debug() {
    if [[ "${CP_DEBUG:-}" == "1" ]]; then
        _cp_color "$CP_COLOR_DIM" "[DEBUG] $*" >&2
    fi
}

# Print header
_cp_header() {
    echo ""
    _cp_color "$CP_COLOR_BOLD$CP_COLOR_CYAN" "$*"
    echo ""
}

# Print sub-header
_cp_subheader() {
    _cp_color "$CP_COLOR_BOLD" "$*"
}

# Format profile list
_cp_format_list() {
    local current_account_id=""

    # Get current profile account_id if auth.json exists
    local codex_auth="$(_cp_get_codex_auth_path)"
    if [[ -f "$codex_auth" ]]; then
        current_account_id="$(_cp_extract_account_id "$codex_auth")"
    fi

    echo ""

    # Header
    local header1="LABEL"
    local header2="EMAIL"
    local header3="PLAN"
    local header4="STATUS"

    printf "  ${CP_COLOR_BOLD}%-20s  %-30s  %-10s  %s${CP_COLOR_RESET}\n" "$header1" "$header2" "$header3" "$header4"
    printf "  %s\n" "--------------------------------------------------------------------------------"

    # Profiles
    while IFS= read -r profile_json; do
        if [[ -z "$profile_json" ]]; then
            continue
        fi

        local key label email plan last_seen
        key=$(echo "$profile_json" | jq -r '.key')
        label=$(echo "$profile_json" | jq -r '.value.label')
        email=$(echo "$profile_json" | jq -r '.value.email // "-"')
        plan=$(echo "$profile_json" | jq -r '.value.plan // "-"')

        # Determine status
        local status=""
        local status_color=""
        if [[ "$key" == "$current_account_id" ]]; then
            status="ACTIVE"
            status_color="$CP_COLOR_GREEN"
        else
            status=""
            status_color="$CP_COLOR_DIM"
        fi

        # Print row
        printf "  %-20s  %-30s  " "$label" "$email"

        # Colorize plan
        if [[ "$plan" == "plus" ]]; then
            printf "${CP_COLOR_YELLOW}%-10s${CP_COLOR_RESET}  " "$plan"
        elif [[ "$plan" == "pro" ]]; then
            printf "${CP_COLOR_CYAN}%-10s${CP_COLOR_RESET}  " "$plan"
        else
            printf "%-10s  " "$plan"
        fi

        # Print status
        if [[ -n "$status" ]]; then
            printf "${status_color}%s${CP_COLOR_RESET}\n" "$status"
        else
            printf "\n"
        fi
    done < <(_cp_get_all_profiles)

    echo ""
}

# Format status output
_cp_format_status() {
    local codex_auth="$(_cp_get_codex_auth_path)"

    echo ""

    if [[ ! -f "$codex_auth" ]]; then
        _cp_warn "No active profile found (auth.json doesn't exist)"
        echo ""
        return 1
    fi

    local account_id email plan
    account_id="$(_cp_extract_account_id "$codex_auth")"
    email="$(_cp_extract_email "$codex_auth")"
    plan="$(_cp_extract_plan "$codex_auth")"

    # Get label from index
    local index="$CP_DATA_DIR/index.json"
    local label=""
    if [[ -f "$index" ]]; then
        label=$(jq -r ".profiles[\"$account_id\"].label // empty" "$index" 2>/dev/null)
    fi

    _cp_subheader "Current Profile"
    echo ""

    printf "  ${CP_COLOR_BOLD}Label:${CP_COLOR_RESET}       %s\n" "${label:-<unknown>}"
    printf "  ${CP_COLOR_BOLD}Account ID:${CP_COLOR_RESET}  %s\n" "$account_id"
    printf "  ${CP_COLOR_BOLD}Email:${CP_COLOR_RESET}       %s\n" "${email:-<unknown>}"
    printf "  ${CP_COLOR_BOLD}Plan:${CP_COLOR_RESET}        %s\n" "$plan"

    echo ""

    # Total profiles count
    local total
    total="$(_cp_profile_count)"
    printf "  ${CP_COLOR_DIM}Total profiles: %s${CP_COLOR_RESET}\n" "$total"

    echo ""
}

# Format save confirmation
_cp_format_save_confirm() {
    local label="$1"
    local email="$2"
    local plan="$3"

    echo ""
    _cp_subheader "Saving Profile"
    echo ""
    echo "  Label:  $label"
    echo "  Email:  $email"
    echo "  Plan:   $plan"
    echo ""
}

# Format load confirmation
_cp_format_load_confirm() {
    local label="$1"
    local email="$2"

    echo ""
    _cp_success "Loaded profile: $label ($email)"
    echo ""
}

# Format delete confirmation
_cp_format_delete_confirm() {
    local label="$1"
    local email="$2"

    echo ""
    _cp_warn "Delete profile: $label ($email)?"
    echo ""
}

# Interactive selection using fzf or simple menu
_cp_select_profile() {
    local prompt="${1:-Select a profile}"

    local labels
    labels="$(_cp_get_labels)"

    if [[ -z "$labels" ]]; then
        _cp_error "No profiles available"
        return 1
    fi

    # Check if fzf is available
    if command -v fzf &>/dev/null; then
        echo "$labels" | fzf --prompt="$prompt > " --height=10 --reverse
    else
        # Simple numbered menu
        local i=1
        local -a label_array

        echo ""
        while IFS= read -r label; do
            [[ -z "$label" ]] && continue
            echo "  [$i] $label"
            label_array+=("$label")
            ((i++))
        done < <(echo "$labels")

        echo ""
        echo -n "Select number: "

        local selection
        read -r selection

        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "${#label_array[@]}" ]]; then
            echo "${label_array[$((selection - 1))]}"
        else
            _cp_error "Invalid selection"
            return 1
        fi
    fi
}

# Print usage
_cp_usage() {
    cat <<'EOF'
Usage: codex-switch <command> [options]

Commands:
  save [--label <name>]    Save current auth.json as a profile
  use [--label <name>]     Switch to a profile (interactive without --label)
  load [--label <name>]    Alias of "use" (kept for compatibility)
  list                     List all profiles
  status                   Show current profile status
  sync-openclaw            Sync current Codex auth into OpenClaw
  doctor                   Show Codex/OpenClaw auth health
  delete [--label <name>]  Delete a profile (interactive without --label)

Options:
  --label <name>     Specify profile label (bypasses interactive selection)
  --yes, -y          Skip confirmation prompts
  --debug            Enable debug output
  --help, -h         Show this help message

Examples:
  codex-switch save --label personal
  codex-switch use --label work
  codex-switch list
  codex-switch status
  codex-switch sync-openclaw
  codex-switch doctor
  codex-switch delete --label work

EOF
}
