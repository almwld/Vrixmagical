#!/usr/bin/env bash
set -euo pipefail
if [[ ! -f android/gradlew ]]; then
  flutter create --platforms=android --org com.virxmagical --project-name virxmagical .
fi
python3 - <<'PY'
from pathlib import Path
gradle = Path("android/app/build.gradle.kts")
if gradle.exists():
    text = gradle.read_text()
    text = text.replace("compileSdk = flutter.compileSdkVersion", "compileSdk = 36")
    text = text.replace("minSdk = flutter.minSdkVersion", "minSdk = 28")
    gradle.write_text(text)
manifest = Path("android/app/src/main/AndroidManifest.xml")
if manifest.exists():
    text = manifest.read_text()
    if "android.permission.INTERNET" not in text:
        text = text.replace("</manifest>", '    <uses-permission android:name="android.permission.INTERNET" />\\n</manifest>')
    manifest.write_text(text)
PY
echo "Android host project is ready (compileSdk 36, minSdk 28)."
