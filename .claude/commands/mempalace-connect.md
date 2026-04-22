Set up MemPalace remote MCP + auto-save hooks in one step (headless-safe, no `claude mcp` commands).

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

### Step 1 — Ensure bundled installer exists locally

```bash
mkdir -p ~/.mempalace/hooks
curl -fsSL -o ~/.mempalace/hooks/install.sh \
  https://raw.githubusercontent.com/iamriajul/mempalace-helm/master/hooks/install.sh
curl -fsSL -o ~/.mempalace/hooks/mempal_save_hook.sh \
  https://raw.githubusercontent.com/iamriajul/mempalace-helm/master/hooks/mempal_save_hook.sh
curl -fsSL -o ~/.mempalace/hooks/mempal_precompact_hook.sh \
  https://raw.githubusercontent.com/iamriajul/mempalace-helm/master/hooks/mempal_precompact_hook.sh
chmod +x ~/.mempalace/hooks/install.sh \
         ~/.mempalace/hooks/mempal_save_hook.sh \
         ~/.mempalace/hooks/mempal_precompact_hook.sh
```

### Step 2 — Configure MCP + hooks directly (headless)

Replace `<URL>` with the argument the user provided.

```bash
~/.mempalace/hooks/install.sh --url "<URL>" --transport http --scope global
```

This writes:
- MCP server entry to `~/.claude.json`
- Hook entries to `~/.claude/settings.local.json`

### Step 3 — Verify the setup

```bash
echo "=== MCP config ==="
python3 -c "
import json, os
p=os.path.expanduser('~/.claude.json')
cfg=json.load(open(p))
print(json.dumps(cfg.get('mcpServers',{}).get('mempalace',{}), indent=2))
"

echo "=== Hook config ==="
python3 -c "
import json, os
p=os.path.expanduser('~/.claude/settings.local.json')
cfg=json.load(open(p))
hooks=cfg.get('hooks',{})
print('Stop hooks:      ', [h['command'] for b in hooks.get('Stop',[]) for h in b.get('hooks',[])])
print('PreCompact hooks:', [h['command'] for b in hooks.get('PreCompact',[]) for h in b.get('hooks',[])])
"
```

### Step 4 — Report to the user

Once all steps succeed, tell the user:

> MemPalace is connected at `<URL>/mcp`.
>
> Auto-save hooks are active:
> - Every 15 messages: save checkpoint prompt
> - Before context compaction: emergency save prompt
>
> Restart Claude Code for settings to take effect.
