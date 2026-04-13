Set up MemPalace remote MCP + auto-save hooks in one step.

## Usage

```
/mempalace-connect <URL>
```

Example: `/mempalace-connect http://mempalace.mempalace.svc.cluster.local`
Example: `/mempalace-connect http://127.0.0.1:8080`

The `<URL>` is the base URL of the MemPalace pod (no trailing slash, no path).
`/mcp` (Streamable HTTP) will be appended automatically.

## What this command does

Run each step below using your Bash tool. Stop and report any error before continuing.

### Step 1 — Download hook scripts

```bash
mkdir -p ~/.mempalace/hooks
curl -fsSL -o ~/.mempalace/hooks/mempal_save_hook.sh \
  https://raw.githubusercontent.com/MemPalace/mempalace/main/hooks/mempal_save_hook.sh
curl -fsSL -o ~/.mempalace/hooks/mempal_precompact_hook.sh \
  https://raw.githubusercontent.com/MemPalace/mempalace/main/hooks/mempal_precompact_hook.sh
chmod +x ~/.mempalace/hooks/mempal_save_hook.sh \
         ~/.mempalace/hooks/mempal_precompact_hook.sh
echo "Hooks downloaded to ~/.mempalace/hooks/"
ls -lh ~/.mempalace/hooks/
```

### Step 2 — Register the MCP server

Replace `<URL>` with the argument the user provided.

```bash
claude mcp add mempalace --transport http "<URL>/mcp"
```

Verify it was added:

```bash
claude mcp list
```

### Step 3 — Wire up the auto-save hooks

Resolve the hook paths and update (or create) `~/.claude/settings.local.json`.

```bash
SAVE_HOOK="$HOME/.mempalace/hooks/mempal_save_hook.sh"
PRECOMPACT_HOOK="$HOME/.mempalace/hooks/mempal_precompact_hook.sh"
SETTINGS="$HOME/.claude/settings.local.json"

mkdir -p "$(dirname "$SETTINGS")"

# Read existing file or start fresh
CURRENT=$(cat "$SETTINGS" 2>/dev/null || echo '{}')

python3 - "$SETTINGS" "$SAVE_HOOK" "$PRECOMPACT_HOOK" "$CURRENT" << 'PYEOF'
import json, sys

settings_path = sys.argv[1]
save_hook     = sys.argv[2]
precompact    = sys.argv[3]
current_json  = sys.argv[4]

cfg = json.loads(current_json)
hooks = cfg.setdefault("hooks", {})

# Stop / Save hook
stop_hooks = hooks.setdefault("Stop", [])
save_entry = {"type": "command", "command": save_hook, "timeout": 30}
# avoid duplicates
if not any(h.get("command") == save_hook for block in stop_hooks for h in block.get("hooks", [])):
    stop_hooks.append({"matcher": "", "hooks": [save_entry]})

# PreCompact hook
pre_hooks = hooks.setdefault("PreCompact", [])
pre_entry = {"type": "command", "command": precompact, "timeout": 30}
if not any(h.get("command") == precompact for block in pre_hooks for h in block.get("hooks", [])):
    pre_hooks.append({"matcher": "", "hooks": [pre_entry]})

with open(settings_path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")

print(f"Wrote {settings_path}")
PYEOF
```

### Step 4 — Verify the setup

```bash
echo "=== MCP servers ===" && claude mcp list
echo "=== Hook config ===" && python3 -c "
import json
cfg = json.load(open('$HOME/.claude/settings.local.json'))
hooks = cfg.get('hooks', {})
print('Stop hooks:     ', [h['command'] for b in hooks.get('Stop',[]) for h in b.get('hooks',[])])
print('PreCompact hooks:', [h['command'] for b in hooks.get('PreCompact',[]) for h in b.get('hooks',[])])
"
```

### Step 5 — Report to the user

Once all steps succeed, tell the user:

> MemPalace is connected at `<URL>/mcp`.
>
> **Auto-save hooks are active:**
> - Every 15 messages Claude will pause and save the session to MemPalace
> - Before every context compaction a full emergency save runs automatically
>
> Restart Claude Code for the hooks to take effect. No further setup needed.
