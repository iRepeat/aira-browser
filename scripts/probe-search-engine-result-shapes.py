#!/usr/bin/env python3
"""Development probe: does each built-in engine's own result page match the shape Aira submits?

Quick Search Switching continues a live search context only when a webpage-owned navigation can be proven to be the
same engine result page (ADR 0082). The primary proof is anchored on the tab's live result document URL: same
normalized host, same result path, and the query parameter name discovered from the live query inside that document.
An engine only needs a `resultPageShape` declaration in `BrowserModels.ets` when its own result page submits its search
box to a different host, path, or query key than the document it is showing. Baidu is the known case.

Run this after adding an engine, or when a user reports that the row disappears on a specific engine:

    python3 scripts/probe-search-engine-result-shapes.py

It reports, per engine, the URL Aira builds, the URL the engine lands on, the engine's own search form (action and input
names), the query keys the engine's own links use, and whether the live-document-anchored proof already covers the
engine's own shape. The verdict mirror is a convenience for this judgement; the shipped proof is
`AddressDisplayFormatter.resolveSearchNavigationQuery`. This probe is a development tool: it needs network access and is
not part of the build.
"""

import re
import sys
import urllib.request
from urllib.parse import urljoin, urlparse

# Aira's default browsing identity, so engines serve the same document shape a phone user sees.
USER_AGENT = (
    'Mozilla/5.0 (Linux; Android 12; SGT-AL10 Build/HUAWEISGT-AL10) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/132.0.0.0 Safari/537.36 ArkWeb/6.0.0.130 Mobile HuaweiBrowser/6.1.1.303'
)
HEADERS = {
    'User-Agent': USER_AGENT,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
}
PROBE_QUERY = 'airaprobe'
MAX_BODY_BYTES = 1200000

# (engine id, searchUrlTemplate) copied from SEARCH_ENGINE_OPTIONS.
ENGINES = [
    ('bing', 'https://www.bing.com/search?q={searchTerms}'),
    ('google', 'https://www.google.com/search?q={searchTerms}'),
    ('duckduckgo', 'https://duckduckgo.com/?q={searchTerms}'),
    ('baidu', 'https://www.baidu.com/s?wd={searchTerms}'),
    ('qihoo', 'https://www.so.com/s?q={searchTerms}'),
    ('sogou', 'https://www.sogou.com/web?query={searchTerms}'),
    ('shenma', 'https://m.sm.cn/s?q={searchTerms}'),
    ('brave', 'https://search.brave.com/search?q={searchTerms}'),
    ('startpage', 'https://www.startpage.com/sp/search?query={searchTerms}'),
    ('ecosia', 'https://www.ecosia.org/search?q={searchTerms}'),
    ('yandex', 'https://yandex.com/search/?text={searchTerms}'),
]

FORM_HEAD_RE = re.compile(r'<form\b[^>]*>', re.I)
ACTION_RE = re.compile(r'\baction\s*=\s*["\']([^"\']*)["\']', re.I)
NAME_RE = re.compile(r'\bname\s*=\s*["\']?([A-Za-z_][A-Za-z0-9_.-]*)', re.I)
INPUT_RE = re.compile(r'<(?:input|select|textarea)\b[^>]*>', re.I)
VALUE_RE = re.compile(r'\bvalue\s*=\s*["\']([^"\']*)["\']', re.I)
QUERY_KEY_HINTS = ('q', 'qs', 'word', 'wd', 'query', 'keyword', 'text', 'kw', 'k')


def normalize_host(value):
    host = value.strip().lower()
    if host.startswith('www.'):
        host = host[4:]
    if host == 'bing.com' or host.endswith('.bing.com'):
        return 'bing.com'
    if host.startswith('google.') or '.google.' in host:
        return 'google'
    return host


def normalize_path(value):
    path = value.strip().lower()
    if len(path) > 1 and path.endswith('/'):
        path = path[:-1]
    return path or '/'


def parse_search_navigation_url(url):
    """Mirror of AddressDisplayFormatter.parseSearchNavigationUrl."""
    trimmed = url.strip()
    lower = trimmed.lower()
    authority_start = 8 if lower.startswith('https://') else (7 if lower.startswith('http://') else -1)
    if authority_start < 0 or authority_start >= len(trimmed):
        return None
    fragment = trimmed.find('#', authority_start)
    content_end = fragment if fragment >= 0 else len(trimmed)
    query_index = trimmed.find('?', authority_start)
    query_start = query_index if 0 <= query_index < content_end else content_end
    path_index = trimmed.find('/', authority_start)
    authority_end = path_index if 0 <= path_index < query_start else query_start
    authority = trimmed[authority_start:authority_end]
    host = normalize_host(authority.split('@')[-1].split(':')[0])
    if not host:
        return None
    path = normalize_path(trimmed[path_index:query_start]) if 0 <= path_index < query_start else '/'
    query = trimmed[query_index + 1:content_end] if 0 <= query_index < content_end else ''
    return {'host': host, 'path': path, 'query': query}


def fetch(url):
    request = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.geturl(), response.read(MAX_BODY_BYTES).decode('utf-8', 'ignore')


def read_query_param(query, name):
    wanted = name.strip().lower()
    for part in query.split('&'):
        separator = part.find('=')
        if separator <= 0:
            continue
        if part[:separator].strip().lower() == wanted:
            return part[separator + 1:]
    return ''


def query_param_names(query):
    names = []
    for part in query.split('&'):
        separator = part.find('=')
        if separator > 0:
            names.append(part[:separator].strip().lower())
    return names


def document_query_key(landed):
    """The key the engine's own result page carries the query under, read from the landed document URL."""
    if landed is None:
        return ''
    for part in landed['query'].split('&'):
        separator = part.find('=')
        if separator > 0 and PROBE_QUERY.lower() in part[separator + 1:].strip().lower():
            return part[:separator].strip().lower()
    return ''


def own_search_forms(final_url, body):
    """The page's own search boxes: the submit action plus the input names that follow the form head.

    Submitting the form produces `<action>?<serialized inputs>`, so the inputs - not the action - carry the query.
    """
    forms = []
    for match in FORM_HEAD_RE.finditer(body):
        head = match.group(0)
        tail = body[match.end():match.end() + 4000]
        names = []
        carries = False
        for chunk in INPUT_RE.findall(tail):
            if '</form>' in chunk:
                break
            name = NAME_RE.search(chunk)
            if name:
                names.append(name.group(1))
            if any(PROBE_QUERY in value for value in VALUE_RE.findall(chunk)):
                carries = True
        action = ACTION_RE.search(head)
        if not names and action is None:
            continue
        forms.append({
            'action': urljoin(final_url, action.group(1)) if action else final_url,
            'inputs': names[:12],
            'carries_query': carries,
        })
    return forms


def report(engine_id, template):
    submitted = template.replace('{searchTerms}', PROBE_QUERY)
    try:
        final_url, body = fetch(submitted)
    except Exception as error:  # noqa: BLE001 - a probe reports every engine, including blocked ones
        print(f'== {engine_id}: FETCH FAILED {type(error).__name__}: {error}')
        print('   status: UNVERIFIED, ask for a phone report before declaring a shape')
        return
    landed = parse_search_navigation_url(final_url)
    landed_key = document_query_key(landed)
    print(f'== {engine_id}')
    print(f'   Aira submits: {submitted}')
    print(f'   landed on   : {final_url}')
    print(f'   normalized  : host={landed["host"]} path={landed["path"]} queryKey={landed_key or "?"}')
    forms = own_search_forms(final_url, body)
    covered = False
    for form in forms[:2]:
        box = parse_search_navigation_url(form['action'])
        same_page = box is not None and landed is not None and \
            box['host'] == landed['host'] and box['path'] == landed['path']
        box_keys = [name.lower() for name in form['inputs']] + query_param_names(box['query'] if box else '')
        same_key = bool(landed_key) and (landed_key in box_keys or landed_key in query_param_names(box['query'] if box else ''))
        print(f'   own box     : action={form["action"]}')
        print(f'                 submit host={box["host"] if box else "?"} path={box["path"] if box else "?"}')
        print(f'                 inputs={form["inputs"]}')
        print(f'                 same result page as the document: {same_page}, same query key: {same_key}')
        if same_page and same_key:
            covered = True
    keys = sorted(set(re.findall(r'[?&]([A-Za-z_]{1,12})=' + PROBE_QUERY, body)))
    print(f'   own keys    : {keys or "none seen for this query"}')
    if covered:
        print('   verdict     : primary proof covers this engine, no resultPageShape needed')
    elif forms:
        print('   verdict     : a resultPageShape declaration is required for this engine')
    else:
        print('   verdict     : no form served here (JS-driven box or challenge page); verify on a phone')
    sys.stdout.flush()


def main():
    for engine in ENGINES:
        report(*engine)
    return 0


if __name__ == '__main__':
    sys.exit(main())
