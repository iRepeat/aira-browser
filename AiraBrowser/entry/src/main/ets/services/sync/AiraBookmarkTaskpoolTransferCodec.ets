import { BookmarkNode } from '../../common/models/BrowserModels';
import { AiraSyncSnapshot } from '../../common/models/AiraSyncModels';
import { util } from '@kit.ArkTS';
import { AiraBookmarkMergeResult } from './AiraBookmarkMergeService';

function writeUtf8Buffer(value: string): ArrayBuffer {
  const encoder = util.TextEncoder.create('utf-8');
  const bytes = encoder.encodeInto(value);
  const packed = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(packed).set(bytes);
  return packed;
}

function readUtf8Buffer(buffer: ArrayBuffer): string {
  const decoder = util.TextDecoder.create('utf-8');
  return decoder.decodeToString(new Uint8Array(buffer));
}

export class AiraBookmarkTaskpoolTransferCodec {
  static encodeSnapshot(snapshot: AiraSyncSnapshot): ArrayBuffer {
    return writeUtf8Buffer(JSON.stringify(snapshot));
  }

  static decodeSnapshot(snapshotBuffer: ArrayBuffer): AiraSyncSnapshot {
    const parsed = JSON.parse(readUtf8Buffer(snapshotBuffer)) as AiraSyncSnapshot;
    if (!Array.isArray(parsed.bookmarkFolders) || !Array.isArray(parsed.bookmarkItems) ||
      !Array.isArray(parsed.bookmarkOrders) || !Array.isArray(parsed.tombstones)) {
      throw new Error('Bookmark TaskPool snapshot is invalid.');
    }
    return parsed;
  }

  static encodeOptionalSnapshot(snapshot: AiraSyncSnapshot | null): ArrayBuffer {
    if (snapshot === null) {
      return new ArrayBuffer(0);
    }
    return AiraBookmarkTaskpoolTransferCodec.encodeSnapshot(snapshot);
  }

  static decodeOptionalSnapshot(snapshotBuffer: ArrayBuffer): AiraSyncSnapshot | null {
    if (snapshotBuffer.byteLength === 0) {
      return null;
    }
    return AiraBookmarkTaskpoolTransferCodec.decodeSnapshot(snapshotBuffer);
  }

  static encodeNodes(nodes: BookmarkNode[]): ArrayBuffer {
    return writeUtf8Buffer(JSON.stringify(nodes));
  }

  static decodeNodes(nodeBuffer: ArrayBuffer): BookmarkNode[] {
    const parsed = JSON.parse(readUtf8Buffer(nodeBuffer)) as BookmarkNode[];
    if (!Array.isArray(parsed)) {
      throw new Error('Bookmark TaskPool node payload is invalid.');
    }
    return parsed;
  }

  static encodeMergeResult(result: AiraBookmarkMergeResult): ArrayBuffer {
    return writeUtf8Buffer(JSON.stringify(result));
  }

  static decodeMergeResult(resultBuffer: ArrayBuffer): AiraBookmarkMergeResult {
    const parsed = JSON.parse(readUtf8Buffer(resultBuffer)) as AiraBookmarkMergeResult;
    if (parsed.snapshot === undefined || !Array.isArray(parsed.conflictDetails)) {
      throw new Error('Bookmark TaskPool merge result is invalid.');
    }
    return parsed;
  }

  static encodeOriginRepairs(nodes: BookmarkNode[]): ArrayBuffer {
    return AiraBookmarkTaskpoolTransferCodec.encodeNodes(nodes);
  }

  static decodeOriginRepairs(nodeBuffer: ArrayBuffer): BookmarkNode[] {
    if (nodeBuffer.byteLength === 0) {
      return [];
    }
    return AiraBookmarkTaskpoolTransferCodec.decodeNodes(nodeBuffer);
  }

  static copyBuffer(buffer: ArrayBuffer): ArrayBuffer {
    const copy = new ArrayBuffer(buffer.byteLength);
    new Uint8Array(copy).set(new Uint8Array(buffer));
    return copy;
  }
}

export function estimateTransferStringBytes(value: string | undefined): number {
  if (value === undefined || value.length === 0) {
    return 0;
  }
  return value.length * 3 + 8;
}

export function estimateBookmarkSnapshotTransferBytes(snapshot: AiraSyncSnapshot | null): number {
  if (snapshot === null) {
    return 0;
  }
  let total = 256 + estimateTransferStringBytes(snapshot.meta.deviceId) +
    estimateTransferStringBytes(snapshot.meta.generatedAt);
  snapshot.bookmarkFolders.forEach((folder): void => {
    total += 96 + estimateTransferStringBytes(folder.id) + estimateTransferStringBytes(folder.title) +
      estimateTransferStringBytes(folder.parentId ?? '') + estimateTransferStringBytes(folder.updatedBy);
  });
  snapshot.bookmarkItems.forEach((item): void => {
    total += 128 + estimateTransferStringBytes(item.id) + estimateTransferStringBytes(item.title) +
      estimateTransferStringBytes(item.url) + estimateTransferStringBytes(item.parentId ?? '') +
      estimateTransferStringBytes(item.updatedBy);
  });
  snapshot.bookmarkOrders.forEach((order): void => {
    total += 64 + estimateTransferStringBytes(order.parentId ?? '') + estimateTransferStringBytes(order.updatedBy);
    order.ids.forEach((id: string): void => {
      total += estimateTransferStringBytes(id);
    });
  });
  snapshot.tombstones.forEach((tombstone): void => {
    total += 64 + estimateTransferStringBytes(tombstone.id) + estimateTransferStringBytes(tombstone.deletedBy);
  });
  if (snapshot.appPrivateBookmarks !== undefined) {
    total += estimateBookmarkSnapshotTransferBytes({
      meta: snapshot.meta,
      bookmarkFolders: snapshot.appPrivateBookmarks.bookmarkFolders,
      bookmarkItems: snapshot.appPrivateBookmarks.bookmarkItems,
      bookmarkOrders: snapshot.appPrivateBookmarks.bookmarkOrders,
      tombstones: snapshot.appPrivateBookmarks.tombstones
    });
  }
  return total;
}

export function estimateBookmarkNodesTransferBytes(nodes: BookmarkNode[]): number {
  let total = 64;
  nodes.forEach((node: BookmarkNode): void => {
    total += 160 +
      estimateTransferStringBytes(node.id) +
      estimateTransferStringBytes(node.title) +
      estimateTransferStringBytes(node.url) +
      estimateTransferStringBytes(node.parentId) +
      estimateTransferStringBytes(node.scope) +
      estimateTransferStringBytes(node.sync.lastModifiedBy) +
      estimateTransferStringBytes(node.sync.deviceId) +
      estimateTransferStringBytes(node.sync.originId) +
      estimateTransferStringBytes(node.sync.source) +
      estimateTransferStringBytes(node.sync.state);
  });
  return total;
}
