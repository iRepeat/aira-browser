/**
 * One bounded queue for the process's `@ohos.net.http` traffic.
 *
 * Every `http.createHttp()` call in this browser creates a native easy handle inside OpenHarmony's NetStack, and
 * NetStack drives those handles from its own `OS_NET_HttpWork` thread over a libcurl multi handle. That thread has
 * crashed in `Curl_llist_append`, `Curl_expire`, `multi_runsingle` and `curl_multi_socket_action` on released
 * list nodes — a use-after-free inside the system library. The faulting frames are all system frames, so the
 * defect itself is not ours to fix. What is ours is how many handles we keep alive at once and when we tear them
 * down.
 *
 * Unbounded fan-out is what this process was doing: a novel shelf, a site-icon pass and a sync round could each
 * start their own requests in the same second, and `onBackground` had no way to stop any of them. Two shapes of
 * that traffic are worth separating, because they deserve opposite treatment when the app leaves the foreground:
 *
 * - `interactive` work is something the reader asked for — a download, a login, a translation. Cancelling it
 *   discards a result a person is waiting on, so it is never cancelled and never blocked behind background work.
 * - `background` work is speculative — icon lookups, probes, feed refreshes, sync rounds, novel prefetch. Nobody
 *   is waiting for it, so leaving the foreground cancels it outright.
 *
 * Callers reach both through `run`, which acquires a slot, hands the body a cancellation token, and releases the
 * slot in a `finally`. The slot is released on every path, including cancellation and throw, so a cancelled
 * request cannot leak capacity.
 *
 * This is a probability reducer, not a fix. The NetStack defect remains; this only removes the concurrency and
 * teardown patterns that made it easy to hit.
 */

/** Traffic classes. Each class has its own concurrency ceiling so one cannot starve another. */
export type AiraHttpRequestScope =
  'novel' |
  'site_icon' |
  'sync' |
  'probe' |
  'update' |
  'user';

/**
 * Whether the work is something a person is waiting for.
 *
 * `interactive` work survives a trip to the background; `background` work does not.
 */
export type AiraHttpRequestPriority = 'interactive' | 'background';

const SCOPE_CONCURRENCY: Record<AiraHttpRequestScope, number> = {
  // A shelf or reader view fans out over covers, catalogs and chapters. Two at a time keeps a page responsive
  // while bounding the handles the multi handle holds.
  'novel': 2,
  // Icon resolution already runs a two-worker pool upstream; this is the ceiling for the requests themselves.
  'site_icon': 2,
  // Sync is serial by contract. One at a time also keeps it off the same multi handle as browsing traffic.
  'sync': 1,
  // Probes are pure speculation and the least valuable traffic in the process.
  'probe': 1,
  'update': 1,
  // Reader-initiated work is bounded only by the network, and never queues behind background work.
  'user': 4
};

const SCOPE_ORDER: AiraHttpRequestScope[] = ['user', 'novel', 'site_icon', 'sync', 'update', 'probe'];

/** Cancellation surface handed to a request body. */
export interface AiraHttpRequestCancellation {
  /** True once the app left the foreground (or the process is tearing down) and this work should stop. */
  isCancelled: () => boolean;
  /** Throws when cancelled, for callers that want to unwind without a branch. */
  throwIfCancelled: () => void;
}

/** Held while a request occupies a slot. Closing it twice is a no-op. */
export interface AiraHttpRequestLease {
  close: () => void;
}

/** Raised when work is abandoned because the app left the foreground. */
export class AiraHttpRequestCancelledError extends Error {
  constructor(scope: AiraHttpRequestScope) {
    super(`HTTP ${scope} request cancelled: the app is no longer in the foreground.`);
  }
}

/**
 * One queued request, waiting for a slot in its scope.
 *
 * A class rather than an interface with function-typed fields: ArkTS refuses to call a function-typed
 * member read off an interface-typed value (`arkts-no-structural-typing`), and it refuses the object
 * literal that would fill such an interface. Declaring the two callbacks as constructor arguments and
 * exposing them as methods keeps the same behaviour and stays inside the checker's rules.
 */
class AiraHttpRequestWaiter {
  readonly scope: AiraHttpRequestScope;
  readonly priority: AiraHttpRequestPriority;
  readonly sequence: number;
  private readonly grantAction: (lease: AiraHttpRequestLease) => void;
  private readonly rejectAction: (error: AiraHttpRequestCancelledError) => void;

  constructor(
    scope: AiraHttpRequestScope,
    priority: AiraHttpRequestPriority,
    sequence: number,
    grantAction: (lease: AiraHttpRequestLease) => void,
    rejectAction: (error: AiraHttpRequestCancelledError) => void
  ) {
    this.scope = scope;
    this.priority = priority;
    this.sequence = sequence;
    this.grantAction = grantAction;
    this.rejectAction = rejectAction;
  }

  grant(lease: AiraHttpRequestLease): void {
    this.grantAction(lease);
  }

  reject(error: AiraHttpRequestCancelledError): void {
    this.rejectAction(error);
  }
}

export class AiraHttpRequestGate {
  private inFlightByScope: Record<string, number> = {};
  private waiters: AiraHttpRequestWaiter[] = [];
  private nextSequence: number = 0;
  /** Cancellation epoch for background work. Bumped on background; waiters from older epochs are dropped. */
  private backgroundEpoch: number = 0;
  private backgroundWorkAllowed: boolean = true;

  /**
   * Runs one request under the gate.
   *
   * The body receives a cancellation token. A `background` call that is waiting when the app leaves the
   * foreground is rejected rather than started; one already running is expected to observe `isCancelled` and
   * unwind on its own, and its slot is released either way.
   */
  async run<T>(
    scope: AiraHttpRequestScope,
    priority: AiraHttpRequestPriority,
    execute: (cancellation: AiraHttpRequestCancellation) => Promise<T>
  ): Promise<T> {
    const lease = await this.acquire(scope, priority);
    const cancellation = this.buildCancellation(scope, priority);
    try {
      cancellation.throwIfCancelled();
      return await execute(cancellation);
    } finally {
      lease.close();
    }
  }

  /** Acquires a slot. Rejects if the work is background work and the app is not in the foreground. */
  acquire(scope: AiraHttpRequestScope, priority: AiraHttpRequestPriority): Promise<AiraHttpRequestLease> {
    if (priority === 'background' && !this.backgroundWorkAllowed) {
      return Promise.reject(new AiraHttpRequestCancelledError(scope));
    }
    if (this.inFlightFor(scope) < this.concurrencyFor(scope)) {
      return Promise.resolve(this.lease(scope));
    }
    return new Promise<AiraHttpRequestLease>((resolve, reject) => {
      this.waiters.push(new AiraHttpRequestWaiter(
        scope,
        priority,
        ++this.nextSequence,
        resolve,
        reject
      ));
    });
  }

  /** True while any request holds a slot. Exposed for diagnostics and tests. */
  hasInFlightWork(): boolean {
    for (const scope of SCOPE_ORDER) {
      if (this.inFlightFor(scope) > 0) {
        return true;
      }
    }
    return false;
  }

  /** In-flight count for one scope. Exposed for diagnostics and tests. */
  inFlightCount(scope: AiraHttpRequestScope): number {
    return this.inFlightFor(scope);
  }

  /** Queued waiter count. Exposed for diagnostics and tests. */
  pendingCount(): number {
    return this.waiters.length;
  }

  /** True while background work is being accepted. */
  isBackgroundWorkAllowed(): boolean {
    return this.backgroundWorkAllowed;
  }

  /**
   * App left the foreground: stop starting background work and reject anything already queued.
   *
   * Interactive work is deliberately untouched — it is a result a person is waiting for, and the reader may
   * return to it. Only the speculative classes are abandoned.
   */
  suspendBackgroundWork(): number {
    if (this.backgroundWorkAllowed) {
      this.backgroundWorkAllowed = false;
      this.backgroundEpoch += 1;
    }
    return this.dropQueuedBackgroundWorkers();
  }

  /** App is back in the foreground: background work may start again on a fresh epoch. */
  resumeBackgroundWork(): void {
    this.backgroundWorkAllowed = true;
  }

  /** Drops every queued waiter. Used when a tab or the whole runtime is torn down. */
  releaseAll(): number {
    const dropped = this.waiters;
    this.waiters = [];
    for (const waiter of dropped) {
      this.rejectWaiter(waiter);
    }
    return dropped.length;
  }

  /** Reject one queued waiter with the cancellation its scope earns. */
  private rejectWaiter(waiter: AiraHttpRequestWaiter): void {
    waiter.reject(new AiraHttpRequestCancelledError(waiter.scope));
  }

  private dropQueuedBackgroundWorkers(): number {
    const kept: AiraHttpRequestWaiter[] = [];
    const dropped: AiraHttpRequestWaiter[] = [];
    for (const waiter of this.waiters) {
      if (waiter.priority === 'background') {
        dropped.push(waiter);
      } else {
        kept.push(waiter);
      }
    }
    this.waiters = kept;
    for (const waiter of dropped) {
      this.rejectWaiter(waiter);
    }
    return dropped.length;
  }

  private buildCancellation(
    scope: AiraHttpRequestScope,
    priority: AiraHttpRequestPriority
  ): AiraHttpRequestCancellation {
    const epoch = this.backgroundEpoch;
    const isCancelled = (): boolean => {
      if (priority !== 'background') {
        return false;
      }
      return !this.backgroundWorkAllowed || this.backgroundEpoch !== epoch;
    };
    return {
      isCancelled: isCancelled,
      throwIfCancelled: (): void => {
        if (isCancelled()) {
          throw new AiraHttpRequestCancelledError(scope);
        }
      }
    };
  }

  private concurrencyFor(scope: AiraHttpRequestScope): number {
    const limit = SCOPE_CONCURRENCY[scope];
    return limit !== undefined && limit > 0 ? limit : 1;
  }

  private inFlightFor(scope: AiraHttpRequestScope): number {
    return this.inFlightByScope[scope] ?? 0;
  }

  private lease(scope: AiraHttpRequestScope): AiraHttpRequestLease {
    this.inFlightByScope[scope] = this.inFlightFor(scope) + 1;
    let open = true;
    return {
      close: (): void => {
        if (!open) {
          return;
        }
        open = false;
        const remaining = this.inFlightFor(scope) - 1;
        this.inFlightByScope[scope] = remaining > 0 ? remaining : 0;
        this.drain();
      }
    };
  }

  /**
   * Starts as much queued work as the ceilings allow.
   *
   * Interactive waiters are preferred so a reader-triggered request cannot be stuck behind speculative traffic.
   */
  private drain(): void {
    let progressed = true;
    while (progressed) {
      progressed = false;
      for (const scope of SCOPE_ORDER) {
        if (this.inFlightFor(scope) >= this.concurrencyFor(scope)) {
          continue;
        }
        const index = this.pickWaiterIndex(scope);
        if (index < 0) {
          continue;
        }
        const removed: AiraHttpRequestWaiter[] = this.waiters.splice(index, 1);
        if (removed.length <= 0) {
          continue;
        }
        removed[0].grant(this.lease(scope));
        progressed = true;
      }
    }
  }

  /** Highest-priority waiter for a scope: interactive first, then arrival order. */
  private pickWaiterIndex(scope: AiraHttpRequestScope): number {
    let best = -1;
    for (let index = 0; index < this.waiters.length; index += 1) {
      const waiter = this.waiters[index];
      if (waiter.scope !== scope) {
        continue;
      }
      if (best < 0) {
        best = index;
        continue;
      }
      const current = this.waiters[best];
      const waiterIsInteractive = waiter.priority === 'interactive';
      const currentIsInteractive = current.priority === 'interactive';
      if (waiterIsInteractive !== currentIsInteractive) {
        if (waiterIsInteractive) {
          best = index;
        }
        continue;
      }
      if (waiter.sequence < current.sequence) {
        best = index;
      }
    }
    return best;
  }
}

export const sharedAiraHttpRequestGate: AiraHttpRequestGate = new AiraHttpRequestGate();
