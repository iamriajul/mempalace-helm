#!/usr/bin/env bash
# MemPalace remote setup.
# Installs /mempalace-connect command files and bundled hook installers.
# Optionally performs full headless setup when --url is provided.

set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/iamriajul/mempalace-helm/master}"
CMD_FILE=".claude/commands/mempalace-connect.md"
CMD_URL="$REPO_RAW/$CMD_FILE"

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
  curl -fsSL https://raw.githubusercontent.com/iamriajul/mempalace-helm/master/install.sh | bash -s -- --url <base-url> [--transport http|sse] [--scope global|project]

Options:
  --url <base-url>         Configure MCP + hooks immediately (headless mode)
  --transport <http|sse>   MCP transport (default: http)
  --scope <global|project> Hook settings target (default: global)
  --name <server-name>     MCP server name (default: mempalace)
USAGE
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

# Install command file into detected agent CLIs.
install_command_file() {
  local target_dir="$1"
  mkdir -p "$target_dir"
  curl -fsSL "$CMD_URL" -o "$target_dir/mempalace-connect.md"
  ok "Command installed: $target_dir/mempalace-connect.md"
}

INSTALLED_ANY="false"
CLAUDE_CMD_DIR="$HOME/.claude/commands"
CODEX_CMD_DIR="$HOME/.codex/commands"
GEMINI_CMD_DIR="$HOME/.gemini/commands"

if command -v claude >/dev/null 2>&1 || [ -d "$HOME/.claude" ]; then
  info "Claude Code detected — installing command file"
  install_command_file "$CLAUDE_CMD_DIR"
  INSTALLED_ANY="true"
fi

if command -v codex >/dev/null 2>&1 || [ -d "$HOME/.codex" ]; then
  info "Codex CLI detected — installing command file"
  install_command_file "$CODEX_CMD_DIR"
  INSTALLED_ANY="true"
fi

if command -v gemini >/dev/null 2>&1 || [ -d "$HOME/.gemini" ]; then
  info "Gemini CLI detected — installing command file"
  install_command_file "$GEMINI_CMD_DIR"
  INSTALLED_ANY="true"
fi

if [ "$INSTALLED_ANY" = "false" ]; then
  info "No known agent CLI detected — installing command file for Claude by default"
  install_command_file "$CLAUDE_CMD_DIR"
fi

# Always install bundled hooks + hooks installer locally.
HOOK_DIR="$HOME/.mempalace/hooks"
mkdir -p "$HOOK_DIR"

info "Installing bundled hook scripts"
curl -fsSL "$HOOK_SAVE_URL" -o "$HOOK_DIR/mempal_save_hook.sh"
curl -fsSL "$HOOK_PRECOMPACT_URL" -o "$HOOK_DIR/mempal_precompact_hook.sh"
curl -fsSL "$HOOK_INSTALL_URL" -o "$HOOK_DIR/install.sh"
chmod +x "$HOOK_DIR/mempal_save_hook.sh" "$HOOK_DIR/mempal_precompact_hook.sh" "$HOOK_DIR/install.sh"
ok "Hooks installed: $HOOK_DIR"

if [ -n "$URL" ]; then
  info "Running headless MCP + hooks configuration"
  "$HOOK_DIR/install.sh" --url "$URL" --transport "$TRANSPORT" --scope "$SCOPE" --name "$SERVER_NAME"
  ok "Headless setup complete"
  exit 0
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Next step"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Option A (agent command):"
echo "  Open a new CLI session and run:"
echo "    /mempalace-connect http://<your-mempalace-host>"
echo ""
echo "Option B (headless, no claude command):"
echo "  ~/.mempalace/hooks/install.sh --url http://<your-mempalace-host>"
echo ""
echo "This configures MCP endpoint + auto-save hooks without requiring claude mcp commands."
