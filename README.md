# codex-switch

`codex-switch` is a small Bash utility for managing multiple Codex accounts on one machine.

It exists for one specific problem: Codex OAuth refresh tokens rotate. If you manage accounts with symlinks or manual file copies, one client can refresh a token and silently invalidate the token another client still holds. The usual failure looks like `refresh_token_reused`.

`codex-switch` keeps each account as a real copy, syncs the currently active token back into its saved profile before switching, and can optionally sync the active token into OpenClaw.

## Features

- Manage multiple Codex profiles with simple labels such as `personal` and `work`
- Save the currently active `~/.codex/auth.json` as a reusable profile
- Switch profiles by copying, not symlinking
- Sync freshly rotated tokens back into the saved profile before every switch
- Sync the active Codex token into OpenClaw's auth store on demand
- Optionally restart a running OpenClaw gateway after sync so the new auth takes effect immediately
- Inspect Codex/OpenClaw auth alignment with a doctor command

## Why copy instead of symlink?

OAuth refresh tokens are not stable. When Codex refreshes its token, the old refresh token can become invalid immediately.

If `~/.codex/auth.json` is a symlink to some other file, a refresh can update one location while the rest of your setup still points at an older token snapshot. That is how you end up with one tool working and another failing.

`codex-switch` avoids that by treating each profile as a standalone file:

1. Read the current `~/.codex/auth.json`
2. Save it back into the matching stored profile
3. Copy the selected profile into `~/.codex/auth.json`
4. Optionally sync that token into OpenClaw

## Requirements

- `bash` 4+
- `jq`
- Optional: `fzf` for interactive selection
- Optional: OpenClaw, if you want `sync-openclaw` and `doctor` integration

Notes:

- On macOS, `/bin/bash` is often too old. Install a newer Bash and make sure `bash` on your `PATH` resolves to Bash 4+.
- The scripts use `#!/usr/bin/env bash` so the first `bash` in `PATH` is what gets executed.

## Installation

Clone the repository and run the installer:

```bash
git clone https://github.com/wweggplant/codex-switch
cd codex-switch
./install.sh
```

Replace the GitHub URL above with your actual repository URL.

By default this installs the executable to `~/.local/bin/codex-switch`.

If `~/.local/bin` is not on your `PATH`, add it:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## Quick start

Log into the first Codex account you want to keep, then save it:

```bash
codex-switch save --label personal
```

Log into another Codex account, then save that too:

```bash
codex-switch save --label work
```

Now you can switch between them:

```bash
codex-switch use --label personal
codex-switch use --label work
```

See what you have stored:

```bash
codex-switch list
codex-switch status
```

## Commands

### Save the current account

```bash
codex-switch save
codex-switch save --label personal
```

This reads the current `~/.codex/auth.json` and stores it under `~/.codex-switch/profiles/`.

### Use a saved account

```bash
codex-switch use
codex-switch use work
codex-switch use --label work
codex-switch load work
codex-switch load --label work
```

Before the switch happens, `codex-switch` first syncs the current `~/.codex/auth.json` back into the matching stored profile. That preserves any refresh token rotation that happened while you were using that account.

`use` is the recommended command. `load` is kept as a compatible alias. Both commands accept either `--label work` or the shorter positional form `work`.

By design, switching does not modify OpenClaw. If you want OpenClaw to follow the same account, run `codex-switch sync-openclaw` explicitly after the switch.

### List profiles

```bash
codex-switch list
```

Example output:

```text
  LABEL                 EMAIL                           PLAN       STATUS
  --------------------------------------------------------------------------------
  personal              me@example.com                  plus       ACTIVE
  work                  me@company.com                  plus
```

### Show current status

```bash
codex-switch status
```

Example output:

```text
  Current Profile

  Label:       personal
  Account ID:  abc123def456
  Email:       me@example.com
  Plan:        plus

  Total profiles: 2

  OpenClaw auth store:  synced
  OpenClaw oauth import: synced
```

### Sync OpenClaw explicitly

```bash
codex-switch sync-openclaw
codex-switch sync-openclaw --restart-gateway
```

Use this when:

- you re-authenticated Codex manually
- OpenClaw still has stale OAuth state
- you want to sync without switching profiles

Use `--restart-gateway` when the OpenClaw gateway is already running and you want the new auth to take effect immediately.

### Run doctor

```bash
codex-switch doctor
```

This prints the current Codex profile and the OpenClaw paths/status that matter:

- `~/.openclaw/agents/main/agent/auth-profiles.json`
- `~/.openclaw/credentials/oauth.json`

### Delete a saved profile

```bash
codex-switch delete
codex-switch delete --label work
codex-switch delete --label work --yes
```

## OpenClaw integration

OpenClaw support is optional.

When OpenClaw is present, `codex-switch sync-openclaw` updates:

- `~/.openclaw/agents/main/agent/auth-profiles.json`
- `~/.openclaw/credentials/oauth.json`

The first file is the primary auth store for current OpenClaw releases. The second is written for compatibility with legacy import flows.

This sync is explicit on purpose. Some people intentionally keep Codex and OpenClaw on different accounts. `codex-switch use` therefore only switches Codex unless you explicitly run `codex-switch sync-openclaw`.

If you switch accounts while OpenClaw is already running, the files will be updated immediately, but the running gateway may still have old credentials in memory. In that case:

```bash
codex-switch sync-openclaw
openclaw gateway restart
```

Or let `codex-switch` do both:

```bash
codex-switch sync-openclaw --restart-gateway
```

## How the switch flow works

The critical behavior is the pre-switch sync:

```text
codex-switch use --label work

1. Read current ~/.codex/auth.json
2. Save it back to the matching stored profile
3. Copy the selected profile to ~/.codex/auth.json
4. Leave OpenClaw unchanged by default
5. Update profile metadata (last_seen)
```

This is what keeps refresh token rotation from silently breaking older saved profiles.

## File layout

Repository layout:

```text
codex-switch/
├── bin/
│   └── codex-switch
├── src/
│   └── codex-switch.sh
├── lib/
│   ├── core.sh
│   ├── format.sh
│   ├── index.sh
│   └── openclaw.sh
├── install.sh
└── README.md
```

Local data layout:

```text
~/.codex-switch/
├── profiles/
│   ├── <account-id>.json
│   └── ...
└── index.json
```

Example `index.json`:

```json
{
  "profiles": {
    "abc123def456": {
      "label": "personal",
      "email": "me@example.com",
      "plan": "plus",
      "last_seen": "2026-03-01T10:00:00Z"
    }
  }
}
```

## Environment variables

| Variable | Default | Description |
| --- | --- | --- |
| `CP_DATA_DIR` | `~/.codex-switch` | Local profile storage directory |
| `CP_DEBUG` | `0` | Enable debug output |
| `CP_NO_COLOR` | `0` | Disable ANSI colors |
| `INSTALL_DIR` | `~/.local/bin` | Install destination for `install.sh` |
| `OPENCLAW_STATE_DIR` | `~/.openclaw` | Override OpenClaw state directory |
| `OPENCLAW_AGENT_DIR` | derived from state dir | Override OpenClaw agent auth directory |

## Security

This tool stores OAuth credentials on disk.

Treat the following as secrets:

- `~/.codex/auth.json`
- `~/.codex-switch/profiles/*.json`
- `~/.openclaw/agents/main/agent/auth-profiles.json`
- `~/.openclaw/credentials/oauth.json`

Do not commit them. Do not paste them into issues. Do not share them in screenshots.

## Troubleshooting

### `refresh_token_reused`

This usually means some client refreshed the token and another client kept an older refresh token.

Try:

```bash
codex-switch doctor
codex-switch sync-openclaw
openclaw gateway restart
```

If the active Codex login itself is wrong, re-authenticate Codex first, then run `codex-switch sync-openclaw` again.

### Profile not found

```bash
codex-switch list
```

### Need more debug output

```bash
CP_DEBUG=1 codex-switch use --label personal
```

## Development

Useful local checks:

```bash
bash -n bin/codex-switch
bash -n src/codex-switch.sh
bash -n lib/core.sh
bash -n lib/index.sh
bash -n lib/format.sh
bash -n lib/openclaw.sh
bash tests/run.sh
```

The project is intentionally dependency-light:

- runtime: Bash + `jq`
- no daemon
- no external service
- local file operations only

## License

MIT. See [LICENSE](LICENSE).
