#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build Mongolian language packs for the second AULA driver family
(DeviceDriver.exe + language/<LCID>.lan).

    python tools/build_lan.py installers/*.exe

For each model it:
  1. extracts the installer,
  2. reads that model's own app/language/1033.lan,
  3. writes app/language/1104.lan (mn-MN) in the vendor's dialect
     (UTF-16 LE with BOM, CRLF, same sections and key numbers),
  4. writes a patched app/config.xml that lists 1104 and, where the binary
     supports it, sets default_lan="1104" so the driver opens in Mongolian.

Translation is keyed by the ENGLISH SOURCE TEXT, never by key number: the
same number means different things on different keyboards in this family
(124 of 380 keys differ), so a key-indexed translation would mislabel the UI.

Nothing here modifies DeviceDriver.exe or mui.dll.
"""
import io
import json
import os
import re
import shutil
import subprocess
import sys

sys.stdout.reconfigure(encoding='utf-8')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MN_FILE = os.path.join(ROOT, 'tools', 'mn_lan.json')
DIST = os.path.join(ROOT, 'dist-lan')
WORK = os.path.join(ROOT, '.work2')

LCID = '1104'          # mn-MN
LANG_LABEL = 'Монгол'


def find_innoextract():
    exe = shutil.which('innoextract')
    if exe:
        return exe
    base = os.path.expandvars(r'%LOCALAPPDATA%\Microsoft\WinGet\Packages')
    for dirpath, _d, files in os.walk(base):
        if 'innoextract.exe' in files:
            return os.path.join(dirpath, 'innoextract.exe')
    sys.exit('innoextract not found')


def load_mn():
    with io.open(MN_FILE, encoding='utf-8') as fh:
        data = json.load(fh)
    return data['strings'], set(data.get('_keep_as_is', []))


def translate_lan(src_path, strings, keep):
    """Rewrite the .lan line by line, keeping sections, numbering and blanks."""
    text = open(src_path, 'rb').read().decode('utf-16')
    out, missing = [], []

    for line in text.replace('\r\n', '\n').split('\n'):
        stripped = line.strip()
        if not stripped or (stripped.startswith('[') and stripped.endswith(']')):
            out.append(stripped)
            continue
        if '=' not in stripped:
            out.append(stripped)
            continue

        key, _sep, value = stripped.partition('=')
        core = value.strip()
        # The vendor pads some values with a leading space (' Add' vs 'Add').
        # Match on the trimmed text and put the original padding back, so one
        # entry covers both spellings instead of duplicating ~150 of them.
        lead = value[:len(value) - len(value.lstrip())]
        trail = value[len(value.rstrip()):]

        if not core:
            out.append(stripped)
        elif value in strings:
            out.append('%s=%s' % (key, strings[value]))
        elif core in strings:
            out.append('%s=%s%s%s' % (key, lead, strings[core], trail))
        elif core in keep or re.fullmatch(r'[\d\s.:%+\-/]*', value):
            out.append(stripped)
        else:
            out.append(stripped)              # leave English rather than guess
            missing.append((key, value))

    blob = '\r\n'.join(out) + '\r\n'
    return blob.encode('utf-16'), missing      # utf-16 -> LE with BOM


def patch_config(src_path, supports_default):
    """Add <lan value="1104"/> and, if supported, make it the default."""
    text = open(src_path, 'rb').read().decode('utf-8-sig')
    note = []

    if '<language.info' not in text:
        return None, ['no <language.info> section - this build selects by system locale only']

    if 'value="%s"' % LCID not in text:
        text = re.sub(r'(<language\.info[^>]*>)',
                      r'\1\r\n\t\t<lan value="%s" />' % LCID, text, count=1)
        note.append('listed %s' % LCID)

    if supports_default:
        if re.search(r'default_lan="\d+"', text):
            text = re.sub(r'default_lan="\d+"', 'default_lan="%s"' % LCID, text, count=1)
        else:
            text = re.sub(r'(<language\.info)', r'\1 default_lan="%s"' % LCID, text, count=1)
        note.append('default_lan=%s' % LCID)

    return ('﻿' + text).encode('utf-8'), note


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)

    inno = find_innoextract()
    strings, keep = load_mn()
    print('innoextract: %s' % inno)
    print('translations: %d strings\n' % len(strings))

    os.makedirs(DIST, exist_ok=True)
    built, skipped = [], []

    for installer in sys.argv[1:]:
        if not os.path.isfile(installer):
            continue
        model = re.sub(r'[^A-Za-z0-9]+', '_',
                       os.path.splitext(os.path.basename(installer))[0]).strip('_')

        work = os.path.join(WORK, model)
        if not os.path.isdir(work):
            os.makedirs(work, exist_ok=True)
            res = subprocess.run([inno, '--extract', '--output-dir', work, '--silent', installer],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if res.returncode != 0:
                shutil.rmtree(work, ignore_errors=True)
                continue

        lan = os.path.join(work, 'app', 'language', '1033.lan')
        cfg = os.path.join(work, 'app', 'config.xml')
        drv = os.path.join(work, 'app', 'DeviceDriver.exe')
        if not (os.path.isfile(lan) and os.path.isfile(cfg)):
            continue

        print('== %s' % model)

        binary = open(drv, 'rb').read() if os.path.isfile(drv) else b''
        supports_default = 'default_lan'.encode('utf-16-le') in binary

        blob, missing = translate_lan(lan, strings, keep)
        cfg_blob, note = patch_config(cfg, supports_default)

        if cfg_blob is None:
            print('    %s - shipping the .lan anyway, but it cannot be made automatic' % note[0])
            skipped.append(model)

        out = os.path.join(DIST, model, 'app')
        os.makedirs(os.path.join(out, 'language'), exist_ok=True)
        open(os.path.join(out, 'language', '%s.lan' % LCID), 'wb').write(blob)
        if cfg_blob:
            open(os.path.join(out, 'config.xml'), 'wb').write(cfg_blob)

        total = len(re.findall(r'(?m)^[^\[\r\n][^=\r\n]*=', open(lan, 'rb').read().decode('utf-16')))
        done = total - len(missing)
        print('    %d/%d translated%s' % (done, total,
              ('   config.xml: ' + ', '.join(note)) if note else ''))
        if missing:
            print('    %d left in English:' % len(missing))
            for k, v in missing[:8]:
                print('      %-5s %s' % (k, v[:60]))
        built.append((model, done, total, supports_default))

    print()
    if built:
        print('Built %d language file(s):' % len(built))
        for model, done, total, auto in built:
            print('  %-28s %d/%d  %s' % (model, done, total,
                  'opens in Mongolian' if auto else 'menu only'))
    if skipped:
        print('\nNo <language.info>, cannot be automatic: %s' % ', '.join(skipped))


if __name__ == '__main__':
    main()
