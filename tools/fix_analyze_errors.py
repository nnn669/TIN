import io
import re
import sys

def read(p):
    with io.open(p, encoding='utf-8') as f:
        return f.read()

def write(p, s):
    with io.open(p, 'w', encoding='utf-8', newline='') as f:
        f.write(s)

changed = []

# 1) app_control_service.dart: drop stale entry operations + unused helper
p = 'lib/core/services/app_control/app_control_service.dart'
s = read(p)
orig = s
lines = s.split('\n')
kept = []
for line in lines:
    st = line.strip()
    if st in (
        'AppControlOperations.addEntry,',
        'AppControlOperations.updateEntry,',
        'AppControlOperations.deleteEntry,',
    ):
        continue
    kept.append(line)
lines = kept

# remove unused _doubleFrom method (balanced braces)
start = None
for i, line in enumerate(lines):
    if re.search(r'\b_doubleFrom\s*\(', line) and ('double' in line or 'dynamic' in line) and line.rstrip().endswith('{'):
        start = i
        break
if start is not None:
    depth = 0
    end = None
    for i in range(start, len(lines)):
        depth += lines[i].count('{') - lines[i].count('}')
        if depth <= 0 and i > start:
            end = i
            break
    if end is not None:
        tail = end + 1
        if tail < len(lines) and lines[tail].strip() == '':
            tail += 1
        del lines[start:tail]
else:
    print('WARN: _doubleFrom not found')

s = '\n'.join(lines)
if s != orig:
    write(p, s)
    changed.append(p)

# 2) mcp test: drop removed temperature named parameter
p = 'test/features/assistant/pages/assistant_settings_edit_page_mcp_test.dart'
s = read(p)
orig = s
s = re.sub(r',?\s*temperature:\s*[^,\)]+', '', s)
if s != orig:
    write(p, s)
    changed.append(p)

print('CHANGED:', changed)

bad = []
for p in changed:
    for n, line in enumerate(read(p).split('\n'), 1):
        if re.search(r'addEntry|updateEntry|deleteEntry|_doubleFrom|temperature', line):
            bad.append('%s:%d:%s' % (p, n, line.strip()))
if bad:
    print('LEFTOVER:')
    print('\n'.join(bad))
    sys.exit(1)
print('OK')
