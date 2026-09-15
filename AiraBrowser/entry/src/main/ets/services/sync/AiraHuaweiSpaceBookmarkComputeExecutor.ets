import { taskpool } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AiraSyncJankProbe } from '../../common/debug/AiraSyncJankProbe';
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
  // Time spent inside the worker building the projection, i.e. exactly the work that used to occupy
  // the caller's thread. Reported back so one log line shows the before/after without needing a
  // fallback run to measure the other half.
  computeMs: number;
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
    const computeStartedAt = Date.now();
    const projection = new HuaweiSpaceBookmarkBlockCodec().buildWriteProjection(request);
    const computeMs = Date.now() - computeStartedAt;
    return {
      projectionBuffer: AiraHuaweiSpaceBookmarkTaskpoolTransferCodec.encodeProjection(projection),
      computeMs,
      errorMessage: ''
    };
  } catch (error) {
    const candidate = error as Error;
    return {
      projectionBuffer: new ArrayBuffer(0),
      computeMs: 0,
      errorMessage: candidate.message ?? JSON.stringify(error)
    };
  }
}

export class AiraHuaweiSpaceBookmarkComputeExecutor implements HuaweiBookmarkProjectionOffload {
  async buildWriteProjection(request: HuaweiBookmarkProjectionRequest): Promise<HuaweiBookmarkProjectionWire> {
    const startedAt = Date.now();
    const encodeStartedAt = Date.now();
    const requestBuffer = AiraHuaweiSpaceBookmarkTaskpoolTransferCodec.encodeProjectionRequest(request);
    const encodeMs = Date.now() - encodeStartedAt;
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
    const decodeStartedAt = Date.now();
    const projection = AiraHuaweiSpaceBookmarkTaskpoolTransferCodec.decodeProjection(outcome.projectionBuffer);
    const decodeMs = Date.now() - decodeStartedAt;
    // Only the encode and the decode still occupy the caller's thread; the projection itself
    // (computeMs) no longer does. Those two numbers are the before/after for this stage, so they are
    // reported together with the same field names as the on-thread path logs.
    const mainThreadMs = encodeMs + decodeMs;
    AiraSyncJankProbe.endExtra(
      'huawei_bookmark_projection',
      startedAt,
      `path=taskpool computeMs=${outcome.computeMs} mainThreadMs=${mainThreadMs}` +
        ` requestBytes=${requestBuffer.byteLength} chunks=${projection.chunks.length}` +
        ` indexes=${projection.indexes.length}`
    );
    hilog.info(
      HUAWEI_BOOKMARK_COMPUTE_LOG_DOMAIN,
      HUAWEI_BOOKMARK_COMPUTE_LOG_TAG,
      'G8 projection path=taskpool encodeMs=%{public}d computeMs=%{public}d decodeMs=%{public}d' +
        ' mainThreadMs=%{public}d wallMs=%{public}d requestBytes=%{public}d chunks=%{public}d indexes=%{public}d',
      encodeMs,
      outcome.computeMs,
      decodeMs,
      mainThreadMs,
      Date.now() - startedAt,
      requestBuffer.byteLength,
      projection.chunks.length,
      projection.indexes.length
    );
    return projection;
  }
}
