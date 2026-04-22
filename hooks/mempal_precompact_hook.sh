#!/usr/bin/env bash
# MemPalace PreCompact hook for Claude Code.
# Always blocks before compaction so the model performs one final memory save.

set -euo pipefail

cat <<'HOOKJSON'
{
  "decision": "block",
  "reason": "Context compaction is about to run. Before compaction, perform an emergency MemPalace save (diary + drawer) for key context, decisions, code, and open tasks."
}
HOOKJSON
