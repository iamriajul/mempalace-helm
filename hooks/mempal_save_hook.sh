#!/usr/bin/env bash
# MemPalace Stop hook for Claude Code.
# Blocks every SAVE_INTERVAL user messages and asks the model to persist memory via MCP tools.

set -euo pipefail

SAVE_INTERVAL="${SAVE_INTERVAL:-15}"
STATE_DIR="${HOME}/.mempalace/hook_state"
mkdir -p "${STATE_DIR}"

INPUT="$(cat)"

# Parse all fields once and sanitize for shell usage.
eval "$(printf '%s' "$INPUT" | python3 -c '
import json, re, sys

def safe(s):
    return re.sub(r"[^a-zA-Z0-9_./~:-]", "", str(s))

payload = json.load(sys.stdin)
session_id = safe(payload.get("session_id", "unknown"))
stop_hook_active = payload.get("stop_hook_active", False)
stop_hook_active = "true" if str(stop_hook_active).lower() in ("true", "1", "yes") else "false"
transcript_path = safe(payload.get("transcript_path", ""))
print(f"SESSION_ID=\"{session_id}\"")
print(f"STOP_HOOK_ACTIVE=\"{stop_hook_active}\"")
print(f"TRANSCRIPT_PATH=\"{transcript_path}\"")
' 2>/dev/null)"

TRANSCRIPT_PATH="${TRANSCRIPT_PATH/#\~/$HOME}"

# Allow stop after the model already entered save flow.
if [ "${STOP_HOOK_ACTIVE}" = "true" ]; then
  echo '{}'
  exit 0
fi

EXCHANGE_COUNT=0
if [ -n "${TRANSCRIPT_PATH}" ] && [ -f "${TRANSCRIPT_PATH}" ]; then
  EXCHANGE_COUNT="$(python3 - "${TRANSCRIPT_PATH}" <<'PYEOF'
import json
import sys

count = 0
with open(sys.argv[1], "r", encoding="utf-8") as f:
    for line in f:
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        msg = entry.get("message")
        if not isinstance(msg, dict):
            continue
        if msg.get("role") != "user":
            continue
        content = msg.get("content", "")
        if isinstance(content, str) and "<command-message>" in content:
            continue
        count += 1
print(count)
PYEOF
)"
fi

LAST_SAVE_FILE="${STATE_DIR}/${SESSION_ID}_last_save"
LAST_SAVE=0
if [ -f "${LAST_SAVE_FILE}" ]; then
  LAST_SAVE_RAW="$(cat "${LAST_SAVE_FILE}" || true)"
  if [[ "${LAST_SAVE_RAW}" =~ ^[0-9]+$ ]]; then
    LAST_SAVE="${LAST_SAVE_RAW}"
  fi
fi

SINCE_LAST=$((EXCHANGE_COUNT - LAST_SAVE))

if [ "${SINCE_LAST}" -ge "${SAVE_INTERVAL}" ] && [ "${EXCHANGE_COUNT}" -gt 0 ]; then
  echo "${EXCHANGE_COUNT}" > "${LAST_SAVE_FILE}"
  cat <<'HOOKJSON'
{
  "decision": "block",
  "reason": "MemPalace checkpoint: before stopping, save key decisions, code changes, and useful facts to MemPalace using MCP tools (diary + drawer) so nothing important is lost."
}
HOOKJSON
  exit 0
fi

echo '{}'
