import { sharedBrowsingActivitySignal } from '../../common/activity/BrowsingActivitySignal';

export interface AiraSyncWorkThrottleClock {
  sleep(delayMs: number): Promise<void>;
  // Optional so existing clocks keep working: the elapsed-time yield budget is the only consumer,
  // and it falls back to Date.now() when a clock does not supply a time source.
  now?(): number;
}

export interface AiraSyncCooperativeThrottle {
  afterBatchItem(processedCount: number): Promise<void>;
  afterStage(): Promise<void>;
}

export interface AiraSyncWorkThrottleOptions {
  batchSize: number;
  batchPauseMs: number;
  stagePauseMs: number;
  yieldBudgetMs?: number;
}

const DEFAULT_BATCH_SIZE: number = 250;
export const AIRA_SYNC_UI_YIELD_MS: number = 16;
const DEFAULT_BATCH_PAUSE_MS: number = AIRA_SYNC_UI_YIELD_MS;
const DEFAULT_STAGE_PAUSE_MS: number = AIRA_SYNC_UI_YIELD_MS;
// Uninterrupted-work budget before yielding. A change count cannot bound the stall by itself: the
// small batches that ordinary use produces (deleting one history record is 5-7 changes) never reach
// a 250-item threshold, so those bursts used to run to completion on the ArkTS thread with no yield
// at all. Bound the run by elapsed time, and keep the count threshold as a coarse ceiling for fast
// loops that would otherwise finish inside one budget.
const DEFAULT_YIELD_BUDGET_MS: number = 24;

// While the user is actively scrolling a heavy page, a 16 ms yield is not enough to keep the
// scroll smooth: the sync still competes for the ArkTS main thread on every wake-up. Hold the
// yield back until the scroll settles, polling in small steps, so sync makes progress without
// fighting the gesture. Bounded so a long continuous scroll cannot stall sync indefinitely.
const BROWSING_YIELD_POLL_MS: number = 100;
const BROWSING_YIELD_MAX_HOLD_MS: number = 4000;

class DefaultAiraSyncWorkThrottleClock implements AiraSyncWorkThrottleClock {
  sleep(delayMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), Math.max(0, delayMs));
    });
  }
}

export class AiraSyncWorkThrottleService implements AiraSyncCooperativeThrottle {
  private clock: AiraSyncWorkThrottleClock;
  private options: AiraSyncWorkThrottleOptions;
  // Start of the current uninterrupted work window; 0 means the next batch item opens one.
  private yieldWindowStartedAtMs: number = 0;

  constructor(clock?: AiraSyncWorkThrottleClock, options?: Partial<AiraSyncWorkThrottleOptions>) {
    this.clock = clock ?? new DefaultAiraSyncWorkThrottleClock();
    this.options = {
      batchSize: options?.batchSize ?? DEFAULT_BATCH_SIZE,
      batchPauseMs: options?.batchPauseMs ?? DEFAULT_BATCH_PAUSE_MS,
      stagePauseMs: options?.stagePauseMs ?? DEFAULT_STAGE_PAUSE_MS,
      yieldBudgetMs: options?.yieldBudgetMs ?? DEFAULT_YIELD_BUDGET_MS
    };
  }

  async afterBatchItem(processedCount: number): Promise<void> {
    if (processedCount <= 0) {
      return;
    }
    const now = this.currentTimeMs();
    if (this.yieldWindowStartedAtMs <= 0) {
      this.yieldWindowStartedAtMs = now;
      return;
    }
    const countDue = processedCount % this.resolveBatchSize() === 0;
    const timeDue = now - this.yieldWindowStartedAtMs >= this.resolveYieldBudgetMs();
    if (!countDue && !timeDue) {
      return;
    }
    await this.pause(this.options.batchPauseMs);
    this.yieldWindowStartedAtMs = this.currentTimeMs();
  }

  async afterStage(): Promise<void> {
    await this.pause(this.options.stagePauseMs);
    this.yieldWindowStartedAtMs = this.currentTimeMs();
  }

  async beforeMainThreadWrite(): Promise<void> {
    await this.pause(this.options.stagePauseMs);
    this.yieldWindowStartedAtMs = this.currentTimeMs();
  }

  private currentTimeMs(): number {
    return this.clock.now !== undefined ? this.clock.now() : Date.now();
  }

  private resolveBatchSize(): number {
    return Math.max(1, this.options.batchSize);
  }

  private resolveYieldBudgetMs(): number {
    return Math.max(0, Math.floor(this.options.yieldBudgetMs ?? DEFAULT_YIELD_BUDGET_MS));
  }

  private async pause(delayMs: number): Promise<void> {
    const baseDelayMs = Math.max(0, delayMs);
    const heldMs = await this.holdWhileBrowsing();
    // Already waited out the gesture: adding the base yield on top would only delay sync.
    if (heldMs > 0) {
      return;
    }
    await this.clock.sleep(baseDelayMs);
  }

  /**
   * Waits out an in-progress scroll gesture, polling in small steps, and returns how long it held
   * (0 when the user was not browsing). Bounded by BROWSING_YIELD_MAX_HOLD_MS so sync always
   * progresses even during a long continuous scroll.
   */
  private async holdWhileBrowsing(): Promise<number> {
    let heldMs = 0;
    while (heldMs < BROWSING_YIELD_MAX_HOLD_MS && this.isBrowsing()) {
      await this.clock.sleep(BROWSING_YIELD_POLL_MS);
      heldMs += BROWSING_YIELD_POLL_MS;
    }
    return heldMs;
  }

  private isBrowsing(): boolean {
    try {
      return sharedBrowsingActivitySignal.isBrowsingRecently();
    } catch (_error) {
      return false;
    }
  }
}
