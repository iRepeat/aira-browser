import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserResolvedThemeMode } from '../../common/models/BrowserModels';
import { CustomHomepageLaunchSnapshot } from './CustomHomepageLaunchSnapshotViewModel';
import { CustomHomepageLaunchSnapshotStore } from '../../services/customhome/CustomHomepageLaunchSnapshotStore';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'CustomHomeSnapshot';
// The homepage can edit its own content without touching any Aira-visible
// source, so refresh the cover periodically while it is on screen. This bounds
// how stale the persisted frame can be without capturing on every frame.
const AUTO_CAPTURE_INTERVAL_MS: number = 4000;
// Fast path: the last reliable moment before the process may be suspended, so a
// page-hide capture cannot afford to wait.
const AUTO_CAPTURE_SETTLE_MS: number = 700;
// The first capture of a fresh document must not fire while the cold-start cover
// is still handing off to the live page. Poking the Web node for a snapshot right
// at the swap showed up as a faint flicker, so the first capture waits until the
// entrance (zoom + hold + fade) has finished; the steady cadence continues after.
const AUTO_CAPTURE_REVEAL_COOLDOWN_MS: number = 1600;
// A homepage can edit its own layout through the bridge (reorder/move/remove a
// shortcut, write storage). Those changes should refresh the cover promptly rather
// than wait for the periodic pass, but a burst of edits must not postpone the
// capture indefinitely: once the first of a burst is this old, the capture fires
// even if more edits keep arriving.
const AUTO_CAPTURE_CONTENT_CHANGE_SETTLE_MS: number = 500;
const AUTO_CAPTURE_CONTENT_CHANGE_MAX_DEFERRAL_MS: number = 2500;

export interface CustomHomepageLaunchSnapshotCaptureRequest {
  renderKey: string;
  themeMode: BrowserResolvedThemeMode;
}

export type CustomHomepageLaunchSnapshotCapture = () => Promise<image.PixelMap | undefined>;

export interface CustomHomepageLaunchSnapshotCaptureSource {
  // Returns the current request, or undefined when capture must not run now
  // (home hidden, private mode, tabs sheet, document not committed).
  resolveRequest: () => CustomHomepageLaunchSnapshotCaptureRequest | undefined;
  capture: CustomHomepageLaunchSnapshotCapture;
}

/**
 * Owns when the launch snapshot is captured: periodic refresh while the homepage
 * is on screen, one deferred capture after a commit, and dropping overlapping
 * captures. Persistence is delegated to the store.
 */
export class CustomHomepageLaunchSnapshotCoordinator {
  private store: CustomHomepageLaunchSnapshotStore;
  private autoCaptureTimer: number = -1;
  private autoCaptureInFlight: boolean = false;
  private contentChangeFirstRequestedAt: number = -1;
  private source?: CustomHomepageLaunchSnapshotCaptureSource = undefined;

  constructor(store: CustomHomepageLaunchSnapshotStore = new CustomHomepageLaunchSnapshotStore()) {
    this.store = store;
  }

  load(currentRenderKey: string, viewportWidth: number = 0, viewportHeight: number = 0):
    CustomHomepageLaunchSnapshot | undefined {
    return this.store.loadSync(currentRenderKey, viewportWidth, viewportHeight);
  }

  startAutoCapture(source: CustomHomepageLaunchSnapshotCaptureSource): void {
    this.source = source;
    this.scheduleAutoCapture(AUTO_CAPTURE_REVEAL_COOLDOWN_MS);
  }

  stopAutoCapture(): void {
    this.source = undefined;
    if (this.autoCaptureTimer >= 0) {
      clearTimeout(this.autoCaptureTimer);
      this.autoCaptureTimer = -1;
    }
  }

  /** Deferred capture for a commit or a fresh home reveal, held past the entrance. */
  requestCapture(): void {
    this.scheduleRequestedCapture(AUTO_CAPTURE_REVEAL_COOLDOWN_MS);
  }

  /** Deferred capture that must run as soon as possible (page hide). */
  requestImmediateCapture(): void {
    this.scheduleRequestedCapture(AUTO_CAPTURE_SETTLE_MS);
  }

  /**
   * The homepage changed its own content/layout through the bridge. Refresh the
   * cover soon after the edits stop, but within a bounded window so a continuing
   * stream of edits still produces a capture.
   */
  requestContentChangeCapture(): void {
    if (this.source === undefined) {
      return;
    }
    const now = Date.now();
    if (this.contentChangeFirstRequestedAt < 0) {
      this.contentChangeFirstRequestedAt = now;
    }
    const elapsed = now - this.contentChangeFirstRequestedAt;
    const remainingBudget = Math.max(
      0,
      AUTO_CAPTURE_CONTENT_CHANGE_MAX_DEFERRAL_MS - elapsed
    );
    this.scheduleRequestedCapture(
      Math.min(AUTO_CAPTURE_CONTENT_CHANGE_SETTLE_MS, remainingBudget)
    );
  }

  private scheduleRequestedCapture(delayMs: number): void {
    if (this.source === undefined) {
      return;
    }
    if (this.autoCaptureTimer >= 0) {
      clearTimeout(this.autoCaptureTimer);
      this.autoCaptureTimer = -1;
    }
    this.scheduleAutoCapture(delayMs);
  }

  /** Drops the cover for one render identity (theme/identity change). */
  invalidate(renderKey: string): void {
    this.store.invalidate(renderKey);
  }

  /** Drops every stored cover. */
  invalidateAll(): void {
    this.stopAutoCapture();
    this.store.invalidateAll();
  }

  private scheduleAutoCapture(delayMs: number): void {
    if (this.source === undefined) {
      return;
    }
    if (this.autoCaptureTimer >= 0) {
      return;
    }
    this.autoCaptureTimer = setTimeout((): void => {
      this.autoCaptureTimer = -1;
      void this.runAutoCapture();
    }, Math.max(0, Math.floor(delayMs)));
  }

  private async runAutoCapture(): Promise<void> {
    const source = this.source;
    if (source === undefined) {
      return;
    }
    this.contentChangeFirstRequestedAt = -1;
    if (!this.autoCaptureInFlight) {
      const request = source.resolveRequest();
      if (request !== undefined && request.renderKey.trim().length > 0) {
        this.autoCaptureInFlight = true;
        try {
          const pixelMap = await source.capture();
          if (pixelMap !== undefined) {
            try {
              await this.store.persist(pixelMap, request.renderKey, request.themeMode);
            } finally {
              // The capture service hands over ownership; the store only reads the frame, so every
              // capture used to strand one full-screen pixel map.
              await pixelMap.release().catch((_error: Error): void => {});
            }
          }
        } catch (error) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'launch snapshot capture failed error=%{public}s', JSON.stringify(error));
        } finally {
          this.autoCaptureInFlight = false;
        }
      }
    }
    this.scheduleAutoCapture(AUTO_CAPTURE_INTERVAL_MS);
  }
}
