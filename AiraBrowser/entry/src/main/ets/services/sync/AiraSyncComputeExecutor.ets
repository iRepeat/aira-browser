import { taskpool, util } from '@kit.ArkTS';
import {
  HuaweiSpaceHistorySyncState
} from '../../common/models/HistorySyncModels';
import {
  HuaweiSpaceHistoryPhysicalMirror,
  HuaweiSpaceHistoryRow,
  HuaweiSpaceHistorySnapshotCodec
} from '../../data/sync/HuaweiSpaceHistorySnapshotCodec';
import { HistorySyncMergeService } from './HistorySyncMergeService';
import {
  AiraHistoryRemoteWriteProjection,
  AiraHistoryTaskpoolTransferCodec
} from './AiraHistoryTaskpoolTransferCodec';
import { AiraSyncWorkThrottleService } from './AiraSyncWorkThrottleService';
import { AiraSyncJankProbe } from '../../common/debug/AiraSyncJankProbe';

// Soft guard on how much we hand to a task: ArrayBuffers in the transfer list
// move ownership instead of being copied, so this is a memory-pressure bound,
// not a serialization limit. A Huawei History snapshot runs ~7 MB of rows today
// and this device's mirror plus its merged state already reached 8.4 MB, so an
// 8 MB bound kept tipping real syncs onto the cooperative path, which decodes on
// the UI thread and turns a ~6 s job into a ~140 s one. Keep it aligned with the
// pack preflight below; exceeding the true platform limit surfaces as a
// serialization error, which the callers already catch and retry cooperatively.
//
// The bound has now been crossed twice by growth alone (8 MB, then 16 MB at 13 MB
// of rows). A device measured on 2026-09-15 packed 13 MB of rows plus a 5.6 MB
// merged state -- 18.9 MB -- so every pass fell to the UI thread and one manual
// sync spent 137 s in the initial merge and another 172 s in the write plan.
// 13 MB row transfers are known to succeed, so the practical limit is above the
// old bound; raising it to 24 MB clears the measured payload while staying close
// enough that the catch-and-retry-cooperatively path still covers a genuine
// platform rejection. The durable answer is a size-independent transfer (chunked
// buffers) rather than another round of raising this number.
const AIRA_SYNC_TASKPOOL_TRANSFER_BUDGET_BYTES: number = 24 * 1024 * 1024;
// Kept equal to the transfer bound: a preflight stricter than the transfer would reject a payload
// the transfer would have accepted, which is the same cliff one gate earlier.
const AIRA_SYNC_TASKPOOL_PACK_PREFLIGHT_BUDGET_BYTES: number = 24 * 1024 * 1024;

export interface AiraHistoryInitialMergePlan {
  merged: HuaweiSpaceHistorySyncState;
  localApplyRequired: boolean;
  remoteWriteRequired: boolean;
}

export interface AiraHistoryRemoteStateDecode {
  state: HuaweiSpaceHistorySyncState;
  legacyRowIds: string[];
}

export interface AiraHistoryRemoteWritePlan {
  projection: AiraHistoryRemoteWriteProjection;
}

export interface AiraHistoryRemoteWriteConfirmation {
  confirmed: HuaweiSpaceHistorySyncState;
  projectionConfirmed: boolean;
  desiredStateConfirmed: boolean;
  localApplyRequired: boolean;
}

interface AiraHistoryRemoteStateDecodeOutcome {
  decoded?: AiraHistoryRemoteStateDecode;
  errorMessage: string;
}

interface AiraHistoryRemoteWritePlanOutcome {
  plan?: AiraHistoryRemoteWritePlan;
  decodeErrorMessage: string;
  computeErrorMessage: string;
}

interface AiraHistoryRemoteWriteConfirmationOutcome {
  confirmation?: AiraHistoryRemoteWriteConfirmation;
  decodeErrorMessage: string;
  computeErrorMessage: string;
}

export class AiraHistoryMirrorDecodeError extends Error {
}

@Concurrent
function decodeHuaweiHistoryRemoteState(
  uid: string,
  deviceId: string,
  rowBuffer: ArrayBuffer,
  now: number
): AiraHistoryRemoteStateDecodeOutcome {
  try {
    const rows = AiraHistoryTaskpoolTransferCodec.decodeRows(rowBuffer);
    const mirror = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId).decodeRows(rows, now);
    return {
      decoded: {
        state: mirror.state,
        legacyRowIds: mirror.legacyRowIds
      },
      errorMessage: ''
    };
  } catch (error) {
    const candidate = error as Error;
    return {
      errorMessage: candidate.message ?? JSON.stringify(error)
    };
  }
}


export interface HuaweiHistoryReplicaPackedOutcome {
  localApplyRequired: boolean;
  remoteWriteRequired: boolean;
  mergedBuffer: ArrayBuffer;
  projection: AiraHistoryRemoteWriteProjection;
  errorMessage: string;
}

interface AiraHistoryReplicaLitePackedOutcome {
  projection?: AiraHistoryRemoteWriteProjection;
  errorMessage: string;
}

@Concurrent
function planHuaweiHistoryReplicaLitePacked(
  uid: string,
  deviceId: string,
  rowBuffer: ArrayBuffer,
  localBuffer: ArrayBuffer,
  dirtyBucketIndexes: number[],
  now: number
): AiraHistoryReplicaLitePackedOutcome {
  try {
    const rows = AiraHistoryTaskpoolTransferCodec.decodeRows(rowBuffer);
    const local = AiraHistoryTaskpoolTransferCodec.decodeState(localBuffer);
    const projection = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .buildProjectionReusingHead(local, rows, dirtyBucketIndexes, now);
    return {
      projection: AiraHistoryTaskpoolTransferCodec.leanProjection(projection),
      errorMessage: ''
    };
  } catch (error) {
    const candidate = error as Error;
    return {
      errorMessage: candidate.message ?? JSON.stringify(error)
    };
  }
}


interface AiraHistoryInitialMergePackedOutcome {
  localApplyRequired: boolean;
  remoteWriteRequired: boolean;
  mergedBuffer: ArrayBuffer;
  errorMessage: string;
}

@Concurrent
function planHuaweiHistoryInitialMergePacked(
  remoteBuffer: ArrayBuffer,
  localBuffer: ArrayBuffer,
  now: number
): AiraHistoryInitialMergePackedOutcome {
  try {
    const remote = AiraHistoryTaskpoolTransferCodec.decodeState(remoteBuffer);
    const local = AiraHistoryTaskpoolTransferCodec.decodeState(localBuffer);
    const mergeService = new HistorySyncMergeService();
    const merged = mergeService.mergeKeepingPreferredVisits(remote, local, now);
    const localApplyRequired = !mergeService.sameState(merged, local);
    const remoteWriteRequired = !mergeService.sameState(merged, remote);
    if (!localApplyRequired && !remoteWriteRequired) {
      return {
        localApplyRequired: false,
        remoteWriteRequired: false,
        mergedBuffer: new ArrayBuffer(0),
        errorMessage: ''
      };
    }
    return {
      localApplyRequired: localApplyRequired,
      remoteWriteRequired: remoteWriteRequired,
      mergedBuffer: AiraHistoryTaskpoolTransferCodec.encodeState(merged),
      errorMessage: ''
    };
  } catch (error) {
    const candidate = error as Error;
    return {
      localApplyRequired: false,
      remoteWriteRequired: false,
      mergedBuffer: new ArrayBuffer(0),
      errorMessage: candidate.message ?? JSON.stringify(error)
    };
  }
}


@Concurrent
function planHuaweiHistoryReplicaPacked(
  uid: string,
  deviceId: string,
  rowBuffer: ArrayBuffer,
  localBuffer: ArrayBuffer,
  now: number
): HuaweiHistoryReplicaPackedOutcome {
  try {
    const current = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .decodeRows(AiraHistoryTaskpoolTransferCodec.decodeRows(rowBuffer), now);
    const local = AiraHistoryTaskpoolTransferCodec.decodeState(localBuffer);
    const mergeService = new HistorySyncMergeService();
    const merged = mergeService.mergeKeepingPreferredVisits(current.state, local, now);
    const localApplyRequired = !mergeService.sameState(merged, local);
    const remoteWriteRequired = !mergeService.sameState(merged, current.state);
    if (!localApplyRequired && !remoteWriteRequired) {
      return {
        localApplyRequired: false,
        remoteWriteRequired: false,
        mergedBuffer: new ArrayBuffer(0),
        projection: {
          rowsToUpsert: [],
          rowIdsToDeleteBeforePublish: [],
          legacyRowIdsToDeleteAfterConfirmation: [],
          targetHeadRowId: '',
          targetDeviceId: '',
          targetGeneration: 0,
          targetStateChecksum: ''
        },
        errorMessage: ''
      };
    }
    const projection = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .buildProjection(merged, current, now);
    return {
      localApplyRequired: localApplyRequired,
      remoteWriteRequired: remoteWriteRequired,
      mergedBuffer: AiraHistoryTaskpoolTransferCodec.encodeState(merged),
      projection: AiraHistoryTaskpoolTransferCodec.leanProjection(projection),
      errorMessage: ''
    };
  } catch (error) {
    const candidate = error as Error;
    return {
      localApplyRequired: false,
      remoteWriteRequired: false,
      mergedBuffer: new ArrayBuffer(0),
      projection: {
        rowsToUpsert: [],
        rowIdsToDeleteBeforePublish: [],
        legacyRowIdsToDeleteAfterConfirmation: [],
        targetHeadRowId: '',
        targetDeviceId: '',
        targetGeneration: 0,
        targetStateChecksum: ''
      },
      errorMessage: candidate.message ?? JSON.stringify(error)
    };
  }
}

@Concurrent
function planHuaweiHistoryInitialMerge(
  remote: HuaweiSpaceHistorySyncState,
  local: HuaweiSpaceHistorySyncState,
  now: number
): AiraHistoryInitialMergePlan {
  const mergeService = new HistorySyncMergeService();
  const merged = mergeService.mergeKeepingPreferredVisits(remote, local, now);
  return {
    merged,
    localApplyRequired: !mergeService.sameState(merged, local),
    remoteWriteRequired: !mergeService.sameState(merged, remote)
  };
}

@Concurrent
function planHuaweiHistoryRemoteWrite(
  uid: string,
  deviceId: string,
  rowBuffer: ArrayBuffer,
  desiredBuffer: ArrayBuffer,
  generatedAt: number
): AiraHistoryRemoteWritePlanOutcome {
  let current: HuaweiSpaceHistoryPhysicalMirror;
  try {
    current = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .decodeRows(AiraHistoryTaskpoolTransferCodec.decodeRows(rowBuffer), generatedAt);
  } catch (error) {
    const candidate = error as Error;
    return {
      decodeErrorMessage: candidate.message ?? JSON.stringify(error),
      computeErrorMessage: ''
    };
  }
  try {
    const desired = AiraHistoryTaskpoolTransferCodec.decodeState(desiredBuffer);
    const projection = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .buildProjection(desired, current, generatedAt);
    return {
      plan: { projection: AiraHistoryTaskpoolTransferCodec.leanProjection(projection) },
      decodeErrorMessage: '',
      computeErrorMessage: ''
    };
  } catch (error) {
    const candidate = error as Error;
    return {
      decodeErrorMessage: '',
      computeErrorMessage: candidate.message ?? JSON.stringify(error)
    };
  }
}

@Concurrent
function confirmHuaweiHistoryRemoteWrite(
  uid: string,
  deviceId: string,
  rowBuffer: ArrayBuffer,
  desiredBuffer: ArrayBuffer,
  projection: AiraHistoryRemoteWriteProjection,
  now: number
): AiraHistoryRemoteWriteConfirmationOutcome {
  let confirmedMirror: HuaweiSpaceHistoryPhysicalMirror;
  try {
    confirmedMirror = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .decodeRows(AiraHistoryTaskpoolTransferCodec.decodeRows(rowBuffer), now);
  } catch (error) {
    const candidate = error as Error;
    return {
      decodeErrorMessage: candidate.message ?? JSON.stringify(error),
      computeErrorMessage: ''
    };
  }
  try {
    const desired = AiraHistoryTaskpoolTransferCodec.decodeState(desiredBuffer);
    const mergeService = new HistorySyncMergeService();
    const projectionConfirmed = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .isProjectionTargetConfirmed(
        confirmedMirror,
        projection.targetHeadRowId,
        projection.targetDeviceId,
        projection.targetGeneration,
        projection.targetStateChecksum
      );
    if (projectionConfirmed) {
      return {
        confirmation: {
          confirmed: confirmedMirror.state,
          projectionConfirmed: true,
          desiredStateConfirmed: true,
          localApplyRequired: false
        },
        decodeErrorMessage: '',
        computeErrorMessage: ''
      };
    }
    const confirmed = mergeService.merge(confirmedMirror.state, mergeService.emptyState(), now);
    const confirmedWithDesired = mergeService.merge(confirmedMirror.state, desired, now);
    return {
      confirmation: {
        confirmed,
        projectionConfirmed: false,
        desiredStateConfirmed: mergeService.sameState(confirmed, confirmedWithDesired),
        localApplyRequired: !mergeService.sameState(confirmed, desired)
      },
      decodeErrorMessage: '',
      computeErrorMessage: ''
    };
  } catch (error) {
    const candidate = error as Error;
    return {
      decodeErrorMessage: '',
      computeErrorMessage: candidate.message ?? JSON.stringify(error)
    };
  }
}

function resolveHuaweiHistoryRemoteWritePlanOutcome(
  outcome: AiraHistoryRemoteWritePlanOutcome
): AiraHistoryRemoteWritePlan {
  if (outcome.decodeErrorMessage.length > 0) {
    throw new AiraHistoryMirrorDecodeError(outcome.decodeErrorMessage);
  }
  if (outcome.plan === undefined) {
    throw new Error(outcome.computeErrorMessage);
  }
  return outcome.plan;
}

function resolveHuaweiHistoryRemoteWriteConfirmationOutcome(
  outcome: AiraHistoryRemoteWriteConfirmationOutcome
): AiraHistoryRemoteWriteConfirmation {
  if (outcome.decodeErrorMessage.length > 0) {
    throw new AiraHistoryMirrorDecodeError(outcome.decodeErrorMessage);
  }
  if (outcome.confirmation === undefined) {
    throw new Error(outcome.computeErrorMessage);
  }
  return outcome.confirmation;
}

// Framing overhead a packed state adds per field (name, quotes, separator). Measured against a packed
// state rather than assumed, and deliberately a small over-count so the estimate stays an upper bound.
const HISTORY_TRANSFER_FIELD_OVERHEAD_BYTES: number = 8;

// Created lazily rather than as a module-level constant. This module also holds the @Concurrent
// workers, and a module-level initializer that calls into a platform API does not reliably survive in
// that shape: a module-level `util.TextEncoder.create('utf-8')` here produced an undefined encoder at
// runtime, so the estimate threw "Cannot read property byteLength of undefined" and failed the whole
// History sync. The two files that do create encoders successfully both hold them as instance fields.
let historyTransferEstimateEncoder: util.TextEncoder | undefined = undefined;

function resolveHistoryTransferEstimateEncoder(): util.TextEncoder | undefined {
  if (historyTransferEstimateEncoder === undefined) {
    try {
      historyTransferEstimateEncoder = util.TextEncoder.create('utf-8');
    } catch (_error) {
      historyTransferEstimateEncoder = undefined;
    }
  }
  return historyTransferEstimateEncoder;
}

function estimateTransferStringBytes(value: string): number {
  // Measured UTF-8 length, not `length * 2 + 32`. The old heuristic assumed the UTF-16 worst case and
  // padded every one of a visit's nine fields, so an ordinary state estimated at roughly twice its
  // packed size: a ~11 MB merge read as ~20 MB, crossed the bound, and ran its whole multi-pass
  // normalization on the UI thread instead of a worker. The estimate, not the payload, was choosing
  // the fallback.
  //
  // This is only an estimate, so it must never be able to fail a sync: if the encoder is unavailable
  // or misbehaves, fall back to the conservative UTF-16 heuristic that the value is an upper bound for.
  const text = typeof value === 'string' ? value : '';
  const encoder = resolveHistoryTransferEstimateEncoder();
  if (encoder !== undefined) {
    try {
      const bytes = encoder.encodeInto(text);
      if (bytes !== undefined && bytes.byteLength !== undefined) {
        return bytes.byteLength + HISTORY_TRANSFER_FIELD_OVERHEAD_BYTES;
      }
    } catch (_error) {
    }
  }
  return text.length * 2 + 32;
}

function estimateHuaweiHistoryStateTransferBytes(state: HuaweiSpaceHistorySyncState): number {
  let total = 64;
  state.visits.forEach((visit): void => {
    total += 128 +
      estimateTransferStringBytes(visit.visitId) +
      estimateTransferStringBytes(visit.clientId) +
      estimateTransferStringBytes(visit.nativeVisitId) +
      estimateTransferStringBytes(visit.url) +
      estimateTransferStringBytes(visit.title) +
      estimateTransferStringBytes(visit.transition) +
      estimateTransferStringBytes(visit.referrer) +
      estimateTransferStringBytes(visit.deviceName) +
      estimateTransferStringBytes(visit.source);
  });
  state.tombstones.forEach((value): void => {
    total += 64 + estimateTransferStringBytes(value.visitId);
  });
  state.deleteRanges.forEach((value): void => {
    total += 96 + estimateTransferStringBytes(value.rangeId) + estimateTransferStringBytes(value.url);
  });
  return total + 128 + estimateTransferStringBytes(state.retentionFrontier.boundaryVisitId);
}

function estimateHuaweiHistoryRowsTransferBytes(rows: HuaweiSpaceHistoryRow[]): number {
  let total = 64;
  rows.forEach((row: HuaweiSpaceHistoryRow): void => {
    total += 128 +
      estimateTransferStringBytes(row.rowId) +
      estimateTransferStringBytes(row.recordKind) +
      estimateTransferStringBytes(row.logicalId) +
      estimateTransferStringBytes(row.data);
  });
  return total;
}

function fitsTaskpoolTransferBudget(estimatedBytes: number): boolean {
  return estimatedBytes > 0 && estimatedBytes <= AIRA_SYNC_TASKPOOL_TRANSFER_BUDGET_BYTES;
}

function fitsTaskpoolPackPreflightBudget(estimatedBytes: number): boolean {
  return estimatedBytes > 0 && estimatedBytes <= AIRA_SYNC_TASKPOOL_PACK_PREFLIGHT_BUDGET_BYTES;
}

function resolveHuaweiHistoryRemoteStateDecodeOutcome(
  outcome: AiraHistoryRemoteStateDecodeOutcome
): AiraHistoryRemoteStateDecode {
  if (outcome.decoded === undefined) {
    throw new AiraHistoryMirrorDecodeError(outcome.errorMessage);
  }
  return outcome.decoded;
}

export class AiraSyncComputeExecutor {
  private readonly cooperativeThrottle: AiraSyncWorkThrottleService = new AiraSyncWorkThrottleService(
    undefined,
    { batchSize: 250, batchPauseMs: 16, stagePauseMs: 16 }
  );

  /**
   * Yield count and sleep time the last cooperative stage paid. Lets a log read split a slow
   * oversized merge into actual work versus yield overhead instead of guessing which it was.
   */
  takeCooperativeYieldStats(): string {
    return this.cooperativeThrottle.takeYieldStats();
  }

  async decodeHuaweiHistoryRemoteState(
    uid: string,
    deviceId: string,
    rows: HuaweiSpaceHistoryRow[]
  ): Promise<AiraHistoryRemoteStateDecode> {
    const now = Date.now();
    const estimatedBytes = estimateHuaweiHistoryRowsTransferBytes(rows);
    if (!fitsTaskpoolPackPreflightBudget(estimatedBytes)) {
      try {
        const mirror = await new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
          .decodeRowsCooperatively(rows, this.cooperativeThrottle, now);
        return {
          state: mirror.state,
          legacyRowIds: mirror.legacyRowIds
        };
      } catch (error) {
        const candidate = error as Error;
        throw new AiraHistoryMirrorDecodeError(candidate.message ?? JSON.stringify(error));
      }
    }
    const rowBuffer = await this.packHuaweiHistoryRowsForTransfer(rows);
    const transferBytes = rowBuffer.byteLength;
    if (!fitsTaskpoolTransferBudget(transferBytes)) {
      try {
        const mirror = await new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
          .decodeRowsCooperatively(rows, this.cooperativeThrottle, now);
        return {
          state: mirror.state,
          legacyRowIds: mirror.legacyRowIds
        };
      } catch (error) {
        const candidate = error as Error;
        throw new AiraHistoryMirrorDecodeError(candidate.message ?? JSON.stringify(error));
      }
    }
    const task = new taskpool.Task(
      'aira-sync-history-decode-state',
      decodeHuaweiHistoryRemoteState,
      uid,
      deviceId,
      rowBuffer,
      now
    );
    task.setTransferList([rowBuffer]);
    const outcome = await taskpool.execute(task, taskpool.Priority.LOW) as AiraHistoryRemoteStateDecodeOutcome;
    return resolveHuaweiHistoryRemoteStateDecodeOutcome(outcome);
  }

  async decodePackedHuaweiHistoryRemoteState(
    uid: string,
    deviceId: string,
    rowBuffer: ArrayBuffer
  ): Promise<AiraHistoryRemoteStateDecode> {
    const now = Date.now();
    if (!fitsTaskpoolTransferBudget(rowBuffer.byteLength)) {
      const rows = AiraHistoryTaskpoolTransferCodec.decodeRows(rowBuffer);
      try {
        const mirror = await new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
          .decodeRowsCooperatively(rows, this.cooperativeThrottle, now);
        return {
          state: mirror.state,
          legacyRowIds: mirror.legacyRowIds
        };
      } catch (error) {
        const candidate = error as Error;
        throw new AiraHistoryMirrorDecodeError(candidate.message ?? JSON.stringify(error));
      }
    }
    const task = new taskpool.Task(
      'aira-sync-history-decode-state',
      decodeHuaweiHistoryRemoteState,
      uid,
      deviceId,
      rowBuffer,
      now
    );
    task.setTransferList([rowBuffer]);
    const outcome = await taskpool.execute(task, taskpool.Priority.LOW) as AiraHistoryRemoteStateDecodeOutcome;
    return resolveHuaweiHistoryRemoteStateDecodeOutcome(outcome);
  }


  async planHuaweiHistoryReplicaLitePacked(
    uid: string,
    deviceId: string,
    rowBuffer: ArrayBuffer,
    local: HuaweiSpaceHistorySyncState,
    dirtyBucketIndexes: number[]
  ): Promise<AiraHistoryRemoteWriteProjection | undefined> {
    const localBuffer = await this.packHuaweiHistoryStateForTransfer(local);
    if (!fitsTaskpoolTransferBudget(rowBuffer.byteLength + localBuffer.byteLength)) {
      return undefined;
    }
    const dirtyBuffer = dirtyBucketIndexes.slice();
    const task = new taskpool.Task(
      'aira-sync-history-replica-lite-packed',
      planHuaweiHistoryReplicaLitePacked,
      uid,
      deviceId,
      rowBuffer,
      localBuffer,
      dirtyBuffer,
      Date.now()
    );
    task.setTransferList([rowBuffer, localBuffer]);
    const startedAt = Date.now();
    let outcome: AiraHistoryReplicaLitePackedOutcome;
    try {
      outcome = await taskpool.execute(task, taskpool.Priority.LOW) as AiraHistoryReplicaLitePackedOutcome;
    } catch (_error) {
      AiraSyncJankProbe.endExtra('history_replica_lite_taskpool', startedAt, 'error=throw');
      return undefined;
    }
    AiraSyncJankProbe.endExtra(
      'history_replica_lite_taskpool',
      startedAt,
      `error=${outcome.errorMessage.length > 0 ? 1 : 0} dirty=${dirtyBuffer.length}`
    );
    if (outcome.errorMessage.length > 0 || outcome.projection === undefined) {
      return undefined;
    }
    return outcome.projection;
  }

  async planHuaweiHistoryReplicaPacked(
    uid: string,
    deviceId: string,
    rowBuffer: ArrayBuffer,
    local: HuaweiSpaceHistorySyncState
  ): Promise<HuaweiHistoryReplicaPackedOutcome> {
    const localBuffer = await this.packHuaweiHistoryStateForTransfer(local);
    const task = new taskpool.Task(
      'aira-sync-history-replica-packed',
      planHuaweiHistoryReplicaPacked,
      uid,
      deviceId,
      rowBuffer,
      localBuffer,
      Date.now()
    );
    task.setTransferList([rowBuffer, localBuffer]);
    const startedAt = Date.now();
    const outcome = await taskpool.execute(task, taskpool.Priority.LOW) as HuaweiHistoryReplicaPackedOutcome;
    AiraSyncJankProbe.endExtra(
      'history_replica_packed',
      startedAt,
      `error=${outcome.errorMessage.length > 0 ? 1 : 0} write=${outcome.remoteWriteRequired ? 1 : 0}`
    );
    return outcome;
  }

  async planHuaweiHistoryInitialMerge(
    remote: HuaweiSpaceHistorySyncState,
    local: HuaweiSpaceHistorySyncState
  ): Promise<AiraHistoryInitialMergePlan> {
    const estimatedBytes = estimateHuaweiHistoryStateTransferBytes(remote) +
      estimateHuaweiHistoryStateTransferBytes(local);
    if (!fitsTaskpoolTransferBudget(estimatedBytes)) {
      return this.planHuaweiHistoryInitialMergeCooperatively(remote, local);
    }
    const packStartedAt = Date.now();
    const remoteBuffer = await this.packHuaweiHistoryStateForTransfer(remote);
    const localBuffer = await this.packHuaweiHistoryStateForTransfer(local);
    AiraSyncJankProbe.endExtra(
      'history_merge_pack',
      packStartedAt,
      `bytes=${remoteBuffer.byteLength + localBuffer.byteLength}`
    );
    if (!fitsTaskpoolTransferBudget(remoteBuffer.byteLength + localBuffer.byteLength)) {
      AiraSyncJankProbe.mark('history_merge_fallback_budget');
      return this.planHuaweiHistoryInitialMergeCooperatively(remote, local);
    }
    const task = new taskpool.Task(
      'aira-sync-history-initial-merge-packed',
      planHuaweiHistoryInitialMergePacked,
      remoteBuffer,
      localBuffer,
      Date.now()
    );
    task.setTransferList([remoteBuffer, localBuffer]);
    const taskStartedAt = Date.now();
    let outcome: AiraHistoryInitialMergePackedOutcome;
    try {
      outcome = await taskpool.execute(task, taskpool.Priority.LOW) as AiraHistoryInitialMergePackedOutcome;
    } catch (_error) {
      AiraSyncJankProbe.endExtra('history_merge_taskpool', taskStartedAt, 'error=throw');
      return this.planHuaweiHistoryInitialMergeCooperatively(remote, local);
    }
    AiraSyncJankProbe.endExtra(
      'history_merge_taskpool',
      taskStartedAt,
      `error=${outcome.errorMessage.length > 0 ? 1 : 0}`
    );
    if (outcome.errorMessage.length > 0) {
      AiraSyncJankProbe.markExtra('history_merge_fallback_cooperative', outcome.errorMessage);
      return this.planHuaweiHistoryInitialMergeCooperatively(remote, local);
    }
    if (!outcome.localApplyRequired && !outcome.remoteWriteRequired) {
      return {
        merged: remote,
        localApplyRequired: false,
        remoteWriteRequired: false
      };
    }
    const unpackStartedAt = Date.now();
    const merged = AiraHistoryTaskpoolTransferCodec.decodeState(outcome.mergedBuffer);
    AiraSyncJankProbe.endExtra(
      'history_merge_unpack',
      unpackStartedAt,
      `apply=${outcome.localApplyRequired ? 1 : 0} write=${outcome.remoteWriteRequired ? 1 : 0}`
    );
    await this.cooperativeThrottle.afterStage();
    return {
      merged: merged,
      localApplyRequired: outcome.localApplyRequired,
      remoteWriteRequired: outcome.remoteWriteRequired
    };
  }

  private async planHuaweiHistoryInitialMergeCooperatively(
    remote: HuaweiSpaceHistorySyncState,
    local: HuaweiSpaceHistorySyncState
  ): Promise<AiraHistoryInitialMergePlan> {
    const now = Date.now();
    const mergeService = new HistorySyncMergeService();
    const merged = await mergeService.mergeKeepingPreferredVisitsCooperatively(
      remote,
      local,
      this.cooperativeThrottle,
      now
    );
    return {
      merged,
      localApplyRequired: !(await mergeService.sameStateCooperatively(
        merged,
        local,
        this.cooperativeThrottle
      )),
      remoteWriteRequired: !(await mergeService.sameStateCooperatively(
        merged,
        remote,
        this.cooperativeThrottle
      ))
    };
  }

  async planHuaweiHistoryRemoteWrite(
    uid: string,
    deviceId: string,
    rows: HuaweiSpaceHistoryRow[],
    desired: HuaweiSpaceHistorySyncState,
    packedRows: ArrayBuffer | undefined = undefined
  ): Promise<AiraHistoryRemoteWritePlan> {
    const packStartedAt = Date.now();
    const rowBuffer = packedRows !== undefined ? packedRows : await this.packHuaweiHistoryRowsForTransfer(rows);
    const desiredBuffer = await this.packHuaweiHistoryStateForTransfer(desired);
    AiraSyncJankProbe.endExtra(
      'history_write_plan_pack',
      packStartedAt,
      `rows=${rows.length} bytes=${rowBuffer.byteLength + desiredBuffer.byteLength} reused=${packedRows !== undefined ? 1 : 0}`
    );
    const transferBytes = rowBuffer.byteLength + desiredBuffer.byteLength;
    if (!fitsTaskpoolTransferBudget(transferBytes)) {
      return this.planHuaweiHistoryRemoteWriteCooperatively(uid, deviceId, rows, desired);
    }
    const task = new taskpool.Task(
      'aira-sync-history-remote-write-plan',
      planHuaweiHistoryRemoteWrite,
      uid,
      deviceId,
      rowBuffer,
      desiredBuffer,
      Date.now()
    );
    task.setTransferList([rowBuffer, desiredBuffer]);
    let outcome: AiraHistoryRemoteWritePlanOutcome;
    const taskpoolStartedAt = Date.now();
    try {
      outcome = await taskpool.execute(task, taskpool.Priority.LOW) as AiraHistoryRemoteWritePlanOutcome;
    } catch (_error) {
      AiraSyncJankProbe.endExtra('history_write_plan_taskpool', taskpoolStartedAt, 'error=throw');
      return this.planHuaweiHistoryRemoteWriteCooperatively(uid, deviceId, rows, desired);
    }
    AiraSyncJankProbe.endExtra(
      'history_write_plan_taskpool',
      taskpoolStartedAt,
      `decodeError=${outcome.decodeErrorMessage.length > 0 ? 1 : 0}` +
        ` computeError=${outcome.computeErrorMessage.length > 0 ? 1 : 0}`
    );
    return resolveHuaweiHistoryRemoteWritePlanOutcome(outcome);
  }

  async confirmHuaweiHistoryRemoteWrite(
    uid: string,
    deviceId: string,
    rows: HuaweiSpaceHistoryRow[],
    projection: AiraHistoryRemoteWriteProjection,
    desired: HuaweiSpaceHistorySyncState
  ): Promise<AiraHistoryRemoteWriteConfirmation> {
    const rowBuffer = await this.packHuaweiHistoryRowsForTransfer(rows);
    const desiredBuffer = await this.packHuaweiHistoryStateForTransfer(desired);
    const transferBytes = rowBuffer.byteLength + desiredBuffer.byteLength;
    if (!fitsTaskpoolTransferBudget(transferBytes)) {
      return this.confirmHuaweiHistoryRemoteWriteCooperatively(
        uid,
        deviceId,
        rows,
        projection,
        desired
      );
    }
    const task = new taskpool.Task(
      'aira-sync-history-remote-write-confirm',
      confirmHuaweiHistoryRemoteWrite,
      uid,
      deviceId,
      rowBuffer,
      desiredBuffer,
      projection,
      Date.now()
    );
    task.setTransferList([rowBuffer, desiredBuffer]);
    let outcome: AiraHistoryRemoteWriteConfirmationOutcome;
    try {
      outcome = await taskpool.execute(task, taskpool.Priority.LOW) as AiraHistoryRemoteWriteConfirmationOutcome;
    } catch (_error) {
      return this.confirmHuaweiHistoryRemoteWriteCooperatively(
        uid,
        deviceId,
        rows,
        projection,
        desired
      );
    }
    return resolveHuaweiHistoryRemoteWriteConfirmationOutcome(outcome);
  }

  private async planHuaweiHistoryRemoteWriteCooperatively(
    uid: string,
    deviceId: string,
    rows: HuaweiSpaceHistoryRow[],
    desired: HuaweiSpaceHistorySyncState
  ): Promise<AiraHistoryRemoteWritePlan> {
    const now = Date.now();
    let current: HuaweiSpaceHistoryPhysicalMirror;
    try {
      current = await new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
        .decodeRowsCooperatively(rows, this.cooperativeThrottle, now);
    } catch (error) {
      const candidate = error as Error;
      throw new AiraHistoryMirrorDecodeError(candidate.message ?? JSON.stringify(error));
    }
    const projection = await new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .buildProjectionCooperatively(desired, current, this.cooperativeThrottle, now);
    return { projection: AiraHistoryTaskpoolTransferCodec.leanProjection(projection) };
  }

  private async confirmHuaweiHistoryRemoteWriteCooperatively(
    uid: string,
    deviceId: string,
    rows: HuaweiSpaceHistoryRow[],
    projection: AiraHistoryRemoteWriteProjection,
    desired: HuaweiSpaceHistorySyncState
  ): Promise<AiraHistoryRemoteWriteConfirmation> {
    const now = Date.now();
    let mirror: HuaweiSpaceHistoryPhysicalMirror;
    try {
      mirror = await new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
        .decodeRowsCooperatively(rows, this.cooperativeThrottle, now);
    } catch (error) {
      const candidate = error as Error;
      throw new AiraHistoryMirrorDecodeError(candidate.message ?? JSON.stringify(error));
    }
    const mergeService = new HistorySyncMergeService();
    const projectionConfirmed = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .isProjectionTargetConfirmed(
        mirror,
        projection.targetHeadRowId,
        projection.targetDeviceId,
        projection.targetGeneration,
        projection.targetStateChecksum
      );
    if (projectionConfirmed) {
      return {
        confirmed: mirror.state,
        projectionConfirmed: true,
        desiredStateConfirmed: true,
        localApplyRequired: false
      };
    }
    const confirmed = await mergeService.mergeCooperatively(
      mirror.state,
      mergeService.emptyState(),
      this.cooperativeThrottle,
      now
    );
    const confirmedWithDesired = await mergeService.mergeCooperatively(
      mirror.state,
      desired,
      this.cooperativeThrottle,
      now
    );
    return {
      confirmed,
      projectionConfirmed: false,
      desiredStateConfirmed: await mergeService.sameStateCooperatively(
        confirmed,
        confirmedWithDesired,
        this.cooperativeThrottle
      ),
      localApplyRequired: !(await mergeService.sameStateCooperatively(
        confirmed,
        desired,
        this.cooperativeThrottle
      ))
    };
  }

  private async packHuaweiHistoryRowsForTransfer(
    rows: HuaweiSpaceHistoryRow[]
  ): Promise<ArrayBuffer> {
    const packed = AiraHistoryTaskpoolTransferCodec.encodeRows(rows);
    await this.cooperativeThrottle.afterStage();
    return packed;
  }

  private async packHuaweiHistoryStateForTransfer(
    state: HuaweiSpaceHistorySyncState
  ): Promise<ArrayBuffer> {
    const packed = AiraHistoryTaskpoolTransferCodec.encodeState(state);
    await this.cooperativeThrottle.afterStage();
    return packed;
  }

}
