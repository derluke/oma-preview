#!/usr/bin/env bash
set -euo pipefail

ui_dir="${FOLIO_UI_DIR:-$HOME/.local/share/folio/ui}"
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
clicker="$(mktemp --tmpdir folio-ui-click.XXXXXX)"
trap 'rm -f "$clicker"' EXIT

cc -O2 -Wall -Wextra -Werror "$project_dir/tests/uinput-click.c" -o "$clicker"

call() { qs -p "$ui_dir" ipc call folio "$@"; }
assert_eq() {
  if [[ "$1" != "$2" ]]; then
    echo "expected '$2', got '$1': $3" >&2
    exit 1
  fi
}

assert_eq "$(call ready)" "true" "Folio UI did not become ready"
address="$(hyprctl clients -j | jq -r '.[] | select(.class=="org.omarchy.folio") | .address' | tail -1)"
if [[ -z "$address" ]]; then
  echo "start Folio before running the UI flow test" >&2
  exit 1
fi
read -r window_x window_y <<< "$(hyprctl clients -j | jq -r '.[] | select(.address=="'"$address"'") | "\(.at[0]) \(.at[1])"')"
read -r max_x max_y <<< "$(hyprctl monitors -j | jq -r '.[0] | "\((.width / .scale | floor) - 1) \((.height / .scale | floor) - 1)"')"

click_item() {
  local point="$1"
  local local_x local_y
  read -r local_x local_y <<< "$point"
  "$clicker" "$((window_x + local_x))" "$((window_y + local_y))" "$max_x" "$max_y"
  sleep 0.2
}

baseline="$(call annotationCount)"
click_item "$(call textButtonCentre)"
assert_eq "$(call tool)" "text" "Text button did not select text placement"
click_item "$(call pagePoint 0.42 0.28)"
text_count="$(call annotationCount)"
assert_eq "$text_count" "$((baseline + 1))" "Page click did not create text"
text_index="$((text_count - 1))"
assert_eq "$(call editingText "$text_index")" "true" "New text did not receive keyboard focus"
assert_eq "$(call tool)" "text" "Text tool should stay selected while its editor is active"
wtype 'Folio pointer flow' -k Return
assert_eq "$(call annotationText "$text_index")" "Folio pointer flow" "Typed text did not reach the annotation"
assert_eq "$(call tool)" "read" "Enter should finish text placement and return to Read"
wtype -k Delete
assert_eq "$(call annotationCount)" "$baseline" "Delete did not remove placed text"

click_item "$(call signButtonCentre)"
if [[ "$(call tool)" == "sign" ]]; then
  click_item "$(call pagePoint 0.30 0.80)"
  sign_count="$(call annotationCount)"
  assert_eq "$sign_count" "$((baseline + 1))" "Page click did not create a signature"
  sign_index="$((sign_count - 1))"
  if (( $(call annotationStrokeCount "$sign_index") <= 0 )); then
    echo "placed signature contains no strokes" >&2
    exit 1
  fi
  wtype -k Delete
  assert_eq "$(call annotationCount)" "$baseline" "Delete did not remove placed signature"
  echo "PASS: Text and saved-signature pointer flows"
else
  echo "PASS: Text pointer flow; signature drawing requires user input (no saved signature)"
fi
