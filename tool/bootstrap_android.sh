#!/usr/bin/env bash
set -euo pipefail
if [[ ! -f android/gradlew ]]; then
  flutter create --platforms=android --org com.virxmagical --project-name virxmagical .
fi
echo "Android host project is ready."
echo "Ensure android/app/build.gradle(.kts) uses minSdk >= 28 for flutter_reality."
