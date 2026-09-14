"""Write bundle metadata and compiled localizations; no runtime Python dependency."""
import json
from pathlib import Path
import plistlib
import sys

root = Path(__file__).resolve().parents[1]
app = Path(sys.argv[1])
metadata = dict(CFBundleIdentifier='local.bjc85.utility', CFBundleName='BJC-85 Utility',
                CFBundleExecutable='BJC85Scanner', CFBundlePackageType='APPL',
                CFBundleShortVersionString='0.2.0', CFBundleVersion='2', LSMinimumSystemVersion='14.0',
                NSHighResolutionCapable=True, NSPrincipalClass='NSApplication', CFBundleDevelopmentRegion='en-CA')
with (app / 'Contents/Info.plist').open('wb') as file:
    plistlib.dump(metadata, file)
catalog = root / 'app/Resources/Localizable.xcstrings'
if catalog.exists():
    data = json.loads(catalog.read_text())
    locales = {data['sourceLanguage']} | {locale for entry in data['strings'].values() for locale in entry.get('localizations', {})}
    for locale in locales:
        directory = app / f'Contents/Resources/{locale}.lproj'
        directory.mkdir(exist_ok=True)
        translations = {key: entry.get('localizations', {}).get(locale, {}).get('stringUnit', {}).get('value', key)
                        for key, entry in data['strings'].items()}
        with (directory / 'Localizable.strings').open('wb') as file:
            plistlib.dump(translations, file, fmt=plistlib.FMT_BINARY)
