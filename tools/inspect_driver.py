#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Sanity-check that the driver really loads its UI text from app/Text/<lang>/text.xml
and its language list from Cfg.ini. Read-only; nothing is executed.

    python tools/inspect_driver.py .work/<MODEL>/app/OemDrv.exe
"""
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

path = sys.argv[1] if len(sys.argv) > 1 else '.work/AULA_F108_driver/app/OemDrv.exe'
data = open(path, 'rb').read()
print('%s  (%d bytes)\n' % (path, len(data)))

TARGETS = [
    'Text' + chr(92),
    chr(92) + 'text.xml',
    'text.xml',
    'Lang%d',
    'lang.ini',
    'LangIndex',
    'Cfg.ini',
    'Text' + chr(92) + '%s' + chr(92) + 'text.xml',
]

print('string references:')
for s in TARGETS:
    u16 = data.count(s.encode('utf-16-le'))
    asc = data.count(s.encode('latin1'))
    flag = 'FOUND' if (u16 or asc) else '  -  '
    print('  %-5s %-28r utf16=%-3d ascii=%d' % (flag, s, u16, asc))

print('\nUTF-16 strings containing "Lang":')
seen = []
for m in re.finditer('Lang'.encode('utf-16-le'), data):
    chunk = data[m.start():m.start() + 80].decode('utf-16-le', 'ignore')
    chunk = chunk.split('\x00')[0]
    chunk = ''.join(c for c in chunk if c.isprintable())
    if len(chunk) > 3 and chunk not in seen:
        seen.append(chunk)
        print('   %s' % chunk[:70])
    if len(seen) >= 12:
        break
