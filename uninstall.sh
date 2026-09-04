#!/usr/bin/env bash
set -euo pipefail

bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"

rm -f "$bin_dir/folio"
rm -f "$data_dir/applications/org.omarchy.folio.desktop"
rm -f "$data_dir/icons/hicolor/scalable/apps/org.omarchy.folio.svg"
rm -rf "$data_dir/folio/ui"
rmdir "$data_dir/folio" 2>/dev/null || true
update-desktop-database "$data_dir/applications" >/dev/null 2>&1 || true
echo "Removed Folio. Its saved signature and bookmarks were left in place."
