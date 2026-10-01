#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build the Mongolian language pack for AULA F-series drivers.

    python tools/build.py path/to/AULA_F108_driver.exe [more.exe ...]

For each installer it:
  1. extracts it with innoextract,
  2. reads app/Text/en/text.xml to learn that model's exact key set,
  3. writes a Mongolian app/Text/mn/text.xml in the vendor's own format
     (UTF-16 LE with BOM, CRLF, tab indent, same element order),
  4. writes a patched Cfg.ini with `Lang<n>=Монгол,mn` appended,
  5. drops both into dist/<MODEL>/ ready to copy over an installed driver.

Nothing here modifies OemDrv.exe. The driver binary the customer runs is
AULA's original, so no unsigned-binary or antivirus problem - the pack is
just two text files the app already knows how to read.
"""

import io
import json
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MN_FILE = os.path.join(ROOT, 'tools', 'mn.json')
DIST = os.path.join(ROOT, 'dist')
WORK = os.path.join(ROOT, '.work')

LANG_LABEL = 'Монгол'
LANG_DIR = 'mn'


def find_innoextract():
    exe = shutil.which('innoextract')
    if exe:
        return exe
    base = os.path.expandvars(r'%LOCALAPPDATA%\Microsoft\WinGet\Packages')
    for dirpath, _dirnames, filenames in os.walk(base):
        if 'innoextract.exe' in filenames:
            return os.path.join(dirpath, 'innoextract.exe')
    sys.exit('innoextract not found. Install it with:\n'
             '  winget install --id dscharrer.innoextract -e')


def load_mn():
    with io.open(MN_FILE, encoding='utf-8') as fh:
        data = json.load(fh)
    overrides = data.pop('_overrides', {})
    overrides.pop('_comment', None)
    data.pop('_comment', None)
    return data, overrides


def read_text_xml(path):
    """Return [(section, key, english)] preserving document order."""
    raw = open(path, 'rb').read()
    text = raw.decode('utf-16')
    text = text.replace('encoding="utf-16"', 'encoding="utf-8"')
    root = ET.fromstring(text)
    out = []
    for section in root:
        for el in section:
            out.append((section.tag, el.tag, el.text or ''))
    return out


def xml_escape(s):
    return (s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;'))


def build_xml(entries, mn, overrides, model):
    """Emit text.xml byte-for-byte in the vendor's dialect."""
    missing = []
    lines = ['<?xml version="1.0" encoding="utf-16"?>', '<root>']
    current = None
    for section, key, english in entries:
        if section != current:
            if current is not None:
                lines.append('\t</%s>' % current)
            lines.append('\t<%s>' % section)
            current = section

        if not english.strip():
            value = ''                      # vendor leaves it blank: keep blank
        else:
            value = overrides.get('%s|%s' % (key, english))
            if value is None:
                value = mn.get(key)
            if value is None or not str(value).strip():
                value = english             # untranslated: fall back to English
                missing.append((key, english))
        # The vendor's own files have no bare LF anywhere, including inside a
        # value; a newline carried in from the JSON must become CRLF to match.
        value = str(value).replace('\r\n', '\n').replace('\n', '\r\n')
        lines.append('\t\t<%s>%s</%s>' % (key, xml_escape(value), key))
    if current is not None:
        lines.append('\t</%s>' % current)
    lines.append('</root>')
    lines.append('')

    if missing:
        print('    WARNING: %d string(s) with no Mongolian text, left in English:' % len(missing))
        for key, english in missing[:10]:
            print('      %-18s %s' % (key, english[:60]))

    return '\r\n'.join(lines).encode('utf-16')   # utf-16 -> LE with BOM


def patch_cfg(src_path, dst_path):
    """Append the Mongolian entry to the Lang list, keeping UTF-16 + CRLF."""
    text = open(src_path, 'rb').read().decode('utf-16')
    if re.search(r'^Lang\d+=.*,%s\s*$' % LANG_DIR, text, re.M):
        print('    Cfg.ini already lists Mongolian')
    else:
        langs = re.findall(r'^Lang(\d+)=', text, re.M)
        nxt = max((int(n) for n in langs), default=0) + 1
        entry = 'Lang%d=%s,%s' % (nxt, LANG_LABEL, LANG_DIR)
        # place it directly after the last existing Lang line
        lines = text.replace('\r\n', '\n').split('\n')
        last = max(i for i, l in enumerate(lines) if l.startswith('Lang'))
        lines.insert(last + 1, entry)
        text = '\r\n'.join(lines)
        if not text.endswith('\r\n'):
            text += '\r\n'
        print('    Cfg.ini += %s' % entry)
    open(dst_path, 'wb').write(text.encode('utf-16'))


README = u"""{title} — Монгол хэлний багц
{rule}

ЮУ ВЭ:
  Драйверын цэсийг монгол болгоно. Драйверын программыг (OemDrv.exe)
  ӨӨРЧЛӨХГҮЙ — зөвхөн хэлний файл нэмнэ.

ХЭРХЭН СУУЛГАХ:
  1. Эхлээд AULA-гийн жинхэнэ драйверыг суулгасан байх ёстой.
  2. "Install_Suulgah.bat" дээр хоёр товшино уу.
     (Windows администратор эрх асууна — Тийм гэж хариулна уу)
  3. Драйверыг нээгээд:  Config → Language → Монгол

ГАРААР СУУЛГАХ (скрипт ажиллахгүй бол):
  1. Драйвер суулгасан хавтсыг олно (дотор нь OemDrv.exe байна).
  2. reference\\app\\Text\\mn  хавтсыг тэнд байгаа  app\\Text  дотор хуулна.
  3. app\\Cfg.ini файлыг Notepad-аар нээж, Lang мөрүүдийн ард нэмнэ:
        Lang{n}=Монгол,mn
     (Файлыг UTF-16 хэлбэрээр хадгална)

БУЦААХ:
  app\\Cfg.ini.bak файлыг Cfg.ini болгож нэрлэнэ, эсвэл Cfg.ini доторх
  Монгол мөрийг устгана.

Асуудал гарвал Peaklab-т хандана уу.
"""


def write_readme(pack_dir, title):
    n = 4
    cfg_ref = os.path.join(pack_dir, 'reference', 'app', 'Cfg.ini')
    if os.path.isfile(cfg_ref):
        text = open(cfg_ref, 'rb').read().decode('utf-16')
        m = re.search(r'^Lang(\d+)=.*,%s\s*$' % LANG_DIR, text, re.M)
        if m:
            n = int(m.group(1))
    body = README.format(title=title, rule='=' * 40, n=n)
    path = os.path.join(pack_dir, 'ЗААВАР.txt')
    with io.open(path, 'w', encoding='utf-8-sig', newline='\r\n') as fh:
        fh.write(body)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)

    inno = find_innoextract()
    mn, overrides = load_mn()
    print('innoextract: %s' % inno)
    print('translations: %d keys, %d overrides\n' % (len(mn), len(overrides)))

    os.makedirs(DIST, exist_ok=True)
    built = []

    for installer in sys.argv[1:]:
        if not os.path.isfile(installer):
            print('SKIP (not found): %s' % installer)
            continue
        model = re.sub(r'[^A-Za-z0-9]+', '_',
                       os.path.splitext(os.path.basename(installer))[0]).strip('_')
        print('== %s' % model)

        work = os.path.join(WORK, model)
        shutil.rmtree(work, ignore_errors=True)
        os.makedirs(work, exist_ok=True)
        # Not every F-series installer is Inno; some are NSIS or a self-
        # extracting archive. Those are simply not this driver family, so skip
        # them rather than aborting the whole run.
        res = subprocess.run([inno, '--extract', '--output-dir', work, '--silent', installer],
                             stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        if res.returncode != 0:
            why = (res.stderr or b'').decode('utf-8', 'replace').strip().splitlines()
            print('    not an Inno installer - skipped (%s)'
                  % (why[-1][:70] if why else 'innoextract exit %d' % res.returncode))
            continue

        en_xml = os.path.join(work, 'app', 'Text', 'en', 'text.xml')
        cfg = os.path.join(work, 'app', 'Cfg.ini')
        if not (os.path.isfile(en_xml) and os.path.isfile(cfg)):
            print('    NOT a BYCOMBO4-style driver (no app/Text/en/text.xml) - skipped')
            continue

        entries = read_text_xml(en_xml)
        title = ''
        cfg_text = open(cfg, 'rb').read().decode('utf-16')
        m = re.search(r'^Title=(.*)$', cfg_text, re.M)
        if m:
            title = m.group(1).strip()
        print('    %s | %d strings' % (title or '?', len(entries)))

        pack_dir = os.path.join(DIST, model)
        ref_dir = os.path.join(pack_dir, 'reference', 'app')
        os.makedirs(os.path.join(ref_dir, 'Text', LANG_DIR), exist_ok=True)

        xml_bytes = build_xml(entries, mn, overrides, model)
        # the installer script reads text.xml sitting next to it
        open(os.path.join(pack_dir, 'text.xml'), 'wb').write(xml_bytes)
        # and a reference copy laid out exactly as it lands on disk
        open(os.path.join(ref_dir, 'Text', LANG_DIR, 'text.xml'), 'wb').write(xml_bytes)
        patch_cfg(cfg, os.path.join(ref_dir, 'Cfg.ini'))

        # one launcher name everywhere: the customer is always told to run Install_Suulgah.bat
        shutil.copy(os.path.join(ROOT, 'pack', 'launcher-mn.bat'), os.path.join(pack_dir, 'Install_Suulgah.bat'))
        shutil.copy(os.path.join(ROOT, 'pack', 'install-mn.ps1'), os.path.join(pack_dir, 'install-mn.ps1'))
        if os.path.exists(os.path.join(pack_dir, 'install-mn.bat')):
            os.remove(os.path.join(pack_dir, 'install-mn.bat'))
        write_readme(pack_dir, title or model)

        zip_path = os.path.join(DIST, '%s_mn' % model)
        shutil.make_archive(zip_path, 'zip', pack_dir)
        built.append((model, title, len(entries), zip_path + '.zip'))
        print('    -> dist/%s_mn.zip' % model)

    print()
    if built:
        print('Built %d language pack(s):' % len(built))
        for model, title, n, _z in built:
            print('  %-28s %-24s %d strings' % (model, title, n))
        print('\nEach zip is what you hand a customer: they install AULA\'s own')
        print('driver first, then run Install_Suulgah.bat and pick Монгол in Config.')
    else:
        print('Nothing built.')


if __name__ == '__main__':
    main()
