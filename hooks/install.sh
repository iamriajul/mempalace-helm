#!/usr/bin/env bash
# Install MemPalace auto-save hooks and register remote MCP without using Claude CLI commands.

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${YELLOW}→${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; }

usage() {
  cat <<'USAGE'
Usage:
  hooks/install.sh --url <base-url> [--transport http|sse] [--name mempalace] [--scope global|project]

Examples:
  hooks/install.sh --url http://127.0.0.1:8080
  hooks/install.sh --url http://mempalace.mempalace.svc.cluster.local --scope project
USAGE
}

URL=""
TRANSPORT="http"
SERVER_NAME="mempalace"
SCOPE="global"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url)
      URL="${2:-}"
      shift 2
      ;;
    --transport)
      TRANSPORT="${2:-}"
      shift 2
      ;;
    --name)
      SERVER_NAME="${2:-}"
      shift 2
      ;;
    --scope)
      SCOPE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [ -z "$URL" ]; then
  err "Missing required --url"
  usage
  exit 1
fi

if [ "$TRANSPORT" != "http" ] && [ "$TRANSPORT" != "sse" ]; then
  err "--transport must be 'http' or 'sse'"
  exit 1
fi

if [ "$SCOPE" != "global" ] && [ "$SCOPE" != "project" ]; then
  err "--scope must be 'global' or 'project'"
  exit 1
fi

# Normalize URL: strip trailing slashes and any explicit /mcp or /sse suffix.
URL="${URL%/}"
URL="${URL%/mcp}"
URL="${URL%/sse}"
ENDPOINT="/mcp"
if [ "$TRANSPORT" = "sse" ]; then
  ENDPOINT="/sse"
fi
FINAL_URL="${URL}${ENDPOINT}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC_SAVE="${SCRIPT_DIR}/mempal_save_hook.sh"
HOOK_SRC_PRECOMPACT="${SCRIPT_DIR}/mempal_precompact_hook.sh"

if [ ! -f "$HOOK_SRC_SAVE" ] || [ ! -f "$HOOK_SRC_PRECOMPACT" ]; then
  err "Hook scripts not found next to installer: ${SCRIPT_DIR}"
  exit 1
fi

HOOK_DIR="$HOME/.mempalace/hooks"
mkdir -p "$HOOK_DIR"
cp "$HOOK_SRC_SAVE" "$HOOK_DIR/mempal_save_hook.sh"
cp "$HOOK_SRC_PRECOMPACT" "$HOOK_DIR/mempal_precompact_hook.sh"
chmod +x "$HOOK_DIR/mempal_save_hook.sh" "$HOOK_DIR/mempal_precompact_hook.sh"
ok "Installed hooks to $HOOK_DIR"

if [ "$SCOPE" = "project" ]; then
  SETTINGS_PATH="$(pwd)/.claude/settings.local.json"
else
  SETTINGS_PATH="$HOME/.claude/settings.local.json"
fi

mkdir -p "$(dirname "$SETTINGS_PATH")"
CLAUDE_CONFIG="$HOME/.claude.json"

SAVE_HOOK="$HOOK_DIR/mempal_save_hook.sh"
PRECOMPACT_HOOK="$HOOK_DIR/mempal_precompact_hook.sh"

info "Writing MCP server to ${CLAUDE_CONFIG}"
info "Writing hooks to ${SETTINGS_PATH}"

python3 - "$CLAUDE_CONFIG" "$SETTINGS_PATH" "$SERVER_NAME" "$TRANSPORT" "$FINAL_URL" "$SAVE_HOOK" "$PRECOMPACT_HOOK" <<'PYEOF'
import json
import os
import sys

claude_cfg_path = sys.argv[1]
settings_path = sys.argv[2]
server_name = sys.argv[3]
transport = sys.argv[4]
url = sys.argv[5]
save_hook = sys.argv[6]
precompact_hook = sys.argv[7]


def load_json(path: str):
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        text = f.read().strip()
        if not text:
            return {}
        return json.loads(text)


def dump_json(path: str, payload):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")


claude_cfg = load_json(claude_cfg_path)
mcp_servers = claude_cfg.setdefault("mcpServers", {})
mcp_servers[server_name] = {"type": transport, "url": url}
dump_json(claude_cfg_path, claude_cfg)

settings = load_json(settings_path)
hooks = settings.setdefault("hooks", {})

def ensure_hook(event: str, command: str):
    blocks = hooks.setdefault(event, [])
    exists = False
    for block in blocks:
        for hook in block.get("hooks", []):
            if hook.get("type") == "command" and hook.get("command") == command:
                exists = True
                break
        if exists:
            break
    if not exists:
        blocks.append({
            "matcher": "",
            "hooks": [{"type": "command", "command": command, "timeout": 30}],
        })

ensure_hook("Stop", save_hook)
ensure_hook("PreCompact", precompact_hook)
dump_json(settings_path, settings)

print(f"configured_mcp={url}")
print(f"configured_hooks={settings_path}")
PYEOF

ok "Configured MCP server '${SERVER_NAME}' -> ${FINAL_URL}"
ok "Configured Stop + PreCompact hooks"

echo ""
echo "Restart Claude Code to load new MCP + hook settings."
