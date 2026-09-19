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
// A timer turn admits pending input without charging a full frame to every compute slice.
const DEFAULT_BATCH_PAUSE_MS: number = 0;
const DEFAULT_STAGE_PAUSE_MS: number = AIRA_SYNC_UI_YIELD_MS;
// Bound uninterrupted work, including small batches that never reach 250 records. A 200 ms
// budget protects throughput but misses many input/frame deadlines. One item remains indivisible;
// callers must split large encoding/decoding operations as well as calling this between records.
const DEFAULT_YIELD_BUDGET_MS: number = 8;

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
  private yieldWindowStartedAtMs: number;
  // Admit one bounded compute slice between interaction yields, rather than sleeping per record.
  private browsingCheckNotBeforeMs: number = 0;
  // How often this throttle actually yielded, and how long it slept doing so. A cooperative path's
  // wall time is compute + these sleeps, and the two were previously indistinguishable in logs: a
  // ~137 s oversized merge could not be attributed to slow work or to yield overhead. Reset with
  // takeYieldStats() when a stage is measured.
  private yieldCount: number = 0;
  private yieldSleptMs: number = 0;

  constructor(clock?: AiraSyncWorkThrottleClock, options?: Partial<AiraSyncWorkThrottleOptions>) {
    this.clock = clock ?? new DefaultAiraSyncWorkThrottleClock();
    this.options = {
      batchSize: options?.batchSize ?? DEFAULT_BATCH_SIZE,
      batchPauseMs: options?.batchPauseMs ?? DEFAULT_BATCH_PAUSE_MS,
      stagePauseMs: options?.stagePauseMs ?? DEFAULT_STAGE_PAUSE_MS,
      yieldBudgetMs: options?.yieldBudgetMs ?? DEFAULT_YIELD_BUDGET_MS
    };
    this.yieldWindowStartedAtMs = this.currentTimeMs();
  }

  /**
   * Returns how many times this throttle yielded and how long it slept, then resets both. Callers log
   * the pair so a cooperative stage's wall time can be split into work and yield overhead.
   */
  takeYieldStats(): string {
    const summary = `yields=${this.yieldCount} sleptMs=${this.yieldSleptMs}`;
    this.yieldCount = 0;
    this.yieldSleptMs = 0;
    return summary;
  }

  async afterBatchItem(processedCount: number): Promise<void> {
    if (processedCount <= 0) {
      return;
    }
    const now = this.currentTimeMs();
    const countDue = processedCount % this.resolveBatchSize() === 0;
    const timeDue = now - this.yieldWindowStartedAtMs >= this.resolveYieldBudgetMs();
    const browsingDue = now >= this.browsingCheckNotBeforeMs && this.isBrowsing();
    if (!countDue && !timeDue && !browsingDue) {
      return;
    }
    await this.pause(this.options.batchPauseMs, timeDue || browsingDue);
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

  private async pause(delayMs: number, interactionFrameDue: boolean = true): Promise<void> {
    const baseDelayMs = Math.max(0, delayMs);
    const pauseStartedAt = this.currentTimeMs();
    this.yieldCount += 1;
    try {
      // Yield one frame during interaction; never wait for the gesture to end. Repeating
      // four-second holds at every stage made a small bookmark sync take 29 seconds.
      await this.clock.sleep(interactionFrameDue && this.isBrowsing() ? Math.max(baseDelayMs, AIRA_SYNC_UI_YIELD_MS) : baseDelayMs);
    } finally {
      this.browsingCheckNotBeforeMs = this.currentTimeMs() + this.resolveYieldBudgetMs();
      this.yieldSleptMs += Math.max(0, this.currentTimeMs() - pauseStartedAt);
    }
  }

  private isBrowsing(): boolean {
    try {
      return sharedBrowsingActivitySignal.isBrowsingRecently();
    } catch (_error) {
      return false;
    }
  }
}
