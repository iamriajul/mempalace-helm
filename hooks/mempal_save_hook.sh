#!/bin/bash
# MEMPALACE REMOTE — SAVE HOOK
#
# Claude Code "Stop" hook. Every SAVE_INTERVAL human messages, blocks the AI
# and instructs it to save the session to MemPalace via MCP tools.
#
# Works with the remote mcp-proxy deployment (Kubernetes or Docker).
# No local `mempalace` installation required.
#
# === INSTALL ===
# Run: hooks/install.sh   (auto-configures .claude/settings.local.json)
# Or manually add to .claude/settings.local.json:
#
#   "hooks": {
#     "Stop": [{
#       "matcher": "",
#       "hooks": [{"type": "command", "command": "/path/to/hooks/mempal_save_hook.sh", "timeout": 30}]
#     }]
#   }

SAVE_INTERVAL=15
STATE_DIR="$HOME/.mempalace/hook_state"
mkdir -p "$STATE_DIR"

INPUT=$(cat)

eval $(echo "$INPUT" | python3 -c "
import sys, json, re
data = json.load(sys.stdin)
safe = lambda s: re.sub(r'[^a-zA-Z0-9_/.\-~]', '', str(s))
print(f'SESSION_ID=\"{safe(data.get(\"session_id\", \"unknown\"))}\"')
print(f'STOP_HOOK_ACTIVE=\"{data.get(\"stop_hook_active\", False)}\"')
print(f'TRANSCRIPT_PATH=\"{safe(data.get(\"transcript_path\", \"\"))}\"')
" 2>/dev/null)

TRANSCRIPT_PATH="${TRANSCRIPT_PATH/#\~/$HOME}"

# Already in a save cycle — let the AI stop normally
if [ "$STOP_HOOK_ACTIVE" = "True" ] || [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    echo "{}"
    exit 0
fi

# Count human messages in transcript
if [ -f "$TRANSCRIPT_PATH" ]; then
    EXCHANGE_COUNT=$(python3 - "$TRANSCRIPT_PATH" <<'PYEOF'
import json, sys
count = 0
with open(sys.argv[1]) as f:
    for line in f:
        try:
            entry = json.loads(line)
            msg = entry.get('message', {})
            if isinstance(msg, dict) and msg.get('role') == 'user':
                content = msg.get('content', '')
                if isinstance(content, str) and '<command-message>' in content:
                    continue
                count += 1
        except:
            pass
print(count)
PYEOF
2>/dev/null)
else
    EXCHANGE_COUNT=0
fi

LAST_SAVE_FILE="$STATE_DIR/${SESSION_ID}_last_save"
LAST_SAVE=0
[ -f "$LAST_SAVE_FILE" ] && LAST_SAVE=$(cat "$LAST_SAVE_FILE")

MESSAGES_SINCE_SAVE=$(( ${EXCHANGE_COUNT:-0} - ${LAST_SAVE:-0} ))

echo "[$(date '+%H:%M:%S')] session=$SESSION_ID exchanges=$EXCHANGE_COUNT since_save=$MESSAGES_SINCE_SAVE" >> "$STATE_DIR/hook.log"

if [ "${MESSAGES_SINCE_SAVE:-0}" -ge "$SAVE_INTERVAL" ]; then
    echo "$EXCHANGE_COUNT" > "$LAST_SAVE_FILE"
    cat << 'HOOKJSON'
{
  "decision": "block",
  "reason": "MEMPALACE SAVE (remote). Before stopping, save this session:\n1. mempalace_diary_write — AAAK-compressed summary of what happened and what you learned\n2. mempalace_add_drawer — verbatim quotes, decisions, code snippets, key context (one drawer per topic)\n3. mempalace_kg_add — any new entity relationships (optional)\nUse appropriate wings/rooms based on the conversation content. Do NOT write to Claude Code's native auto-memory. Save to MemPalace, then stop normally."
}
HOOKJSON
else
    echo "{}"
fi
