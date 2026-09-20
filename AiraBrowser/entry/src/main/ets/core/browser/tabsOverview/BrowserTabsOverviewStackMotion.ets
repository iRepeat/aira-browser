import {
  BrowserTabsOverviewStackLayoutPolicy,
  SPRING_CANCEL_STIFFNESS,
  SPRING_STIFFNESS
} from './BrowserTabsOverviewStackLayoutPolicy';

export type BrowserTabsStackFrameScheduler = (callback: (timeInNano: number) => void) => void;

/**
 * Owns the displayed scalar position, including interruption.
 *
 * Both the drag and the settle write the same scalar, so a gesture that starts while a settle is
 * still running continues from the value on screen instead of from a stale endpoint. The deck then
 * evaluates its nonlinear layout at that scalar on every display frame; animating only the endpoint
 * transforms would interpolate straight through the deck spacing.
 */
export class BrowserTabsOverviewStackMotion {
  private readonly policy: BrowserTabsOverviewStackLayoutPolicy =
    new BrowserTabsOverviewStackLayoutPolicy();
  private position: number = 0;
  private generation: number = 0;
  private dragging: boolean = false;
  private previousOffset: number = 0;

  getPosition(): number {
    return this.position;
  }

  isDragging(): boolean {
    return this.dragging;
  }

  /** Cancel any in-flight settle and detach from the finger. Leaves `position` where it is. */
  stop(): void {
    this.generation += 1;
    this.dragging = false;
    this.previousOffset = 0;
  }

  /**
   * Place the deck on a card and cancel any motion.
   *
   * Only for an already-integral slot. A settle that is interrupted by non-gesture state (a tab
   * closing, the overlay leaving) must go through `settle`/`cancel` instead, or the deck is left
   * between two cards with no frame left to move it.
   */
  seed(position: number, count: number): number {
    this.stop();
    this.position = this.policy.clamp(position, count);
    return this.position;
  }

  /**
   * Reposition without interrupting a drag.
   *
   * The tab list can change mid-gesture (a snapshot lands, an icon resolves). Restarting the motion
   * there would cancel the finger, and leaving `position` alone would make the next delta jump back
   * to the stale value, so the displayed position is adopted in place.
   */
  setPosition(position: number): number {
    this.position = Number.isFinite(position) ? position : this.position;
    return this.position;
  }

  begin(): void {
    this.stop();
    this.dragging = true;
    this.previousOffset = 0;
  }

  drag(offsetX: number, width: number, count: number): number {
    if (!this.dragging || !Number.isFinite(offsetX)) {
      return this.position;
    }
    this.position = this.policy.advanceDrag(this.position, offsetX - this.previousOffset, width, count);
    this.previousOffset = offsetX;
    return this.position;
  }

  release(velocityX: number, width: number, count: number, schedule: BrowserTabsStackFrameScheduler,
    publish: (position: number) => void): void {
    const release = this.policy.release(this.position, velocityX, width, count);
    this.settle(release.target, release.velocity, SPRING_STIFFNESS, schedule, publish);
  }

  /** Reference `onDragCancel`: settle to the nearest card with the softer cancel spring. */
  cancel(count: number, schedule: BrowserTabsStackFrameScheduler,
    publish: (position: number) => void): void {
    const target = Math.round(this.policy.clamp(this.position, count));
    this.settle(target, 0, SPRING_CANCEL_STIFFNESS, schedule, publish);
  }

  /**
   * Settle from wherever the deck currently sits.
   *
   * Used when something other than the gesture ends the interaction (a tab closes, the section
   * changes, the overlay leaves). Without this the deck would keep a fractional position with no
   * frame callback left to move it.
   */
  settleToNearest(count: number, schedule: BrowserTabsStackFrameScheduler,
    publish: (position: number) => void): void {
    const target = Math.round(this.policy.clamp(this.position, count));
    if (target === this.position) {
      this.stop();
      return;
    }
    this.settle(target, 0, SPRING_CANCEL_STIFFNESS, schedule, publish);
  }

  private settle(target: number, velocity: number, stiffness: number,
    schedule: BrowserTabsStackFrameScheduler, publish: (position: number) => void): void {
    this.stop();
    const epoch = this.generation;
    const start = this.position;
    let startTime = -1;
    const tick = (time: number): void => {
      if (epoch !== this.generation) {
        return;
      }
      if (startTime < 0) {
        startTime = time;
      }
      const sample = this.policy.sampleSpring(start, target, velocity, (time - startTime) / 1000000000,
        stiffness);
      this.position = sample.position;
      publish(this.position);
      if (!sample.finished && epoch === this.generation) {
        schedule(tick);
      }
    };
    schedule(tick);
  }
}
