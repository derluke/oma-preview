#!/usr/bin/env bash
set -euo pipefail

bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
codex_skills_dir="${CODEX_HOME:-$HOME/.codex}/skills"

rm -f "$bin_dir/oma-preview"
rm -f "$data_dir/applications/org.omarchy.oma-preview.desktop"
rm -f "$data_dir/icons/hicolor/scalable/apps/org.omarchy.oma-preview.svg"
rm -rf "$data_dir/oma-preview/ui"
rmdir "$data_dir/oma-preview" 2>/dev/null || true
rm -f "$codex_skills_dir/oma-preview/agents/openai.yaml"
rm -f "$codex_skills_dir/oma-preview/SKILL.md"
rmdir "$codex_skills_dir/oma-preview/agents" 2>/dev/null || true
rmdir "$codex_skills_dir/oma-preview" 2>/dev/null || true
update-desktop-database "$data_dir/applications" >/dev/null 2>&1 || true
echo "Removed Oma Preview and its Codex skill. Saved signatures, bookmarks, and drafts were left in place."
