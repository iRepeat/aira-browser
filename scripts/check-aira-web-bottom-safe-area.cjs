const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.DEVECO_TYPESCRIPT_PATH ||
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
let now = 10000;
let timerId = 0;
const timers = new Map();
const cache = new Map();
class Clock extends Date { static now() { return now; } }
function load(relative) {
  const filename = path.resolve(root, relative);
  if (cache.has(filename)) return cache.get(filename);
  const module = { exports: {} };
  cache.set(filename, module.exports);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
  }).outputText;
  vm.runInNewContext(code, {
    module, exports: module.exports, Date: Clock,
    setTimeout(fn, delay) { const id = ++timerId; timers.set(id, { fn, due: now + delay }); return id; },
    clearTimeout(id) { timers.delete(id); },
    $r: value => value,
    require(specifier) {
      if (specifier === '@ohos.url') return { default: { URL: { parseURL: value => new URL(value) } } };
      if (specifier === '@kit.ArkWeb') return { webview: {} };
      if (specifier === '@kit.ArkData') return { preferences: {} };
      if (specifier === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
      assert.ok(specifier.startsWith('.'), `Unexpected dependency ${specifier}`);
      return load(path.relative(root, path.resolve(path.dirname(filename), `${specifier}.ets`)));
    }
  }, { filename });
  return module.exports;
}
async function advance(ms) {
  const until = now + ms;
  for (;;) {
    const next = [...timers].filter(([, timer]) => timer.due <= until).sort((a, b) => a[1].due - b[1].due)[0];
    if (!next) break;
    const [id, timer] = next;
    now = timer.due;
    timers.delete(id);
    timer.fn();
    for (let i = 0; i < 6; i++) await Promise.resolve();
  }
  now = until;
}
const { WebBottomSafeAreaScriptService } = load('services/web/WebBottomSafeAreaScriptService.ets');
const script = WebBottomSafeAreaScriptService.buildSampleScript();
// Controlled geometry fixtures execute the production detector, not a duplicate algorithm.
function fixture({ position = 'fixed', width = 390, barWidth = width, bottom = 800,
  barHeight = 60, count = 5, role = '', cursorTabs = false, hidden = false, dialog = false,
  overlay = false, stickyBottom = '0px', viewportHeight = 800, nested = false } = {}) {
  const nodes = [];
  function node(tagName, left, top, w, h, parent, attrs = {}, style = {}) {
    const item = {
      tagName, nodeType: 1, isConnected: true, parentElement: parent, attrs, children: [], disabled: false,
      style: { position: 'static', display: 'block', visibility: 'visible', opacity: '1',
        pointerEvents: 'auto', cursor: 'auto', bottom: 'auto', ...style },
      getBoundingClientRect: () => ({ left, top, width: w, height: h, right: left + w, bottom: top + h }),
      getAttribute: key => attrs[key] ?? null,
      hasAttribute: key => key in attrs,
      contains(other) { for (; other; other = other.parentElement) if (other === this) return true; return false; },
      closest: () => dialog ? {} : null
    };
    if (parent) parent.children.push(item);
    nodes.push(item);
    return item;
  }
  const body = node('BODY', 0, 0, width, viewportHeight, null);
  const bar = node('NAV', 0, bottom - barHeight, barWidth, barHeight, body, { role },
    { position, bottom: stickyBottom, display: hidden ? 'none' : 'block' });
  for (let i = 0; i < count; i++) {
    const control = node(cursorTabs ? 'DIV' : 'A', i * barWidth / count, bottom - barHeight,
      barWidth / count, barHeight, bar, cursorTabs ? {} : { href: `/tab/${i}` },
      cursorTabs ? { cursor: 'pointer' } : {});
    if (nested) node('SPAN', i * barWidth / count + 4, bottom - barHeight + 4,
      barWidth / count - 8, barHeight - 8, control, {}, { cursor: 'pointer' });
  }
  if (overlay) node('DIV', 0, 0, width, viewportHeight, body);
  let hitTests = 0;
  const document = {
    hidden: false, fullscreenElement: null, documentElement: { clientWidth: width },
    elementFromPoint(x, y) {
      hitTests++;
      return [...nodes].reverse().find(item => {
        if (!item.isConnected || bar.contains(item) && (!bar.isConnected || bar.style.display === 'none')) return false;
        const r = item.getBoundingClientRect();
        return x >= r.left && x < r.right && y >= r.top && y < r.bottom;
      }) || null;
    },
    createTreeWalker(parent) {
      const list = nodes.filter(item => item !== parent && parent.contains(item));
      let index = 0;
      return { nextNode: () => list[index++] || null };
    }
  };
  const window = { innerHeight: viewportHeight, visualViewport: { scale: 1, height: viewportHeight } };
  const performance = { now: () => 0 };
  const run = () => vm.runInNewContext(script, { document, window, performance, getComputedStyle: node => node.style });
  return { run, document, window, performance, bar, body, node, hits: () => hitTests };
}
assert.equal(fixture().run(), 'detected', 'five-tab bottom navigation');
assert.equal(fixture({ nested: true }).run(), 'detected', 'nested icon/label targets are deduplicated');
assert.equal(fixture({ cursorTabs: true }).run(), 'detected', 'framework div tabs');
assert.equal(fixture({ viewportHeight: 699, bottom: 699 }).run(), 'detected', 'still detected after reserving 101vp');
assert.equal(fixture({ position: 'sticky' }).run(), 'detected');
assert.equal(fixture({ position: 'sticky', stickyBottom: 'auto' }).run(), 'absent');
for (const options of [
  { position: 'static' }, { position: 'absolute' }, { count: 1 }, { barWidth: 50 },
  { bottom: 60 }, { barHeight: 300 }, { hidden: true }, { dialog: true }, { overlay: true },
  { position: 'sticky', bottom: 750 }
]) assert.equal(fixture(options).run(), 'absent', JSON.stringify(options));
const zoom = fixture(); zoom.window.visualViewport.scale = 2;
assert.equal(zoom.run(), 'suspended');
const keyboard = fixture(); keyboard.window.visualViewport.height = 440;
assert.equal(keyboard.run(), 'suspended');
const background = fixture(); background.document.hidden = true;
assert.equal(background.run(), 'suspended');
const expensive = fixture();
let elapsed = 0; expensive.performance.now = () => (elapsed += 5);
assert.equal(expensive.run(), 'deferred', 'exhausted time budget yields without changing detection state');
const bounded = fixture({ position: 'static' }); bounded.run();
assert.ok(bounded.hits() <= 20, 'normal pages use a bounded number of hit-tests');

const { BrowserWebViewportCoordinator: Viewport } = load('core/browser/BrowserWebViewportCoordinator.ets');
const geometry = { hostHeightPx: 844, visualTopInsetPx: 40, visualBottomInsetPx: 101,
  fullViewport: false, largeScreenShellActive: false, nativeVideoTakeoverActive: false };
assert.equal(Viewport.resolvePresentation(geometry).contentHeightPx, 703);
assert.equal(Viewport.resolvePresentation({ ...geometry, visualBottomInsetPx: 0 }).contentHeightPx, 804);
assert.equal(Viewport.resolvePresentation({ ...geometry, fullViewport: true }).contentHeightPx, 844);
assert.equal(Viewport.resolvePresentation({ ...geometry, largeScreenShellActive: true }).fillParentHeight, true);
assert.equal(Viewport.resolvePresentation({ ...geometry, nativeVideoTakeoverActive: true }).fillParentHeight, true);

const { BrowserWebBottomSafeAreaCoordinator } = load('core/browser/BrowserWebBottomSafeAreaCoordinator.ets');
function events(target) {
  const listeners = new Map();
  target.addEventListener = (name, fn) => { if (!listeners.has(name)) listeners.set(name, new Set()); listeners.get(name).add(fn); };
  target.removeEventListener = (name, fn) => listeners.get(name)?.delete(fn);
  target.dispatch = (name, extra = {}) => { for (const fn of [...(listeners.get(name) || [])]) fn({ type: name, target, ...extra }); };
  target.listenerCount = () => [...listeners.values()].reduce((sum, set) => sum + set.size, 0);
}
function page(options) {
  const f = fixture(options);
  events(f.window); events(f.document); events(f.window.visualViewport);
  f.window.top = f.window;
  const signals = [];
  f.window.__airaPageBehaviorNativeBridge = { onSignal: payload => signals.push(JSON.parse(payload)) };
  let mutation;
  let resize;
  const context = vm.createContext({ document: f.document, window: f.window, performance: f.performance,
    getComputedStyle: node => node.style, Date: Clock,
    setTimeout(fn, delay) { const id = ++timerId; timers.set(id, { fn, due: now + delay }); return id; },
    clearTimeout(id) { timers.delete(id); },
    MutationObserver: class { constructor(fn) { this.fn = fn; mutation = this; } observe() { this.active = true; } disconnect() { this.active = false; } },
    ResizeObserver: class { constructor(fn) { this.fn = fn; resize = this; } observe() { this.active = true; } disconnect() { this.active = false; } }
  });
  const run = source => vm.runInContext(source, context);
  run(WebBottomSafeAreaScriptService.buildInstallScript('test-document'));
  return { ...f, signals, run,
    mutate(records) { if (mutation?.active) mutation.fn(records); },
    resize() { if (resize?.active) resize.fn([]); },
    command(name) { run(WebBottomSafeAreaScriptService.buildCommandScript('test-document', name)); }
  };
}
function runtime() {
  const scripts = [];
  const controller = { runJavaScript(script) { scripts.push(script); return Promise.resolve(''); } };
  const facts = { tabId: 'a', url: 'https://example.test/', controller, eligible: true,
    suspended: false, insetSuppressed: false, systemBottomInsetVp: 24 };
  const updates = [];
  const coordinator = new BrowserWebBottomSafeAreaCoordinator({ readFacts: () => facts,
    applyBottomInset: inset => updates.push(inset) });
  return { coordinator, facts, updates, scripts,
    token(tab = facts.tabId) { return coordinator.sessions.get(tab)?.token; },
    signal(result, overrides = {}) {
      const session = coordinator.sessions.get(facts.tabId);
      return coordinator.handleSignal(facts.tabId, JSON.stringify({ kind: 'bottom-safe-area',
        token: session.token, sequence: session.sequence + 1, result, ...overrides }));
    }
  };
}
(async () => {
  const p = page();
  await advance(120);
  assert.deepEqual(p.signals.map(s => s.result), ['detected'], 'initial event finds a bar without waiting seconds');
  const initialHits = p.hits();
  await advance(120000);
  assert.equal(p.hits(), initialHits, 'idle documents perform zero recurring DOM scans');
  assert.equal(timers.size, 0, 'no idle polling timers');
  const news = p.node('ARTICLE', 0, 100, 390, 100, p.body);
  for (let i = 0; i < 100; i++) p.mutate([{ type: 'childList', target: news, addedNodes: [] }]);
  await advance(1000);
  assert.equal(p.hits(), initialHits, 'unrelated feed updates do not recheck a cached bar');
  p.document.dispatch('touchstart');
  p.bar.style.display = 'none';
  p.mutate([{ type: 'attributes', target: p.bar }]);
  await advance(5000);
  assert.equal(p.hits(), initialHits, 'held finger blocks page geometry reads');
  p.document.dispatch('touchend');
  for (let i = 0; i < 10; i++) { p.document.dispatch('scroll'); await advance(100); }
  assert.equal(p.hits(), initialHits, 'nested/inertial scroll postpones pending checks');
  await advance(1200);
  assert.deepEqual(p.signals.map(s => s.result), ['detected', 'absent'], 'confirmed hidden bar releases inset');
  p.bar.style.display = 'block';
  for (let i = 0; i < 100; i++) p.mutate([{ type: 'childList', target: p.body, addedNodes: [p.bar] }]);
  await advance(300);
  assert.deepEqual(p.signals.map(s => s.result), ['detected', 'absent', 'detected'], 'dynamic bar is found from coalesced mutations');
  const dynamicHits = p.hits();
  p.resize(); p.window.dispatch('resize'); await advance(300);
  assert.equal(p.signals.length, 3, 'native signals are deduplicated');
  assert.ok(p.hits() - dynamicHits < 10, 'cached element validation avoids repeating all bottom hit tests');
  p.command('pause');
  const pausedHits = p.hits();
  p.mutate([{ type: 'attributes', target: p.bar }]); p.window.dispatch('resize');
  await advance(60000);
  assert.equal(p.hits(), pausedHits, 'settings/background pauses observers and work');
  assert.equal(p.document.listenerCount(), 1, 'only lifecycle listener remains paused');
  p.command('resume'); await advance(120);
  assert.ok(p.hits() > pausedHits);
  p.document.hidden = true; p.document.dispatch('visibilitychange');
  const hiddenHits = p.hits(); await advance(60000); assert.equal(p.hits(), hiddenHits);
  p.document.hidden = false; p.document.dispatch('visibilitychange'); await advance(300);
  p.window.dispatch('pagehide');
  assert.equal(timers.size, 0);
  p.window.dispatch('pageshow'); await advance(300);
  p.command('dispose');
  assert.equal(p.document.listenerCount() + p.window.listenerCount() + p.window.visualViewport.listenerCount(), 0);
  assert.equal(timers.size, 0, 'disable removes timers and all listeners');

  const late = page({ hidden: true }); await advance(120);
  assert.equal(late.signals.at(-1).result, 'absent');
  let readAddedNodes = 0;
  const hugeTextBatch = new Proxy({ length: 1000000 }, { get(target, key) {
    if (key === 'length') return target.length;
    readAddedNodes++; return { nodeType: 3 };
  } });
  late.mutate([{ type: 'childList', target: late.body, addedNodes: hugeTextBatch }]);
  assert.ok(readAddedNodes <= 16, 'large text-only mutation batches have a strict callback work bound');
  late.bar.style.display = 'block';
  late.mutate([{ type: 'attributes', target: late.bar }]); await advance(300);
  assert.equal(late.signals.at(-1).result, 'detected', 'previously absent page reacts to a late bar');
  late.bar.isConnected = false;
  late.mutate([{ type: 'childList', target: late.body, addedNodes: [] }]); await advance(650);
  assert.equal(late.signals.at(-1).result, 'absent', 'removal of cached element is detected');
  late.command('dispose');

  const exhausted = page();
  let cost = 0; exhausted.performance.now = () => (cost += 5);
  await advance(10000);
  assert.equal(exhausted.signals.length, 0, 'budget exhaustion does not discard prior state');
  assert.equal(timers.size, 0, 'budget retries end instead of becoming polling');
  exhausted.command('dispose');

  // Run both production layers together through the actual tagged bridge protocol.
  const integratedPage = page(); integratedPage.command('dispose');
  const integratedFacts = { tabId: 'integrated', url: 'https://example.test/',
    controller: { runJavaScript: source => Promise.resolve(integratedPage.run(source)) },
    eligible: true, suspended: false, systemBottomInsetVp: 24 };
  const integratedUpdates = [];
  const integrated = new BrowserWebBottomSafeAreaCoordinator({ readFacts: () => integratedFacts,
    applyBottomInset: value => integratedUpdates.push(value) });
  integratedPage.window.__airaPageBehaviorNativeBridge.onSignal = payload => integrated.handleSignal('integrated', payload);
  integrated.setVisible(true); integrated.setEnabled(true); await advance(120);
  assert.deepEqual(integratedUpdates, [101], 'page detection activates the native inset through the bridge');
  integrated.setVisible(false); integratedPage.bar.style.display = 'none'; await advance(1000);
  assert.deepEqual(integratedUpdates, [101]);
  integrated.setVisible(true);
  assert.deepEqual(integratedUpdates, [101], 'resume restores memory before async validation');
  await advance(1000);
  assert.deepEqual(integratedUpdates, [101, 0], 'quiet verification detects a bar removed while settings were open');
  integrated.dispose();
  assert.equal(integratedPage.document.listenerCount() + integratedPage.window.listenerCount(), 0);

  const a = runtime();
  a.coordinator.setVisible(true); await advance(60000);
  assert.equal(a.scripts.length, 0, 'default off installs nothing');
  a.coordinator.setEnabled(true);
  a.signal('detected'); assert.deepEqual(a.updates, [101]);
  const idleCalls = a.scripts.length; await advance(120000);
  assert.equal(a.scripts.length, idleCalls, 'native coordinator never polls');
  a.coordinator.setVisible(false);
  assert.equal(a.updates.at(-1), 101, 'settings hide preserves geometry and detection');
  const settingsCalls = a.scripts.length; await advance(60000); assert.equal(a.scripts.length, settingsCalls);
  a.coordinator.setVisible(true);
  assert.deepEqual(a.updates, [101], 'return from settings never briefly collapses safe area');
  // A cover that only hides the page pauses detection but keeps the reserved space, so dismissing
  // it cannot resize the Web viewport. Only a surface that owns the bottom edge releases the space.
  a.facts.suspended = true; a.coordinator.reconcile();
  assert.equal(a.updates.at(-1), 101, 'a cover pauses detection without releasing the reserved space');
  a.facts.suspended = false; a.coordinator.reconcile(); assert.equal(a.updates.at(-1), 101);
  a.facts.insetSuppressed = true; a.coordinator.reconcile(); assert.equal(a.updates.at(-1), 0);
  a.facts.insetSuppressed = false; a.coordinator.reconcile(); assert.equal(a.updates.at(-1), 101);
  a.coordinator.handleTouch('a', true); a.signal('absent'); await advance(10000);
  assert.equal(a.updates.at(-1), 101, 'late bridge result cannot resize during gesture');
  a.coordinator.handleTouch('a', false);
  for (let i = 0; i < 10; i++) { a.coordinator.handleScroll('a'); await advance(100); }
  assert.equal(a.updates.at(-1), 101);
  await advance(1300); assert.equal(a.updates.at(-1), 0);
  a.signal('detected');
  const token = a.token();
  a.facts.url += '#news'; a.coordinator.reconcile(); assert.equal(a.token(), token, 'same-document URL retains session');
  a.facts.tabId = 'b'; a.coordinator.reconcile(); assert.equal(a.updates.at(-1), 0);
  a.facts.tabId = 'a'; a.coordinator.reconcile(); assert.equal(a.updates.at(-1), 101, 'tab return reuses document result');
  a.coordinator.handleDocumentBegin('a'); assert.equal(a.updates.at(-1), 0);
  a.coordinator.requestCheck('a');
  a.signal('detected', { token }); assert.equal(a.updates.at(-1), 0, 'same-URL reload rejects old generation');
  a.signal('detected'); assert.equal(a.updates.at(-1), 101);
  a.signal('absent', { sequence: 0 }); assert.equal(a.updates.at(-1), 101, 'out-of-order bridge ignored');
  a.coordinator.retainTabs(['a']); assert.equal(a.coordinator.sessions.size, 1, 'closed tabs release cached controllers');
  a.facts.controller = { runJavaScript: () => Promise.resolve('') }; a.coordinator.reconcile();
  assert.equal(a.updates.at(-1), 0, 'controller replacement invalidates document memory');
  a.coordinator.setEnabled(false);
  assert.equal(a.coordinator.sessions.size, 0);
  assert.equal(a.updates.at(-1), 0);
  a.coordinator.dispose();
  assert.equal(timers.size, 0);

  const { DEFAULT_BROWSER_EXPERIMENT_SETTINGS, PreferencesRepository } = load('data/preferences/PreferencesRepository.ets');
  assert.equal(DEFAULT_BROWSER_EXPERIMENT_SETTINGS.webBottomSafeAreaEnabled, false);
  const repository = new PreferencesRepository();
  const legacy = { ...DEFAULT_BROWSER_EXPERIMENT_SETTINGS };
  delete legacy.webBottomSafeAreaEnabled;
  await repository.updateExperimentSettings(legacy);
  assert.equal(repository.getPreferences().experiments.webBottomSafeAreaEnabled, false, 'older settings default off');
  const { SettingsDetailActionResolver } = load('core/settings/SettingsDetailActionResolver.ets');
  const resolver = new SettingsDetailActionResolver();
  let settings = resolver.buildExperimentSettingsForAction('toggle_web_bottom_safe_area', true, legacy);
  await repository.updateExperimentSettings(settings);
  assert.equal(repository.getPreferences().experiments.webBottomSafeAreaEnabled, true);
  settings = resolver.buildExperimentSettingsForAction('toggle_pull_refresh', false, settings);
  assert.equal(settings.webBottomSafeAreaEnabled, true, 'other settings preserve opt-in');
  const { ArkPreferencesStorageAdapter } = load('data/preferences/ArkPreferencesStorageAdapter.ets');
  const stored = new Map();
  const store = { getSync: (key, fallback) => stored.get(key) ?? fallback,
    putSync: (key, value) => stored.set(key, value), flushSync() {} };
  const adapter = new ArkPreferencesStorageAdapter();
  adapter.store = store;
  await adapter.writeExperimentSettings(settings);
  const reopened = new ArkPreferencesStorageAdapter(); reopened.store = store;
  assert.equal((await reopened.readExperimentSettings(DEFAULT_BROWSER_EXPERIMENT_SETTINGS)).webBottomSafeAreaEnabled,
    true, 'opt-in survives storage serialization and a fresh adapter');
  await adapter.writeExperimentSettings(legacy);
  assert.equal((await reopened.readExperimentSettings(DEFAULT_BROWSER_EXPERIMENT_SETTINGS)).webBottomSafeAreaEnabled,
    false, 'legacy persisted settings default off');
  await adapter.writeExperimentSettings({ ...legacy, webBottomSafeAreaEnabled: 'true' });
  assert.equal((await reopened.readExperimentSettings(DEFAULT_BROWSER_EXPERIMENT_SETTINGS)).webBottomSafeAreaEnabled,
    false, 'malformed persisted opt-in cannot enable the experiment');

  // The tabs overview covers the page inside the same shell instead of navigating away, so nothing
  // else re-evaluates bottom avoidance on the way out. Without this callback the observer stays
  // paused and the page never regains its reserved space.
  const shellSource = fs.readFileSync(path.resolve(root, 'app/pages/BrowserShellPage.ets'), 'utf8');
  assert.match(shellSource, /@Watch\('handleTabsOverviewBottomSafeAreaChange'\)\s*showTabsSheet/,
    'the tabs overview must re-evaluate bottom avoidance when it opens or closes');
  const handlerStart = shellSource.indexOf('private handleTabsOverviewBottomSafeAreaChange(');
  assert.ok(handlerStart >= 0, 'the tabs overview change handler must exist');
  assert.match(shellSource.slice(handlerStart, handlerStart + 320),
    /browserWebBottomSafeAreaCoordinator\.requestCheck\(this\.activeTabId\)/,
    'the tabs overview change handler must re-request a bottom-safe-area check');
  assert.match(shellSource,
    /suspended: this\.resolveWebBottomSafeAreaInsetSuppressed\(\) \|\| this\.showTabsSheet,\s*\n\s*insetSuppressed: this\.resolveWebBottomSafeAreaInsetSuppressed\(\)/,
    'pausing detection and releasing the reserved space must stay separate facts');
  console.log('Web bottom safe area: event runtime, document memory, input budgets, viewport, and settings checks passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
