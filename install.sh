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
    bash -s -- --url <base-url> [--transport http|sse] [--scope global|project] [--name mempalace]

Options:
  --url <base-url>         Configure MCP + hooks immediately (headless mode)
  --transport <http|sse>   MCP transport (default: http)
  --scope <global|project> Hook settings target (default: global)
  --name <server-name>     MCP server name (default: mempalace)
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
SCOPE="global"
SERVER_NAME="mempalace"

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

if [ -n "$URL" ]; then
  info "Running headless configuration"
  "$HOOK_DIR/install.sh" --url "$URL" --transport "$TRANSPORT" --scope "$SCOPE" --name "$SERVER_NAME"
  ok "Setup complete"
  exit 0
fi

echo ""
echo "Next step:"
echo "  ~/.mempalace/hooks/install.sh --url http://<your-mempalace-host> --transport http --scope global"
echo ""
echo "This installs MCP + auto-save hooks without any Claude command usage."
