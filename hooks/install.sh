#!/bin/bash
# MEMPALACE REMOTE — HOOK INSTALLER
#
# Installs the auto-save hooks into .claude/settings.local.json
# for the current project (or globally with --global).
#
# Usage:
#   ./hooks/install.sh              # install into .claude/settings.local.json (project)
#   ./hooks/install.sh --global     # install into ~/.claude/settings.local.json (all projects)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAVE_HOOK="$SCRIPT_DIR/mempal_save_hook.sh"
PRECOMPACT_HOOK="$SCRIPT_DIR/mempal_precompact_hook.sh"

chmod +x "$SAVE_HOOK" "$PRECOMPACT_HOOK"

# Determine target settings file
if [ "$1" = "--global" ]; then
    SETTINGS_FILE="$HOME/.claude/settings.local.json"
    echo "Installing hooks globally → $SETTINGS_FILE"
else
    SETTINGS_FILE=".claude/settings.local.json"
    mkdir -p .claude
    echo "Installing hooks for this project → $SETTINGS_FILE"
fi

# Build the hooks JSON block
HOOKS_JSON=$(cat << ENDJSON
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$SAVE_HOOK",
            "timeout": 30
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$PRECOMPACT_HOOK",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
ENDJSON
)

if [ -f "$SETTINGS_FILE" ]; then
    # Merge hooks into existing file using Python
    python3 - "$SETTINGS_FILE" "$SAVE_HOOK" "$PRECOMPACT_HOOK" << 'PYEOF'
import json, sys

settings_file = sys.argv[1]
save_hook = sys.argv[2]
precompact_hook = sys.argv[3]

with open(settings_file) as f:
    settings = json.load(f)

hooks = settings.setdefault("hooks", {})

# Stop hook
stop_entry = {"type": "command", "command": save_hook, "timeout": 30}
stop_hooks = hooks.setdefault("Stop", [])
if not stop_hooks:
    stop_hooks.append({"matcher": "", "hooks": [stop_entry]})
elif not any(h.get("command") == save_hook for group in stop_hooks for h in group.get("hooks", [])):
    stop_hooks[0].setdefault("hooks", []).append(stop_entry)

# PreCompact hook
precompact_entry = {"type": "command", "command": precompact_hook, "timeout": 30}
precompact_hooks = hooks.setdefault("PreCompact", [])
if not precompact_hooks:
    precompact_hooks.append({"matcher": "", "hooks": [precompact_entry]})
elif not any(h.get("command") == precompact_hook for group in precompact_hooks for h in group.get("hooks", [])):
    precompact_hooks[0].setdefault("hooks", []).append(precompact_entry)

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("Merged hooks into existing settings file.")
PYEOF
else
    echo "$HOOKS_JSON" > "$SETTINGS_FILE"
    echo "Created $SETTINGS_FILE"
fi

echo ""
echo "✓ MemPalace auto-save hooks installed."
echo "  Save hook:      $SAVE_HOOK"
echo "  PreCompact hook: $PRECOMPACT_HOOK"
echo ""
echo "Make sure the MCP server is registered:"
echo "  claude mcp add mempalace --transport http http://<your-mempalace-host>/mcp"
