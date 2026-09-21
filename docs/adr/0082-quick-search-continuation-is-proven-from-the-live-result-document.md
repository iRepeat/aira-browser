# Quick Search Continuation Is Proven From The Live Result Document

Accepted: 2026-09-21. Amends ADR 0054.

## Context

ADR 0054 made Quick Search Switching fail closed: only an Aira-submitted search carries context, and any webpage-owned
navigation hides the surface because Aira cannot know what the page searched for. Its decision text states that
"later webpage-owned searches, filters, pagination, and route changes remain unowned and hide the surface" and that
context is "never reconstructed by parsing URLs".

The ordinary user flow is the opposite of that assumption. A user submits `123`, sees the result page, notices the typo
inside the result page's own search box, corrects it there, and searches again. The row disappeared on that second
search and only came back through Back, on the old query. The surface was therefore unavailable exactly when the user
had just corrected the one input it needs.

## Decision

An ordinary webpage-owned main-frame navigation on a tab that already has a live Aira Search Result Context continues
that context when the new document can be proven to be the same engine result page as the tab's live result document.
`resolveSearchNavigationQuery` in `AddressDisplayFormatter` (the existing owner of search-navigation URL shape, next to
`isMatchingSearchNavigation`) owns that proof. It is anchored on the live result document URL plus the live query:

- the observed document URL must match the live result document's normalized host and result path
  (`parseSearchNavigationUrl` normalization, which already folds `www.` and territorial forms such as `*.google.*`); and
- the query parameter name is discovered from the live query value inside the live result document URL, and the observed
  value is read through that parameter name only.

A proven continuation inherits the live engine and replaces only the query. Anything else keeps the ADR 0054 handling:
the navigation stays unowned, the context is released, and the row hides. Aira still never infers an engine from an
arbitrary URL, never reads page content, and never persists context across process death.

A second proof covers the engines whose own result page does not use the shape Aira submits. A built-in engine may
declare `SearchEngineResultPageShape` (`hosts`, `pathSuffixes`, `queryKeys`) in `SEARCH_ENGINE_OPTIONS`, next to the
search template it already declares. `SearchEngineTemplateService.resolveResultPageShape` resolves that shape by an
engine identity Aira already holds - the live context's own engine - and `resolveSearchNavigationQuery` uses it only
after the live result document anchor fails, and only when the observed document URL proves one declared host, one
declared result path suffix, and one declared query key. Baidu is the observed case: Aira submits
`https://www.baidu.com/s?wd=`, while Baidu's own mobile result page posts its search box to `/from=844b/ssid=0/s` with
`word=` and its own result links live on `https://m.baidu.com/from=844b/ssid=0/s?word=`. A custom engine cannot declare
a shape, because Aira cannot verify how its result page submits a search.

`BrowserQuickSearchSwitchingCoordinator` keeps owning the policy and applies the same proof at three typed entry
points: `handlePageBegin` for the document, the committed navigation (`handleNavigationCommitted` / `handlePageEnd`) because ArkWeb can report the committed entry before `onPageBegin`, and `handleHistoryApiUrlChange`
for a same-document `pushState`/`replaceState` inside the proven result page. An unassociated `popstate` still hides.

A proven continuation re-enters the ordinary owned navigation transaction, so redirects, regionalized result URLs,
committed-entry replacement, reload, load failure, and runtime restore keep behaving exactly like an Aira-submitted
search. The committed continuation entry receives an exact history association, so Back/Forward restore the query that
belongs to each entry instead of the newest one.

## Considered Options

- Keeping the surface on the previous query was rejected: tapping another engine would search the stale query, which is
  worse than hiding.
- Matching the observed URL against the selected engine's `searchUrlTemplate` was rejected: a territorial engine
  redirect moves the host away from the template, and custom templates may carry the terms in a path instead of a query
  parameter, so the template cannot serve as the anchor.
- Treating any result-looking URL as a new Aira context was rejected: it would show the row on pages Aira never
  submitted and on other engines' result pages.
- Reading the query from the page (title or DOM) was rejected: page content is not a trusted navigation fact, and the
  repository forbids parsing page content to reconstruct navigation context.
- Picking "whichever query parameter the observed URL adds" was rejected: a page's own request carries tokens and
  options (`sa`, `ts`, `ie`, `rsv_t`), so the guess would read a token as the query.
- Folding every `m.`/regional host of every engine into one normalized host was rejected: the shared normalization
  exists for address display, and widening it would change what the address bar treats as one search navigation.
- Letting an arbitrary result-looking URL declare its own engine was rejected for the declared shape too: the shape is
  only ever resolved from the live context's engine, never used to identify an engine from a URL.
- Unifying the proof with `isMatchingSearchNavigation` was rejected for this change: that function answers a
  comparison question for the address display (is this URL the same search as the pending display text?), and rewriting
  it would put the address-bar display behaviour at risk for no gain.

## Consequences

The row now survives an in-page search, a filter change, a result-tab change, and pagination whenever the engine keeps
its own result URL shape, and it still disappears for unrelated pages, other engines' result pages, and other paths on
the same host. The query shown on the row is the corrected one, so switching engines searches what the user is reading.

Custom engines that place `{searchTerms}` in the path, engines whose result page moves to a different host or path
without a declared shape, and engines whose own result page uses a query key Aira has not verified cannot be continued
and keep the previous fail-closed behaviour. The proof can also continue a context when a link on the result page points
at that same engine result page with the terms in a proven parameter; that outcome is accepted because the resulting row
still describes the document the user is reading.

A declared shape is engine knowledge, so a wrong or stale declaration widens continuation for that engine only. The
shape is verified against the engine's own result page before it is added, and Baidu's `pathSuffixes: ['/s']` means any
Baidu path ending in `/s` counts as that engine's result page.

## Verification

- `scripts/check-architecture-guardrails.sh` pins the single proof owner, its two anchors, the declared-shape lookup by
the live engine identity, the verified Baidu query keys, the three continuation entry points, and that each proven
continuation stays ahead of the unowned reset in that file.
- `scripts/check-aira-quick-search-continuation.cjs` pins the fail-closed ordering, that the continuation path reads no
  engine roster, that an undeclared or incomplete shape stays fail-closed, and that the committed continuation keeps a
  history association.
- Proportional phone validation covers: correcting the query inside a Google and a Baidu result page, Baidu result-page
  paging, result-tab and filter changes, Back/Forward across a continued entry, an in-page search that redirects, and an
  engine switch made from the continued row.
- `scripts/probe-search-engine-result-shapes.py` re-checks every built-in engine's own result-page shape against the live
  web, so a new engine or a changed engine page can be judged before a declaration is added.

## Revision: engine-declared result-page shapes

Accepted 2026-09-21, after phone validation of the first version.

Phone validation found Google fixed and Baidu still hiding the row. The observed Baidu result page does not use the shape
Aira submits: its search box is `<form method="get" action="/from=844b/ssid=0/s"><input name="word">`, and its own
result links are `https://m.baidu.com/from=844b/ssid=0/s?pn=10&word=123&...`. Both the result path and the query key
differ from Aira's `https://www.baidu.com/s?wd=`, and the mobile result host is `m.baidu.com`, so the live-result-document
anchor could not prove the continuation and the first unprovable document released the context before the commit could.

The decision above therefore adds the declared-shape proof, owned by the engine catalog and resolved by the engine
template service, instead of widening the shared host normalization or guessing the query parameter.

## Engine Survey

`scripts/probe-search-engine-result-shapes.py` reads each built-in engine's own result page with Aira's default browsing
identity and reports the URL Aira submits, the URL the engine lands on, the engine's own search box, and whether the
primary proof already covers that box. Surveyed 2026-09-21:

| Engine | Aira submits | The engine's own result page | Own search box | Primary proof |
| --- | --- | --- | --- | --- |
| bing | `www.bing.com/search?q=` | same host and path | `action=/search`, input `q` | covers |
| google | `www.google.com/search?q=` | same, possibly a territorial host | `q` (JS box) | covers, confirmed on a phone |
| duckduckgo | `duckduckgo.com/?q=` | same | `q` (JS box) | covers |
| baidu | `www.baidu.com/s?wd=` | `www.`/`m.baidu.com/s?wd=` | `action=/from=844b/ssid=0/s`, input `word` | needs the declaration above |
| qihoo | `www.so.com/s?q=` | `m.so.com/s?q=` | `action=https://m.so.com/s`, input `q` | covers |
| sogou | `www.sogou.com/web?query=` | `m.sogou.com/web/searchList.jsp?...&keyword=` | same URL, input `keyword` | covers |
| shenma | `m.sm.cn/s?q=` | same | `action=s`, input `q` | covers |
| brave | `search.brave.com/search?q=` | HTTP 429 from this machine | unverified | unknown |
| startpage | `www.startpage.com/sp/search?query=` | JS shell, no form served | unverified | unknown |
| ecosia | `www.ecosia.org/search?q=` | HTTP 403 from this machine | unverified | unknown |
| yandex | `yandex.com/search/?text=` | bot challenge page | unverified | unknown |

The five verified engines whose own box already lands on the same host, path, and query key as the document they are
showing need no declaration, because the primary proof is anchored on that document. Baidu is the only engine whose own
box leaves both the path and the key of the document it is showing. A shape is declared only after the probe (or a phone
report) proves it, because a wrong declaration widens continuation for that engine.
