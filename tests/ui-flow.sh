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
assert_ne() {
  if [[ "$1" == "$2" ]]; then
    echo "expected values to differ ('$1'): $3" >&2
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

drag_item() {
  local start="$1" end="$2"
  local start_x start_y end_x end_y
  read -r start_x start_y <<< "$start"
  read -r end_x end_y <<< "$end"
  "$clicker" "$((window_x + start_x))" "$((window_y + start_y))" "$max_x" "$max_y" "$((window_x + end_x))" "$((window_y + end_y))"
  sleep 0.25
}

baseline="$(call annotationCount)"
click_item "$(call textButtonCentre)"
assert_eq "$(call tool)" "text" "Text button did not select text placement"
click_item "$(call pagePoint 0.42 0.28)"
cancel_count="$(call annotationCount)"
assert_eq "$cancel_count" "$((baseline + 1))" "Page click did not create cancellable text"
cancel_index="$((cancel_count - 1))"
assert_eq "$(call editingText "$cancel_index")" "true" "New text did not receive keyboard focus"
wtype -k Escape
assert_eq "$(call annotationCount)" "$baseline" "Escape did not remove a new text annotation"
assert_eq "$(call tool)" "read" "Escape did not return to Read"

click_item "$(call textButtonCentre)"
click_item "$(call pagePoint 0.42 0.28)"
text_count="$(call annotationCount)"
assert_eq "$text_count" "$((baseline + 1))" "Page click did not create text"
text_index="$((text_count - 1))"
assert_eq "$(call editingText "$text_index")" "true" "New text did not receive keyboard focus"
assert_eq "$(call tool)" "text" "Text tool should stay selected while its editor is active"
wtype 'Folio pointer flow'
page_before_typing="$(call currentPage)"
wtype -k Left -k Right
assert_eq "$(call currentPage)" "$page_before_typing" "Caret arrow keys changed the PDF page"
wtype -M shift -k Return -m shift
assert_eq "$(call editingText "$text_index")" "true" "Shift+Enter should keep editing for a new line"
wtype 'second line'
expected_text=$'Folio pointer flow\nsecond line'
assert_eq "$(call annotationText "$text_index")" "$expected_text" "Multiline text did not reach the annotation"
wtype -k Return
assert_eq "$(call editingText "$text_index")" "false" "Enter did not finish multiline text editing"
click_item "$(call pagePoint 0.88 0.93)"
assert_eq "$(call selectedAnnotation)" "-1" "Clicking outside did not clear the selection"
assert_eq "$(call tool)" "read" "Clicking outside should return to Read"

click_item "$(call annotationPoint "$text_index")"
assert_eq "$(call selectedAnnotation)" "$text_index" "Clicking text did not select it for moving"
old_position="$(call annotationPosition "$text_index")"
drag_item "$(call annotationPoint "$text_index")" "$(call pagePoint 0.55 0.34)"
new_position="$(call annotationPosition "$text_index")"
assert_ne "$new_position" "$old_position" "Dragging did not move the selected text"
old_text_width="$(call annotationWidth "$text_index")"
drag_item "$(call annotationResizePoint "$text_index")" "$(call pagePoint 0.74 0.34)"
new_text_width="$(call annotationWidth "$text_index")"
assert_ne "$new_text_width" "$old_text_width" "Dragging the text resize handle did not change its width"

click_item "$(call editButtonCentre)"
assert_eq "$(call editingText "$text_index")" "true" "Visible Edit control did not enter text editing"
wtype -M ctrl -k a -m ctrl 'Discard me'
wtype -k Home -k Delete
assert_eq "$(call annotationCount)" "$((baseline + 1))" "Delete removed the annotation while its caret was active"
assert_eq "$(call annotationText "$text_index")" "iscard me" "Delete did not edit characters at the active caret"
wtype -k Escape
assert_eq "$(call annotationText "$text_index")" "$expected_text" "Escape did not restore the prior multiline text"
assert_eq "$(call editingText "$text_index")" "false" "Escape did not exit existing text editing"
click_item "$(call sizeUpCentre)"
assert_eq "$(call annotationSize "$text_index")" "16" "Text size control did not update the annotation"
click_item "$(call fontButtonCentre)"
assert_eq "$(call annotationFont "$text_index")" "serif" "Font control did not update the annotation"
click_item "$(call blueButtonCentre)"
assert_eq "$(call annotationColor "$text_index")" "#2563eb" "Colour control did not update the annotation"
click_item "$(call deleteButtonCentre)"
assert_eq "$(call annotationCount)" "$baseline" "Delete did not remove placed text"

click_item "$(call textButtonCentre)"
click_item "$(call pagePoint 0.42 0.38)"
inherited_index="$baseline"
assert_eq "$(call annotationSize "$inherited_index")" "16" "The next text box did not inherit point size"
assert_eq "$(call annotationFont "$inherited_index")" "serif" "The next text box did not inherit typeface"
assert_eq "$(call annotationColor "$inherited_index")" "#2563eb" "The next text box did not inherit colour"
wtype -k Escape
assert_eq "$(call annotationCount)" "$baseline" "Escape did not remove the inherited-style test box"

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
  old_width="$(call annotationWidth "$sign_index")"
  drag_item "$(call annotationResizePoint "$sign_index")" "$(call pagePoint 0.62 0.90)"
  new_width="$(call annotationWidth "$sign_index")"
  if [[ "$old_width" == "$new_width" ]]; then
    echo "signature resize handle did not update the annotation" >&2
    exit 1
  fi
  click_item "$(call deleteButtonCentre)"
  assert_eq "$(call annotationCount)" "$baseline" "Delete did not remove placed signature"
  signature_result="signature"
else
  signature_result="signature-skipped"
fi

assert_eq "$(call requestClose)" "true" "Could not request a normal application close"
sleep 0.2
assert_eq "$(call closePromptVisible)" "true" "Dirty close did not show the draft choices"
click_item "$(call closeCancelCentre)"
assert_eq "$(call closePromptVisible)" "false" "Cancel did not dismiss the close prompt"

echo "PASS: Text cancel, multiline Shift+Enter, Enter-to-finish, move, edit, formatting defaults, delete, ${signature_result}, and dirty-close flows"
