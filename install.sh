#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
codex_skills_dir="${CODEX_HOME:-$HOME/.codex}/skills"

for dependency in qs qpdf pdfinfo rsvg-convert cargo xdg-mime; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "Folio needs '$dependency', but it is not installed." >&2
    exit 1
  fi
done

cargo build --release --manifest-path "$project_dir/Cargo.toml"
install -Dm755 "$project_dir/target/release/folio" "$bin_dir/folio"
install -Dm644 "$project_dir/data/org.omarchy.folio.desktop" "$data_dir/applications/org.omarchy.folio.desktop"
install -Dm644 "$project_dir/assets/org.omarchy.folio.svg" "$data_dir/icons/hicolor/scalable/apps/org.omarchy.folio.svg"
install -d "$data_dir/folio/ui"
install -m644 "$project_dir"/ui/*.qml "$project_dir/ui/qmldir" "$data_dir/folio/ui/"
install -Dm644 "$project_dir/skills/folio-pdf/SKILL.md" "$codex_skills_dir/folio-pdf/SKILL.md"
install -Dm644 "$project_dir/skills/folio-pdf/agents/openai.yaml" "$codex_skills_dir/folio-pdf/agents/openai.yaml"

update-desktop-database "$data_dir/applications" >/dev/null 2>&1 || true
gtk-update-icon-cache -f -t "$data_dir/icons/hicolor" >/dev/null 2>&1 || true
xdg-mime default org.omarchy.folio.desktop application/pdf

echo "Installed Folio, its Codex skill, and made it the default PDF app."
