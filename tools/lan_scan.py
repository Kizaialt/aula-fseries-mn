#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Survey the second AULA driver family (DeviceDriver.exe + language/<LCID>.lan).

    python tools/lan_scan.py installers/*.exe

Extracts each installer, finds app/language/1033.lan, and reports the union of
strings across every model in the family. Writes tools/lan_strings.json.
"""
import io
import json
import os
import re
import shutil
import subprocess
import sys
from collections import OrderedDict

sys.stdout.reconfigure(encoding='utf-8')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, '.work2')
OUT = os.path.join(ROOT, 'tools', 'lan_strings.json')


def find_innoextract():
    exe = shutil.which('innoextract')
    if exe:
        return exe
    base = os.path.expandvars(r'%LOCALAPPDATA%\Microsoft\WinGet\Packages')
    for dirpath, _d, files in os.walk(base):
        if 'innoextract.exe' in files:
            return os.path.join(dirpath, 'innoextract.exe')
    sys.exit('innoextract not found')


def read_lan(path):
    """Parse the vendor's UTF-16 INI dialect into [(section, key, value)]."""
    raw = open(path, 'rb').read()
    text = raw.decode('utf-16')
    rows, section = [], ''
    for line in text.replace('\r\n', '\n').split('\n'):
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith('[') and stripped.endswith(']'):
            section = stripped[1:-1]
            continue
        if '=' in stripped:
            k, _sep, v = stripped.partition('=')
            rows.append((section, k.strip(), v))
    return rows


def main():
    inno = find_innoextract()
    models = OrderedDict()

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
        if not (os.path.isfile(lan) and os.path.isfile(cfg)):
            continue

        rows = read_lan(lan)
        cfg_text = open(cfg, 'rb').read().decode('utf-8-sig', 'replace')
        langs = re.findall(r'<lan\s+value="(\d+)"', cfg_text)
        default = re.search(r'default_lan="(\d+)"', cfg_text)
        name = re.search(r'<keyboard\s+name="([^"]+)"', cfg_text)
        shipped = sorted(os.listdir(os.path.join(work, 'app', 'language')))

        models[model] = {
            'strings': rows,
            'config_langs': langs,
            'default_lan': default.group(1) if default else None,
            'device': name.group(1) if name else '?',
            'shipped': shipped,
        }
        print('%-26s %-28s %3d strings  config=%s default=%s'
              % (model, models[model]['device'], len(rows),
                 ','.join(langs), models[model]['default_lan']))
        print('%-26s files: %s' % ('', ', '.join(shipped)))

    if not models:
        print('no models of this family found')
        return

    union = OrderedDict()
    for model, info in models.items():
        for section, key, value in info['strings']:
            union.setdefault((section, key), OrderedDict())[model] = value

    print('\nmodels in family : %d' % len(models))
    print('union of keys    : %d' % len(union))

    varying = {k: v for k, v in union.items() if len(set(v.values())) > 1}
    print('keys whose English differs between models: %d' % len(varying))
    for (section, key), byModel in list(varying.items())[:12]:
        vals = sorted(set(byModel.values()))
        print('  [%s] %-4s %s' % (section, key, ' | '.join(repr(v)[:34] for v in vals[:3])))

    payload = [{'section': s, 'key': k, 'values': v} for (s, k), v in union.items()]
    with io.open(OUT, 'w', encoding='utf-8') as fh:
        json.dump({'models': {m: {kk: vv for kk, vv in i.items() if kk != 'strings'}
                              for m, i in models.items()},
                   'union': payload}, fh, ensure_ascii=False, indent=1)
    print('\nwrote %s' % os.path.relpath(OUT, ROOT))


if __name__ == '__main__':
    main()
