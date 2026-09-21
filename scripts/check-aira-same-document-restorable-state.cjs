const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

// A same-document navigation (History API, fragment, SPA route) commits a new entry without loading a
// document. Reopening that tab must land on the route the user left, so the tab's restorable state has to
// follow the route change, and the WebState that describes the previous document must not be replayed.
// Regression this guards: a deep client-side route stayed restorable only as far as the last real document
// (for a site entered from its own home page: that site's first page), so a restore after a background /
// foreground trip put the user back on the first page.
const repoRoot = path.resolve(__dirname, '..');
const lifecyclePath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserWebPageLifecycleApplicationCoordinator.ets');
const commitCoordinatorPath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserWebEventCommitCoordinator.ets');

const lifecycle = fs.readFileSync(lifecyclePath, 'utf8');
const commitCoordinator = fs.readFileSync(commitCoordinatorPath, 'utf8');

function section(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  assert.ok(start >= 0, `Missing section: ${startMarker}`);
  const end = source.indexOf(endMarker, start);
  assert.ok(end > start, `Missing section end: ${endMarker}`);
  return source.slice(start, end);
}

const sameDocumentPatch = section(
  lifecycle,
  'private applySameDocumentCommittedPatch(',
  'private updateActiveCommittedUrl('
);
const historyApiBranch = section(
  lifecycle,
  'private applyHistoryApiUrlChange(',
  'private applyNavigationCommittedPatch('
);
const navigationCommittedPatch = section(
  lifecycle,
  'private applyNavigationCommittedPatch(',
  'private applySameDocumentCommittedPatch('
);
const entryCommittedCommit = section(
  commitCoordinator,
  'applyNavigationEntryCommittedCommit(',
  'applyTitleReceive('
);

test('ArkWeb same-document commits reach the same-document tab state path', () => {
  assert.ok(
    lifecycle.includes('details.isSameDocument === true'),
    'the ArkWeb committed-navigation facts must be forwarded as same-document, not re-derived'
  );
  assert.ok(
    navigationCommittedPatch.includes('if (isSameDocument) {') &&
      navigationCommittedPatch.includes('this.applySameDocumentCommittedPatch(tabId, committedUrl, nextTitle);'),
    'a same-document commit must not take the document-load patch (loading state, no restorable advance)'
  );
  assert.ok(
    commitCoordinator.includes('applyNavigationCommittedPatch: (tabId: string, url: string, isSameDocument: boolean) => void;') &&
      entryCommittedCommit.includes('host.applyNavigationCommittedPatch(tabId, committedUrl, isSameDocument);'),
    'the commit coordinator must pass the same-document fact into the tab state host'
  );
});

test('the History API route path reuses the same same-document tab state', () => {
  assert.ok(
    historyApiBranch.includes('this.applySameDocumentCommittedPatch(tabId, url, tab.title);'),
    'pushState / replaceState / popstate / hashchange must advance the same restorable state'
  );
});

test('a same-document route change advances the restorable state', () => {
  assert.ok(
    sameDocumentPatch.includes('this.dependencies.sessionStateStore.buildLoadSuccessPatch(committedUrl, title)'),
    'the route change must reuse the load-success patch instead of inventing a second restorable-state rule'
  );
  ['lastGoodUrl:', 'lastGoodTitle:', 'lastRestorableUrl:', 'lastRestorableTitle:'].forEach((field) => {
    assert.ok(
      sameDocumentPatch.includes(field),
      `a route change must advance ${field} so a restore cannot fall back to the previous document`
    );
  });
  assert.ok(
    sameDocumentPatch.includes("runtimeState: 'active'"),
    'a same-document route change is not a document load, so the tab must not be left loading'
  );
  assert.ok(
    !sameDocumentPatch.includes("runtimeState: 'loading'"),
    'a same-document route change must not mark the tab as loading a document'
  );
});

test('a route change drops the WebState that describes the previous document', () => {
  assert.ok(
    sameDocumentPatch.includes("webStatePath: ''") && sameDocumentPatch.includes('webStateUpdatedAt: 0'),
    'the persisted WebState belongs to the pre-route document and must not be replayed as this page'
  );
});

console.log('Same-document restorable state contract passed.');
