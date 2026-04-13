#!/bin/bash
# MEMPALACE REMOTE — PRE-COMPACT HOOK
#
# Claude Code "PreCompact" hook. Fires RIGHT BEFORE context compression.
# Always blocks — forces a full save before the window shrinks.
#
# Works with the remote mcp-proxy deployment (Kubernetes or Docker).
# No local `mempalace` installation required.
#
# === INSTALL ===
# Run: hooks/install.sh   (auto-configures .claude/settings.local.json)
# Or manually add to .claude/settings.local.json:
#
#   "hooks": {
#     "PreCompact": [{
#       "matcher": "",
#       "hooks": [{"type": "command", "command": "/path/to/hooks/mempal_precompact_hook.sh", "timeout": 30}]
#     }]
#   }

STATE_DIR="$HOME/.mempalace/hook_state"
mkdir -p "$STATE_DIR"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id','unknown'))" 2>/dev/null)

echo "[$(date '+%H:%M:%S')] PRE-COMPACT session=$SESSION_ID" >> "$STATE_DIR/hook.log"

cat << 'HOOKJSON'
{
  "decision": "block",
  "reason": "COMPACTION IMMINENT (MemPalace remote). Save ALL session content before context is lost:\n1. mempalace_diary_write — thorough AAAK-compressed session summary\n2. mempalace_add_drawer — ALL verbatim quotes, decisions, code, context (one drawer per topic)\n3. mempalace_kg_add — entity relationships (optional)\nBe thorough — after compaction, detailed context is gone. Do NOT write to Claude Code's native auto-memory. Save everything to MemPalace, then allow compaction to proceed."
}
HOOKJSON
