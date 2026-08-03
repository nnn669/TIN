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
path.write_text(updated)

fixture = Path('test/features/assistant/pages/assistant_settings_edit_page_mcp_test.dart')
if not fixture.exists():
    raise RuntimeError('assistant MCP test is missing')
fixture_text = fixture.read_text()
old = "Assistant(id: _assistantId, name: 'Test Assistant', temperature: 0.6)"
new = "Assistant(id: _assistantId, name: 'Test Assistant')"
if fixture_text.count(old) != 1:
    raise RuntimeError('expected one assistant temperature fixture')
fixture.write_text(fixture_text.replace(old, new, 1))

print('desktop assistant temperature block and fixture cleaned')