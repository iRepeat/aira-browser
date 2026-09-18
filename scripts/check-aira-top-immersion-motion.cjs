const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.DEVECO_TYPESCRIPT_PATH ||
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');

const root = path.resolve(__dirname, '..');
const sourceRoot = path.join(root, 'AiraBrowser/entry/src/main/ets');
const cache = new Map();
function load(relativePath) {
  const filename = path.join(sourceRoot, relativePath);
  if (cache.has(filename)) return cache.get(filename);
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    fileName: filename
  }).outputText;
  vm.runInNewContext(code, {
    module, exports: module.exports, Date,
    setTimeout: () => 1, clearTimeout() {},
    require(specifier) {
      if (specifier === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
      if (specifier === '@kit.ArkWeb') return { webview: {} };
      if (specifier === './BrowserContinuationCoordinator') {
        return { sharedBrowserContinuationCoordinator: { updateActiveTabScroll() {} } };
      }
      if (specifier === '../../common/debug/AiraScrollOscProbe') {
        return { AiraScrollOscProbe: { markSignal() {}, markSource() {} } };
      }
      assert.ok(specifier.startsWith('.'), `Unexpected dependency: ${specifier}`);
      return load(path.relative(sourceRoot, path.resolve(path.dirname(filename), `${specifier}.ets`)));
    }
  }, { filename });
  cache.set(filename, module.exports);
  return module.exports;
}

const { BrowserWebTopImmersionSessionCoordinator } =
  load('core/browser/BrowserWebTopImmersionSessionCoordinator.ets');
const { BrowserTopImmersionScrollCoordinator } = load('core/browser/BrowserTopImmersionScrollCoordinator.ets');
const { BrowserBottomChromeScrollCoordinator } = load('core/browser/BrowserBottomChromeScrollCoordinator.ets');
const { BrowserWebScrollInteractionCoordinator } = load('core/browser/BrowserWebScrollInteractionCoordinator.ets');

function fixture() {
  const facts = {
    activeTabId: 'tab-1', browserShellVisible: true, webPageVisible: true,
    homePageVisible: false, tabsSheetVisible: false, scrollTopImmersionEnabled: true,
    alwaysTopImmersionEnabled: false, fullScreenModeEnabled: false,
    webAppTopSafeAreaHidden: false, assistantVideoTakeoverActive: false,
    scrollOffsetY: 0, addressFocused: false, bottomPanelInteractive: false, statusBarVisible: true
  };
  const updates = [];
  const coordinator = new BrowserWebTopImmersionSessionCoordinator({
    resolveFacts: () => facts,
    host: {
      resolveVisibleTopInsetPx: () => 40,
      applyPresentation(visible, inset, source, durationMs = 0) {
        updates.push({ visible, inset, source, durationMs });
        facts.statusBarVisible = visible;
      },
      applyWindowVisibility: async () => true,
      scheduleSafeInsetSettle() {}
    }
  }, new BrowserTopImmersionScrollCoordinator({
    hideDeltaPx: 24, revealDeltaPx: 32, visibilitySwitchCooldownMs: 0
  }));
  const scroll = y => {
    facts.scrollOffsetY = y;
    coordinator.handleScroll(facts.activeTabId, y);
  };
  const hide = () => { scroll(0); scroll(40); };
  return { facts, updates, coordinator, scroll, hide };
}

const normal = fixture();
normal.hide();
normal.scroll(0);
assert.deepEqual(normal.updates.map(update => update.inset), [0, 40]);
for (const update of normal.updates) {
  assert.ok(update.durationMs > 0 && update.durationMs <= 240,
    `Scroll ${update.visible ? 'reveal' : 'hide'} must animate instead of snapping; duration=${update.durationMs}`);
}

// Exercise the actual order: bottom chrome restores first, then top immersion
// resolves fresh shell facts from that same user scroll event.
for (const behavior of ['compact', 'hidden']) {
  const item = fixture();
  let bottomPresentation = 'resting';
  item.facts.bottomPanelInteractive = true;
  const interaction = new BrowserWebScrollInteractionCoordinator({
    bottomChromeScrollCoordinator: new BrowserBottomChromeScrollCoordinator({
      applyPresentationDeltaPx: 28, restorePresentationDeltaPx: 24, transitionCooldownMs: 0
    }),
    topImmersionSessionCoordinator: item.coordinator,
    recentActionManager: { recordClick() {} },
    scrollPerformanceCoordinator: {
      createState: () => ({}), activateForMove: state => state
    },
    smoothModeService: {}, runtimeLifecyclePort: {}
  }, {
    resolveFacts: () => ({
      activeTabId: item.facts.activeTabId, webPageVisible: true, addressFocused: false,
      currentDetent: 'low', currentPresentation: bottomPresentation, tabsSheetVisible: false,
      webAppImmersiveMode: false, fullScreenModeEnabled: false,
      smoothModeRuntimeEnabled: false, experimentSettings: {}
    }),
    applyBottomChromeDecision(decision) {
      bottomPresentation = decision.presentation;
      item.facts.bottomPanelInteractive = bottomPresentation === 'resting';
    }
  });
  interaction.applyBottomToolbarScrollBehavior(behavior, item.facts.activeTabId);
  interaction.handleTouch(item.facts.activeTabId, 'down');
  interaction.handleTouch(item.facts.activeTabId, 'move');
  for (const y of [0, 40, 16]) {
    item.facts.scrollOffsetY = y;
    interaction.handleScroll(item.facts.activeTabId, y);
  }
  assert.equal(bottomPresentation, 'resting');
  assert.deepEqual(item.updates.map(update => update.inset), [0, 40]);
  assert.ok(item.updates.at(-1).durationMs > 0,
    `Top inset must animate when ${behavior} bottom chrome restores during the same scroll event`);
}

for (const source of ['history-navigation', 'tabs-overview-entry', 'navigation-start']) {
  const item = fixture();
  item.hide();
  item.coordinator.requestVisible(source);
  assert.equal(item.updates.at(-1).durationMs, 0, `${source} must settle immediately`);
}
for (const field of ['addressFocused', 'bottomPanelInteractive', 'tabsSheetVisible']) {
  const item = fixture();
  item.hide();
  item.facts[field] = true;
  item.scroll(0);
  assert.equal(item.updates.at(-1).durationMs, 0, `${field} is not a scroll reveal`);
}
const disabled = fixture();
disabled.hide();
disabled.facts.scrollTopImmersionEnabled = false;
disabled.coordinator.syncPolicy('settings');
assert.equal(disabled.updates.at(-1).durationMs, 0);

const forced = fixture();
forced.facts.fullScreenModeEnabled = true;
forced.coordinator.requestFullscreenHidden();
assert.equal(forced.updates.at(-1).durationMs, 0, 'Fullscreen must settle immediately');

const refresh = fixture();
refresh.coordinator.refreshVisibleInset('quick-search');
assert.equal(refresh.updates.at(-1).durationMs, 0, 'Chrome content changes must settle immediately');

const renderer = fs.readFileSync(path.join(sourceRoot,
  'app/components/browser/BrowserWebViewportSurfaceHost.ets'), 'utf8');
assert.doesNotMatch(renderer, /if\s*\(this\.presentation\.topSafeOverlayHeightPx\s*>\s*0\)/,
  'Top chrome must remain mounted while its height animates to/from zero');
assert.doesNotMatch(renderer, /\.animation\(/,
  'Do not apply unconditional animations to history-navigation geometry');
console.log('Top immersion motion passed: scroll hide/reveal animate; navigation and forced changes settle immediately.');
