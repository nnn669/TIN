from pathlib import Path
import re

path = Path('lib/features/assistant/pages/assistant_settings_edit_page.dart')
if not path.exists():
    raise RuntimeError('assistant settings page is missing')
text = path.read_text()
pattern = r"\r?\n            // Temperature\r?\n.*?\r?\n            // Top-P\r?\n"
updated, count = re.subn(pattern, "\n            // Top-P\n", text, count=1, flags=re.S)
if count != 1:
    raise RuntimeError(f'expected one desktop temperature block, got {count}')
if 'temperature:' in updated or 'clearTemperature' in updated or 'a.temperature' in updated:
    raise RuntimeError('temperature residue remains in assistant settings page')
path.write_text(updated)
print('desktop assistant temperature block removed')