import { taskpool } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HuaweiSpaceBookmarkBlockCodec } from '../../data/sync/HuaweiSpaceBookmarkBlockCodec';
import {
  AiraHuaweiSpaceBookmarkTaskpoolTransferCodec,
  HuaweiBookmarkProjectionOffload,
  HuaweiBookmarkProjectionRequest,
  HuaweiBookmarkProjectionWire
} from './AiraHuaweiSpaceBookmarkTaskpoolTransferCodec';

const HUAWEI_BOOKMARK_COMPUTE_LOG_DOMAIN: number = 0x0000;
const HUAWEI_BOOKMARK_COMPUTE_LOG_TAG: string = 'AiraHuaweiSpace';

// Same bound the History TaskPool path uses: the transfer list moves ownership rather than copying,
// so this guards memory pressure, not serialization. A bookmark projection is far smaller than a
// History mirror; the bound exists so a pathological snapshot degrades to the cooperative path
// instead of attempting an oversized transfer.
const AIRA_HUAWEI_BOOKMARK_TASKPOOL_BUDGET_BYTES: number = 16 * 1024 * 1024;

interface HuaweiBookmarkProjectionPackedOutcome {
  projectionBuffer: ArrayBuffer;
  errorMessage: string;
}

/**
 * Builds the G8 bookmark write projection (canonical records, lane/segment chunking, per-chunk
 * SHA-256, index shards and the manifest) off the ArkTS main thread.
 *
 * This is pure computation. It loads only `HuaweiSpaceBookmarkBlockCodec`, which holds no store
 * handle, so nothing RDB-bound enters the worker's load graph; the caller keeps the dependent RDB
 * work on the main thread (storage epoch resolution, existence probe, batch insert).
 *
 * Errors are returned rather than thrown so the caller can fall back to the on-thread builder.
 */
@Concurrent
function buildHuaweiBookmarkProjectionPacked(
  requestBuffer: ArrayBuffer
): HuaweiBookmarkProjectionPackedOutcome {
  try {
    const request = AiraHuaweiSpaceBookmarkTaskpoolTransferCodec.decodeProjectionRequest(requestBuffer);
    const projection = new HuaweiSpaceBookmarkBlockCodec().buildWriteProjection(request);
    return {
      projectionBuffer: AiraHuaweiSpaceBookmarkTaskpoolTransferCodec.encodeProjection(projection),
      errorMessage: ''
    };
  } catch (error) {
    const candidate = error as Error;
    return {
      projectionBuffer: new ArrayBuffer(0),
      errorMessage: candidate.message ?? JSON.stringify(error)
    };
  }
}

export class AiraHuaweiSpaceBookmarkComputeExecutor implements HuaweiBookmarkProjectionOffload {
  async buildWriteProjection(request: HuaweiBookmarkProjectionRequest): Promise<HuaweiBookmarkProjectionWire> {
    const requestBuffer = AiraHuaweiSpaceBookmarkTaskpoolTransferCodec.encodeProjectionRequest(request);
    if (requestBuffer.byteLength > AIRA_HUAWEI_BOOKMARK_TASKPOOL_BUDGET_BYTES) {
      throw new Error(
        `Huawei Bookmark TaskPool request exceeds the transfer budget: ${requestBuffer.byteLength}`
      );
    }
    const task = new taskpool.Task(
      'aira-huawei-bookmark-write-projection',
      buildHuaweiBookmarkProjectionPacked,
      requestBuffer
    );
    task.setTransferList([requestBuffer]);
    const outcome = await taskpool.execute(task, taskpool.Priority.LOW) as HuaweiBookmarkProjectionPackedOutcome;
    if (outcome === undefined || outcome.errorMessage.length > 0) {
      throw new Error(
        outcome === undefined ? 'Huawei Bookmark TaskPool job returned no outcome.' : outcome.errorMessage
      );
    }
    const projection = AiraHuaweiSpaceBookmarkTaskpoolTransferCodec.decodeProjection(outcome.projectionBuffer);
    hilog.info(
      HUAWEI_BOOKMARK_COMPUTE_LOG_DOMAIN,
      HUAWEI_BOOKMARK_COMPUTE_LOG_TAG,
      'G8 write projection built on TaskPool requestBytes=%{public}d chunks=%{public}d indexes=%{public}d',
      requestBuffer.byteLength,
      projection.chunks.length,
      projection.indexes.length
    );
    return projection;
  }
}
