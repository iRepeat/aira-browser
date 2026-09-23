#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.DEVECO_TYPESCRIPT_PATH ||
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');

const coreRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets/core/browser');

function transpile(filename) {
  const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS },
    fileName: filename,
    reportDiagnostics: true
  });
  const errors = (result.diagnostics || []).filter((diagnostic) => diagnostic.category === ts.DiagnosticCategory.Error);
  assert.equal(errors.length, 0, filename);
  return result.outputText;
}

function load(filename, dependencies) {
  const module = { exports: {} };
  vm.runInNewContext(transpile(filename), {
    module,
    exports: module.exports,
    require(id) {
      assert.ok(Object.hasOwn(dependencies, id), `Unexpected runtime dependency: ${id}`);
      return dependencies[id];
    }
  }, { filename });
  return module.exports;
}

const actionModule = load(path.join(coreRoot, 'BrowserTabPreviewActionCoordinator.ets'), {});
const {
  shouldCaptureTabPreviewOnLifecycleExit,
  BrowserTabPreviewActionCoordinator
} = actionModule;

assert.equal(shouldCaptureTabPreviewOnLifecycleExit({
  activeTabId: 'tab-1',
  showHomePage: false,
  source: 'ability-background'
}), true, 'a visible web tab still needs a lifecycle capture');
assert.equal(shouldCaptureTabPreviewOnLifecycleExit({
  activeTabId: 'tab-1',
  showHomePage: false,
  tabsOverviewVisible: true,
  source: 'ability-background'
}), false, 'tabs overview must keep the scrolled card image');
assert.equal(shouldCaptureTabPreviewOnLifecycleExit({
  activeTabId: 'tab-1',
  showHomePage: true,
  source: 'page-disappear'
}), false);

const events = [];
const requests = [];
const coordinator = new BrowserTabPreviewActionCoordinator();
coordinator.captureLifecycleExit({
  buildRequest: (tabId) => {
    requests.push(tabId);
    return undefined;
  },
  previewCoordinator: {},
  notifyChanged: () => {
    assert.fail('skipping the overview recapture must not refresh the card');
  },
  recordRuntimeEvent: (event, details, tabId) => {
    events.push({ event, details, tabId });
  }
}, {
  activeTabId: 'tab-1',
  showHomePage: false,
  tabsOverviewVisible: true,
  source: 'ability-background'
});
assert.deepEqual(requests, [], 'lifecycle exit must not start webPageSnapshot while the overview is open');
assert.equal(events.length, 1);
assert.equal(events[0].event, 'tab_preview_lifecycle_capture_skipped');
assert.match(events[0].details, /tabs-overview-visible/);

const storeModule = load(path.join(coreRoot, 'BrowserTabPreviewImageLeaseStore.ets'), {});
const previewModule = load(path.join(coreRoot, 'BrowserTabPreviewCoordinator.ets'), {
  './BrowserTabPreviewImageLeaseStore': storeModule,
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {} } },
  '@kit.ArkUI': {},
  '@kit.ArkWeb': {},
  '@kit.ImageKit': {},
  '../tabs/TabManager': {},
  '../../services/web/BrowserTabPreviewCaptureService': {
    BrowserTabPreviewCaptureService: class {},
    buildBrowserTabPreviewComponentSnapshotId: (tabId) => `component-${tabId}`,
    buildBrowserTabPreviewVisibleSnapshotId: (tabId) => `visible-${tabId}`,
    buildBrowserTabPreviewVisibleSurfaceSnapshotId: (tabId) => `surface-${tabId}`,
    buildBrowserTabWebComponentSnapshotId: (tabId) => `web-${tabId}`
  },
  '../../services/web/BrowserTabPreviewCacheStore': {
    BrowserTabPreviewCacheStore: class {
      async savePreviewImageWithStats() {
        return { uri: 'file://scrolled', bytes: 8 };
      }
    },
    DEFAULT_BROWSER_TAB_PREVIEW_SCOPE_ID: 'default'
  },
  './BrowserTabPreviewMetrics': {
    BROWSER_TAB_PREVIEW_PIXEL_WIDTH: 400,
    BROWSER_TAB_PREVIEW_PIXEL_HEIGHT: 800
  },
  './BrowserTabPreviewMetricsService': { sharedBrowserTabPreviewMetrics: { recordTransitionImage() {} } },
  '../../services/web/BrowserTabPreviewTypes': {},
  '../../services/web/BrowserTabPreviewDebugExportService': {},
  './BrowserProfileBoundaryService': { BrowserProfileBoundaryService: class {} },
  '../../services/web/BrowserRuntimeLifecyclePort': {}
});

function pixelMap() {
  return { release: () => Promise.resolve() };
}

const tab = {
  id: 'tab-1',
  url: 'https://example.com/article',
  title: 'Article',
  isHome: false,
  profileId: 'default',
  privacyMode: 'regular',
  dataScope: 'profile_persistent'
};
const previewCoordinator = new previewModule.BrowserTabPreviewCoordinator({}, {
  isHostedControllerAttached: () => true,
  isBackgroundHot: () => false,
  resolveWebViewportSnapshotSize: () => ({ width: 400, height: 800 })
});
previewCoordinator.profileBoundaryService.isSessionEphemeral = () => false;
previewCoordinator.captureCacheDirectoryStatsInBackground = () => {};

const coveredRequest = previewCoordinator.buildCaptureRequest({
  tab,
  controller: {},
  activeTabId: tab.id,
  showTabsSheet: true,
  showHomePage: false,
  suspendHostedWebSurface: false,
  hostedControllerAttached: true,
  activeControllerAttached: true,
  backgroundHot: false,
  shouldCaptureNativeErrorSurface: false,
  hasLiveController: true,
  force: true,
  requireSharedSnapshot: true
});
assert.equal(coveredRequest.keepExistingSnapshot, true);
assert.equal(coveredRequest.allowWhileLocked, false);
assert.equal(coveredRequest.preferVisibleSnapshot, false);

const visibleRequest = previewCoordinator.buildCaptureRequest({
  tab,
  controller: {},
  activeTabId: tab.id,
  showTabsSheet: false,
  showHomePage: false,
  suspendHostedWebSurface: false,
  hostedControllerAttached: true,
  activeControllerAttached: true,
  backgroundHot: false,
  shouldCaptureNativeErrorSurface: false,
  hasLiveController: true,
  force: true
});
assert.equal(visibleRequest.keepExistingSnapshot, false);
assert.equal(visibleRequest.preferVisibleSnapshot, true);

async function main() {
  let captureCalls = 0;
  previewCoordinator.captureService.captureWebPage = async () => {
    captureCalls += 1;
    return { snapshot: pixelMap(), source: 'web', sharedSnapshotImageUri: 'file://top' };
  };
  previewCoordinator.previewEntries[tab.id] = {
    tabId: tab.id,
    sharedSnapshotImageUri: 'file://scrolled',
    sharedSnapshotImageWidth: 400,
    sharedSnapshotImageHeight: 800,
    capturedAt: 50,
    transitionReady: true,
    transitionSource: {
      captureSource: 'visible-tab-surface',
      captureScope: 'full-surface',
      transitionFrame: 'captured-surface'
    },
    captureSource: 'visible-tab-surface',
    signature: '',
    lastKnownGoodSignature: ''
  };
  assert.equal(await previewCoordinator.capturePreview(coveredRequest), false);
  assert.equal(captureCalls, 0, 'a covered tab must not call webPageSnapshot');
  assert.equal(previewCoordinator.getSharedSnapshotState(tab.id).sharedSnapshotImageUri, 'file://scrolled');

  let releaseCapture;
  const captureStarted = new Promise((resolve) => {
    previewCoordinator.captureService.captureWebPage = () => new Promise((resolveCapture) => {
      releaseCapture = () => resolveCapture({
        snapshot: pixelMap(),
        source: 'web',
        sharedSnapshotImageUri: 'file://top',
        transitionSource: {
          captureSource: 'web',
          captureScope: 'web-content',
          transitionFrame: 'current-web'
        }
      });
      resolve();
    });
  });
  const inFlight = previewCoordinator.capturePreview({
    ...visibleRequest,
    keepExistingSnapshot: false
  });
  await captureStarted;
  assert.equal(await previewCoordinator.persistImmediateSharedSnapshot(tab, pixelMap(), {
    captureSource: 'visible-tab-surface',
    captureScope: 'full-surface',
    transitionFrame: 'captured-surface'
  }), true);
  releaseCapture();
  assert.equal(await inFlight, false, 'a snapshot that started before the overview image must be dropped');
  assert.equal(previewCoordinator.getSharedSnapshotState(tab.id).sharedSnapshotImageUri, 'file://scrolled');
  assert.equal(previewCoordinator.getSharedSnapshotState(tab.id).captureSource, 'visible-tab-surface');

  const overlay = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/app/components/browser/BrowserTabsFloatingOverlay.ets'), 'utf8');
  const morphOverlay = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/app/components/browser/BrowserTabsSharedSnapshotOverlay.ets'), 'utf8');
  assert.match(overlay, /snapshotImageUri: this\.resolveCardSnapshotImageUri\(item\)/);
  assert.match(overlay, /this\.entryMorphImageUri = liveUri/);
  assert.match(morphOverlay, /if \(this\.resolveRenderableImageUri\(\)\.length > 0\) \{\s*this\.buildUriImage\(\)/);
  console.log('Tab preview lifecycle snapshot checks passed.');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
