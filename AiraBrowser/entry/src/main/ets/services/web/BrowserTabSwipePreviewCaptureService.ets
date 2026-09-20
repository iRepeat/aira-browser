import { UIContext } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserTabPreviewCaptureService,
  BrowserTabPreviewWebViewportSize,
  buildBrowserTabWebComponentSnapshotId
} from './BrowserTabPreviewCaptureService';
import { BrowserTabSwipePreviewImage } from '../../core/browser/BrowserTabSwipePreviewCoordinator';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'TabSwipeCapture';

interface BrowserTabSwipePreviewSize {
  width: number;
  height: number;
}

export interface BrowserTabSwipePreviewCaptureRequest {
  tabId: string;
  controller: webview.WebviewController;
  viewport: BrowserTabPreviewWebViewportSize;
  uiContext?: UIContext;
}

/**
 * Produces the swipe cover image through ArkWeb's own page snapshot.
 *
 * The ArkUI component snapshot cannot read ArkWeb same-layer content, so it returns a blank
 * surface — which painted a solid rectangle over the incoming side of a swipe. ArkWeb's
 * `webPageSnapshot` renders the real page pixels, and it also works while the tab is still the
 * outgoing one.
 *
 * The image is memory-only: it is never written to the persisted preview cache and never replaces
 * the tab overview thumbnail.
 */
export class BrowserTabSwipePreviewCaptureService {
  private captureService: BrowserTabPreviewCaptureService = new BrowserTabPreviewCaptureService();

  async capture(request: BrowserTabSwipePreviewCaptureRequest): Promise<BrowserTabSwipePreviewImage | undefined> {
    try {
      const result = await this.captureService.captureWebPage(request.controller, request.tabId, {
        uiContext: request.uiContext,
        webComponentSnapshotId: buildBrowserTabWebComponentSnapshotId(request.tabId),
        // Web page only: no window, surface, or component fallback can produce the page pixels,
        // and the fallbacks would only offer chrome-bearing images.
        componentSnapshotOnly: false,
        preferVisibleSnapshot: false,
        allowWindowSnapshot: false,
        allowSurfaceSnapshot: false,
        // Keep the image in memory and out of the shared overview cache.
        persistSharedSnapshot: false,
        requireSharedSnapshot: false,
        preferredWebViewportSnapshotSize: request.viewport
      });
      if (result.snapshot === undefined) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'web snapshot unavailable tab=%{public}s reason=%{public}s',
          request.tabId, result.failureReason);
        return undefined;
      }
      const size = await this.resolveSize(result.snapshot);
      if (size === undefined) {
        this.release(result.snapshot);
        return undefined;
      }
      return { pixelMap: result.snapshot, width: size.width, height: size.height };
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'web snapshot threw tab=%{public}s error=%{public}s',
        request.tabId, JSON.stringify(error));
      return undefined;
    }
  }

  release(pixelMap: image.PixelMap): void {
    try {
      void pixelMap.release().catch((_error: Error): void => {});
    } catch (_) {}
  }

  private async resolveSize(pixelMap: image.PixelMap): Promise<BrowserTabSwipePreviewSize | undefined> {
    try {
      const info = await pixelMap.getImageInfo();
      if (info.size.width > 0 && info.size.height > 0) {
        return { width: info.size.width, height: info.size.height };
      }
    } catch (_) {
      // Fall through to the default size so a readable image is not discarded.
    }
    return undefined;
  }
}
