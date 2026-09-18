import { display } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CUSTOM_HOMEPAGE_PREVIEW_TAB_ID } from '../../core/customhome/CustomHomepageRuntimeCoordinator';
import {
  BrowserTabPreviewCaptureOptions,
  BrowserTabPreviewCaptureService
} from '../web/BrowserTabPreviewCaptureService';
import { BrowserTabPreviewImageService } from '../web/BrowserTabPreviewImageService';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'CustomHomeSnapshot';
// The homepage already has a preview identity; reusing it keeps the shared pipeline's logs and
// metrics under the same name instead of inventing a tab id the diagnostics would misread.
const CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_CAPTURE_ID: string = CUSTOM_HOMEPAGE_PREVIEW_TAB_ID;
const CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_MIN_PIXEL_WIDTH: number = 720;
const CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_MAX_PIXEL_WIDTH: number = 1620;

export interface CustomHomepageLaunchSnapshotCaptureTarget {
  /** The committed document's own viewport (vp), as measured from its Web node. */
  viewportWidth: number;
  viewportHeight: number;
  /** Shape of the surface the cover is drawn on, so the frame needs no re-crop to fit it. */
  aspectRatio: number;
}

/**
 * Captures the committed homepage document for the cold-start cover.
 *
 * This reuses the tab-preview pipeline rather than calling `webPageSnapshot` directly, because
 * that pipeline already solves the two problems a cover has:
 *
 * 1. It prefers a raw surface-region capture of the document's own pixels, which does not re-lay
 *    the page out. A bare `webPageSnapshot` re-lays the page out at the size it is handed, so
 *    asking for the shell viewport produced a frame whose content had been laid out against a
 *    height the document never had — the cover then read as stretched until the live page
 *    replaced it.
 * 2. It normalizes the frame to a target aspect ratio by cropping, so the cover can be drawn at
 *    the surface's shape without the image being resampled to fit it.
 *
 * The frame is returned as a pixel map, and the caller owns it from there.
 */
export class CustomHomepageLaunchSnapshotCaptureService {
  private previewCaptureService: BrowserTabPreviewCaptureService = new BrowserTabPreviewCaptureService();
  private imageService: BrowserTabPreviewImageService = new BrowserTabPreviewImageService();

  async capture(
    controller: webview.WebviewController,
    snapshotId: string,
    target: CustomHomepageLaunchSnapshotCaptureTarget
  ): Promise<image.PixelMap | undefined> {
    if (snapshotId.trim().length <= 0) {
      return undefined;
    }
    const viewportWidth = Math.max(0, Math.round(target.viewportWidth));
    const viewportHeight = Math.max(0, Math.round(target.viewportHeight));
    const options: BrowserTabPreviewCaptureOptions = {
      // The Web component's own id: a container id makes `webPageSnapshot` fail with 17100001.
      webComponentSnapshotId: snapshotId,
      // No `uiContext`, so the visible-snapshot pass skips its component-snapshot candidate: a
      // Surface-level component snapshot does not reliably include Web pixels and would hand back
      // the themed backplate instead of the page.
      allowWindowSnapshot: false,
      allowSurfaceSnapshot: true,
      preferVisibleSnapshot: true,
      requireSharedSnapshot: false,
      persistSharedSnapshot: false,
      preferredWebViewportSnapshotSize: viewportWidth > 1 && viewportHeight > 1 ?
        { width: viewportWidth, height: viewportHeight } : undefined
    };
    const result = await this.previewCaptureService.captureWebPage(
      controller,
      CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_CAPTURE_ID,
      options
    );
    const rawPixelMap = result.snapshot;
    if (rawPixelMap === undefined) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        'launch snapshot capture empty source=%{public}s reason=%{public}s',
        result.source, result.failureReason);
      return undefined;
    }
    const normalizedPixelMap = await this.imageService.normalizeForSharedSnapshot(
      rawPixelMap,
      CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_CAPTURE_ID,
      result.source,
      {
        targetAspectRatio: this.resolveTargetAspectRatio(target),
        edgeCropRatio: 0,
        maxPixelWidth: this.resolveMaxPixelWidth(viewportWidth)
      }
    );
    if (normalizedPixelMap !== rawPixelMap) {
      // The normalized frame is a new allocation; the raw capture is not referenced again.
      try {
        await rawPixelMap.release();
      } catch (error) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'launch snapshot raw release failed error=%{public}s',
          JSON.stringify(error));
      }
    }
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'launch snapshot captured source=%{public}s viewport=%{public}d x %{public}d',
      result.source, viewportWidth, viewportHeight);
    return normalizedPixelMap;
  }

  private resolveTargetAspectRatio(target: CustomHomepageLaunchSnapshotCaptureTarget): number {
    const aspectRatio = target.aspectRatio;
    if (!Number.isFinite(aspectRatio) || aspectRatio <= 0) {
      return 0;
    }
    return aspectRatio;
  }

  // Keeps the stored frame at the surface's own pixel width instead of the thumbnail default,
  // which would soften a full-screen cover, while still bounding what one cover may occupy.
  private resolveMaxPixelWidth(viewportWidth: number): number {
    const density = this.resolveDisplayDensity();
    const pixelWidth = Math.round(Math.max(1, viewportWidth) * density);
    if (!Number.isFinite(pixelWidth) || pixelWidth <= 0) {
      return CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_MIN_PIXEL_WIDTH;
    }
    return Math.max(
      CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_MIN_PIXEL_WIDTH,
      Math.min(CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_MAX_PIXEL_WIDTH, pixelWidth)
    );
  }

  private resolveDisplayDensity(): number {
    try {
      const density = display.getDefaultDisplaySync().densityPixels;
      return Number.isFinite(density) && density > 0 ? density : 1;
    } catch (_error) {
      return 1;
    }
  }
}
