/**
 * Foreground browsing activity, shared across layers.
 *
 * Automatic sync (bookmark / personalization / history) does a burst of RDB and marshaling work
 * shortly after startup: measured on device it lands about 22 s, 30 s and 31 s after content is
 * ready, with synchronous RDB transactions of hundreds of milliseconds inside. When that burst
 * overlaps the user actively scrolling a heavy page, the two compete for the ArkTS main thread and
 * the scroll stutters.
 *
 * The Web scroll path marks interaction here; sync scheduling and its cooperative throttle consult
 * it and hold maintenance work back until the user pauses. Nothing is dropped — the work runs at
 * the next quiet moment, and every wait has an upper bound so a long scroll cannot starve sync.
 *
 * Lives in common/ because both the shell (app/), the sync owners (core/, services/) and the
 * database write path (data/) need it.
 */
const RECENT_INTERACTION_WINDOW_MS: number = 2500;

class BrowsingActivitySignal {
  private lastInteractionAt: number = 0;

  markBrowsingInteraction(now: number = Date.now()): void {
    this.lastInteractionAt = now;
  }

  isBrowsingRecently(now: number = Date.now()): boolean {
    return this.lastInteractionAt > 0 && now - this.lastInteractionAt < RECENT_INTERACTION_WINDOW_MS;
  }
}

export const sharedBrowsingActivitySignal: BrowsingActivitySignal = new BrowsingActivitySignal();

export const BROWSING_RECENT_WINDOW_MS: number = RECENT_INTERACTION_WINDOW_MS;
