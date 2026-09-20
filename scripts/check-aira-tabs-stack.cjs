const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.DEVECO_TYPESCRIPT_PATH ||
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');

function load(relative, requireDependency) {
  const filename = path.resolve(__dirname, '..', relative);
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    fileName: filename, reportDiagnostics: true
  });
  assert.equal((compiled.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error).length,
    0, `Transpile errors in ${filename}`);
  const module = { exports: {} };
  vm.runInNewContext(compiled.outputText, {
    module, exports: module.exports, require: requireDependency
  }, { filename });
  return module.exports;
}
const exportsUnderTest = load(
  'AiraBrowser/entry/src/main/ets/core/browser/tabsOverview/BrowserTabsOverviewStackLayoutPolicy.ets',
  name => { throw new Error(`Pure policy must not import ${name}`); });
const policy = new exportsUnderTest.BrowserTabsOverviewStackLayoutPolicy();
const close = (actual, expected, tolerance = 1e-9) =>
  assert.ok(Math.abs(actual - expected) <= tolerance, `${actual} != ${expected}`);
const fields = ['offsetX', 'scale', 'opacity', 'titleOpacity', 'shadeOpacity', 'zIndex'];

test('the Hyperion suite executes against the actual transpiled ETS source', () => {
  let cases = 0;
  const suite = load('AiraBrowser/entry/src/test/BrowserTabsOverviewStackLayoutPolicy.test.ets', name => {
    if (name === '@ohos/hypium') return {
      describe: (_name, body) => body(),
      it: (name, _flags, body) => {
        try { body(); cases++; } catch (error) { throw new Error(name, { cause: error }); }
      },
      expect: value => ({
        assertTrue: () => assert.equal(value, true),
        assertFalse: () => assert.equal(value, false)
      })
    };
    assert.equal(name, '../main/ets/core/browser/tabsOverview/BrowserTabsOverviewStackLayoutPolicy');
    return exportsUnderTest;
  });
  suite.default();
  assert.equal(cases, 14);
});

// Fixed values independently evaluated by transliterating AppSwitcherOverlay.kt (commit 8298945).
// Inputs: index, raw scroll position, count, card width. Outputs follow `fields`.
const goldens = [
  [[2, 2, 6, 250], [0, .98, 1, 1, 0, 2]],
  [[1, 2, 6, 250], [-55, .97, 1, 0, .25, 1]],
  [[0, 2, 6, 250], [-70.4, .965, 1, 0, .5, 0]],
  [[3, 2, 6, 250], [212.5, 1, 1, 1, 0, 3]],
  [[0, 2.5, 6, 250], [-73.21986676296929, .9635355339059327, .5, 0, .5, 0]],
  [[2, 2.5, 6, 250], [-35.96768830317987, .974142135623731, 1, .5, .125, 2]],
  [[3, 2.5, 6, 250], [92.4959973502132, .99, 1, 1, 0, 3]],
  [[4, 2.5, 6, 250], [345.67537706926646, 1, 1, .5, 0, 4]],
  [[5, 2.5, 6, 250], [638.0973555526352, 1, 1, 0, 0, 5]],
  [[0, -.5, 6, 250], [54.64285714285714, .98, 1, 1, 0, 0]],
  [[1, -.5, 6, 250], [293.2310267857143, 1, 1, 1, 0, 1]],
  [[2, -.5, 6, 250], [574.9481745001135, 1, 1, 0, 0, 2]],
  [[5, 5.5, 6, 250], [-49.33035714285714, .96425, 1, 1, 0, 5]],
  [[4, 5.5, 6, 250], [-79.66517857142858, .934202380952381, 1, 0, .25, 4]],
  [[3, 5.5, 6, 250], [-86.84345238095237, .9236428571428571, 1, 0, .5, 3]]
];
test('independent goldens cover depth, parallax, fades and differential overscroll', () => {
  for (const [input, expected] of goldens) {
    const actual = policy.resolveCard(...input);
    assert.deepEqual(Object.keys(actual).sort(), [...fields].sort());
    fields.forEach((field, i) => close(actual[field], expected[i]));
  }
});
test('title tent, shade and left fade have exact boundaries', () => {
  for (const [relative, title, shade, opacity] of [
    [-3, 0, .5, 0], [-2.75, 0, .5, .25], [-2, 0, .5, 1],
    [-.75, .25, .1875, 1], [-.25, .75, .0625, 1],
    [0, 1, 0, 1], [.75, 1, 0, 1], [1.25, .75, 0, 1], [2, 0, 0, 1]
  ]) {
    const m = policy.resolveCard(4, 4 - relative, 10, 250);
    [m.titleOpacity, m.shadeOpacity, m.opacity]
      .forEach((value, i) => close(value, [title, shade, opacity][i]));
  }
  // The title fades through opacity alone: the deck must not expose a blur channel at all.
  for (let relative = -3; relative <= 3; relative += 0.25) {
    const metrics = policy.resolveCard(4, 4 - relative, 10, 250);
    assert.deepEqual(Object.keys(metrics).sort(), [...fields].sort());
    assert.ok(metrics.titleOpacity >= 0 && metrics.titleOpacity <= 1);
  }
});
test('release projects the velocity and only discards it after an overscroll', () => {
  for (const [position, velocity, target, speed] of [
    [2, -600, 3, 4], [2, 600, 1, -4], [2.5, 0, 3, 0],
    [-.5, -1800, 3, 0], [5.5, 1800, 3, 0], [0, 600, 0, -4], [5, -600, 5, 4],
    [5.5, -1800, 5, 0], [-.5, 1800, 0, 0]
  ]) {
    const result = policy.release(position, velocity, 250, 6);
    assert.deepEqual(Object.keys(result).sort(), ['target', 'velocity']);
    assert.equal(result.target, target);
    close(result.velocity, speed);
  }
});
test('drag friction matches the reference at both edges, including a single card', () => {
  for (const [position, delta, expected] of [
    [2, -150, 2.7], [2, 150, 1.3], [0, 150, -.42], [0, -150, .7],
    [-2, 150, -2.21], [-2, -150, -1.3], [7, -150, 7.21], [7, 150, 6.3],
    [.1, 150, -.6], [5, 150, 4.3], [5, -150, 5.42]
  ]) close(policy.advanceDrag(position, delta, 250, 6), expected);
  close(policy.advanceDrag(0, -150, 250, 1), .42);
  close(policy.advanceDrag(0, 150, 250, 1), -.42);
});
test('spring independent golden with initial velocity and fixed stiffness 80', () => {
  // 50-digit decimal evaluation of the analytic critically damped solution, not a replica.
  const sample = policy.sampleSpring(0, 0, 3, .12);
  close(sample.position, .12307468943367433);
  close(sample.velocity, -.07519107558619749);
  assert.equal(sample.finished, false);
  close(policy.sampleSpring(1, 0, 0, .1).position, .7745208708001288);
  for (const [start, target] of [[0, 5], [5, 0], [-.5, 0], [5.5, 5]]) {
    let previous = Math.abs(start - target);
    for (let frame = 0; frame <= 240; frame++) {
      const sample = policy.sampleSpring(start, target, 0, frame / 60);
      const distance = Math.abs(sample.position - target);
      assert.ok(distance <= previous + 1e-12);
      assert.ok(sample.position >= Math.min(start, target) && sample.position <= Math.max(start, target));
      previous = distance;
    }
    const end = policy.sampleSpring(start, target, 0, 4);
    assert.equal(end.finished, true);
    assert.equal(end.position, target);
    assert.equal(end.velocity, 0);
  }
  assert.equal(policy.sampleSpring(1, 0, 0, -.1).position, 1);
  // The reference rest condition requires both displacement and velocity under the threshold.
  const crawling = policy.sampleSpring(.1, 0, 0, .92);
  assert.ok(Math.abs(crawling.position) < .0005 && Math.abs(crawling.velocity) >= .0005);
  assert.equal(crawling.finished, false);
});
test('cancel uses the softer StiffnessLow spring, not the release stiffness', () => {
  const cancelled = policy.sampleSpring(3, 2, 0, .12, 200);
  close(cancelled.position, 2.4941602779191264);
  close(cancelled.velocity, -4.39733007451937);
  close(policy.sampleSpring(3, 2, 0, .12).position, 2.70881196649359);
  assert.ok(cancelled.position < policy.sampleSpring(3, 2, 0, .12).position);
});
test('the visible window covers the viewport and never exceeds the deck', () => {
  for (const position of [-1, 0, 2.5, 5, 19, 25]) {
    const range = policy.resolveVisibleRange(position, 20, 390, 250);
    assert.ok(range.first >= 0 && range.first <= range.last && range.last <= 19);
    const clamped = Math.min(Math.max(position, 0), 19);
    assert.ok(range.first <= Math.floor(clamped) && range.last >= Math.ceil(clamped));
  }
  // A wider viewport can only widen the trailing window, never narrow it.
  let previous = 0;
  for (const viewport of [200, 390, 800, 1400]) {
    const last = policy.resolveVisibleRange(0, 60, viewport, 250).last;
    assert.ok(last >= previous);
    previous = last;
  }
});
test('the anchored card survives insertions, removals and its own deletion', () => {
  const previous = ['a', 'b', 'c', 'd'];
  assert.equal(policy.reconcilePosition(2, previous, previous), 2);
  assert.equal(policy.reconcilePosition(2, previous, ['z', 'a', 'b', 'c', 'd']), 3);
  assert.equal(policy.reconcilePosition(2, previous, ['a', 'c', 'd']), 1);
  assert.equal(policy.reconcilePosition(2, previous, ['a', 'b', 'd']), 2);
  assert.equal(policy.reconcilePosition(3, previous, ['a', 'b', 'c']), 2);
  close(policy.reconcilePosition(2.4, previous, ['a', 'c', 'd']), 1.4);
  assert.equal(policy.reconcilePosition(2, previous, []), 0);
});
test('empty counts, invalid indices and nonfinite inputs yield defined finite results', () => {
  // The reference never fades the trailing side; right-side cards leave the sheet by position.
  for (const count of [0, -1, NaN, Infinity, -Infinity]) {
    assert.equal(policy.clamp(4, count), 0);
    assert.equal(policy.resolveMaxIndex(count), 0);
    assert.equal(policy.advanceDrag(4, -150, 250, count), 0);
    const release = policy.release(4, -600, 250, count);
    assert.equal(release.target, 0);
    assert.equal(release.velocity, 0);
  }
  assert.equal(policy.resolveCard(0, 0, 0, 250).opacity, 0);
  assert.equal(policy.resolveCard(0, 0, 1, 250).opacity, 1);
  for (const bad of [NaN, Infinity, -Infinity]) {
    for (const value of Object.values(policy.resolveCard(bad, bad, bad, bad)))
      assert.ok(Number.isFinite(value));
    assert.equal(policy.resolveCard(bad, 2, 6, 250).opacity, 0);
    const spring = policy.sampleSpring(bad, bad, bad, bad);
    assert.equal(spring.finished, true);
    assert.equal(spring.position, 0);
    assert.equal(spring.velocity, 0);
  }
  // A non-positive or non-finite width must not divide the drag or the release.
  for (const width of [0, -1, NaN, Infinity]) {
    close(policy.advanceDrag(2, -150, width, 6), 2);
    const release = policy.release(2.2, -600, width, 6);
    assert.equal(release.target, 2);
    assert.equal(release.velocity, 0);
  }
});

test('motion owns one scalar position and rejects stale frames after a retarget', () => {
  const motionExports = load(
    'AiraBrowser/entry/src/main/ets/core/browser/tabsOverview/BrowserTabsOverviewStackMotion.ets',
    name => {
      assert.equal(name, './BrowserTabsOverviewStackLayoutPolicy');
      return exportsUnderTest;
    });
  const motion = new motionExports.BrowserTabsOverviewStackMotion();
  const frames = [];
  const schedule = callback => frames.push(callback);
  assert.equal(motion.seed(3, 6), 3);
  // A drag is delta-based, so the same cumulative offset applied twice must not double-count.
  motion.begin();
  motion.drag(40, 250, 6);
  close(motion.drag(80, 250, 6), motion.getPosition());
  let published = [];
  motion.release(0, 250, 6, schedule, position => published.push(position));
  assert.equal(published.length, 0);
  assert.equal(frames.length, 1);
  // Frames advance the displayed position monotonically towards the projected card.
  let previous = motion.getPosition();
  for (let i = 0; i < 400 && frames.length > 0; i++) {
    const frame = frames.shift();
    frame(i * 16000000);
    if (published.length > 0) {
      assert.ok(published[published.length - 1] >= previous - 1e-9);
      previous = published[published.length - 1];
    }
  }
  assert.equal(motion.getPosition(), Math.round(motion.getPosition()));
  // A retarget invalidates every in-flight frame from the previous animation.
  motion.release(0, 250, 6, schedule, () => {});
  const stale = frames.shift();
  motion.stop();
  const before = motion.getPosition();
  stale(999 * 16000000);
  assert.equal(motion.getPosition(), before);
});

test('an interruption settles the deck onto a card instead of freezing it', () => {
  const motionExports = load(
    'AiraBrowser/entry/src/main/ets/core/browser/tabsOverview/BrowserTabsOverviewStackMotion.ets',
    name => { assert.equal(name, './BrowserTabsOverviewStackLayoutPolicy'); return exportsUnderTest; });
  const motion = new motionExports.BrowserTabsOverviewStackMotion();
  const frames = [];
  const schedule = callback => frames.push(callback);
  motion.seed(2, 6);
  motion.begin();
  motion.drag(90, 250, 6);
  const fractional = motion.getPosition();
  assert.notEqual(fractional, Math.round(fractional));
  // A non-gesture interruption must finish the movement, not just stop it.
  motion.settleToNearest(6, schedule, () => {});
  let frame = 0;
  while (frames.length > 0 && frame < 600) frames.shift()(frame++ * 16000000);
  assert.equal(motion.getPosition(), Math.round(fractional));
  // Already on a card: the abort is a no-op rather than an endless frame chain.
  motion.seed(3, 6);
  const quiet = [];
  motion.settleToNearest(6, callback => quiet.push(callback), () => {});
  assert.equal(quiet.length, 0);
  assert.equal(motion.getPosition(), 3);
  // Cancelling a drag uses the cancel spring and still lands on a card.
  motion.begin();
  motion.drag(-60, 250, 6);
  const cancelFrames = [];
  motion.cancel(6, callback => cancelFrames.push(callback), () => {});
  let tick = 0;
  while (cancelFrames.length > 0 && tick < 600) cancelFrames.shift()(tick++ * 16000000);
  assert.equal(motion.getPosition(), Math.round(motion.getPosition()));
});

test('the overlay deck wires the policy, per-frame motion and the reference visuals', () => {
  const overlay = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/app/components/browser/BrowserTabsFloatingOverlay.ets'), 'utf8');
  // The horizontal branch is a Stack of translated cards, never a List.
  const horizontal = overlay.slice(overlay.indexOf('private buildHorizontalCardsLayer'),
    overlay.indexOf('private buildBlankGridItem'));
  assert.match(horizontal, /Stack\(\{ alignContent: Alignment\.Center \}\)/);
  assert.match(horizontal, /PanGesture\(\{ direction: PanDirection\.Horizontal/);
  assert.doesNotMatch(horizontal, /\bList\(/);
  // Selection and closing both stop the deck motion first.
  assert.match(overlay, /private selectOverviewTab\(tabId: string/);
  assert.match(overlay, /private stopDeckMotion\(\): void/);
  assert.match(overlay, /this\.deckMotion\.release\(/);
  assert.match(overlay, /postFrameCallback\(new BrowserTabsStackFrameCallback/);
  // The position is seeded once per entry, from the entry target when there is one, and seeding is
  // what latches it: a section switch reseeds through `seedDeckPosition`.
  const seedBody = overlay.slice(overlay.indexOf('private seedDeckPosition('),
    overlay.indexOf('private selectOverviewTab('));
  assert.match(seedBody, /this\.deckPositionSeeded = true/);
  // Anything that interrupts the gesture has to finish the movement.
  assert.match(overlay, /private abortDeckMotion\(\): void \{\s*this\.stopDeckMotion\(\);\s*this\.settleDeckToNearestCard\(\);/);
  assert.match(overlay, /this\.abortDeckMotion\(\);/);
  // The deck item key must not include the index, or every later card is rebuilt on a removal.
  assert.doesNotMatch(overlay, /resolveCardIdentityKey\(item\)\}\|\$\{item\.index\}/);
  // The per-frame scalar must not re-run presentation construction.
  assert.match(overlay, /if \(this\.isHorizontalCardsLayout\(\)\) \{\s*return this\.deckItems\.length <= 0;/);
  // Shade and cover are the reference's dark overlay and card-filling screenshot.
  assert.match(overlay, /deckShadeOpacity: this\.isHorizontalCardsLayout\(\)/);
  assert.match(overlay, /snapshotCoverEnabled: this\.isHorizontalCardsLayout\(\)/);
  const card = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/app/components/browser/BrowserTabOverviewCard.ets'), 'utf8');
  assert.match(card, /ImageFit\.Cover/);
  assert.match(card, /private buildDeckShadeOverlay\(\)/);
  // The title transition rides on opacity alone. Upstream's per-frame label blur is not ported, so
  // no deck path may reintroduce a title blur radius.
  const item = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/app/components/browser/BrowserTabOverviewItem.ets'), 'utf8');
  const policySource = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/core/browser/tabsOverview/BrowserTabsOverviewStackLayoutPolicy.ets'), 'utf8');
  assert.doesNotMatch(item, /identityBlurRadius|\.blur\(this\.identity/);
  assert.doesNotMatch(overlay, /identityBlurRadius|titleBlurRadius/);
  // The metrics contract carries no blur field; the header comment may still name upstream's term.
  assert.doesNotMatch(policySource, /titleBlurRadius\s*[,:=]/);
  // Card slots are doubled so the entering morph can hold a slot of its own strictly between the
  // covered card and its successor, instead of becoming one more layer above the whole deck. The
  // holder is inside the deck's own Stack, so its `zIndex` competes with the cards' and not with the
  // cards layer as a whole.
  assert.match(horizontal, /this\.buildDeckEntryMorphSlot\(\)/);
  assert.match(horizontal, /\.zIndex\(item\.index \* 2\)/);
  assert.match(horizontal, /\.zIndex\(this\.resolveDeckEntryMorphLayerZIndex\(\)\)/);
  // Clip stays on for the deck's lifetime. Toggling it at the morph handover re-rasterises every
  // card in the same frame the current card is revealed.
  assert.match(horizontal, /\.clip\(true\)/);
  assert.match(horizontal, /Stack\(\) \{\s*if \(this\.shouldMountSharedSnapshotInDeck\(\)\) \{\s*this\.buildSharedSnapshotOverlay\(true\)/);
  assert.match(overlay, /private shouldMountSharedSnapshotInDeck\(\): boolean \{\s*return this\.entrySharedSnapshotMounted &&\s*this\.entrySharedSnapshotState\.direction === 'enter' &&/);
  assert.match(overlay, /return slot < 0 \? 0 : slot \* 2 \+ 1;/);
  assert.match(overlay, /if \(this\.entrySharedSnapshotMounted && !this\.shouldMountSharedSnapshotInDeck\(\)\) \{\s*this\.buildSharedSnapshotOverlay\(\)/);
  // In-deck morph must not reuse the overlay-root 20/25 z-index; the slot wrapper owns stacking.
  assert.match(overlay, /snapshotLayerZIndex: inDeck \? 0 : FLOATING_TABS_SHARED_SNAPSHOT_Z_INDEX/);
  assert.match(overlay, /this\.buildSharedSnapshotOverlay\(true\)/);
  // Waiting snaps to the origin (duration 0). Settling uses the 350ms implicit fly-in. A duration of
  // 0 for the whole displacement made ArkUI snap the derived translate to rest with no motion.
  assert.match(overlay, /if \(!this\.entryDisplacementSettlingEnabled\) \{\s*return 0;/);
  assert.match(overlay, /return this\.animationViewModel\.getSharedSnapshotEnterDurationMs\(\);/);
  // SettlingEnabled dropping must not yank an in-flight displacement back to the origin.
  assert.match(overlay, /if \(this\.entryDisplacementProgress > 0 && this\.entryDisplacementProgress < 1\) \{\s*return;/);
  // In-deck morph already covers the current card; hiding that preview leaves a hole at unmount.
  assert.match(overlay, /coveredByMorph: this\.shouldHideCardSurfaceUnderMorph\(item\.tab\.id\)/);
  assert.match(overlay, /if \(this\.shouldMountSharedSnapshotInDeck\(\)\) \{\s*return false;/);
  const coordinator = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/core/browser/BrowserTabsOverviewSessionCoordinator.ets'), 'utf8');
  // Morph unmount and the covered-card reveal land in one presentation publish.
  assert.match(coordinator, /sharedSnapshotState: buildBrowserTabsSharedSnapshotIdleState\(\),\s*sceneState: this\.sceneDriver\.buildSettledState/);
  assert.match(coordinator, /shouldDeferEntryAnimationSettle\(this\.presentationState\.sceneState\)/);
  // The grid path keeps its own scroller and must not be switched to the deck.
  const grid = overlay.slice(overlay.indexOf('private buildGridCardsLayer'),
    overlay.indexOf('private buildHorizontalCardsLayer'));
  assert.match(grid, /Grid\(this\.scroller\)/);
  assert.doesNotMatch(grid, /resolveDeckMetrics/);
});
