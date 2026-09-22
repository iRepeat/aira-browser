import { describe, expect, it } from '@ohos/hypium';
import {
  AiraHttpRequestCancellation,
  AiraHttpRequestGate,
  AiraHttpRequestLease,
  AiraHttpRequestScope
} from '../main/ets/services/network/AiraHttpRequestGate';

/**
 * The gate exists because NetStack's `OS_NET_HttpWork` thread has crashed on released libcurl list nodes while
 * this browser kept an unbounded number of easy handles alive. These cases pin the two properties that shape
 * that traffic: a per-class ceiling that never over-admits, and a background suspension that abandons queued
 * speculative work without touching reader-initiated work.
 */

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(resolve, ms);
  });
}

export default function airaHttpRequestGateTest(): void {
  describe('AiraHttpRequestGate', () => {
    it('never admits more requests than the class ceiling allows', 0, async () => {
      const gate = new AiraHttpRequestGate();
      let active = 0;
      let peak = 0;

      const runOne = async (): Promise<void> => {
        await gate.run('novel', 'background', async (): Promise<void> => {
          active += 1;
          peak = Math.max(peak, active);
          await delay(1);
          active -= 1;
        });
      };

      const all: Promise<void>[] = [];
      for (let index = 0; index < 8; index += 1) {
        all.push(runOne());
      }
      await Promise.all(all);

      // The novel class is capped at two; a ceiling that let a burst through would show a higher peak.
      expect(peak).assertEqual(2);
      expect(gate.inFlightCount('novel')).assertEqual(0);
      expect(gate.pendingCount()).assertEqual(0);
    });

    it('keeps concurrent classes independent so one cannot starve another', 0, async () => {
      const gate = new AiraHttpRequestGate();
      const held: AiraHttpRequestLease[] = [];

      const hold = async (scope: AiraHttpRequestScope): Promise<void> => {
        const lease = await gate.acquire(scope, 'background');
        held.push(lease);
      };

      await hold('sync');
      await hold('novel');
      await hold('novel');

      // Both novel slots are taken, so a third novel request must queue...
      let queued = false;
      const pendingNovel = gate.acquire('novel', 'background').then((lease: AiraHttpRequestLease): void => {
        lease.close();
      });
      pendingNovel.then((): void => {
        queued = true;
      });
      await delay(5);
      expect(gate.pendingCount()).assertEqual(1);
      expect(queued).assertFalse();

      // ...while a different class still gets its own slot immediately.
      expect(gate.inFlightCount('sync')).assertEqual(1);
      expect(gate.inFlightCount('site_icon')).assertEqual(0);
      const iconLease = await gate.acquire('site_icon', 'background');
      expect(gate.inFlightCount('site_icon')).assertEqual(1);
      iconLease.close();

      held.forEach((lease: AiraHttpRequestLease): void => lease.close());
      await pendingNovel;
      expect(queued).assertTrue();
      expect(gate.pendingCount()).assertEqual(0);
    });

    it('rejects queued background work when the app leaves the foreground', 0, async () => {
      const gate = new AiraHttpRequestGate();
      const holders: AiraHttpRequestLease[] = [];
      holders.push(await gate.acquire('novel', 'background'));
      holders.push(await gate.acquire('novel', 'background'));

      // A queued speculative request must be dropped rather than started later.
      let rejected = false;
      const queued = gate.run('novel', 'background', async (): Promise<string> => {
        return 'started';
      }).catch((_error: Error): string => {
        rejected = true;
        return 'dropped';
      });

      await delay(5);
      expect(gate.pendingCount()).assertEqual(1);

      const abandoned = gate.suspendBackgroundWork();
      expect(abandoned).assertEqual(1);
      expect(await queued).assertEqual('dropped');
      expect(rejected).assertTrue();
      expect(gate.pendingCount()).assertEqual(0);
      expect(gate.isBackgroundWorkAllowed()).assertFalse();

      holders.forEach((lease: AiraHttpRequestLease): void => lease.close());
    });

    it('refuses to start new background work while suspended', 0, async () => {
      const gate = new AiraHttpRequestGate();
      gate.suspendBackgroundWork();

      let started = false;
      const outcome = await gate.run('probe', 'background', async (): Promise<string> => {
        started = true;
        return 'started';
      }).catch((_error: Error): string => {
        return 'refused';
      });

      expect(outcome).assertEqual('refused');
      expect(started).assertFalse();

      gate.resumeBackgroundWork();
      const resumed = await gate.run('probe', 'background', async (): Promise<string> => {
        return 'started';
      });
      expect(resumed).assertEqual('started');
    });

    it('lets reader-initiated work run through a suspension and never marks it cancelled', 0, async () => {
      const gate = new AiraHttpRequestGate();
      const observed: boolean[] = [];

      const interactive = gate.run('user', 'interactive', async (
        cancellation: AiraHttpRequestCancellation
      ): Promise<string> => {
        // Suspending mid-flight must not be visible to a reader-initiated request: someone is waiting on it.
        gate.suspendBackgroundWork();
        observed.push(cancellation.isCancelled());
        return 'finished';
      });

      expect(await interactive).assertEqual('finished');
      expect(observed[0]).assertFalse();
      expect(gate.isBackgroundWorkAllowed()).assertFalse();
    });

    it('releases the slot when a request body throws', 0, async () => {
      const gate = new AiraHttpRequestGate();

      let threw = false;
      try {
        await gate.run('novel', 'background', async (): Promise<void> => {
          throw new Error('body failed');
        });
      } catch (_error) {
        threw = true;
      }

      // A leaked slot would strand the class at its ceiling and stall every later request.
      expect(threw).assertTrue();
      expect(gate.inFlightCount('novel')).assertEqual(0);
      expect(gate.hasInFlightWork()).assertFalse();
    });

    it('releases the slot when the body is cancelled before it starts', 0, async () => {
      const gate = new AiraHttpRequestGate();
      gate.suspendBackgroundWork();
      gate.resumeBackgroundWork();

      let threw = false;
      try {
        await gate.run('novel', 'background', async (
          cancellation: AiraHttpRequestCancellation
        ): Promise<void> => {
          cancellation.throwIfCancelled();
        });
      } catch (_error) {
        threw = true;
      }

      expect(threw).assertFalse();
      expect(gate.inFlightCount('novel')).assertEqual(0);
    });

    it('prefers reader-initiated work over queued speculative work', 0, async () => {
      const gate = new AiraHttpRequestGate();
      const order: string[] = [];

      // Fill the novel ceiling so both classes queue behind it.
      const blockerOne = await gate.acquire('novel', 'background');
      const blockerTwo = await gate.acquire('novel', 'background');

      const background = gate.acquire('novel', 'background').then((lease: AiraHttpRequestLease): void => {
        order.push('background');
        lease.close();
      });
      await delay(1);
      const interactive = gate.acquire('novel', 'interactive').then((lease: AiraHttpRequestLease): void => {
        order.push('interactive');
        lease.close();
      });
      await delay(1);

      blockerOne.close();
      await interactive;
      blockerTwo.close();
      await background;

      // The reader's request arrived second but must be served first.
      expect(order[0]).assertEqual('interactive');
      expect(order[1]).assertEqual('background');
    });

    it('drops every queued waiter on release so a teardown cannot strand callers', 0, async () => {
      const gate = new AiraHttpRequestGate();
      const blockers: AiraHttpRequestLease[] = [
        await gate.acquire('probe', 'background')
      ];

      const queuedOne = gate.acquire('probe', 'background').catch((): string => 'dropped');
      const queuedTwo = gate.acquire('probe', 'background').catch((): string => 'dropped');
      await delay(5);
      expect(gate.pendingCount()).assertEqual(2);

      expect(gate.releaseAll()).assertEqual(2);
      expect(await queuedOne).assertEqual('dropped');
      expect(await queuedTwo).assertEqual('dropped');
      expect(gate.pendingCount()).assertEqual(0);

      blockers.forEach((lease: AiraHttpRequestLease): void => lease.close());
    });
  });
}
