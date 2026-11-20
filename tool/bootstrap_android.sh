#!/usr/bin/env bash
set -euo pipefail
if [[ ! -f android/gradlew ]]; then
  flutter create --platforms=android --org com.virxmagical --project-name virxmagical .
fi
python3 tool/configure_android.py
python3 -m pip install --disable-pip-version-check --no-input -r tool/requirements-build.txt
python3 tool/generate_launcher_icons.py
echo "Android host is ready (compileSdk 36, minSdk 29, arm64-v8a, SVG-derived launcher icons)."
