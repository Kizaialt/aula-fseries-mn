#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
One-click bundles for the DeviceDriver.exe / language/*.lan family.

    python tools/build_lan.py installers/*.exe     # make the 1104.lan files
    python tools/bundle_lan.py installers/*.exe    # then wrap them

Each zip holds AULA's own installer, our 1104.lan and a script. The customer
downloads one file, double-clicks Install_Suulgah.bat, clicks through AULA's wizard,
and the driver opens in Mongolian.

The bundled installer is AULA's original byte for byte; its SHA-256 is printed
here and written into the zip so it can be checked against AULA's download.
"""
import hashlib
import io
import os
import re
import shutil
import sys

sys.stdout.reconfigure(encoding='utf-8')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, 'dist-lan')
BUNDLE = os.path.join(ROOT, 'dist-auto')
WORK = os.path.join(ROOT, '.work2')

README = u"""{title} — Монгол хэлтэй драйвер
{rule}

НЭГ ТОВШИЛТООР СУУЛГАХ:

  "Install_Suulgah.bat" дээр хоёр товшино уу.

  Дараа нь:
    1. AULA-гийн суулгагч нээгдэнэ — Next / Install дарж дуусгана
    2. Администратор эрх асууна — Тийм гэж хариулна
    3. Дуусна

  {opens}


ЮУ ХИЙГДЭХ ВЭ:

  - AULA-гийн ЖИНХЭНЭ драйверыг суулгана (энэ zip дотор байгаа,
    өөрчлөөгүй эх файл)
  - Монгол хэлний файлыг нэмнэ (app\\language\\1104.lan)
  - config.xml дотор монгол хэлийг бүртгэнэ (нөөц: config.xml.bak)

  Драйверын программ (DeviceDriver.exe, mui.dll) ОГТ өөрчлөгдөхгүй.


ХЭЛЭЭ БУЦААХ:
  Драйвер дотор Settings -> Language -> English


ЭХ ФАЙЛЫН БАТАЛГАА:
  driver\\{setup}
  SHA-256: {sha}

  Энэ бол AULA-гийн албан ёсны сайтаас татсан файл, өөрчлөөгүй.
  Шалгах:  certutil -hashfile "driver\\{setup}" SHA256

Асуудал гарвал Peaklab-т хандана уу.
"""

# The launcher is a file (pack/launcher.bat): UTF-8, CRLF, no BOM. tools/qa/test_installers.ps1 checks it.
BAT = io.open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'pack', 'launcher.bat'),
              encoding='utf-8', newline='').read()

AUTO_LINE = 'Драйверыг нээхэд шууд МОНГОЛ хэл дээр гарна.'
MANUAL_LINE = ('Драйверыг нээгээд Settings -> Language -> Монгол сонгоно уу.\n'
               '  (энэ загвар дээр хэлийг урьдчилан тохируулах боломжгүй)')


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)

    os.makedirs(BUNDLE, exist_ok=True)
    built = []

    for installer in sys.argv[1:]:
        if not os.path.isfile(installer):
            continue
        model = re.sub(r'[^A-Za-z0-9]+', '_',
                       os.path.splitext(os.path.basename(installer))[0]).strip('_')

        lan = os.path.join(DIST, model, 'app', 'language', '1104.lan')
        if not os.path.isfile(lan):
            continue

        title, auto = model, False
        cfg = os.path.join(WORK, model, 'app', 'config.xml')
        if os.path.isfile(cfg):
            text = open(cfg, 'rb').read().decode('utf-8-sig', 'replace')
            m = re.search(r'<keyboard\s+name="([^"]+)"', text)
            if m:
                title = m.group(1).strip()
            auto = '<language.info' in text

        print('== %s  (%s)%s' % (model, title, '' if auto else '   [menu only]'))

        out = os.path.join(BUNDLE, model)
        shutil.rmtree(out, ignore_errors=True)
        os.makedirs(os.path.join(out, 'driver'), exist_ok=True)
        os.makedirs(os.path.join(out, 'lang'), exist_ok=True)

        setup_name = os.path.basename(installer)
        shutil.copy(installer, os.path.join(out, 'driver', setup_name))
        shutil.copy(lan, os.path.join(out, 'lang', '1104.lan'))
        shutil.copy(os.path.join(ROOT, 'pack', 'install-auto-lan.ps1'),
                    os.path.join(out, 'install-auto.ps1'))
        with io.open(os.path.join(out, 'Install_Suulgah.bat'), 'w', encoding='utf-8', newline='') as fh:
            fh.write(BAT)

        digest = sha256(installer)
        with io.open(os.path.join(out, 'ЗААВАР.txt'), 'w',
                     encoding='utf-8-sig', newline='\r\n') as fh:
            fh.write(README.format(title=title, rule='=' * 42, setup=setup_name,
                                   sha=digest, opens=AUTO_LINE if auto else MANUAL_LINE))

        zip_path = os.path.join(BUNDLE, '%s_mn_auto' % model)
        shutil.make_archive(zip_path, 'zip', out)
        size = os.path.getsize(zip_path + '.zip')
        built.append((model, title, size, auto))
        print('    vendor sha256 %s' % digest[:24])
        print('    -> dist-auto/%s_mn_auto.zip  (%.1f MB)' % (model, size / 1048576.0))

    print()
    if built:
        print('Built %d one-click bundle(s):' % len(built))
        for model, title, size, auto in built:
            print('  %-26s %-30s %5.1f MB  %s'
                  % (model, title[:30], size / 1048576.0,
                     'opens in Mongolian' if auto else 'menu only'))
    else:
        print('Nothing built - run tools/build_lan.py first.')


if __name__ == '__main__':
    main()
