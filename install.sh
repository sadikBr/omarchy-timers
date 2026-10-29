#!/usr/bin/env bash
# Install (or update) the bsadik.timers Omarchy shell plugin from this repo.
#
#   ./install.sh             copy plugin, add bar widget, take over the reminder keys and menu
#   ./install.sh --uninstall remove plugin, bar widget, keybindings and menu entries
#
# Safe to re-run: every step checks before changing anything.

set -euo pipefail

ID="bsadik.timers"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/$ID"
DEST="$HOME/.config/omarchy/plugins/$ID"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
BINDINGS="$HOME/.config/hypr/bindings.lua"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
STATE="$HOME/.local/state/omarchy/bsadik-timers.json"
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

BIND_START="-- >>> $ID >>>"
BIND_END="-- <<< $ID <<<"
MENU_START="  // >>> $ID >>>"
MENU_END="  // <<< $ID <<<"

say() { printf '\033[1;34m::\033[0m %s\n' "$*"; }

edit_shell_json() {
  local filter="$1"
  jq --arg id "$ID" "$filter" "$SHELL_JSON" >"$SHELL_JSON.tmp"
  mv "$SHELL_JSON.tmp" "$SHELL_JSON"
}

remove_binding() {
  [[ -f $BINDINGS ]] || return 0
  sed -i "/^$BIND_START\$/,/^$BIND_END\$/d" "$BINDINGS"
}

remove_menu() {
  [[ -f $MENU ]] || return 0
  sed -i "\|^$MENU_START\$|,\|^$MENU_END\$|d" "$MENU"
}

reload_hyprland() {
  if command -v hyprctl >/dev/null && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    hyprctl reload >/dev/null
    local errors
    errors=$(hyprctl configerrors)
    [[ -z $errors || $errors == *"no errors"* ]] || echo "$errors" >&2
  fi
}

uninstall() {
  if command -v omarchy-shell >/dev/null; then
    omarchy-shell -q "$ID" stop >/dev/null 2>&1 || true
  fi
  say "Removing $DEST"
  rm -rf "$DEST"
  if [[ -f $SHELL_JSON ]]; then
    say "Removing bar widget"
    edit_shell_json '
      (.bar.layout // {}) |= with_entries(.value |= map(select(.id != $id)))
      | (.plugins // []) |= map(select(.id != $id))'
  fi
  say "Restoring the stock reminder keys and menu"
  remove_binding
  remove_menu
  reload_hyprland
  say "Uninstalled. Timers and settings are kept in $STATE (delete it to forget them)."
}

install() {
  [[ -f $SRC/manifest.json ]] || { echo "missing $SRC/manifest.json" >&2; exit 1; }
  for cmd in jq rsync pw-play; do
    command -v "$cmd" >/dev/null || { echo "missing dependency: $cmd" >&2; exit 1; }
  done

  say "Copying plugin to $DEST"
  mkdir -p "$DEST"
  rsync -a --delete "$SRC/" "$DEST/"
  omarchy plugin validate "$DEST" >/dev/null

  [[ -f $SHELL_JSON ]] || cp "$OMARCHY_PATH/config/omarchy/shell.json" "$SHELL_JSON"

  # A plugin that is also a bar widget is enabled by its bar entry, so it must
  # not also sit in plugins[]. Place it in the center, right after the clock;
  # if the clock isn't there, append it to the center section.
  say "Adding bar widget next to the clock"
  edit_shell_json '
    (.plugins // []) |= map(select(.id != $id))
    | if ([.bar.layout[]?[]?.id] | index($id)) then .
      else .bar.layout.center = (
        (.bar.layout.center // []) as $center
        | ($center | map(.id) | index("omarchy.clock")) as $clock
        | if $clock == null then $center + [{id: $id}]
          else $center[:$clock + 1] + [{id: $id}] + $center[$clock + 1:] end)
      end'

  # Take over the stock reminder keys (SUPER+CTRL+R and friends).
  say "Binding SUPER+CTRL+R (popup), SUPER+CTRL+ALT+R (stopwatch), SUPER+SHIFT+CTRL+R (stop alarm)"
  remove_binding
  cat >>"$BINDINGS" <<EOF
$BIND_START
-- Timers plugin (replaces the stock reminder keys).
hl.unbind("SUPER + CTRL + R")
hl.unbind("SUPER + CTRL + ALT + R")
hl.unbind("SUPER + SHIFT + CTRL + R")
o.bind("SUPER + CTRL + R", "Timers", "omarchy-shell shell toggle $ID")
o.bind("SUPER + CTRL + ALT + R", "Start a stopwatch", "omarchy-shell $ID stopwatch ''")
o.bind("SUPER + SHIFT + CTRL + R", "Stop the ringing alarm", "omarchy-shell $ID stop")
$BIND_END
EOF
  reload_hyprland

  # Point the menu's Trigger > Reminder entries at the plugin. Same ids as the
  # stock entries, so they override them in place.
  say "Pointing Trigger > Reminder in the Omarchy menu at the plugin"
  mkdir -p "$(dirname "$MENU")"
  [[ -f $MENU ]] || printf '{\n}\n' >"$MENU"
  remove_menu
  local entries
  entries=$(cat <<EOF
$MENU_START
  "trigger.reminder": {"icon":"󰔛","label":"Timer","aliases":["reminder","timer","timers"]},
  "trigger.reminder.set": {"icon":"󰔛","label":"Timer","aliases":["reminder-set","remind"],"action":"omarchy-shell shell toggle $ID"},
  "trigger.reminder.show": {"icon":"󱎫","label":"Stopwatch","action":"omarchy-shell $ID stopwatch ''"},
  "trigger.reminder.clear": {"icon":"󰃢","label":"Clear finished","action":"omarchy-shell $ID clearDone"},
$MENU_END
EOF
)
  # Insert before the closing brace of the top-level object.
  local last
  last=$(grep -n '^}' "$MENU" | tail -1 | cut -d: -f1)
  [[ -n $last ]] || { echo "can't find the closing } in $MENU" >&2; exit 1; }
  { head -n $((last - 1)) "$MENU"; printf '%s\n' "$entries"; tail -n +"$last" "$MENU"; } >"$MENU.tmp"
  mv "$MENU.tmp" "$MENU"

  # The shell caches plugin QML that is already loaded, so code changes only
  # take effect after a restart. Timers live on disk and survive it.
  if command -v omarchy-shell >/dev/null && omarchy-shell shell ping 2>/dev/null | grep -q ok; then
    say "Restarting the Omarchy shell to load the new code"
    omarchy restart shell >/dev/null 2>&1 || say "Restart failed; run: omarchy restart shell"
  fi

  say "Done. Click the timer icon next to the clock, or press SUPER+CTRL+R."
}

case "${1:-}" in
  --uninstall) uninstall ;;
  "") install ;;
  *) echo "usage: $0 [--uninstall]" >&2; exit 2 ;;
esac
