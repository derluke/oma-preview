#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cmake -S "$project_dir/native" -B "$project_dir/target/contact" -DCMAKE_BUILD_TYPE=Release
cmake --build "$project_dir/target/contact" --parallel 2
install -d "$project_dir/ui/native"
install -m644 "$project_dir/target/contact/qml/"* "$project_dir/ui/native/"
