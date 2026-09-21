const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

// A download that belongs to an ad frame or a subresource must not move the tab's own document. Two
// things previously made it move anyway, and both were user-visible as "the page jumped back to an
// earlier URL":
//   1. the rewind target was the runtime's last committed document, which legitimately lags whenever the
//      download guard suppressed that commit, so the rewind could land on the site's first page;
//   2. the download prompt is re-presented on every shell foreground resume, so the same download rewound
//      (and re-loaded with clearHistory) an unchanged page again and again.
// This guards the record-repair/rewind split and the once-per-prompt rewind.
const repoRoot = path.resolve(__dirname, '..');
const stateCoordinatorPath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserDownloadNavigationStateCoordinator.ets');
const overlayCoordinatorPath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserDownloadConfirmOverlayCoordinator.ets');
const shellPagePath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets');

const stateCoordinator = fs.readFileSync(stateCoordinatorPath, 'utf8');
const overlayCoordinator = fs.readFileSync(overlayCoordinatorPath, 'utf8');
const shellPage = fs.readFileSync(shellPagePath, 'utf8');

function section(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  assert.ok(start >= 0, `Missing section: ${startMarker}`);
  const end = source.indexOf(endMarker, start);
  assert.ok(end > start, `Missing section end: ${endMarker}`);
  return source.slice(start, end);
}

// The guard call sites sit inside bodies whose tail contains the `buildResetPatch(` definition, so
// extract them by brace-balanced method ranges instead of by the next definition marker.
function methodBody(source, signature) {
  const start = source.indexOf(signature);
  assert.ok(start >= 0, `Missing method: ${signature}`);
  const openBrace = source.indexOf('{', start);
  assert.ok(openBrace > start, `Missing method body: ${signature}`);
  let depth = 0;
  for (let index = openBrace; index < source.length; index += 1) {
    const character = source[index];
    if (character === '{') {
      depth += 1;
    } else if (character === '}') {
      depth -= 1;
      if (depth === 0) {
        return source.slice(start, index + 1);
      }
    }
  }
  assert.fail(`Unbalanced method body: ${signature}`);
}

const fallbackResolution = section(
  stateCoordinator,
  'private resolveFallbackUrl(',
  'private resolveLiveDocumentUrl('
);
const liveDocumentGuards = methodBody(stateCoordinator, 'shouldSuppressNavigationReplay(');
const promptReset = methodBody(stateCoordinator, 'resetPromptNavigationState(');
const presentRewind = section(
  overlayCoordinator,
  'if (!inlineDocumentResolution.shouldPreserveStableDocument) {',
  'this.activeLeaseId = presentation.lease.id;'
);

test('the live document is a first-class input to the rewind decision', () => {
  assert.ok(
    stateCoordinator.includes('resolveLiveDocumentUrl?: (tabId: string) => string;'),
    'the download coordinator must be able to ask what ArkWeb is actually showing'
  );
  assert.ok(
    shellPage.includes('resolveLiveDocumentUrl: (tabId: string): string => {') &&
      shellPage.includes('controller.getUrl()'),
    'the shell must answer with the live controller URL'
  );
});

test('a download that did not take over the tab document never rewinds the page', () => {
  assert.ok(
    fallbackResolution.includes('const downloadTookOverDocument =') &&
      fallbackResolution.includes('if (!downloadTookOverDocument && normalizedLiveDocumentUrl.length > 0) {') &&
      fallbackResolution.includes('return liveDocumentUrl;'),
    'an ad-frame or subresource download must keep the tab on its current document'
  );
  assert.ok(
    stateCoordinator.includes('private isLiveDocumentUnchanged(tabId: string, targetUrl: string): boolean {') &&
      liveDocumentGuards.includes('!this.isLiveDocumentUnchanged(tabId, restoredUrl)') &&
      promptReset.includes('!this.isLiveDocumentUnchanged(activeTab.id, restoredUrl)'),
    'both rewind call sites must skip the load when ArkWeb already shows the repaired record URL'
  );
});

test('the runtime last committed document is not preferred over the tab last good page', () => {
  const lastGoodIndex = fallbackResolution.indexOf('const lastGoodUrl = tab.lastGoodUrl.trim();');
  const previousStableIndex = fallbackResolution.indexOf('const normalizedPreviousStableUrl = this.normalizeUrl(previousStableUrl);');
  assert.ok(lastGoodIndex >= 0 && previousStableIndex >= 0,
    'both candidates must stay in the fallback chain');
  assert.ok(lastGoodIndex < previousStableIndex,
    'a lagging runtime last-known URL must not outrank the tab last good page');
});

test('one prompt rewinds at most once', () => {
  assert.ok(
    overlayCoordinator.includes('private rewoundPromptGuids: Record<string, boolean | undefined> = {};') &&
      presentRewind.includes('if (this.rewoundPromptGuids[prompt.guid] !== true) {') &&
      presentRewind.includes('this.rewoundPromptGuids[prompt.guid] = true;') &&
      presentRewind.includes('this.navigationStateCoordinator.resetPromptNavigationState(prompt.url);'),
    're-presenting the same pending download must not rewind the tab again'
  );
  assert.ok(
    overlayCoordinator.includes('private forgetRewoundPrompt(guid: string): void {') &&
      overlayCoordinator.includes('this.forgetRewoundPrompt(effectiveGuid);'),
    'confirming or cancelling a prompt must release its rewind record'
  );
});

console.log('Download rewind does not move an unchanged page contract passed.');
