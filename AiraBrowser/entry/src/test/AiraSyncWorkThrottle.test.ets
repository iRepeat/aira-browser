import { describe, expect, it } from '@ohos/hypium';
import {
  AiraSyncWorkThrottleClock,
  AiraSyncWorkThrottleService
} from '../main/ets/services/sync/AiraSyncWorkThrottleService';

class RecordingThrottleClock implements AiraSyncWorkThrottleClock {
  private currentMs: number = 1000;
  sleepDelaysMs: number[] = [];
  longestWorkMs: number = 0;
  private workMs: number = 0;

  now(): number {
    return this.currentMs;
  }

  advance(ms: number): void {
    this.currentMs += ms;
    this.workMs += ms;
    this.longestWorkMs = Math.max(this.longestWorkMs, this.workMs);
  }

  sleep(delayMs: number): Promise<void> {
    this.sleepDelaysMs.push(delayMs);
    this.currentMs += Math.max(0, delayMs);
    this.workMs = 0;
    return Promise.resolve();
  }
}

export default function airaSyncWorkThrottleTest(): void {
  describe('Sync work throttle yielding', () => {
    it('yields inside a small batch once the elapsed-time budget passes', 0, async () => {
      const clock = new RecordingThrottleClock();
      const throttle = new AiraSyncWorkThrottleService(clock, { batchSize: 250, yieldBudgetMs: 24 });

      // Seven changes, the shape a single history deletion produces. A 250-item threshold never
      // fires for this, so before the budget existed the whole batch ran with no yield at all.
      for (let index = 1; index <= 7; index++) {
        clock.advance(10);
        await throttle.afterBatchItem(index);
      }

      expect(clock.sleepDelaysMs.length > 0).assertTrue();
    });

    it('does not yield while a small batch stays inside the budget', 0, async () => {
      const clock = new RecordingThrottleClock();
      const throttle = new AiraSyncWorkThrottleService(clock, { batchSize: 250, yieldBudgetMs: 24 });

      for (let index = 1; index <= 7; index++) {
        clock.advance(1);
        await throttle.afterBatchItem(index);
      }

      expect(clock.sleepDelaysMs.length).assertEqual(0);
    });

    it('keeps the count threshold as a ceiling for fast loops', 0, async () => {
      const clock = new RecordingThrottleClock();
      const throttle = new AiraSyncWorkThrottleService(clock, { batchSize: 250, yieldBudgetMs: 24 });

      // No time passes at all, so only the count path can yield here.
      for (let index = 1; index <= 250; index++) {
        await throttle.afterBatchItem(index);
      }

      expect(clock.sleepDelaysMs.length).assertEqual(1);
    });

    it('restarts the budget window at a stage boundary', 0, async () => {
      const clock = new RecordingThrottleClock();
      const throttle = new AiraSyncWorkThrottleService(clock, { batchSize: 250, yieldBudgetMs: 24 });

      await throttle.afterBatchItem(1);
      clock.advance(1000);
      await throttle.afterStage();
      const sleepsAfterStage = clock.sleepDelaysMs.length;

      // The stage boundary already yielded and restarted the window, so the next single item must
      // not yield again immediately.
      await throttle.afterBatchItem(2);

      expect(clock.sleepDelaysMs.length).assertEqual(sleepsAfterStage);
    });

    it('treats a zero budget as yield-on-every-item', 0, async () => {
      const clock = new RecordingThrottleClock();
      const throttle = new AiraSyncWorkThrottleService(clock, { batchSize: 250, yieldBudgetMs: 0 });

      await throttle.afterBatchItem(1);
      await throttle.afterBatchItem(2);

      expect(clock.sleepDelaysMs.length).assertEqual(2);
    });

    it('keeps default uninterrupted work below one frame without a full-frame sleep per slice', 0, async () => {
      const clock = new RecordingThrottleClock();
      const throttle = new AiraSyncWorkThrottleService(clock, { batchSize: 250 });

      for (let index = 1; index <= 250; index++) {
        clock.advance(1);
        await throttle.afterBatchItem(index);
      }

      expect(clock.longestWorkMs <= 16).assertTrue();
      expect(clock.sleepDelaysMs.length > 1).assertTrue();
      expect(clock.sleepDelaysMs.every((delay: number): boolean => delay === 0)).assertTrue();
    });
  });
}
