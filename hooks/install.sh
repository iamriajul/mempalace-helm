#!/usr/bin/env bash
# Install MemPalace auto-save hooks and register remote MCP without Claude CLI commands.

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${YELLOW}→${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; }

usage() {
  cat <<'USAGE'
Usage:
  hooks/install.sh [--url <base-url>] [--transport http|sse] [--name mempalace] [--scope global|project] [--token <bearer-token>] [--no-prompt]

Examples:
  hooks/install.sh --url http://127.0.0.1:8080
  hooks/install.sh --url http://mempalace.mempalace.svc.cluster.local --scope project
USAGE
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Missing required command: $1"
    exit 1
  fi
}

URL=""
TRANSPORT="http"
SERVER_NAME="mempalace"
SCOPE="global"
TOKEN="${MCP_BEARER_TOKEN:-${BEARER_TOKEN:-}}"
PROMPT="true"

can_prompt() {
  [ "$PROMPT" = "true" ] && [ -r /dev/tty ]
}

prompt_line() {
  local prompt="$1"
  local value
  if ! can_prompt; then
    return 1
  fi
  IFS= read -r -p "$prompt" value < /dev/tty || return 1
  printf '%s' "$value"
}

prompt_secret() {
  local prompt="$1"
  local value
  if ! can_prompt; then
    return 1
  fi
  IFS= read -r -s -p "$prompt" value < /dev/tty || return 1
  printf '\n' > /dev/tty
  printf '%s' "$value"
}

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
    --token)
      TOKEN="${2:-}"
      shift 2
      ;;
    --no-prompt)
      PROMPT="false"
      shift
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

if [ -z "$URL" ] && [ -n "${SERVICE_URL:-}" ]; then
  URL="${SERVICE_URL}"
fi

if [ -z "$URL" ]; then
  if can_prompt; then
    URL="$(prompt_line 'Enter MemPalace SERVICE_URL (example: http://127.0.0.1:8080): ' || true)"
    URL="${URL:-}"
  fi
fi

if [ -z "$URL" ]; then
  err "Missing URL. Pass --url, set SERVICE_URL, or run interactively with a TTY."
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
if [[ ! "$URL" =~ ^https?:// ]]; then
  err "--url must start with http:// or https://"
  exit 1
fi
if [[ ! "$SERVER_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  err "--name may only contain letters, digits, dot, underscore, or hyphen"
  exit 1
fi
if printf '%s' "$TOKEN" | grep -q '[[:cntrl:]]'; then
  err "--token contains unsupported control characters"
  exit 1
fi

if [ -z "$TOKEN" ] && can_prompt; then
  USE_TOKEN="$(prompt_line 'Use bearer token auth? [y/N]: ' || true)"
  case "${USE_TOKEN:-}" in
    y|Y|yes|YES)
      TOKEN="$(prompt_secret 'Bearer token: ' || true)"
      ;;
  esac
fi

need_cmd python3

# Normalize URL: strip trailing slashes and explicit endpoint suffixes.
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
if [ "$HOOK_SRC_SAVE" != "$HOOK_DIR/mempal_save_hook.sh" ]; then
  cp "$HOOK_SRC_SAVE" "$HOOK_DIR/mempal_save_hook.sh"
fi
if [ "$HOOK_SRC_PRECOMPACT" != "$HOOK_DIR/mempal_precompact_hook.sh" ]; then
  cp "$HOOK_SRC_PRECOMPACT" "$HOOK_DIR/mempal_precompact_hook.sh"
fi
chmod +x "$HOOK_DIR/mempal_save_hook.sh" "$HOOK_DIR/mempal_precompact_hook.sh"
ok "Installed hooks to $HOOK_DIR"

if [ "$SCOPE" = "project" ]; then
  SETTINGS_PATH="$(pwd)/.claude/settings.local.json"
else
  SETTINGS_PATH="$HOME/.claude/settings.local.json"
fi
CLAUDE_CONFIG="$HOME/.claude.json"

mkdir -p "$(dirname "$SETTINGS_PATH")"
mkdir -p "$(dirname "$CLAUDE_CONFIG")"

SAVE_HOOK="$HOOK_DIR/mempal_save_hook.sh"
PRECOMPACT_HOOK="$HOOK_DIR/mempal_precompact_hook.sh"

info "Writing MCP server to ${CLAUDE_CONFIG}"
info "Writing hooks to ${SETTINGS_PATH}"

python3 - "$CLAUDE_CONFIG" "$SETTINGS_PATH" "$SERVER_NAME" "$TRANSPORT" "$FINAL_URL" "$SAVE_HOOK" "$PRECOMPACT_HOOK" "$TOKEN" <<'PYEOF'
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
token = sys.argv[8]


def load_json(path: str):
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        raw = f.read().strip()
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON in {path}: {exc}")


def dump_json(path: str, payload):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp_path = f"{path}.tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")
    os.replace(tmp_path, path)


def ensure_hook(hooks_cfg: dict, event: str, command: str):
    blocks = hooks_cfg.setdefault(event, [])
    for block in blocks:
        for hook in block.get("hooks", []):
            if hook.get("type") == "command" and hook.get("command") == command:
                return
    blocks.append({
        "matcher": "",
        "hooks": [{"type": "command", "command": command, "timeout": 30}],
    })


claude_cfg = load_json(claude_cfg_path)
servers = claude_cfg.setdefault("mcpServers", {})
current = servers.get(server_name, {})
if not isinstance(current, dict):
    current = {}
server_cfg = dict(current)
server_cfg["type"] = transport
server_cfg["url"] = url
if token:
    headers = server_cfg.get("headers", {})
    if not isinstance(headers, dict):
        headers = {}
    headers["Authorization"] = f"Bearer {token}"
    server_cfg["headers"] = headers
servers[server_name] = server_cfg
dump_json(claude_cfg_path, claude_cfg)

settings = load_json(settings_path)
hooks = settings.setdefault("hooks", {})
ensure_hook(hooks, "Stop", save_hook)
ensure_hook(hooks, "PreCompact", precompact_hook)
dump_json(settings_path, settings)

print(f"configured_mcp={url}")
print(f"configured_hooks={settings_path}")
PYEOF

ok "Configured MCP server '${SERVER_NAME}' -> ${FINAL_URL}"
ok "Configured Stop + PreCompact hooks"

echo ""
echo "Restart Claude Code to load updated MCP + hook settings."
