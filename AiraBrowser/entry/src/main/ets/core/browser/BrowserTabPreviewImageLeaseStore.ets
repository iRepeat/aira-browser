import { image } from '@kit.ImageKit';

interface BrowserTabPreviewImageLeaseEntry {
  count: number;
  releaseImage?: () => Promise<void>;
}

// Entry ownership ends at requestRelease; reader leases only delay disposal.
// ImageKit is used as a type only. Platform disposal is supplied by the owner.
export class BrowserTabPreviewImageLeaseStore {
  private readonly entries: WeakMap<image.PixelMap, BrowserTabPreviewImageLeaseEntry> = new WeakMap();
  private readonly releasedImages: WeakSet<image.PixelMap> = new WeakSet();

  retain(pixelMap: image.PixelMap): boolean {
    if (this.releasedImages.has(pixelMap)) {
      return false;
    }
    let entry = this.entries.get(pixelMap);
    if (entry === undefined) {
      entry = { count: 0 };
      this.entries.set(pixelMap, entry);
    }
    entry.count += 1;
    return true;
  }

  async requestRelease(pixelMap: image.PixelMap, releaseImage: () => Promise<void>): Promise<void> {
    if (this.releasedImages.has(pixelMap)) {
      return;
    }
    let entry = this.entries.get(pixelMap);
    if (entry === undefined) {
      entry = { count: 0 };
      this.entries.set(pixelMap, entry);
    }
    if (entry.releaseImage === undefined) {
      entry.releaseImage = releaseImage;
    }
    await this.releaseIfUnused(pixelMap, entry);
  }

  async releaseLease(pixelMap: image.PixelMap): Promise<void> {
    const entry = this.entries.get(pixelMap);
    if (entry === undefined || entry.count <= 0) {
      return;
    }
    entry.count -= 1;
    await this.releaseIfUnused(pixelMap, entry);
  }

  private async releaseIfUnused(pixelMap: image.PixelMap, entry: BrowserTabPreviewImageLeaseEntry): Promise<void> {
    if (entry.count > 0) {
      return;
    }
    this.entries.delete(pixelMap);
    const releaseImage = entry.releaseImage;
    if (releaseImage === undefined) {
      // The cache still owns the image; it can be leased again.
      return;
    }
    // Mark before invoking platform code, including reentrant or failing callbacks.
    this.releasedImages.add(pixelMap);
    try {
      await releaseImage();
    } catch (_error) {
      // Disposal is attempted once. The platform adapter owns error reporting.
    }
  }
}
