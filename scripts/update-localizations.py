"""Update literal L/LF keys while preserving existing translations. No runtime Python."""
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
catalog = root / 'app/Resources/Localizable.xcstrings'
data = json.loads(catalog.read_text()) if catalog.exists() else {'sourceLanguage': 'en-CA', 'strings': {}, 'version': '1.0'}
sources = {}
for path in sorted((root / 'app').rglob('*.swift')):
    for match in re.finditer(r'\bLF?\(("(?:\\.|[^"\\])*")', path.read_text()):
        key = json.loads(match[1])
        sources.setdefault(key, set()).add(str(path.relative_to(root)))
for key, files in sources.items():
    entry = data['strings'].setdefault(key, {})
    entry['extractionState'] = 'manual'
    entry['comment'] = 'User interface: ' + ', '.join(sorted(files))
    if any(word in key for word in ['DTP', 'FAX', 'OCR', 'Photo', 'Text Enhanced', 'White-Level']):
        entry['comment'] += '. Historical Canon Macintosh terminology; preserve the distinction between original processing and qualified native modes.'
    entry.setdefault('localizations', {}).setdefault('en-CA', {'stringUnit': {'state': 'translated', 'value': key}})
data['strings'] = {key: data['strings'][key] for key in sorted(sources)}
catalog.parent.mkdir(exist_ok=True)
catalog.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
print(f'{len(sources)} English (Canada) localization keys')
