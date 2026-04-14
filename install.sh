#!/usr/bin/env bash
# MemPalace remote setup — installs the /mempalace-connect skill into your AI agent CLI.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/iamriajul/mempalace-helm/master/install.sh | bash
#
# After running, start a new session in your agent CLI and run:
#   /mempalace-connect http://<your-mempalace-host>

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/iamriajul/mempalace-helm/master"
SKILL_FILE=".claude/commands/mempalace-connect.md"
SKILL_URL="$REPO_RAW/$SKILL_FILE"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${YELLOW}→${NC} $*"; }

echo ""
echo "MemPalace — agent skill installer"
echo "==================================="
echo ""

# ── Claude Code ────────────────────────────────────────────────────────────────
CLAUDE_CMD_DIR="$HOME/.claude/commands"
if command -v claude &>/dev/null || [ -d "$HOME/.claude" ]; then
  info "Claude Code detected — installing skill..."
  mkdir -p "$CLAUDE_CMD_DIR"
  curl -fsSL "$SKILL_URL" -o "$CLAUDE_CMD_DIR/mempalace-connect.md"
  ok "Skill installed: $CLAUDE_CMD_DIR/mempalace-connect.md"
  INSTALLED_ANY=true
fi

# ── Codex CLI ──────────────────────────────────────────────────────────────────
CODEX_CMD_DIR="$HOME/.codex/commands"
if command -v codex &>/dev/null || [ -d "$HOME/.codex" ]; then
  info "Codex CLI detected — installing skill..."
  mkdir -p "$CODEX_CMD_DIR"
  curl -fsSL "$SKILL_URL" -o "$CODEX_CMD_DIR/mempalace-connect.md"
  ok "Skill installed: $CODEX_CMD_DIR/mempalace-connect.md"
  INSTALLED_ANY=true
fi

# ── Gemini CLI ─────────────────────────────────────────────────────────────────
GEMINI_CMD_DIR="$HOME/.gemini/commands"
if command -v gemini &>/dev/null || [ -d "$HOME/.gemini" ]; then
  info "Gemini CLI detected — installing skill..."
  mkdir -p "$GEMINI_CMD_DIR"
  curl -fsSL "$SKILL_URL" -o "$GEMINI_CMD_DIR/mempalace-connect.md"
  ok "Skill installed: $GEMINI_CMD_DIR/mempalace-connect.md"
  INSTALLED_ANY=true
fi

# ── Fallback: install for Claude Code unconditionally ─────────────────────────
if [ -z "${INSTALLED_ANY:-}" ]; then
  info "No agent CLI detected — installing for Claude Code (default)..."
  mkdir -p "$CLAUDE_CMD_DIR"
  curl -fsSL "$SKILL_URL" -o "$CLAUDE_CMD_DIR/mempalace-connect.md"
  ok "Skill installed: $CLAUDE_CMD_DIR/mempalace-connect.md"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Next step"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Open a new session in your agent CLI and run:"
echo ""
echo "    /mempalace-connect http://<your-mempalace-host>"
echo ""
echo "  The skill will:"
echo "    • Register the MCP server (/mcp endpoint)"
echo "    • Download and wire up the auto-save hooks"
echo "    • Update your settings.local.json"
echo ""
