import { describe, expect, it } from '@ohos/hypium';
import {
  BROWSER_TABS_OVERVIEW_SWIPE_DISMISS_MAX_THRESHOLD_VP,
  BROWSER_TABS_OVERVIEW_SWIPE_DISMISS_MIN_THRESHOLD_VP,
  BROWSER_TABS_OVERVIEW_SWIPE_FLYOUT_MAX_DURATION_MS,
  BROWSER_TABS_OVERVIEW_SWIPE_FLYOUT_MIN_DURATION_MS,
  BrowserTabsOverviewSwipeDismissPolicy
} from '../main/ets/core/browser/tabsOverview/BrowserTabsOverviewSwipeDismissPolicy';

export default function browserTabsOverviewSwipeDismissPolicyTest(): void {
  describe('BrowserTabsOverviewSwipeDismissPolicy', () => {
    it('dismisses at half the card extent', 0, () => {
      const policy = new BrowserTabsOverviewSwipeDismissPolicy();

      // 2-column phone card measured at ~196vp: half is 98, inside the clamp band.
      expect(policy.resolveThresholdVp(196)).assertEqual(98);
    });

    /**
     * The reported case: a 336vp host gives ~144vp two-column cards, where a fixed 96vp threshold
     * was exactly two thirds of the card.
     */
    it('lowers the old two-thirds phone threshold to roughly half', 0, () => {
      const policy = new BrowserTabsOverviewSwipeDismissPolicy();

      const threshold = policy.resolveThresholdVp(144);
      expect(threshold).assertEqual(72);
      expect(threshold < 96).assertTrue();
    });

    it('clamps a wide desktop card so half of it is not a chore', 0, () => {
      const policy = new BrowserTabsOverviewSwipeDismissPolicy();

      // A 3-column 1600vp window gives ~512vp cards; half would be 256vp.
      expect(policy.resolveThresholdVp(512)).assertEqual(BROWSER_TABS_OVERVIEW_SWIPE_DISMISS_MAX_THRESHOLD_VP);
    });

    it('clamps the shortest cards so a nudge cannot dismiss them', 0, () => {
      const policy = new BrowserTabsOverviewSwipeDismissPolicy();

      expect(policy.resolveThresholdVp(120)).assertEqual(BROWSER_TABS_OVERVIEW_SWIPE_DISMISS_MIN_THRESHOLD_VP);
    });

    it('never returns a non-positive or non-finite threshold', 0, () => {
      const policy = new BrowserTabsOverviewSwipeDismissPolicy();

      expect(policy.resolveThresholdVp(0) >= BROWSER_TABS_OVERVIEW_SWIPE_DISMISS_MIN_THRESHOLD_VP).assertTrue();
      expect(policy.resolveThresholdVp(Number.NaN) >= BROWSER_TABS_OVERVIEW_SWIPE_DISMISS_MIN_THRESHOLD_VP)
        .assertTrue();
    });

    it('commits a horizontal drag that crossed the threshold', 0, () => {
      const policy = new BrowserTabsOverviewSwipeDismissPolicy();

      expect(policy.shouldDismissOnRelease({
        mode: 'horizontal', offsetVp: -98, velocityVpPerSecond: 0, thresholdVp: 98
      })).assertTrue();
      expect(policy.shouldDismissOnRelease({
        mode: 'horizontal', offsetVp: 98, velocityVpPerSecond: 0, thresholdVp: 98
      })).assertTrue();
    });

    it('snaps back a short slow horizontal drag', 0, () => {
      const policy = new BrowserTabsOverviewSwipeDismissPolicy();

      expect(policy.shouldDismissOnRelease({
        mode: 'horizontal', offsetVp: 40, velocityVpPerSecond: 200, thresholdVp: 98
      })).assertFalse();
    });

    it('commits a short fast horizontal fling in the drag direction', 0, () => {
      const policy = new BrowserTabsOverviewSwipeDismissPolicy();

      expect(policy.shouldDismissOnRelease({
        mode: 'horizontal', offsetVp: -40, velocityVpPerSecond: -900, thresholdVp: 98
      })).assertTrue();
    });

    it('does not commit a fling that reverses against the travel', 0, () => {
      const policy = new BrowserTabsOverviewSwipeDismissPolicy();

      expect(policy.shouldDismissOnRelease({
        mode: 'horizontal', offsetVp: -40, velocityVpPerSecond: 900, thresholdVp: 98
      })).assertFalse();
    });

    it('does not commit a twitch that never travelled far enough to be a fling', 0, () => {
      const policy = new BrowserTabsOverviewSwipeDismissPolicy();

      expect(policy.shouldDismissOnRelease({
        mode: 'horizontal', offsetVp: -8, velocityVpPerSecond: 1400, thresholdVp: 98
      })).assertFalse();
    });

    it('treats upward travel as dismissing and ignores upward flings', 0, () => {
      const policy = new BrowserTabsOverviewSwipeDismissPolicy();

      expect(policy.shouldDismissOnRelease({
        mode: 'upward', offsetVp: -130, velocityVpPerSecond: 0, thresholdVp: 130
      })).assertTrue();
      expect(policy.shouldDismissOnRelease({
        mode: 'upward', offsetVp: 130, velocityVpPerSecond: 0, thresholdVp: 130
      })).assertFalse();
      expect(policy.shouldDismissOnRelease({
        mode: 'upward', offsetVp: -70, velocityVpPerSecond: -900, thresholdVp: 130
      })).assertTrue();
    });

    it('survives non-finite gesture values', 0, () => {
      const policy = new BrowserTabsOverviewSwipeDismissPolicy();

      expect(policy.shouldDismissOnRelease({
        mode: 'horizontal',
        offsetVp: Number.NaN,
        velocityVpPerSecond: Number.NaN,
        thresholdVp: Number.NaN
      })).assertFalse();
    });

    /**
     * The card leaves at the speed the finger had: the flight is the distance left divided by that
     * speed, so a flick is gone at once and a slow release drifts out.
     */
    it('gives a dismissed card the release speed, bounded at both ends', 0, () => {
      const policy = new BrowserTabsOverviewSwipeDismissPolicy();

      expect(policy.resolveFlyoutDurationMs(800, 4000)).assertEqual(200);
      expect(policy.resolveFlyoutDurationMs(800, 2000)).assertEqual(400);
      expect(policy.resolveFlyoutDurationMs(800, 1000))
        .assertEqual(BROWSER_TABS_OVERVIEW_SWIPE_FLYOUT_MAX_DURATION_MS);
      expect(policy.resolveFlyoutDurationMs(800, 20000))
        .assertEqual(BROWSER_TABS_OVERVIEW_SWIPE_FLYOUT_MIN_DURATION_MS);
      expect(policy.resolveFlyoutDurationMs(800, 0))
        .assertEqual(BROWSER_TABS_OVERVIEW_SWIPE_FLYOUT_MAX_DURATION_MS);
    });

    it('rejects non-finite fly-out input and ignores the release direction', 0, () => {
      const policy = new BrowserTabsOverviewSwipeDismissPolicy();

      expect(policy.resolveFlyoutDurationMs(Number.NaN, Number.NaN))
        .assertEqual(BROWSER_TABS_OVERVIEW_SWIPE_FLYOUT_MIN_DURATION_MS);
      expect(policy.resolveFlyoutDurationMs(800, -4000)).assertEqual(200);
    });
  });
}
