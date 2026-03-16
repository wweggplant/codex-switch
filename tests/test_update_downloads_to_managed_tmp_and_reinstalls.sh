#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

home_dir="$(make_temp_home)"
trap 'rm -rf "$home_dir"' EXIT

remote_repo="$home_dir/remote-repo"
mkdir -p "$remote_repo/bin"

cat > "$remote_repo/bin/codex-switch" <<'EOF'
#!/usr/bin/env bash
echo "fixture-update"
EOF

cat > "$remote_repo/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
DATA_DIR="${DATA_DIR:-$HOME/.codex-switch}"

mkdir -p "$INSTALL_DIR" "$DATA_DIR/profiles"
rm -f "$INSTALL_DIR/codex-switch"
ln -s "$PROJECT_DIR/bin/codex-switch" "$INSTALL_DIR/codex-switch"
chmod +x "$PROJECT_DIR/bin/codex-switch"

if [[ ! -f "$DATA_DIR/index.json" ]]; then
    echo '{"profiles":{}}' > "$DATA_DIR/index.json"
fi
EOF

chmod +x "$remote_repo/bin/codex-switch" "$remote_repo/install.sh"

git -C "$remote_repo" init -b main >/dev/null
git -C "$remote_repo" config user.name "Codex Switch Test" >/dev/null
git -C "$remote_repo" config user.email "test@example.com" >/dev/null
git -C "$remote_repo" add install.sh bin/codex-switch >/dev/null
git -C "$remote_repo" commit -m "fixture" >/dev/null

output="$(PATH="$home_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$home_dir" CP_DATA_DIR="$home_dir/.codex-switch" CP_NO_COLOR=1 CP_UPDATE_REPO_URL="$remote_repo" CP_UPDATE_BRANCH="main" "$BIN" update 2>&1)"
expected_target="$(cd "$home_dir/.codex-switch/tmp/codex-switch/bin" && pwd)/codex-switch"

assert_contains "$output" "Updated codex-switch" "update should report success"
assert_eq "$expected_target" "$(readlink "$home_dir/.local/bin/codex-switch")" "update should reinstall codex-switch from the managed tmp directory"
assert_eq "fixture-update" "$("$home_dir/.local/bin/codex-switch")" "installed codex-switch should come from the downloaded repo"

echo "PASS: test_update_downloads_to_managed_tmp_and_reinstalls"
