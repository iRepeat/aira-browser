import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { BrowserResolvedThemeMode } from '../../common/models/BrowserModels';
import {
  CustomHomepageLaunchSnapshot,
  CustomHomepageLaunchSnapshotMetadata,
  CustomHomepageLaunchSnapshotViewModel
} from '../../core/customhome/CustomHomepageLaunchSnapshotViewModel';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'CustomHomeSnapshot';
const CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_DIR_NAME: string = 'custom-homepage-launch';
const CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_FILE_PREFIX: string = 'cover-';
const CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_IMAGE_EXT: string = '.jpg';
const CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_METADATA_EXT: string = '.json';
const CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_QUALITY: number = 80;
const CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_BUFFER_SIZE: number = 8 * 1024 * 1024;
// Upper bound on how many render identities keep a stored frame at once. Covers
// both themes of a handful of homepages without letting repeated imports grow the
// directory; the least recently captured are dropped first.
const CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_MAX_IDENTITIES: number = 8;

interface CustomHomepageLaunchSnapshotPixelSize {
  width: number;
  height: number;
}

/**
 * Persists the last committed third-party homepage frame so a cold start can show
 * it during the document reload instead of a blank theme background.
 *
 * Frames are stored per render identity, not in a single slot. Light and dark are
 * different render keys, and so is a re-imported or replaced homepage, so a single
 * slot would mean switching the theme (or the system flipping it overnight)
 * destroyed the only cover available. Keying by render key keeps a valid frame for
 * each identity that has been seen, so toggling back and forth — or waking into a
 * theme the user last used days ago — still has the right picture.
 *
 * The metadata file is written last and is the commit point: a snapshot is only
 * readable once both its image and its metadata exist and validate. Writes and
 * reads never throw to the caller; a missing or corrupt snapshot simply means the
 * cover is unavailable.
 */
export class CustomHomepageLaunchSnapshotStore {
  private viewModel: CustomHomepageLaunchSnapshotViewModel = new CustomHomepageLaunchSnapshotViewModel();

  /**
   * Synchronous read for the very first presentation. The metadata file is tiny;
   * reading it here keeps the cover available in the first frame without waiting
   * on an async task that would already be too late.
   *
   * `viewportWidth`/`viewportHeight` reject a frame whose shape no longer matches
   * the screen, so a capture taken at a different orientation is never shown
   * stretched (which read as a jump at the live handoff).
   */
  loadSync(
    currentRenderKey: string,
    viewportWidth: number = 0,
    viewportHeight: number = 0,
    nowMs: number = Date.now()
  ): CustomHomepageLaunchSnapshot | undefined {
    const key = currentRenderKey.trim();
    if (key.length <= 0) {
      return undefined;
    }
    const imagePath = this.resolveImagePath(key);
    const metadataPath = this.resolveMetadataPath(key);
    try {
      if (!fileIo.accessSync(metadataPath) || !fileIo.accessSync(imagePath)) {
        return undefined;
      }
      const metadata = this.viewModel.parseMetadata(fileIo.readTextSync(metadataPath));
      if (metadata === undefined || !this.viewModel.isMetadataUsable(metadata, key, nowMs)) {
        hilog.info(LOG_DOMAIN, LOG_TAG,
          'launch snapshot rejected reason=stale-or-mismatch ageMs=%{public}d',
          metadata === undefined ? -1 : nowMs - metadata.capturedAt);
        // Only this identity's frame is dropped; other themes keep theirs.
        this.invalidate(key);
        return undefined;
      }
      if (!this.viewModel.isAspectUsable(metadata, viewportWidth, viewportHeight)) {
        // Skip showing it but keep the file: the shape only mismatches right now,
        // and the next capture overwrites it anyway. Deleting would also throw away
        // a frame that becomes usable again if the screen returns to that shape.
        hilog.info(LOG_DOMAIN, LOG_TAG,
          'launch snapshot skipped reason=aspect stored=%{public}dx%{public}d viewport=%{public}dx%{public}d',
          metadata.width, metadata.height, Math.round(viewportWidth), Math.round(viewportHeight));
        return undefined;
      }
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'launch snapshot loaded width=%{public}d height=%{public}d theme=%{public}s',
        metadata.width, metadata.height, metadata.themeMode);
      return this.viewModel.buildSnapshot(fileUri.getUriFromPath(imagePath), metadata);
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'launch snapshot load failed error=%{public}s', JSON.stringify(error));
      return undefined;
    }
  }

  async persist(
    pixelMap: image.PixelMap,
    renderKey: string,
    themeMode: BrowserResolvedThemeMode
  ): Promise<boolean> {
    const key = renderKey.trim();
    if (key.length <= 0) {
      return false;
    }
    const imagePath = this.resolveImagePath(key);
    const metadataPath = this.resolveMetadataPath(key);
    try {
      this.ensureDir();
      const size = this.resolvePixelMapSize(pixelMap);
      const packedData = await this.packImage(pixelMap);
      await this.writeBuffer(imagePath, packedData);
      const metadata = this.viewModel.buildMetadata(
        key,
        themeMode,
        size.width,
        size.height,
        Date.now()
      );
      await this.writeText(metadataPath, this.viewModel.serializeMetadata(metadata));
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'launch snapshot persisted renderKey=%{public}s theme=%{public}s width=%{public}d height=%{public}d bytes=%{public}d',
        key, metadata.themeMode, size.width, size.height, packedData.byteLength);
      await this.sweepExpiredFrames(key, metadata.capturedAt);
      return true;
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'launch snapshot persist failed error=%{public}s', JSON.stringify(error));
      return false;
    }
  }

  /** Drops the frame for one render identity. Other identities are untouched. */
  invalidate(renderKey: string): void {
    const key = renderKey.trim();
    if (key.length <= 0) {
      return;
    }
    this.removeIfPresent(this.resolveMetadataPath(key));
    this.removeIfPresent(this.resolveImagePath(key));
  }

  /** Drops every stored frame. */
  invalidateAll(): void {
    try {
      const names = fileIo.listFileSync(this.resolveDir());
      names.forEach((name: string): void => {
        if (this.isCoverFile(name)) {
          this.removeIfPresent(`${this.resolveDir()}/${name}`);
        }
      });
    } catch (_error) {
    }
  }

  private resolveDir(): string {
    return `${AppRuntimeContext.getApplicationContext().filesDir}/${CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_DIR_NAME}`;
  }

  private resolveImagePath(renderKey: string): string {
    return `${this.resolveDir()}/${this.buildFileStem(renderKey)}${CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_IMAGE_EXT}`;
  }

  private resolveMetadataPath(renderKey: string): string {
    return `${this.resolveDir()}/${this.buildFileStem(renderKey)}${CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_METADATA_EXT}`;
  }

  // FNV-1a over the render key, rendered as hex. Deterministic for a given identity
  // and filename-safe, so a frame can be found again by key without listing the
  // directory; the metadata still stores the full key so a collision would be
  // detected rather than shown.
  private buildFileStem(renderKey: string): string {
    let hash = 0x811c9dc5;
    for (let index = 0; index < renderKey.length; index += 1) {
      hash ^= renderKey.charCodeAt(index);
      hash = (hash * 0x01000193) >>> 0;
    }
    return `${CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_FILE_PREFIX}${hash.toString(16)}`;
  }

  private isCoverFile(fileName: string): boolean {
    return fileName.startsWith(CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_FILE_PREFIX) &&
      (fileName.endsWith(CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_IMAGE_EXT) ||
        fileName.endsWith(CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_METADATA_EXT));
  }

  // Bounds disk use: a frame past its TTL is removed, and when more identities have
  // been seen than the cap allows, the oldest ones are removed too — a user who
  // re-imports or switches homepages repeatedly must not grow this directory
  // without limit. Runs after the commit point so a sweep failure can never lose
  // the frame just written, and never touches the frame it was given.
  private async sweepExpiredFrames(currentRenderKey: string, nowMs: number): Promise<void> {
    const currentStem = this.buildFileStem(currentRenderKey);
    try {
      const names = await fileIo.listFile(this.resolveDir());
      const others: CustomHomepageLaunchSnapshotMetadata[] = [];
      for (let index = 0; index < names.length; index += 1) {
        const name = names[index];
        if (!name.endsWith(CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_METADATA_EXT) ||
          name.startsWith(currentStem)) {
          continue;
        }
        let metadata: CustomHomepageLaunchSnapshotMetadata | undefined = undefined;
        try {
          metadata = this.viewModel.parseMetadata(
            fileIo.readTextSync(`${this.resolveDir()}/${name}`)
          );
        } catch (_error) {
          continue;
        }
        if (metadata === undefined) {
          continue;
        }
        if (!this.viewModel.isMetadataUsable(metadata, metadata.renderKey, nowMs)) {
          this.invalidate(metadata.renderKey);
          continue;
        }
        others.push(metadata);
      }
      if (others.length < CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_MAX_IDENTITIES) {
        return;
      }
      others.sort((left: CustomHomepageLaunchSnapshotMetadata,
        right: CustomHomepageLaunchSnapshotMetadata): number => left.capturedAt - right.capturedAt);
      const excess = others.length - (CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_MAX_IDENTITIES - 1);
      for (let index = 0; index < excess; index += 1) {
        this.invalidate(others[index].renderKey);
      }
    } catch (_error) {
    }
  }

  private ensureDir(): void {
    const dir = this.resolveDir();
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true);
    }
  }

  private removeIfPresent(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (_error) {
    }
  }

  private resolvePixelMapSize(pixelMap: image.PixelMap): CustomHomepageLaunchSnapshotPixelSize {
    try {
      const imageInfo = pixelMap.getImageInfoSync();
      return {
        width: Math.max(1, Math.floor(imageInfo.size.width)),
        height: Math.max(1, Math.floor(imageInfo.size.height))
      };
    } catch (_error) {
      return { width: 0, height: 0 };
    }
  }

  private async packImage(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
    const packer = image.createImagePacker();
    try {
      return await packer.packToData(pixelMap, {
        format: 'image/jpeg',
        quality: CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_QUALITY,
        bufferSize: CUSTOM_HOMEPAGE_LAUNCH_SNAPSHOT_BUFFER_SIZE
      });
    } finally {
      try {
        await packer.release();
      } catch (_error) {
      }
    }
  }

  private async writeBuffer(path: string, data: ArrayBuffer): Promise<void> {
    const file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, data);
    } finally {
      await fileIo.close(file);
    }
  }

  private async writeText(path: string, text: string): Promise<void> {
    const file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, text);
    } finally {
      await fileIo.close(file);
    }
  }
}
