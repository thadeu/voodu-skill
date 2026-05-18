#!/usr/bin/env bash
# voodu-claudekit — installer
#
# Symlinks this repo into Claude Code's discovery paths:
#   ~/.claude/skills/voodu     → repo root (skill discovery)
#   ~/.claude/commands/vd      → repo/commands (/vd:* slash commands)
#
# Re-run safely: existing symlinks are replaced. Existing real files /
# directories at those paths abort the script with a clear message.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SKILL_DIR="$CLAUDE_DIR/skills/voodu"
COMMANDS_DIR="$CLAUDE_DIR/commands/vd"

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
NC=$'\033[0m'

log()  { printf '%s[voodu-claudekit]%s %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%s[voodu-claudekit]%s %s\n' "$YELLOW" "$NC" "$*"; }
err()  { printf '%s[voodu-claudekit]%s %s\n' "$RED" "$NC" "$*" >&2; }

link() {
  local src="$1"
  local dst="$2"

  mkdir -p "$(dirname "$dst")"

  if [[ -L "$dst" ]]; then
    local existing
    existing="$(readlink "$dst")"
    if [[ "$existing" == "$src" ]]; then
      log "already linked: $dst"
      return 0
    fi
    warn "replacing symlink: $dst (was → $existing)"
    rm "$dst"
  elif [[ -e "$dst" ]]; then
    err "$dst already exists and is not a symlink. Move it aside and re-run."
    exit 1
  fi

  ln -s "$src" "$dst"
  log "linked $dst → $src"
}

log "installing from $REPO_DIR"
link "$REPO_DIR"          "$SKILL_DIR"
link "$REPO_DIR/commands" "$COMMANDS_DIR"

cat <<EOF

${GREEN}Done.${NC}

Open Claude Code in any project and try:
  /vd:help        — index of every slash command
  /vd:apply       — apply / flags / examples
  /vd:manifests   — every HCL kind
  /vd:examples    — copy-paste-ready manifests

Or just ask in plain language: "how do I rollback a deployment in voodu?"
EOF
