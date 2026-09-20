import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserTabsOverviewStackLayoutPolicy,
  SPRING_CANCEL_STIFFNESS
} from '../main/ets/core/browser/tabsOverview/BrowserTabsOverviewStackLayoutPolicy';

const EPSILON: number = 1e-9;

function close(actual: number, expected: number, tolerance: number = EPSILON): void {
  expect(Math.abs(actual - expected) <= tolerance).assertTrue();
}

/**
 * Golden values in this file are evaluated independently of this policy — by transliterating
 * `AppSwitcherOverlay.kt` (SoxiaLiSA/StackSwipe, MIT, commit 8298945) for the offsets, fades, shades
 * and z-order, and from the documented depth formula for the scale, which Aira deliberately changed —
 * so a formula change cannot silently re-baseline them.
 *
 * That depth formula: the focused card is the standard size, so is every card in front of it, and
 * every card *behind* it is `0.96x` smaller per level, floored at the third level.
 */
export default function browserTabsOverviewStackLayoutPolicyTest(): void {
  describe('BrowserTabsOverviewStackLayoutPolicy', () => {
    const policy = new BrowserTabsOverviewStackLayoutPolicy();

    it('places every focused and trailing card at the reference offset and scale', 0, () => {
      // index, scroll position, count, card width -> offsetX, scale, opacity, title, shade, z
      const goldens: number[][] = [
        [2, 2, 6, 250, 0, 1, 1, 1, 0, 2],
        [1, 2, 6, 250, -55, 0.96, 1, 0, 0.25, 1],
        [0, 2, 6, 250, -70.39999999999999, 0.9216, 1, 0, 0.5, 0],
        [3, 2, 6, 250, 212.5, 1, 1, 1, 0, 3],
        [0, 2.5, 6, 250, -73.21986676296929, 0.9029798987795907, 0.5, 0, 0.5, 0],
        [2, 2.5, 6, 250, -35.96768830317987, 0.9797958971132712, 1, 0.5, 0.125, 2],
        [3, 2.5, 6, 250, 92.4959973502132, 1, 1, 1, 0, 3],
        [4, 2.5, 6, 250, 345.67537706926646, 1, 1, 0.5, 0, 4],
        [5, 2.5, 6, 250, 638.0973555526352, 1, 1, 0, 0, 5]
      ];
      for (const golden of goldens) {
        const metrics = policy.resolveCard(golden[0], golden[1], golden[2], golden[3]);
        close(metrics.offsetX, golden[4]);
        close(metrics.scale, golden[5]);
        close(metrics.opacity, golden[6]);
        close(metrics.titleOpacity, golden[7]);
        close(metrics.shadeOpacity, golden[8]);
        close(metrics.zIndex, golden[9]);
      }
    });

    /**
     * The deck's depth cue: the focused card is the standard size, so is every card in front of it,
     * and every card behind it steps down one level. What sits in front therefore never shrinks as the
     * deck is swiped, and a card grows into the standard size as it is swiped into the centre. The
     * reference ramped the trailing side *past* the focus instead (`0.98 -> 1.0`), so the biggest card
     * sat right of the focus and every card grew as it left the centre: the opposite of a stack.
     */
    it('keeps the focus and the cards in front at the standard size and steps down behind it', 0, () => {
      for (const relative of [0, 0.5, 1, 1.5, 2, 3, 4]) {
        close(policy.resolveCard(3 + relative, 3, 10, 250).scale, 1);
      }
      close(policy.resolveCard(2, 3, 10, 250).scale, 0.96);
      close(policy.resolveCard(1, 3, 10, 250).scale, 0.9216);
      close(policy.resolveCard(0, 3, 10, 250).scale, 0.8847359999999999);
      // Half-card steps while a card is being swiped into the centre, still monotonic.
      close(policy.resolveCard(2.5, 3, 10, 250).scale, 0.9797958971132712);
      let previous = 1;
      for (let distance = 1; distance <= 6; distance += 0.5) {
        const scale = policy.resolveCard(3 - distance, 3, 10, 250).scale;
        expect(scale <= previous).assertTrue();
        previous = scale;
      }
      close(previous, 0.8847359999999999);
    });

    it('keeps the left stack on its geometric peek series', 0, () => {
      // The leading strip converges: each card exposes 0.28 of the previous one, so the offsets run
      // as `width * 0.22 * (1 - 0.28^(d-1))` with d counting cards left of focus.
      close(policy.resolveCard(4, 5, 6, 250).offsetX, -55);
      close(policy.resolveCard(3, 5, 6, 250).offsetX, -70.39999999999999);
      close(policy.resolveCard(2, 5, 6, 250).offsetX, -74.712);
      close(policy.resolveCard(1, 5, 6, 250).offsetX, -75.91936);
      close(policy.resolveCard(0, 5, 6, 250).offsetX, -76.2574208);
      close(policy.resolveCard(4, 5, 6, 250).scale, 0.96);
      close(policy.resolveCard(3, 5, 6, 250).scale, 0.9216);
      close(policy.resolveCard(2, 5, 6, 250).scale, 0.8847359999999999);
      // The series converges to `-width * 0.22 / 0.72`, and the depth scale to its third-level floor.
      const far = policy.resolveCard(0, 25, 30, 250);
      close(far.offsetX, -76.38888888888889, 1e-6);
      close(far.scale, 0.8847359999999999, 1e-9);
    });

    it('moves trailing cards with parallax and keeps z-order fixed by index', 0, () => {
      // relPos^1.2 * width * 0.85, not a linear stride.
      close(policy.resolveCard(3, 2, 6, 250).offsetX, 212.5);
      close(policy.resolveCard(4, 2, 6, 250).offsetX, 488.19680087373985);
      close(policy.resolveCard(5, 2, 6, 250).offsetX, 794.1534740048922);
      for (let index = 0; index < 6; index++) {
        for (let position = -0.75; position <= 5.75; position += 0.25) {
          close(policy.resolveCard(index, position, 6, 250).zIndex, index);
        }
      }
    });

    it('fades and shades only the cards left of the focused one', 0, () => {
      // Reference: fully visible at relPos >= -2, gone at relPos = -3.
      close(policy.resolveCard(4, 5, 10, 250).opacity, 1);
      close(policy.resolveCard(3, 5, 10, 250).opacity, 1);
      close(policy.resolveCard(2, 4.5, 10, 250).opacity, 0.5);
      close(policy.resolveCard(2, 5, 10, 250).opacity, 0);
      close(policy.resolveCard(1, 5, 10, 250).opacity, 0);
      close(policy.resolveCard(0, 6, 10, 250).opacity, 0);
      // Shade grows 0.25 per card and caps at 0.5.
      close(policy.resolveCard(4, 5, 10, 250).shadeOpacity, 0.25);
      close(policy.resolveCard(3, 5, 10, 250).shadeOpacity, 0.5);
      close(policy.resolveCard(0, 5, 10, 250).shadeOpacity, 0.5);
      close(policy.resolveCard(5, 5, 10, 250).shadeOpacity, 0);
    });

    it('runs the title tent between one card either side of focus', 0, () => {
      // titleAlpha = clamp(min(1 + relPos, 2 - relPos), 0, 1). The deck fades the title through
      // this channel only; upstream's per-frame label blur is deliberately dropped.
      const rows: number[][] = [
        [-3, 0], [-2.75, 0], [-2, 0], [-1.5, 0],
        [-1, 0], [-0.75, 0.25], [-0.5, 0.5], [-0.25, 0.75],
        [0, 1], [0.5, 1], [1, 1], [1.25, 0.75], [2, 0], [3, 0]
      ];
      for (const row of rows) {
        const metrics = policy.resolveCard(5, 5 - row[0], 12, 250);
        close(metrics.titleOpacity, row[1]);
      }
    });

    it('stretches both edges differently, so cards fan out instead of shifting together', 0, () => {
      const leftEdge: number[][] = [
        [0, -0.5, 250, 54.64285714285714, 1],
        [1, -0.5, 250, 293.2310267857143, 1],
        [2, -0.5, 250, 574.9481745001135, 1]
      ];
      for (const golden of leftEdge) {
        close(policy.resolveCard(golden[0], golden[1], 6, golden[2]).offsetX, golden[3]);
        close(policy.resolveCard(golden[0], golden[1], 6, golden[2]).scale, golden[4]);
      }
      const rightEdge: number[][] = [
        [5, 5.5, 250, -49.33035714285714, 0.9839285714285715],
        [4, 5.5, 250, -79.66517857142857, 0.9245714285714286],
        [3, 5.5, 250, -86.84345238095237, 0.8821028571428572]
      ];
      for (const golden of rightEdge) {
        close(policy.resolveCard(golden[0], golden[1], 6, golden[2]).offsetX, golden[3]);
        close(policy.resolveCard(golden[0], golden[1], 6, golden[2]).scale, golden[4]);
      }
      // Left overscroll keeps every card at its resting scale (the sink only applies past the right).
      close(policy.resolveCard(0, -0.5, 6, 250).scale, 1);
    });

    it('applies 70 percent base friction and progressive edge resistance while dragging', 0, () => {
      const goldens: number[][] = [
        [2, -150, 250, 6, 2.7],
        [2, 150, 250, 6, 1.3],
        [0, 150, 250, 6, -0.42],
        [0, -150, 250, 6, 0.7],
        [-2, 150, 250, 6, -2.21],
        [-2, -150, 250, 6, -1.3],
        [7, -150, 250, 6, 7.21],
        [7, 150, 250, 6, 6.3],
        [0.1, 150, 250, 6, -0.6],
        [5, 150, 250, 6, 4.3],
        [5, -150, 250, 6, 5.42],
        // A single card still rubber-bands, then springs back.
        [0, -150, 250, 1, 0.42],
        [0, 150, 250, 1, -0.42]
      ];
      for (const golden of goldens) {
        close(policy.advanceDrag(golden[0], golden[1], golden[2], golden[3]), golden[4]);
      }
    });

    it('projects the release from velocity and drops it after an overscroll', 0, () => {
      const goldens: number[][] = [
        [2, -600, 250, 6, 3, 4],
        [2, 600, 250, 6, 1, -4],
        [2.5, 0, 250, 6, 3, 0],
        // An overscrolled release drops the initial velocity but keeps the projected card.
        [-0.5, -1800, 250, 6, 3, 0],
        [5.5, 1800, 250, 6, 3, 0],
        // A slow release short of the midpoint stays on the current card.
        [2.9, -30, 250, 6, 3, 0.2],
        [2.1, 30, 250, 6, 2, -0.2],
        // Velocity pointing away from the reachable end is still applied to the projection.
        [0, 600, 250, 6, 0, -4],
        [5, -600, 250, 6, 5, 4],
        [2.2, -600, 250, 6, 3, 4],
        // Past the right edge, a leftward fling still selects the projected card.
        [5.5, -1800, 250, 6, 5, 0],
        // Past the left edge, a rightward fling still selects the projected card.
        [-0.5, 1800, 250, 6, 0, 0],
        [0.42, -600, 250, 1, 0, 0]
      ];
      for (const golden of goldens) {
        const release = policy.release(golden[0], golden[1], golden[2], golden[3]);
        expect(release.target === golden[4]).assertTrue();
        close(release.velocity, golden[5]);
      }
    });

    it('settles with the reference critically damped spring at stiffness 80', 0, () => {
      // Independently evaluated from x'' + 2w x' + w^2 x = 0 with w = sqrt(80).
      const golden = policy.sampleSpring(0, 0, 3, 0.12);
      close(golden.position, 0.12307468943367433);
      close(golden.velocity, -0.07519107558619749);
      expect(golden.finished).assertFalse();
      const second = policy.sampleSpring(1, 0, 0, 0.1);
      close(second.position, 0.7745208708001288);
      close(second.velocity, -3.2707337583824327);
      // No overshoot: the deck comes to rest, it does not bounce past the target.
      let previous = Number.POSITIVE_INFINITY;
      for (let frame = 0; frame <= 240; frame++) {
        const sample = policy.sampleSpring(0, 4, 0, frame / 60);
        const distance = Math.abs(sample.position - 4);
        expect(distance <= previous + 1e-12).assertTrue();
        expect(sample.position >= 0 && sample.position <= 4).assertTrue();
        previous = distance;
      }
      const end = policy.sampleSpring(0, 4, 0, 4);
      expect(end.finished).assertTrue();
      close(end.position, 4);
      close(end.velocity, 0);
      // Reference rest condition: both the displacement and the velocity must fall under
      // `visibilityThreshold`. A value-only check would stop the deck while it is still moving.
      expect(policy.sampleSpring(0.00049, 0, 0, 0).finished).assertTrue();
      expect(policy.sampleSpring(0.0005, 0, 0, 0).finished).assertFalse();
      const crawling = policy.sampleSpring(0.1, 0, 0, 0.92);
      expect(Math.abs(crawling.position) < 0.0005).assertTrue();
      expect(Math.abs(crawling.velocity) >= 0.0005).assertTrue();
      expect(crawling.finished).assertFalse();
    });

    it('uses the softer cancel stiffness for a cancelled gesture', 0, () => {
      // Reference `onDragCancel` uses `Spring.StiffnessLow` (200) instead of the release's 80, so a
      // cancelled drag springs back noticeably faster.
      const cancelled = policy.sampleSpring(3, 2, 0, 0.12, SPRING_CANCEL_STIFFNESS);
      close(cancelled.position, 2.4941602779191264);
      close(cancelled.velocity, -4.39733007451937);
      // The stiffer cancel spring has travelled further towards the target at the same instant.
      const released = policy.sampleSpring(3, 2, 0, 0.12);
      expect(cancelled.position < released.position).assertTrue();
      close(released.position, 2.70881196649359);
      // Non-positive or non-finite stiffness must not produce NaN.
      for (const stiffness of [0, -1, Number.NaN, Number.POSITIVE_INFINITY]) {
        const sample = policy.sampleSpring(1, 0, 0, 0.1, stiffness);
        expect(Number.isFinite(sample.position)).assertTrue();
        expect(Number.isFinite(sample.velocity)).assertTrue();
      }
    });

    it('resumes from a sampled position and velocity after an interruption', 0, () => {
      const first = policy.sampleSpring(0, 4, 3, 0.12);
      const resumed = policy.sampleSpring(first.position, 4, first.velocity, 0.08);
      const whole = policy.sampleSpring(0, 4, 3, 0.2);
      close(resumed.position, whole.position, 1e-9);
      close(resumed.velocity, whole.velocity, 1e-9);
      // A retarget at zero elapsed time keeps the current state.
      const retarget = policy.sampleSpring(first.position, 2, first.velocity, 0);
      close(retarget.position, first.position);
      close(retarget.velocity, first.velocity);
      // Interrupting with a drag continues from the displayed position, not from a stale endpoint.
      const dragged = policy.advanceDrag(first.position, -15, 250, 6);
      close(dragged, first.position + 0.07);
      const settled = policy.sampleSpring(dragged, 3, 0, 0.1);
      expect(Number.isFinite(settled.position)).assertTrue();
      expect(settled.finished).assertFalse();
    });

    it('handles empty single and non-finite inputs without propagating NaN', 0, () => {
      close(policy.resolveCard(0, 0, 0, 250).opacity, 0);
      close(policy.release(0, -600, 250, 0).target, 0);
      close(policy.advanceDrag(5, -150, 250, 0), 0);
      close(policy.clamp(4, 0), 0);
      close(policy.resolveMaxIndex(0), 0);
      const invalids: number[] = [Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY];
      for (const bad of invalids) {
        close(policy.clamp(bad, 6), 0);
        close(policy.resolveMaxIndex(bad), 0);
        const card = policy.resolveCard(bad, bad, bad, bad);
        close(card.offsetX, 0);
        close(card.opacity, 0);
        close(card.zIndex, 0);
        const release = policy.release(bad, bad, bad, bad);
        close(release.target, 0);
        close(release.velocity, 0);
        const spring = policy.sampleSpring(bad, bad, bad, bad);
        expect(spring.finished).assertTrue();
        close(spring.position, 0);
        close(spring.velocity, 0);
      }
      // A zero or non-finite width must not divide the drag or the release.
      const widths: number[] = [0, -1, Number.NaN, Number.POSITIVE_INFINITY];
      for (const width of widths) {
        close(policy.advanceDrag(2, -150, width, 6), 2);
        const release = policy.release(2.2, -600, width, 6);
        close(release.target, 2);
        close(release.velocity, 0);
      }
      // A non-finite index has no identity, so it is reported as invisible.
      close(policy.resolveCard(Number.NaN, 2, 6, 250).scale, 0);
    });

    it('builds only the cards that can still be seen, including the trailing parallax', 0, () => {
      // Left: the reference culls at relPos <= -3, so three faded cards stay alive.
      const wide = policy.resolveVisibleRange(5, 20, 390, 250);
      expect(wide.first === 2).assertTrue();
      // Right: inverted `relPos^1.2 * width * 0.85 <= viewport / 2 + width`, so a narrow viewport
      // needs fewer trailing cards than a wide one.
      const narrow = policy.resolveVisibleRange(5, 20, 200, 250);
      const broad = policy.resolveVisibleRange(5, 20, 1400, 250);
      expect(narrow.last <= broad.last).assertTrue();
      expect(narrow.last >= 6).assertTrue();
      // The window is clamped to the deck, and a single card always renders.
      const edge = policy.resolveVisibleRange(19, 20, 390, 250);
      expect(edge.last === 19).assertTrue();
      expect(policy.resolveVisibleRange(0, 1, 390, 250).last === 0).assertTrue();
      expect(policy.resolveVisibleRange(0, 0, 390, 250).first === 0).assertTrue();
      const bad = policy.resolveVisibleRange(Number.NaN, Number.NaN, Number.NaN, Number.NaN);
      expect(bad.first === 0).assertTrue();
      expect(bad.last === 0).assertTrue();
    });

    it('keeps the anchored card focused when the tab list changes', 0, () => {
      const previous: string[] = ['a', 'b', 'c', 'd'];
      close(policy.reconcilePosition(2, previous, ['a', 'b', 'c', 'd']), 2);
      // An insertion before the anchor shifts the anchor down by one.
      close(policy.reconcilePosition(2, previous, ['z', 'a', 'b', 'c', 'd']), 3);
      // A removal before the anchor shifts the anchor up by one.
      close(policy.reconcilePosition(2, previous, ['a', 'c', 'd']), 1);
      // Closing the anchored tab hands the slot to its successor.
      close(policy.reconcilePosition(2, previous, ['a', 'b', 'd']), 2);
      // Closing the last card falls back to the new last card.
      close(policy.reconcilePosition(3, previous, ['a', 'b', 'c']), 2);
      // The fractional part of an in-flight drag is preserved.
      close(policy.reconcilePosition(2.4, previous, ['a', 'c', 'd']), 1.4);
      close(policy.reconcilePosition(2.4, previous, ['z', 'a', 'b', 'c', 'd']), 3.4);
      close(policy.reconcilePosition(2, previous, []), 0);
    });
  });
}
