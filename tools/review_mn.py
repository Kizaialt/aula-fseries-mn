#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Second-opinion review of the Mongolian translations, via an OpenAI-compatible API.

    set OPENAI_API_KEY=...            (PowerShell: $env:OPENAI_API_KEY="...")
    python tools/review_mn.py tools/mn_lan.json
    python tools/review_mn.py tools/mn.json --model gpt-4o

This does NOT overwrite anything. It writes a review file listing only the
strings the reviewer disagrees with, so the changes can be read before any are
taken. Translation is a judgement call; a diff you can argue with is worth more
than a silent rewrite.

The glossary below is sent with every batch. Terminology consistency across the
four Peaklab driver projects is the point: a customer who sees "Товчлуур" in the
web driver should not see a different word in the desktop one. A reviewer given
no glossary will happily suggest synonyms that are individually fine and
collectively a mess.
"""
import argparse
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

sys.stdout.reconfigure(encoding='utf-8')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

GLOSSARY = """Established terminology (keep these consistent - they are already
shipping in the WIN 60/68 HE web driver, the AULA F-series pack and the KYSONA
M600 pack):

  key / товчлуур            keyboard / гар            mouse / хулгана
  macro / макро             profile / профайл         lighting / гэрэлтүүлэг
  brightness / тодрол       speed / хурд              colour / өнгө
  save / хадгалах           cancel / цуцлах           delete / устгах
  apply / хэрэглэх          reset / сэргээх           settings / тохиргоо
  firmware / фирмвэр        driver / драйвер          switch (physical) / свич
  polling rate / дуудлагын давтамж                    calibration / калибрац
  dead zone / мэдрэхгүй бүс                           travel, actuation / гүн
  delay / саатал            frame / кадр              device / төхөөрөмж

Left deliberately untranslated because Mongolian gamers know them in English:
  Rapid Trigger, SOCD, DKS, MT, TGL, RS, RKRT, DPI, LOD, Fn, RGB, USB, 2.4G
"""

SYSTEM = """You are reviewing Mongolian (Cyrillic) UI strings for a gaming
keyboard and mouse driver sold in Mongolia. The audience is gamers, mostly
teens to thirties, who cannot read English comfortably.

For each item you get the English source and the current Mongolian. Reply with
JSON only: a list of objects, one per item, in the same order:

  {"i": <index>, "verdict": "ok" | "better", "suggestion": "...", "why": "..."}

Use "ok" when the current translation is correct and natural - even if you
would have phrased it differently. Only use "better" when the current one is
actually wrong, unnatural to a native speaker, or inconsistent with the
glossary. Keep suggestions short: these are buttons, labels and menu items in a
cramped desktop UI, so length matters. Never translate the terms the glossary
says to leave in English. Preserve any leading or trailing spaces exactly.
"""


def load(path, english_from=None):
    """Return {english_source: mongolian}.

    Some translation files are keyed by the English text (mn_lan.json, the
    KYSONA one) and some by the vendor's own key names (mn.json uses tc_*).
    For the latter the key name is NOT the source text - reviewing against
    'tc_apply' instead of 'Save' produces confident nonsense - so the English
    has to be pulled from the vendor's own en file first.
    """
    with io.open(path, encoding='utf-8') as fh:
        data = json.load(fh)

    if 'strings' in data:
        return data['strings']

    pairs = {k: v for k, v in data.items()
             if not k.startswith('_') and isinstance(v, str)}

    if not english_from:
        return pairs

    en = {}
    root = ET.parse(english_from).getroot()
    for section in root:
        for el in section:
            if el.text:
                en[el.tag] = el.text

    out, unmapped = {}, 0
    for key, mn in pairs.items():
        source = en.get(key)
        if source:
            out[source] = mn
        else:
            unmapped += 1
    if unmapped:
        print('  note: %d keys had no English source and were skipped' % unmapped)
    return out


def call(url, key, model, payload, retries=4):
    body = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(
        url, data=body,
        headers={'Content-Type': 'application/json',
                 'Authorization': 'Bearer %s' % key})
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                return json.loads(resp.read().decode('utf-8'))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode('utf-8', 'replace')[:300]
            if exc.code in (429, 500, 502, 503, 504) and attempt < retries - 1:
                wait = 2 ** attempt * 5
                print('    HTTP %d, retrying in %ds' % (exc.code, wait))
                time.sleep(wait)
                continue
            sys.exit('API error %d: %s' % (exc.code, detail))
        except Exception as exc:
            if attempt < retries - 1:
                time.sleep(2 ** attempt * 5)
                continue
            sys.exit('request failed: %s' % exc)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('source', help='tools/mn.json or tools/mn_lan.json')
    ap.add_argument('--model', default=os.environ.get('REVIEW_MODEL', 'gpt-4o'))
    ap.add_argument('--batch', type=int, default=40)
    ap.add_argument('--limit', type=int, default=0, help='review only the first N (for a cheap trial)')
    ap.add_argument('--english', help='vendor en/text.xml, for files keyed by tc_* names')
    ap.add_argument('--url', default=os.environ.get('OPENAI_BASE_URL',
                                                    'https://api.openai.com/v1') + '/chat/completions')
    args = ap.parse_args()

    key = os.environ.get('OPENAI_API_KEY')
    if not key:
        sys.exit('OPENAI_API_KEY is not set.\n'
                 '  PowerShell:  $env:OPENAI_API_KEY = "sk-..."\n'
                 '  then re-run. The key is read from the environment and never written to disk.')

    strings = load(args.source, args.english)
    items = [(en, mn) for en, mn in strings.items() if mn and mn.strip()]
    if args.limit:
        items = items[:args.limit]
    print('reviewing %d strings with %s\n' % (len(items), args.model))

    findings = []
    for start in range(0, len(items), args.batch):
        chunk = items[start:start + args.batch]
        listing = '\n'.join(
            '%d. EN: %s\n   MN: %s' % (start + n, json.dumps(en, ensure_ascii=False),
                                       json.dumps(mn, ensure_ascii=False))
            for n, (en, mn) in enumerate(chunk))
        payload = {
            'model': args.model,
            'temperature': 0,
            'messages': [
                {'role': 'system', 'content': SYSTEM + '\n\n' + GLOSSARY},
                {'role': 'user', 'content': listing},
            ],
            'response_format': {'type': 'json_object'},
        }
        payload['messages'][-1]['content'] += (
            '\n\nReturn a JSON object: {"items": [ ... ]} with one entry per line above.')

        data = call(args.url, key, args.model, payload)
        text = data['choices'][0]['message']['content']
        try:
            parsed = json.loads(text).get('items', [])
        except Exception:
            print('    batch %d: unparseable reply, skipped' % (start // args.batch))
            continue

        for entry in parsed:
            idx = entry.get('i')
            if not isinstance(idx, int) or not (0 <= idx < len(items)):
                continue
            if entry.get('verdict') != 'better':
                continue
            en, mn = items[idx]
            suggestion = (entry.get('suggestion') or '').strip()
            if not suggestion or suggestion == mn:
                continue
            findings.append({'en': en, 'current': mn,
                             'suggested': suggestion, 'why': entry.get('why', '')})

        print('  %d/%d reviewed, %d suggestions so far'
              % (min(start + args.batch, len(items)), len(items), len(findings)))

    out = os.path.join(ROOT, 'tools', 'review-%s.json'
                       % os.path.splitext(os.path.basename(args.source))[0])
    with io.open(out, 'w', encoding='utf-8') as fh:
        json.dump({'model': args.model, 'source': args.source,
                   'reviewed': len(items), 'findings': findings}, fh,
                  ensure_ascii=False, indent=1)

    print('\n%d of %d strings questioned (%.0f%%)'
          % (len(findings), len(items), 100.0 * len(findings) / max(len(items), 1)))
    print('wrote %s' % os.path.relpath(out, ROOT))
    print('\nNothing was changed. Read the findings, then apply the ones you agree with.')
    for f in findings[:15]:
        print('\n  EN  %s' % f['en'][:70])
        print('  now %s' % f['current'][:70])
        print('  ->  %s' % f['suggested'][:70])
        if f['why']:
            print('      (%s)' % f['why'][:90])


if __name__ == '__main__':
    main()
