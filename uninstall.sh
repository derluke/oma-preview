#!/usr/bin/env bash
set -euo pipefail

bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
codex_skills_dir="${CODEX_HOME:-$HOME/.codex}/skills"

rm -f "$bin_dir/folio"
rm -f "$data_dir/applications/org.omarchy.folio.desktop"
rm -f "$data_dir/icons/hicolor/scalable/apps/org.omarchy.folio.svg"
rm -rf "$data_dir/folio/ui"
rmdir "$data_dir/folio" 2>/dev/null || true
rm -f "$codex_skills_dir/folio-pdf/agents/openai.yaml"
rm -f "$codex_skills_dir/folio-pdf/SKILL.md"
rmdir "$codex_skills_dir/folio-pdf/agents" 2>/dev/null || true
rmdir "$codex_skills_dir/folio-pdf" 2>/dev/null || true
update-desktop-database "$data_dir/applications" >/dev/null 2>&1 || true
echo "Removed Folio and its Codex skill. Saved signatures, bookmarks, and drafts were left in place."
