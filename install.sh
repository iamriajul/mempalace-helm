#!/usr/bin/env bash
# MemPalace bootstrap installer.
# Installs local hook scripts and optional headless MCP + hook configuration.

set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/iamriajul/mempalace-helm/master}"
HOOK_SAVE_URL="$REPO_RAW/hooks/mempal_save_hook.sh"
HOOK_PRECOMPACT_URL="$REPO_RAW/hooks/mempal_precompact_hook.sh"
HOOK_INSTALL_URL="$REPO_RAW/hooks/install.sh"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${YELLOW}→${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; }

usage() {
  cat <<'USAGE'
Usage:
  curl -fsSL https://raw.githubusercontent.com/iamriajul/mempalace-helm/master/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/iamriajul/mempalace-helm/master/install.sh | \
    bash -s -- [--url <base-url>] [--transport http|sse] [--scope user|project] [--name mempalace] [--agent <agent>]... [--token <bearer-token>] [--no-prompt]

Options:
  --url <base-url>         MemPalace base URL (falls back to SERVICE_URL env or interactive prompt)
  --transport <http|sse>   MCP transport (default: http)
  --scope <user|project>   MCP + hook config scope (`global`/`local` also accepted; default: user)
  --name <server-name>     MCP server name (default: mempalace)
  --agent <agent>          Repeat to target specific agents; default is all compatible agents for the selected scope
  --token <bearer-token>   Optional bearer token for MCP Authorization header
  --no-prompt              Disable interactive prompts; fail if required values are missing
  -h, --help               Show this help text
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
SCOPE="user"
SERVER_NAME="mempalace"
AGENTS=()
TOKEN="${MCP_BEARER_TOKEN:-${BEARER_TOKEN:-}}"
NO_PROMPT="false"

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
    --scope)
      SCOPE="${2:-}"
      shift 2
      ;;
    --name)
      SERVER_NAME="${2:-}"
      shift 2
      ;;
    --agent)
      AGENTS+=("${2:-}")
      shift 2
      ;;
    --token)
      TOKEN="${2:-}"
      shift 2
      ;;
    --no-prompt)
      NO_PROMPT="true"
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

echo ""
echo "MemPalace — installer"
echo "======================"
echo ""

need_cmd curl

HOOK_DIR="$HOME/.mempalace/hooks"
mkdir -p "$HOOK_DIR"

fetch() {
  local src="$1"
  local dst="$2"
  curl -fsSL --retry 3 --retry-delay 1 "$src" -o "$dst"
  if [ ! -s "$dst" ]; then
    err "Downloaded file is empty: $dst"
    exit 1
  fi
}

info "Installing local hook CLI"
fetch "$HOOK_SAVE_URL" "$HOOK_DIR/mempal_save_hook.sh"
fetch "$HOOK_PRECOMPACT_URL" "$HOOK_DIR/mempal_precompact_hook.sh"
fetch "$HOOK_INSTALL_URL" "$HOOK_DIR/install.sh"
chmod +x "$HOOK_DIR/mempal_save_hook.sh" "$HOOK_DIR/mempal_precompact_hook.sh" "$HOOK_DIR/install.sh"
ok "Installed: $HOOK_DIR"

info "Configuring MCP + hooks"
ARGS=(--transport "$TRANSPORT" --scope "$SCOPE" --name "$SERVER_NAME")
[ -n "$URL" ] && ARGS+=(--url "$URL")
if [ "${#AGENTS[@]}" -gt 0 ]; then
  for agent in "${AGENTS[@]}"; do
    ARGS+=(--agent "$agent")
  done
fi
[ -n "$TOKEN" ] && ARGS+=(--token "$TOKEN")
[ "$NO_PROMPT" = "true" ] && ARGS+=(--no-prompt)
"$HOOK_DIR/install.sh" "${ARGS[@]}"
ok "Setup complete"

echo "Run again anytime:"
echo "  ~/.mempalace/hooks/install.sh --url http://<your-mempalace-host> --transport http --scope user"
