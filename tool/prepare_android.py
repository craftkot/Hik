#!/usr/bin/env python3
"""Patch the android/ scaffold created by `flutter create` for SAF support."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
destination = root / 'android/app/src/main/kotlin/com/ehtid/game_lab/MainActivity.kt'
destination.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / 'android_native/MainActivity.kt', destination)
manifest = root / 'android/app/src/main/AndroidManifest.xml'
content = manifest.read_text(encoding='utf-8')
if 'android.permission.INTERNET' not in content:
    content = content.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
manifest.write_text(content, encoding='utf-8')
print('Installed Android SAF bridge and translation network permission.')
