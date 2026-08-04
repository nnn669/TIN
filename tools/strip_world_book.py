import io
import re
import sys

def read(p):
    with io.open(p, encoding='utf-8') as f:
        return f.read()

def write(p, s):
    with io.open(p, 'w', encoding='utf-8', newline='') as f:
        f.write(s)

def drop_lines(text, predicates):
    out = []
    for line in text.split('\n'):
        if any(pred(line) for pred in predicates):
            continue
        out.append(line)
    return '\n'.join(out)

def remove_block(text, start_marker, open_char='{', close_char='}'):
    """Remove a balanced block starting at the line containing start_marker."""
    lines = text.split('\n')
    start = None
    for i, line in enumerate(lines):
        if start_marker in line:
            start = i
            break
    if start is None:
        return text, False
    depth = 0
    end = None
    for i in range(start, len(lines)):
        depth += lines[i].count(open_char) - lines[i].count(close_char)
        if depth <= 0 and i > start:
            end = i
            break
        if depth == 0 and i == start and open_char in lines[i]:
            end = i
            break
    if end is None:
        return text, False
    # also swallow a single trailing blank line
    tail = end + 1
    if tail < len(lines) and lines[tail].strip() == '':
        tail += 1
    del lines[start:tail]
    return '\n'.join(lines), True

changed = []

# ---- home_page.dart ----
p = 'lib/features/home/pages/home_page.dart'
s = read(p)
orig = s
s = drop_lines(s, [
    lambda l: 'world_book_provider.dart' in l,
    lambda l: 'world_book_popover.dart' in l,
    lambda l: 'world_book_sheet.dart' in l,
    lambda l: 'WorldBookProvider>().initialize();' in l,
    lambda l: 'onOpenWorldBook:' in l,
])
s, ok = remove_block(s, 'Future<void> _openWorldBookPopover() async {')
if not ok:
    print('WARN: _openWorldBookPopover block not found')
if s != orig:
    write(p, s)
    changed.append(p)

# ---- assistant_settings_edit_basic_tab.dart ----
p = 'lib/features/assistant/pages/assistant_settings_edit_basic_tab.dart'
s = read(p)
orig = s
lines = s.split('\n')
idx = None
for i, line in enumerate(lines):
    if 'AppControlPolicy.worldBook' in line:
        idx = i
        break
if idx is not None:
    start = idx
    while start > 0 and '_AppControlCapabilityMeta(' not in lines[start]:
        start -= 1
    depth = 0
    end = None
    for i in range(start, len(lines)):
        depth += lines[i].count('(') - lines[i].count(')')
        if depth <= 0 and i > start:
            end = i
            break
    if end is not None:
        del lines[start:end + 1]
        s = '\n'.join(lines)
if s != orig:
    write(p, s)
    changed.append(p)

print('CHANGED:', changed)

leftover = []
for p in changed:
    for n, line in enumerate(read(p).split('\n'), 1):
        if re.search(r'world_book|WorldBook|worldBook', line):
            leftover.append('%s:%d:%s' % (p, n, line))
if leftover:
    print('LEFTOVER:')
    print('\n'.join(leftover))
    sys.exit(1)
print('OK')
