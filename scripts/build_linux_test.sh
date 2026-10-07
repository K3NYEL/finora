#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

flutter pub get
flutter build linux --debug

printf '\nBuild de pruebas creada en:\n%s\n' "$PWD/build/linux/x64/debug/bundle/finora"
