#!/usr/bin/env bash
# Apply these claudzilla customizations to this machine. Run it from wherever this folder lives.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CZ="${CLAUDZILLA_DIR:-$HOME/claudzilla}"
MARGIN=plugins/margin/hooks/register.tsx

# Check before changing anything, so a missing piece never leaves a half-applied setup.
[ -d "$CZ/.git" ] || { echo "apply.sh: no claudzilla clone at $CZ; install claudzilla first" >&2; exit 1; }
[ -d "$DEST/hud" ] && [ -d "$DEST/themes" ] ||
  { echo "apply.sh: claudzilla's hud part is missing; run $CZ/install.sh --add hud first" >&2; exit 1; }

# The panel recolor below leaves the clone modified, which stops claudzilla's auto-update.
# So this script is the update path: undo the recolor, update, then recolor again.
# It refuses when the file holds edits other than the two recolored lines, so nothing else is lost.
if ! git -C "$CZ" diff --quiet -- "$MARGIN"; then
  if git -C "$CZ" diff -U0 -- "$MARGIN" | grep -vE '^(\+\+\+|---) ' | grep -E '^[+-]' |
     grep -vE '^[+-]const (HUD|DIM) = ' >/dev/null; then
    echo "apply.sh: $CZ/$MARGIN has edits besides the panel recolor; resolve them first" >&2
    exit 1
  fi
  git -C "$CZ" checkout -- "$MARGIN"
fi
# Like claudzilla's own updater, move only to the newest release tag, never past it.
{ git -C "$CZ" fetch -q &&
  git -C "$CZ" merge -q --ff-only "$(git -C "$CZ" describe --tags --abbrev=0 --match 'v[0-9]*' '@{u}')"; } ||
  echo "apply.sh: claudzilla update failed; continuing with the current version" >&2

link() {  # $1 source, $2 destination; a real file or folder already there is kept as a backup
  if [ -e "$2" ] && [ ! -L "$2" ]; then
    local bak
    bak="$2.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$2" "$bak"
    echo "apply.sh: moved your existing $2 to $bak" >&2
  fi
  ln -sfn "$1" "$2"
}

# The status line runs hud-filter.pl through this link, so the folder can live at any path.
link "$HERE" "$DEST/claudzilla-theme"

# The installer reads this file and never writes it, so a link keeps edits here live.
link "$HERE/settings.overrides.json" "$DEST/settings.overrides.json"

# themes/ links into the claudzilla clone; an untracked file there does not block its auto-update.
link "$HERE/theme.json" "$DEST/themes/opencode.json"

# The installer rewrites claudzilla.json (its "install" key), so merge our keys in instead of linking.
node -e '
const fs=require("fs"),[mine,dst]=process.argv.slice(1);
const cur=fs.existsSync(dst)?JSON.parse(fs.readFileSync(dst,"utf8")):{};
const add=JSON.parse(fs.readFileSync(mine,"utf8"));
fs.writeFileSync(dst,JSON.stringify({...cur,...add,hud:{...cur.hud,...add.hud}},null,2)+"\n")' \
  "$HERE/claudzilla.json" "$DEST/claudzilla.json"

# Merges settings.overrides.json into settings.json.
"$CZ/install.sh" "$@"

# Margin panel: its fixed colors to the opencode palette. DIM holds the same colors at 60%, for divider lines.
# The panel loads from the clone, so this shows from the next session or /reload-plugins.
perl -i -pe '
  $n += s/^const HUD = \{.*\}$/const HUD = { label: "#9d7cd8", faint: "#606060", idle: "#5c9cf5", action: "#7fd88f", compacted: "#f5a742", dirty: "#f5a742", churn: "#7fd88f", latest: "#e5c07b" }/;
  $n += s/^const DIM = \{.*\}$/const DIM = { label: "#5e4a82", action: "#4c8256", compacted: "#936428" }/;
  END { die "apply.sh: expected 2 color lines in register.tsx, changed $n\n" if $n != 2 }' "$CZ/$MARGIN"
