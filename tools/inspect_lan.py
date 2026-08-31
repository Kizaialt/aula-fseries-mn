#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
How does the second AULA driver family (DeviceDriver.exe + language/*.lan)
choose which language file to load? Read-only.

    python tools/inspect_lan.py .work2/<MODEL>/app/DeviceDriver.exe
"""
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

path = sys.argv[1] if len(sys.argv) > 1 else '.work2/F98PRO/app/DeviceDriver.exe'
data = open(path, 'rb').read()
print('%s  (%d bytes)\n' % (path, len(data)))

BS = chr(92)
NEEDLES = [
    '.lan', 'language' + BS, '%d.lan', '%s.lan',
    'GetUserDefaultLCID', 'GetSystemDefaultLCID', 'GetUserDefaultUILanguage',
    'LanguageID', 'LangID', 'Language', '1033', '1049', 'config.xml',
]

print('references (ascii / utf-16):')
for s in NEEDLES:
    a = data.count(s.encode('latin1'))
    u = data.count(s.encode('utf-16-le'))
    if a or u:
        print('  %-26r ascii=%-3d utf16=%d' % (s, a, u))

print('\nstrings mentioning "lan" (utf-16):')
seen = set()
for m in re.finditer('lan'.encode('utf-16-le'), data):
    start = max(0, m.start() - 100)
    seg = data[start:m.start() + 80].decode('utf-16-le', 'ignore')
    parts = [p for p in seg.split('\x00') if 'lan' in p.lower() and len(p) > 3]
    for p in parts:
        p = ''.join(c for c in p if c.isprintable())
        if p and p not in seen:
            seen.add(p)
            print('   %s' % p[:78])
    if len(seen) > 18:
        break

print('\nascii strings mentioning lan/lcid:')
for m in sorted({x.decode('latin1') for x in
                 re.findall(rb'[\x20-\x7e]{5,60}', data)
                 if re.search(rb'(?i)\.lan|lcid|languag', x)})[:18]:
    print('   %s' % m)
