import { BrowserResolvedThemeMode } from '../../common/models/BrowserModels';

/**
 * Policy owner for the cold-start launch snapshot of a third-party homepage.
 *
 * ArkWeb cannot keep a Web document alive across process death, so a cold start
 * must reload the document and briefly shows the theme background before the real
 * page commits. The launch snapshot covers that window with the last committed
 * homepage frame. This view model owns only the metadata shape, the
 * render-identity validation, and the age limit; persistence lives in the
 * service layer and capture scheduling in the coordinator.
 */
export interface CustomHomepageLaunchSnapshotMetadata {
  schemaVersion: number;
  renderKey: string;
  themeMode: BrowserResolvedThemeMode;
  width: number;
  height: number;
  capturedAt: number;
}

export interface CustomHomepageLaunchSnapshot {
  uri: string;
  width: number;
  height: number;
  renderKey: string;
}

// Bumped to 2 when covers became captures of the document's own viewport, normalized to the
// surface's shape. A version-1 frame was captured at the shell viewport and its content had been
// laid out against a height the document never had, so it must not be shown again.
export const CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_SCHEMA_VERSION: number = 2;
// Frames are stored per render identity (theme included), so keeping an older one
// does not crowd out the current theme — the only risk in showing one is a stale
// layout. That risk is preferred over a blank flash: the frame is cross-faded out
// within a few hundred milliseconds of the real page painting, and a homepage that
// edits its own layout has its frame refreshed while it is on screen. The TTL is
// therefore generous, so a theme the user has not used in weeks (or a system
// light/dark flip overnight) still has a cover instead of falling back to a flash.
export const CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_TTL_MS: number = 30 * 24 * 60 * 60 * 1000;
// How far the cover's shape may differ from the current viewport and still be
// shown. The frame is cropped to the surface's shape at capture time, so a frame
// stored for a different shape (notably a 90° orientation flip) would be drawn
// with the wrong crop and read as a jump the moment the live page replaces it.
// The tolerance leaves room for small measurement differences while rejecting an
// orientation change, whose aspect ratio differs by far more than this.
const CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_ASPECT_TOLERANCE: number = 0.12;

export class CustomHomepageLaunchSnapshotViewModel {
  buildMetadata(
    renderKey: string,
    themeMode: BrowserResolvedThemeMode,
    width: number,
    height: number,
    capturedAt: number
  ): CustomHomepageLaunchSnapshotMetadata {
    return {
      schemaVersion: CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_SCHEMA_VERSION,
      renderKey: renderKey.trim(),
      themeMode: themeMode === 'dark' ? 'dark' : 'light',
      width: Math.max(0, Math.floor(width)),
      height: Math.max(0, Math.floor(height)),
      capturedAt: Math.max(0, Math.floor(capturedAt))
    };
  }

  serializeMetadata(metadata: CustomHomepageLaunchSnapshotMetadata): string {
    return JSON.stringify(metadata);
  }

  parseMetadata(raw: string): CustomHomepageLaunchSnapshotMetadata | undefined {
    const trimmed = raw.trim();
    if (trimmed.length <= 0) {
      return undefined;
    }
    let parsed: CustomHomepageLaunchSnapshotMetadata;
    try {
      parsed = JSON.parse(trimmed) as CustomHomepageLaunchSnapshotMetadata;
    } catch (_error) {
      return undefined;
    }
    if (parsed === null || typeof parsed !== 'object') {
      return undefined;
    }
    if (parsed.schemaVersion !== CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_SCHEMA_VERSION) {
      return undefined;
    }
    if (typeof parsed.renderKey !== 'string' || parsed.renderKey.trim().length <= 0) {
      return undefined;
    }
    const capturedAt = Number(parsed.capturedAt);
    if (!Number.isFinite(capturedAt) || capturedAt <= 0) {
      return undefined;
    }
    return {
      schemaVersion: CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_SCHEMA_VERSION,
      renderKey: parsed.renderKey.trim(),
      themeMode: parsed.themeMode === 'dark' ? 'dark' : 'light',
      width: Math.max(0, Math.floor(Number(parsed.width) || 0)),
      height: Math.max(0, Math.floor(Number(parsed.height) || 0)),
      capturedAt: Math.floor(capturedAt)
    };
  }

  /**
   * A snapshot may only be shown when it was captured for the exact current
   * render identity and has not aged out. Any source, content, appearance, or
   * forced-dark change produces a different render key and rejects the old frame
   * instead of showing a stale layout.
   */
  isMetadataUsable(
    metadata: CustomHomepageLaunchSnapshotMetadata,
    currentRenderKey: string,
    nowMs: number
  ): boolean {
    const renderKey = currentRenderKey.trim();
    if (renderKey.length <= 0 || metadata.renderKey !== renderKey) {
      return false;
    }
    const ageMs = Math.max(0, nowMs) - metadata.capturedAt;
    if (!Number.isFinite(ageMs) || ageMs < 0) {
      return false;
    }
    return ageMs <= CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_TTL_MS;
  }

  // True when the stored frame has the same shape as the viewport it would be
  // shown in. Unknown dimensions count as usable: an older capture predates the
  // size fields, and refusing it would drop a cover that may still be correct.
  isAspectUsable(
    metadata: CustomHomepageLaunchSnapshotMetadata,
    viewportWidth: number,
    viewportHeight: number
  ): boolean {
    if (metadata.width <= 0 || metadata.height <= 0) {
      return true;
    }
    const viewportAspect = viewportWidth / viewportHeight;
    if (!Number.isFinite(viewportAspect) || viewportAspect <= 0) {
      return true;
    }
    const storedAspect = metadata.width / metadata.height;
    if (!Number.isFinite(storedAspect) || storedAspect <= 0) {
      return true;
    }
    return Math.abs(storedAspect - viewportAspect) / viewportAspect <=
      CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_ASPECT_TOLERANCE;
  }

  buildSnapshot(uri: string, metadata: CustomHomepageLaunchSnapshotMetadata): CustomHomepageLaunchSnapshot {
    return {
      uri: uri.trim(),
      width: metadata.width,
      height: metadata.height,
      renderKey: metadata.renderKey
    };
  }
}
