#!/bin/bash
# Rename herdr panes to their detected agent kind, for tabs that pair claude + codex.
# One-shot and idempotent: no daemon, no polling. Run from a keybinding or a skill.
#
#   rename-panes.sh            # every tab that has a claude+codex pair
#   rename-panes.sh --current  # only the caller's tab ($HERDR_TAB_ID)
set -euo pipefail

only_tab=""
if [[ "${1:-}" == "--current" ]]; then
  only_tab="${HERDR_TAB_ID:-}"
  [[ -n "$only_tab" ]] || { echo "no HERDR_TAB_ID: run inside a herdr pane" >&2; exit 1; }
fi

snapshot=$(herdr api snapshot)

# tabs holding both a claude and a codex agent
tabs=$(jq -r '
  .result.snapshot.agents
  | group_by(.tab_id)
  | map(select(([.[].agent] | index("claude")) and ([.[].agent] | index("codex"))))
  | .[][0].tab_id' <<<"$snapshot")

[[ -n "$tabs" ]] || { echo "no claude+codex pair found"; exit 0; }

renamed=0
for tab in $tabs; do
  [[ -z "$only_tab" || "$tab" == "$only_tab" ]] || continue

  panes=$(jq -r --arg tab "$tab" '
    .result.snapshot.agents[] | select(.tab_id == $tab and (.agent == "claude" or .agent == "codex"))
    | "\(.pane_id)\t\(.agent)"' <<<"$snapshot")

  layout=$(herdr pane layout --pane "$(head -1 <<<"$panes" | cut -f1)")

  # sort left-to-right by pane x so the report matches what the user sees
  while IFS=$'\t' read -r x pane kind; do
    herdr pane rename "$pane" "$kind" >/dev/null

    # Agent names must be unique among live agents, so fall back to a tab-scoped name.
    name="$kind"
    if ! herdr agent rename "$pane" "$name" >/dev/null 2>&1; then
      name="$kind-${tab##*:}"
      herdr agent rename "$pane" "$name" >/dev/null 2>&1 || name="(use pane id $pane)"
    fi
    echo "$tab  $pane  x=$x  pane-label=$kind  agent-name=$name"
    renamed=$((renamed + 1))
  done < <(
    while IFS=$'\t' read -r pane kind; do
      x=$(jq -r --arg p "$pane" '.result.layout.panes[] | select(.pane_id == $p) | .rect.x' <<<"$layout")
      printf '%s\t%s\t%s\n' "$x" "$pane" "$kind"
    done <<<"$panes" | sort -n
  )
done

[[ $renamed -gt 0 ]] || echo "no matching tab (--current tab has no claude+codex pair)"
