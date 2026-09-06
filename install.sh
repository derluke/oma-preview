#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
codex_skills_dir="${CODEX_HOME:-$HOME/.codex}/skills"

for dependency in qs qpdf pdfinfo rsvg-convert cargo xdg-mime cmake c++ pkg-config wayland-scanner; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "Oma Preview needs '$dependency', but it is not installed." >&2
    exit 1
  fi
done

cargo build --release --manifest-path "$project_dir/Cargo.toml"
bash "$project_dir/native/build.sh"
install -Dm755 "$project_dir/target/release/oma-preview" "$bin_dir/oma-preview"
install -Dm644 "$project_dir/data/org.omarchy.oma-preview.desktop" "$data_dir/applications/org.omarchy.oma-preview.desktop"
install -Dm644 "$project_dir/assets/org.omarchy.oma-preview.svg" "$data_dir/icons/hicolor/scalable/apps/org.omarchy.oma-preview.svg"
install -d "$data_dir/oma-preview/ui"
install -m644 "$project_dir"/ui/*.qml "$project_dir/ui/qmldir" "$project_dir/ui/idle.pdf" "$data_dir/oma-preview/ui/"
install -d "$data_dir/oma-preview/ui/native"
install -m644 "$project_dir"/ui/native/* "$data_dir/oma-preview/ui/native/"
install -Dm644 "$project_dir/skills/oma-preview/SKILL.md" "$codex_skills_dir/oma-preview/SKILL.md"
install -Dm644 "$project_dir/skills/oma-preview/agents/openai.yaml" "$codex_skills_dir/oma-preview/agents/openai.yaml"

update-desktop-database "$data_dir/applications" >/dev/null 2>&1 || true
gtk-update-icon-cache -f -t "$data_dir/icons/hicolor" >/dev/null 2>&1 || true
xdg-mime default org.omarchy.oma-preview.desktop application/pdf

echo "Installed Oma Preview, its Codex skill, and made it the default PDF app."
