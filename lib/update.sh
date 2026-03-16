#!/usr/bin/env bash
# codex-switch self-update helpers

_CP_DEFAULT_UPDATE_REPO_URL="${CP_DEFAULT_UPDATE_REPO_URL:-https://github.com/wweggplant/codex-switch}"
_CP_DEFAULT_UPDATE_BRANCH="${CP_DEFAULT_UPDATE_BRANCH:-main}"

_cp_detect_update_repo_url() {
    if [[ -n "${CP_UPDATE_REPO_URL:-}" ]]; then
        echo "$CP_UPDATE_REPO_URL"
        return 0
    fi

    if [[ -n "${CP_PROJECT_DIR:-}" ]] && [[ -d "$CP_PROJECT_DIR/.git" ]]; then
        local remote_url
        remote_url="$(git -C "$CP_PROJECT_DIR" config --get remote.origin.url 2>/dev/null || true)"
        if [[ -n "$remote_url" ]]; then
            echo "$remote_url"
            return 0
        fi
    fi

    echo "$_CP_DEFAULT_UPDATE_REPO_URL"
}

_cp_detect_update_branch() {
    if [[ -n "${CP_UPDATE_BRANCH:-}" ]]; then
        echo "$CP_UPDATE_BRANCH"
        return 0
    fi

    if [[ -n "${CP_PROJECT_DIR:-}" ]] && [[ -d "$CP_PROJECT_DIR/.git" ]]; then
        local branch
        branch="$(git -C "$CP_PROJECT_DIR" branch --show-current 2>/dev/null || true)"
        if [[ -n "$branch" ]]; then
            echo "$branch"
            return 0
        fi
    fi

    echo "$_CP_DEFAULT_UPDATE_BRANCH"
}

_cp_detect_install_dir() {
    if [[ -n "${INSTALL_DIR:-}" ]]; then
        echo "$INSTALL_DIR"
        return 0
    fi

    local command_path=""
    command_path="$(command -v codex-switch 2>/dev/null || true)"
    if [[ -n "$command_path" ]]; then
        dirname "$command_path"
        return 0
    fi

    echo "$HOME/.local/bin"
}

_cp_update_managed_dir() {
    echo "${CP_UPDATE_DIR:-$CP_DATA_DIR/tmp/codex-switch}"
}

_cp_remove_tree() {
    local path="$1"

    if [[ -z "$path" ]] || [[ "$path" == "/" ]]; then
        return 1
    fi

    rm -rf "$path"
}

_cp_cmd_update() {
    local repo_url branch install_dir update_dir update_root stage_dir backup_dir=""

    if ! command -v git >/dev/null 2>&1; then
        _cp_error "git is required for codex-switch update"
        return 1
    fi

    repo_url="$(_cp_detect_update_repo_url)"
    branch="$(_cp_detect_update_branch)"
    install_dir="$(_cp_detect_install_dir)"
    update_dir="$(_cp_update_managed_dir)"
    update_root="$(dirname "$update_dir")"

    mkdir -p "$update_root"
    stage_dir="$(mktemp -d "$update_root/codex-switch.update.XXXXXX")"

    _cp_info "Downloading $repo_url ($branch) into $stage_dir"
    if ! git clone --depth 1 --branch "$branch" "$repo_url" "$stage_dir"; then
        _cp_remove_tree "$stage_dir"
        _cp_error "Failed to clone $repo_url ($branch)"
        return 1
    fi

    if [[ ! -f "$stage_dir/install.sh" ]]; then
        _cp_remove_tree "$stage_dir"
        _cp_error "Downloaded repo is missing install.sh"
        return 1
    fi

    if [[ -e "$update_dir" ]]; then
        backup_dir="$update_root/codex-switch.backup.$$"
        _cp_remove_tree "$backup_dir" 2>/dev/null || true
        mv "$update_dir" "$backup_dir"
    fi

    mv "$stage_dir" "$update_dir"
    stage_dir=""

    _cp_info "Running install.sh from $update_dir"
    if ! (
        cd "$update_dir"
        INSTALL_DIR="$install_dir" DATA_DIR="$CP_DATA_DIR" bash ./install.sh
    ); then
        _cp_error "install.sh failed during update"

        if [[ -d "$update_dir" ]]; then
            _cp_remove_tree "$update_dir"
        fi

        if [[ -n "$backup_dir" ]] && [[ -d "$backup_dir" ]]; then
            mv "$backup_dir" "$update_dir"

            mkdir -p "$install_dir"
            rm -f "$install_dir/codex-switch"
            ln -s "$update_dir/bin/codex-switch" "$install_dir/codex-switch"
        fi

        return 1
    fi

    if [[ -n "$backup_dir" ]] && [[ -d "$backup_dir" ]]; then
        _cp_remove_tree "$backup_dir"
    fi

    _cp_success "Updated codex-switch"
    _cp_info "Managed source: $update_dir"

    return 0
}
