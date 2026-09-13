import { webview } from '@kit.ArkWeb';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'CustomHomeSnapshot';
const CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_CAPTURE_TIMEOUT_MS: number = 1800;

interface CustomHomepageLaunchSnapshotCaptureSize {
  width: string;
  height: string;
}

/**
 * Captures the committed homepage document for the cold-start cover.
 *
 * A Surface-level component snapshot does not reliably include the pixels of a
 * plain Web node, so the frame must come from the Web controller itself. The
 * capture lives here rather than in the page so the shell stays free of Home
 * presentation timers.
 */
export class CustomHomepageLaunchSnapshotCaptureService {
  async capture(
    controller: webview.WebviewController,
    snapshotId: string,
    width: number,
    height: number
  ): Promise<image.PixelMap | undefined> {
    if (snapshotId.trim().length <= 0) {
      return undefined;
    }
    const size: CustomHomepageLaunchSnapshotCaptureSize = {
      width: `${Math.max(1, Math.round(width))}vp`,
      height: `${Math.max(1, Math.round(height))}vp`
    };
    return await new Promise<image.PixelMap | undefined>(
      (resolve: (value: image.PixelMap | undefined) => void): void => {
        let settled = false;
        const timeoutId = setTimeout((): void => {
          if (settled) {
            return;
          }
          settled = true;
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'launch snapshot capture timeout');
          resolve(undefined);
        }, CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_CAPTURE_TIMEOUT_MS);
        try {
          controller.webPageSnapshot({ id: snapshotId, size: size }, (error, result) => {
            if (settled) {
              return;
            }
            settled = true;
            clearTimeout(timeoutId);
            if (error !== undefined || result?.status !== true || result.imagePixelMap === undefined) {
              hilog.warn(LOG_DOMAIN, LOG_TAG, 'launch snapshot capture empty or error');
              resolve(undefined);
              return;
            }
            resolve(result.imagePixelMap);
          });
        } catch (error) {
          if (!settled) {
            settled = true;
            clearTimeout(timeoutId);
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'launch snapshot capture threw error=%{public}s', JSON.stringify(error));
            resolve(undefined);
          }
        }
      }
    );
  }
}
