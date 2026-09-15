import { taskpool } from '@kit.ArkTS';
import { BookmarkNode } from '../../common/models/BrowserModels';
import {
  AiraBookmarkConflictResolution,
  AiraSyncSnapshot
} from '../../common/models/AiraSyncModels';
import { AiraSyncJankProbe } from '../../common/debug/AiraSyncJankProbe';
import {
  AiraBookmarkMergeDeletionPolicy,
  AiraBookmarkMergeResult,
  AiraBookmarkMergeService
} from './AiraBookmarkMergeService';
import {
  AiraBookmarkSnapshotCompute,
  AiraBookmarkSnapshotComputeResult
} from './AiraBookmarkSnapshotCompute';
import {
  AiraBookmarkTaskpoolTransferCodec,
  estimateBookmarkNodesTransferBytes,
  estimateBookmarkSnapshotTransferBytes
} from './AiraBookmarkTaskpoolTransferCodec';
import { AiraSyncWorkThrottleService } from './AiraSyncWorkThrottleService';

const AIRA_BOOKMARK_TASKPOOL_TRANSFER_BUDGET_BYTES: number = 16 * 1024 * 1024;
const AIRA_BOOKMARK_TASKPOOL_PACK_PREFLIGHT_BUDGET_BYTES: number = 16 * 1024 * 1024;

interface AiraBookmarkMergePackedOutcome {
  resultBuffer: ArrayBuffer;
  errorMessage: string;
}

interface AiraBookmarkSnapshotPackedOutcome {
  snapshotBuffer: ArrayBuffer;
  originRepairBuffer: ArrayBuffer;
  errorMessage: string;
}

@Concurrent
function mergeBookmarksPacked(
  baselineBuffer: ArrayBuffer,
  localBuffer: ArrayBuffer,
  remoteBuffer: ArrayBuffer,
  deviceId: string,
  resolution: string,
  deletionPolicy: string
): AiraBookmarkMergePackedOutcome {
  try {
    const baseline = AiraBookmarkTaskpoolTransferCodec.decodeOptionalSnapshot(baselineBuffer);
    const local = AiraBookmarkTaskpoolTransferCodec.decodeSnapshot(localBuffer);
    const remote = AiraBookmarkTaskpoolTransferCodec.decodeOptionalSnapshot(remoteBuffer);
    const mergeService = new AiraBookmarkMergeService();
    const result = mergeService.merge(
      baseline,
      local,
      remote,
      deviceId,
      resolution.length > 0 ? resolution as AiraBookmarkConflictResolution : undefined,
      deletionPolicy as AiraBookmarkMergeDeletionPolicy
    );
    return {
      resultBuffer: AiraBookmarkTaskpoolTransferCodec.encodeMergeResult(result),
      errorMessage: ''
    };
  } catch (error) {
    const candidate = error as Error;
    return {
      resultBuffer: new ArrayBuffer(0),
      errorMessage: candidate.message ?? JSON.stringify(error)
    };
  }
}

@Concurrent
function buildBookmarkSnapshotPacked(
  regularBuffer: ArrayBuffer,
  privateBuffer: ArrayBuffer,
  previousBuffer: ArrayBuffer,
  deviceId: string,
  generatedAt: string
): AiraBookmarkSnapshotPackedOutcome {
  try {
    const regularNodes = AiraBookmarkTaskpoolTransferCodec.decodeNodes(regularBuffer);
    const privateNodes = AiraBookmarkTaskpoolTransferCodec.decodeNodes(privateBuffer);
    const previousSnapshot = AiraBookmarkTaskpoolTransferCodec.decodeOptionalSnapshot(previousBuffer);
    const computed = new AiraBookmarkSnapshotCompute().buildFreshSnapshot(
      regularNodes,
      privateNodes,
      deviceId,
      generatedAt,
      previousSnapshot
    );
    return {
      snapshotBuffer: AiraBookmarkTaskpoolTransferCodec.encodeSnapshot(computed.snapshot),
      originRepairBuffer: AiraBookmarkTaskpoolTransferCodec.encodeOriginRepairs(computed.originRepairs),
      errorMessage: ''
    };
  } catch (error) {
    const candidate = error as Error;
    return {
      snapshotBuffer: new ArrayBuffer(0),
      originRepairBuffer: new ArrayBuffer(0),
      errorMessage: candidate.message ?? JSON.stringify(error)
    };
  }
}

function fitsTaskpoolTransferBudget(estimatedBytes: number): boolean {
  return estimatedBytes > 0 && estimatedBytes <= AIRA_BOOKMARK_TASKPOOL_TRANSFER_BUDGET_BYTES;
}

function fitsTaskpoolPackPreflightBudget(estimatedBytes: number): boolean {
  return estimatedBytes > 0 && estimatedBytes <= AIRA_BOOKMARK_TASKPOOL_PACK_PREFLIGHT_BUDGET_BYTES;
}

export class AiraBookmarkComputeExecutor {
  private readonly mergeService: AiraBookmarkMergeService = new AiraBookmarkMergeService();
  private readonly cooperativeThrottle: AiraSyncWorkThrottleService = new AiraSyncWorkThrottleService();

  async mergeCooperatively(
    baseline: AiraSyncSnapshot | null,
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot | null,
    throttle: AiraSyncWorkThrottleService,
    deviceId: string = local.meta.deviceId,
    resolution?: AiraBookmarkConflictResolution,
    deletionPolicy: AiraBookmarkMergeDeletionPolicy = 'propagate'
  ): Promise<AiraBookmarkMergeResult> {
    const estimatedBytes = estimateBookmarkSnapshotTransferBytes(baseline) +
      estimateBookmarkSnapshotTransferBytes(local) +
      estimateBookmarkSnapshotTransferBytes(remote);
    if (!fitsTaskpoolPackPreflightBudget(estimatedBytes) && estimatedBytes > 0) {
      AiraSyncJankProbe.mark('bookmark_merge_fallback_budget');
      return this.mergeService.mergeCooperatively(
        baseline,
        local,
        remote,
        throttle,
        deviceId,
        resolution,
        deletionPolicy
      );
    }
    const packStartedAt = Date.now();
    const baselineBuffer = AiraBookmarkTaskpoolTransferCodec.encodeOptionalSnapshot(baseline);
    const localBuffer = AiraBookmarkTaskpoolTransferCodec.encodeSnapshot(local);
    const remoteBuffer = AiraBookmarkTaskpoolTransferCodec.encodeOptionalSnapshot(remote);
    const transferBytes = baselineBuffer.byteLength + localBuffer.byteLength + remoteBuffer.byteLength;
    AiraSyncJankProbe.endExtra(
      'bookmark_merge_pack',
      packStartedAt,
      `bytes=${transferBytes} folders=${local.bookmarkFolders.length} items=${local.bookmarkItems.length}`
    );
    await throttle.afterStage();
    if (!fitsTaskpoolTransferBudget(transferBytes)) {
      AiraSyncJankProbe.mark('bookmark_merge_fallback_budget');
      return this.mergeService.mergeCooperatively(
        baseline,
        local,
        remote,
        throttle,
        deviceId,
        resolution,
        deletionPolicy
      );
    }
    const task = new taskpool.Task(
      'aira-sync-bookmark-merge-packed',
      mergeBookmarksPacked,
      baselineBuffer,
      localBuffer,
      remoteBuffer,
      deviceId,
      resolution ?? '',
      deletionPolicy
    );
    task.setTransferList([baselineBuffer, localBuffer, remoteBuffer]);
    const taskStartedAt = Date.now();
    let outcome: AiraBookmarkMergePackedOutcome;
    try {
      outcome = await taskpool.execute(task, taskpool.Priority.LOW) as AiraBookmarkMergePackedOutcome;
    } catch (_error) {
      AiraSyncJankProbe.endExtra('bookmark_merge_taskpool', taskStartedAt, 'error=throw');
      return this.mergeService.mergeCooperatively(
        baseline,
        local,
        remote,
        throttle,
        deviceId,
        resolution,
        deletionPolicy
      );
    }
    AiraSyncJankProbe.endExtra(
      'bookmark_merge_taskpool',
      taskStartedAt,
      `error=${outcome.errorMessage.length > 0 ? 1 : 0}`
    );
    if (outcome.errorMessage.length > 0) {
      AiraSyncJankProbe.markExtra('bookmark_merge_fallback_cooperative', outcome.errorMessage);
      return this.mergeService.mergeCooperatively(
        baseline,
        local,
        remote,
        throttle,
        deviceId,
        resolution,
        deletionPolicy
      );
    }
    const unpackStartedAt = Date.now();
    const result = AiraBookmarkTaskpoolTransferCodec.decodeMergeResult(outcome.resultBuffer);
    AiraSyncJankProbe.endExtra(
      'bookmark_merge_unpack',
      unpackStartedAt,
      `apply=${result.localApplyRequired ? 1 : 0} write=${result.remoteWriteRequired ? 1 : 0} conflicts=${result.conflictCount}`
    );
    await throttle.afterStage();
    return result;
  }

  async buildFreshSnapshot(
    regularNodes: BookmarkNode[],
    privateNodes: BookmarkNode[],
    deviceId: string,
    previousSnapshot?: AiraSyncSnapshot | null
  ): Promise<AiraBookmarkSnapshotComputeResult | undefined> {
    const generatedAt = new Date().toISOString();
    const estimatedBytes = estimateBookmarkNodesTransferBytes(regularNodes) +
      estimateBookmarkNodesTransferBytes(privateNodes) +
      estimateBookmarkSnapshotTransferBytes(previousSnapshot ?? null);
    if (!fitsTaskpoolPackPreflightBudget(estimatedBytes) && estimatedBytes > 0) {
      AiraSyncJankProbe.mark('bookmark_snapshot_fallback_budget');
      return undefined;
    }
    const packStartedAt = Date.now();
    const regularBuffer = AiraBookmarkTaskpoolTransferCodec.encodeNodes(regularNodes);
    const privateBuffer = AiraBookmarkTaskpoolTransferCodec.encodeNodes(privateNodes);
    const previousBuffer = AiraBookmarkTaskpoolTransferCodec.encodeOptionalSnapshot(previousSnapshot ?? null);
    const transferBytes = regularBuffer.byteLength + privateBuffer.byteLength + previousBuffer.byteLength;
    AiraSyncJankProbe.endExtra(
      'bookmark_snapshot_pack',
      packStartedAt,
      `bytes=${transferBytes} regular=${regularNodes.length} private=${privateNodes.length}`
    );
    await this.cooperativeThrottle.afterStage();
    if (!fitsTaskpoolTransferBudget(transferBytes)) {
      AiraSyncJankProbe.mark('bookmark_snapshot_fallback_budget');
      return undefined;
    }
    const task = new taskpool.Task(
      'aira-sync-bookmark-snapshot-packed',
      buildBookmarkSnapshotPacked,
      regularBuffer,
      privateBuffer,
      previousBuffer,
      deviceId,
      generatedAt
    );
    task.setTransferList([regularBuffer, privateBuffer, previousBuffer]);
    const taskStartedAt = Date.now();
    let outcome: AiraBookmarkSnapshotPackedOutcome;
    try {
      outcome = await taskpool.execute(task, taskpool.Priority.LOW) as AiraBookmarkSnapshotPackedOutcome;
    } catch (_error) {
      AiraSyncJankProbe.endExtra('bookmark_snapshot_taskpool', taskStartedAt, 'error=throw');
      return undefined;
    }
    AiraSyncJankProbe.endExtra(
      'bookmark_snapshot_taskpool',
      taskStartedAt,
      `error=${outcome.errorMessage.length > 0 ? 1 : 0}`
    );
    if (outcome.errorMessage.length > 0) {
      AiraSyncJankProbe.markExtra('bookmark_snapshot_fallback_cooperative', outcome.errorMessage);
      return undefined;
    }
    const unpackStartedAt = Date.now();
    const snapshot = AiraBookmarkTaskpoolTransferCodec.decodeSnapshot(outcome.snapshotBuffer);
    const originRepairs = AiraBookmarkTaskpoolTransferCodec.decodeOriginRepairs(outcome.originRepairBuffer);
    AiraSyncJankProbe.endExtra(
      'bookmark_snapshot_unpack',
      unpackStartedAt,
      `folders=${snapshot.bookmarkFolders.length} items=${snapshot.bookmarkItems.length} repairs=${originRepairs.length}`
    );
    await this.cooperativeThrottle.afterStage();
    return {
      snapshot: snapshot,
      originRepairs: originRepairs
    };
  }
}
