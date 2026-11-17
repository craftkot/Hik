#!/usr/bin/env python3
"""Patch generated Android scaffold for user-approved SAF + EHTID overlay."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
java = root / 'android/app/src/main/kotlin/com/ehtid/game_lab'
java.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / 'android_native/MainActivity.kt', java / 'MainActivity.kt')
shutil.copyfile(root / 'android_native/OverlayService.kt', java / 'OverlayService.kt')

manifest = root / 'android/app/src/main/AndroidManifest.xml'
content = manifest.read_text(encoding='utf-8')
for permission in (
    'android.permission.INTERNET',
    'android.permission.SYSTEM_ALERT_WINDOW',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_SPECIAL_USE',
    'android.permission.POST_NOTIFICATIONS',
):
    if f'android:name="{permission}"' not in content:
        content = content.replace(
            '<application',
            f'<uses-permission android:name="{permission}"/>\n    <application',
            1,
        )
service = """    <service
        android:name=".OverlayService"
        android:exported="false"
        android:foregroundServiceType="specialUse">
        <property
            android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
            android:value="user_requested_floating_game_value_helper" />
    </service>
"""
if 'android:name=".OverlayService"' not in content:
    content = content.replace('</application>', service + '    </application>', 1)
manifest.write_text(content, encoding='utf-8')
print('Installed Android SAF + consent-based overlay foreground service.')
