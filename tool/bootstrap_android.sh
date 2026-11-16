#!/usr/bin/env bash
set -euo pipefail
if [[ ! -f android/gradlew ]]; then
  flutter create --platforms=android --org com.virxmagical --project-name virxmagical .
fi
python3 tool/configure_android.py
echo "Android host is ready (compileSdk 36, minSdk 29, arm64-v8a)."
