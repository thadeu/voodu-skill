#!/usr/bin/env bash
# voodu-skill — installer
#
# Symlinks the skill into Claude Code's skill discovery path:
#   ~/.claude/skills/voodu     → skills/voodu
#
# Re-run safely: an existing symlink is replaced. A real file / directory
# at that path aborts the script with a clear message.
#
# Other agents (Codex, Cursor, …): use `npx skills add thadeu/voodu-skill`.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$REPO_DIR/skills/voodu"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SKILL_DIR="$CLAUDE_DIR/skills/voodu"

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
NC=$'\033[0m'

log()  { printf '%s[voodu-skill]%s %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%s[voodu-skill]%s %s\n' "$YELLOW" "$NC" "$*"; }
err()  { printf '%s[voodu-skill]%s %s\n' "$RED" "$NC" "$*" >&2; }

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

log "installing from $SKILL_SRC"
link "$SKILL_SRC" "$SKILL_DIR"

cat <<EOF

${GREEN}Done.${NC}

The voodu skill is installed. Just ask in plain language, e.g.:
  "write a voodu statefulset for postgres"
  "how do I roll back a deployment in voodu?"
  "migrate this Kamal app to voodu"

Claude loads SKILL.md and pulls the matching reference/ doc.
EOF
