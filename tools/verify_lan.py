#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Check every generated 1104.lan against the model's own English original.

    python tools/verify_lan.py
"""
import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, 'dist-lan')
WORK = os.path.join(ROOT, '.work2')


def parse(path):
    raw = open(path, 'rb').read()
    text = raw.decode('utf-16')
    rows, section = [], ''
    for line in text.replace('\r\n', '\n').split('\n'):
        s = line.strip()
        if not s:
            continue
        if s.startswith('[') and s.endswith(']'):
            section = s[1:-1]
        elif '=' in s:
            k, _, v = s.partition('=')
            rows.append((section, k.strip(), v))
    return rows, raw


def main():
    ok = True
    for model in sorted(os.listdir(DIST)):
        mn_path = os.path.join(DIST, model, 'app', 'language', '1104.lan')
        en_path = os.path.join(WORK, model, 'app', 'language', '1033.lan')
        if not (os.path.isfile(mn_path) and os.path.isfile(en_path)):
            continue

        en, _ = parse(en_path)
        mn, raw = parse(mn_path)

        same_keys = [(s, k) for s, k, _ in en] == [(s, k) for s, k, _ in mn]
        bom = raw[:2] == b'\xff\xfe'
        crlf = b'\r\x00\n\x00' in raw
        cyr = sum(1 for _, _, v in mn if re.search(r'[Ѐ-ӿ]', v))
        english_left = [(k, v) for (_, k, v), (_, _, ev) in zip(mn, en)
                        if v == ev and re.search(r'[A-Za-z]{4}', v)
                        and not re.fullmatch(r'[\w\s.:%+\-/()]*', v) is None
                        and v.strip() not in {'ms', 'MS', 'FontSize', 'Fn Layer',
                                              'Proportion 100%', 'M87 keyboard'}]
        # config.xml
        cfg_path = os.path.join(DIST, model, 'app', 'config.xml')
        cfg_note = 'none'
        if os.path.isfile(cfg_path):
            t = open(cfg_path, 'rb').read().decode('utf-8-sig')
            listed = 'value="1104"' in t
            default = 'default_lan="1104"' in t
            cfg_note = 'listed=%s default=%s' % (listed, default)
            ok &= listed

        good = same_keys and bom and crlf and cyr > 150
        ok &= good
        print('%-28s keys=%-5s BOM=%-5s CRLF=%-5s cyrillic=%-4d english_left=%-3d  config.xml %s  %s'
              % (model, same_keys, bom, crlf, cyr, len(english_left), cfg_note,
                 'OK' if good else 'FAIL'))
        if english_left[:4]:
            for k, v in english_left[:4]:
                print('      still English: %-5s %s' % (k, v[:52]))

    print('\n%s' % ('ALL CHECKS PASS' if ok else 'PROBLEMS FOUND'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
