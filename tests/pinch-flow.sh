#!/usr/bin/env bash
set -euo pipefail
if [[ "${OMA_PREVIEW_DEDICATED_TEST_DESKTOP:-}" != 1 ]]; then
  echo 'Refusing global input: run only in a dedicated test desktop with OMA_PREVIEW_DEDICATED_TEST_DESKTOP=1.' >&2
  exit 2
fi

ui_dir="${OMA_PREVIEW_UI_DIR:-$HOME/.local/share/oma-preview/ui}"
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
pincher="$project_dir/target/oma-preview-uinput-pinch"

cc -O2 -Wall -Wextra -Werror "$project_dir/tests/uinput-pinch.c" -o "$pincher"
call() { qs -p "$ui_dir" ipc call oma-preview "$@"; }

address="$(hyprctl clients -j | jq -r '.[] | select(.class=="org.omarchy.oma-preview") | .address' | tail -1)"
if [[ -z "$address" ]]; then
  echo "start Oma Preview before running the pinch flow test" >&2
  exit 1
fi

read -r window_x window_y window_w window_h <<< "$(
  hyprctl clients -j | jq -r --arg address "$address" \
    '.[] | select(.address==$address) | "\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"'
)"
read -r max_x max_y <<< "$(
  hyprctl monitors -j | jq -r '.[0] | "\((.width / .scale | floor) - 1) \((.height / .scale | floor) - 1)"'
)"

centre_x=$((window_x + window_w * 2 / 3))
centre_y=$((window_y + window_h / 2))

"$pincher" "$centre_x" "$centre_y" 220 90 "$max_x" "$max_y"
sleep 0.3
pinched_in="$(call zoom)"
"$pincher" "$centre_x" "$centre_y" 90 220 "$max_x" "$max_y"
sleep 0.3
pinched_out="$(call zoom)"

awk -v smaller="$pinched_in" -v larger="$pinched_out" 'BEGIN { exit !(larger > smaller) }' || {
  echo "pinch-out did not increase zoom ($pinched_in -> $pinched_out)" >&2
  exit 1
}

echo "PASS: Native two-contact pinch changed zoom from $pinched_in to $pinched_out"
