const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

// A typo is usually noticed inside the result page's own search box, not in the address bar. That second search is a
// webpage-owned navigation, and ADR 0054 hid the Quick Search Switching row for it, which removed the row exactly in
// the flow it exists for. ADR 0082 continues the live Aira context when the new document proves to be the same engine
// result page as the tab's live result document, and keeps the fail-closed handling for everything else.
// Regression this guards: correcting the query inside the page left the tab with no quick-engine row and no way back
// to it except Back, while switching on the stale query would have searched the wrong text.
const repoRoot = path.resolve(__dirname, '..');
const formatterPath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/AddressDisplayFormatter.ets');
const coordinatorPath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/core/search/BrowserQuickSearchSwitchingCoordinator.ets');
const templateServicePath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/services/search/SearchEngineTemplateService.ets');
const modelsPath = path.join(repoRoot, 'AiraBrowser/entry/src/main/ets/common/models/BrowserModels.ets');

const formatter = fs.readFileSync(formatterPath, 'utf8');
const coordinator = fs.readFileSync(coordinatorPath, 'utf8');
const templateService = fs.readFileSync(templateServicePath, 'utf8');
const models = fs.readFileSync(modelsPath, 'utf8');

function section(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  assert.ok(start >= 0, `Missing section: ${startMarker}`);
  const end = source.indexOf(endMarker, start);
  assert.ok(end > start, `Missing section end: ${endMarker}`);
  return source.slice(start, end);
}

const queryProof = section(
  formatter,
  'export function resolveSearchNavigationQuery(',
  'interface SearchNavigationUrlParts {'
);
const declaredResultPageProof = section(
  formatter,
  'function resolveDeclaredResultPageQuery(',
  'interface SearchNavigationUrlParts {'
);
const continuationProof = section(
  coordinator,
  'private resolveContinuationContext(',
  'private nextGeneration('
);
const pageBegin = section(coordinator, 'handlePageBegin(', 'handleNavigationCommitted(');
const committedNavigation = section(
  coordinator,
  'private reconcileCommittedNavigation(',
  'private isPendingOwnedMainFrameNewEntryCommit('
);
const historyApiChange = section(
  coordinator,
  'handleHistoryApiUrlChange(',
  'handleLoadFinished('
);

test('the continuation query is proven against the live result document', () => {
  assert.ok(
    queryProof.includes('parseSearchNavigationUrl(resultDocumentUrl)'),
    'the proof must parse the live result document URL Aira already trusts, not only the observed URL'
  );
  assert.ok(
    queryProof.includes('current.host === resultDocument.host') &&
      queryProof.includes('current.path === resultDocument.path'),
    'the observed document must match the live result document host and result path, so a different engine or a ' +
      'different page on the same host can never continue the context'
  );
  assert.ok(
    queryProof.includes('findQueryParamNameByValue(resultDocument.query, previousQuery)'),
    'the query parameter must be discovered from the previous query inside the live result document URL'
  );
  assert.ok(
    queryProof.includes('readQueryParamValue(current.query, queryParamName)'),
    'the observed query value must be read through that discovered parameter only'
  );
  assert.ok(
    queryProof.indexOf("return '';") < queryProof.indexOf('readQueryParamValue('),
    'an unprovable document must return no query before any value is read'
  );
});

test('only a proven same-engine result document continues the live context', () => {
  assert.ok(
    continuationProof.includes('const liveContext = session.currentContext;') &&
      continuationProof.includes('if (liveContext === undefined'),
    'the continuation needs a live Aira result context on this tab, so a hidden tab cannot have the row revived'
  );
  assert.ok(
    continuationProof.includes('session.pendingContext !== undefined'),
    'an Aira-owned navigation in flight must not be re-interpreted as a webpage-owned continuation'
  );
  assert.ok(
    continuationProof.includes('resolveSearchNavigationQuery(') &&
      continuationProof.includes('this.templateService.resolveResultPageShape(liveContext.engineId)'),
    'the continuation must reuse the single search-navigation query proof, with the declared result-page shape of ' +
      'the live context engine only'
  );
  assert.ok(
    continuationProof.includes('committedUrl.length > 0 ? liveContext.committedUrl : liveContext.targetUrl'),
    'the anchor must be the document the tab is really showing, with the built target as the fallback'
  );
  assert.ok(
    continuationProof.includes('if (query.length === 0)') && continuationProof.includes('return undefined;'),
    'a navigation that cannot be proven must stay unowned'
  );
  assert.ok(
    continuationProof.includes('engineId: liveContext.engineId'),
    'a continuation inherits the live engine; the engine roster must never be consulted to guess one from a URL'
  );
  assert.ok(
    !continuationProof.includes('listEngines'),
    'the continuation proof must not read the engine roster, so no engine is ever inferred from a URL'
  );
});

test('an engine result-page shape may continue only when the engine declared it', () => {
  assert.ok(
    formatter.includes('engineResultPageShape?: SearchEngineResultPageShape') &&
      declaredResultPageProof.includes('if (engineResultPageShape === undefined)') &&
      declaredResultPageProof.includes("return '';"),
    'an engine with no declared result-page shape must keep the fail-closed behaviour'
  );
  assert.ok(
    declaredResultPageProof.includes('normalizeSearchNavigationHost(host) === current.host') &&
      declaredResultPageProof.includes('current.path.endsWith(normalizedSuffix)'),
    'a declared shape must prove the recorded host and a result path suffix before any query is read'
  );
  assert.ok(
    queryProof.indexOf('findQueryParamNameByValue(resultDocument.query, previousQuery)') <
      queryProof.indexOf('resolveDeclaredResultPageQuery('),
    'the live result document anchor must be tried before the declared engine shape'
  );
  assert.ok(
    templateService.includes('resolveResultPageShape(engineId: SearchEngineId)') &&
      templateService.includes('candidate.id === engineId'),
    'the declared shape must be resolved by an engine identity Aira already holds'
  );
  assert.ok(
    templateService.includes('shape.hosts.length === 0') && templateService.includes('shape.queryKeys.length === 0'),
    'an incompletely declared shape must not be usable'
  );
  assert.ok(
    models.includes('resultPageShape: {') && models.includes("hosts: ['baidu.com', 'm.baidu.com']") &&
      models.includes("pathSuffixes: ['/s']") && models.includes("queryKeys: ['wd', 'word']"),
    'Baidu must keep the verified shape of its own result page, whose search box posts /from=<code>/ssid=<n>/s with ' +
      'word= while Aira submits /s?wd='
  );
});

test('every entry point keeps a proven continuation ahead of the unowned handling', () => {
  assert.ok(
    pageBegin.indexOf("'continuation-page-begin'") > 0 &&
      pageBegin.indexOf("'continuation-page-begin'") < pageBegin.indexOf("'unowned-page-begin'"),
    'a proven page-begin continuation must be handled before the page-begin unowned reset'
  );
  assert.ok(
    pageBegin.includes('session.pendingContext = continuationContext;') &&
      pageBegin.includes('session.latestOwnedBeginUrl = normalizedEventUrl;'),
    'a proven continuation must re-enter the owned navigation transaction so redirects, replacement, and load ' +
      'failure keep the same behaviour as an Aira-submitted search'
  );
  assert.ok(
    committedNavigation.indexOf('${source}-continuation') > 0 &&
      committedNavigation.indexOf('${source}-continuation') < committedNavigation.indexOf('${source}-unowned'),
    'a proven committed continuation must be handled before the commit unowned reset, because ArkWeb can report the ' +
      'committed entry before onPageBegin'
  );
  assert.ok(
    committedNavigation.includes('session.associations.push({') &&
      committedNavigation.includes('context: committedContext'),
    'a committed continuation must own an exact history association so Back/Forward restore the right query'
  );
  assert.ok(
    historyApiChange.indexOf("'history-api-continuation'") > 0 &&
      historyApiChange.indexOf("'history-api-continuation'") < historyApiChange.indexOf("'history-api-change'"),
    'a same-document route change inside the proven result page must be handled before the history reset'
  );
  assert.ok(
    historyApiChange.includes("(event.kind === 'pushState' || event.kind === 'replaceState')"),
    'only same-document route changes with a new document URL can continue; an unassociated popstate must keep hiding'
  );
});

console.log('Quick Search continuation contract passed.');
