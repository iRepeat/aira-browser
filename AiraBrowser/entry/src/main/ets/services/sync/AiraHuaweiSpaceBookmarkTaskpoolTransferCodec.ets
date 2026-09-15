import { util } from '@kit.ArkTS';
import {
  AiraBookmarkHistoryDescriptor,
  AiraSyncSnapshot
} from '../../common/models/AiraSyncModels';

/**
 * Transfer framing for Huawei Space bookmark work that runs on TaskPool.
 *
 * Deliberately imports no relationalStore: this module is loaded inside the concurrent worker, and
 * only the pure codec half of a Huawei bookmark sync belongs there. The block codec
 * (`HuaweiSpaceBookmarkBlockCodec`) is constructed inside the worker by the executor, and the RDB
 * repository is never handed across the thread boundary.
 */

export interface HuaweiBookmarkProjectionRequest {
  storageEpoch: number;
  commitId: string;
  parentCommitIds: string[];
  snapshot: AiraSyncSnapshot;
  history: AiraBookmarkHistoryDescriptor;
  deviceId: string;
  generatedAt: string;
  updatedAt: number;
}

export interface HuaweiBookmarkBlockWire {
  id: string;
  encoded: string;
}

/**
 * What a write needs once the projection is built, without the parsed chunk/index/record graphs the
 * builder also produces. Kept narrow on purpose: it is both the TaskPool return shape and the shape
 * the RDB write consumes, so neither side has to reconstruct fields it never reads.
 */
export interface HuaweiBookmarkProjectionWire {
  commitId: string;
  storageEpoch: number;
  deviceId: string;
  updatedAt: number;
  manifestJson: string;
  chunks: HuaweiBookmarkBlockWire[];
  indexes: HuaweiBookmarkBlockWire[];
}

/**
 * A sink for projection work. The repository holds one when a TaskPool executor has been injected and
 * otherwise builds the projection itself, so an unavailable task pool degrades to the previous
 * behaviour instead of failing the write.
 */
export interface HuaweiBookmarkProjectionOffload {
  buildWriteProjection(request: HuaweiBookmarkProjectionRequest): Promise<HuaweiBookmarkProjectionWire>;
}

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

export class AiraHuaweiSpaceBookmarkTaskpoolTransferCodec {
  static encodeProjectionRequest(request: HuaweiBookmarkProjectionRequest): ArrayBuffer {
    return writeUtf8Buffer(JSON.stringify(request));
  }

  static decodeProjectionRequest(buffer: ArrayBuffer): HuaweiBookmarkProjectionRequest {
    const parsed = JSON.parse(readUtf8Buffer(buffer)) as HuaweiBookmarkProjectionRequest;
    if (parsed === null || parsed.snapshot === undefined || !Array.isArray(parsed.parentCommitIds)) {
      throw new Error('Huawei Bookmark TaskPool projection request is invalid.');
    }
    return parsed;
  }

  static encodeProjection(projection: HuaweiBookmarkProjectionWire): ArrayBuffer {
    return writeUtf8Buffer(JSON.stringify(projection));
  }

  static decodeProjection(buffer: ArrayBuffer): HuaweiBookmarkProjectionWire {
    const parsed = JSON.parse(readUtf8Buffer(buffer)) as HuaweiBookmarkProjectionWire;
    if (parsed === null || !Array.isArray(parsed.chunks) || !Array.isArray(parsed.indexes) ||
      typeof parsed.manifestJson !== 'string') {
      throw new Error('Huawei Bookmark TaskPool projection result is invalid.');
    }
    return parsed;
  }
}
