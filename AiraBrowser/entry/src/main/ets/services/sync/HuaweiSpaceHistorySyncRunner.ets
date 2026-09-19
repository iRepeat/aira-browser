import { BusinessError } from '@kit.BasicServicesKit';
import { HuaweiHistoryDatabasePlan } from '../../data/sync/HuaweiHistoryReplicaReader';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HISTORY_SYNC_MAX_VISITS, HistorySyncMutation, HistorySyncRunResult, HuaweiSpaceHistorySyncState } from '../../common/models/HistorySyncModels';
import { BrowserDatabase } from '../../data/database/BrowserDatabase';
import {
  HuaweiSpaceHistoryRemoteStore,
  HuaweiSpaceHistoryWriteResult
} from '../../data/sync/HuaweiSpaceHistoryRemoteStore';
import { HuaweiSpaceHistorySnapshotCodec } from '../../data/sync/HuaweiSpaceHistorySnapshotCodec';
import {
  AiraHistoryInitialMergePlan,
  AiraSyncComputeExecutor,
  HuaweiHistoryReplicaPackedOutcome
} from './AiraSyncComputeExecutor';
import { AiraHistoryTaskpoolTransferCodec, AiraHistoryRemoteWriteProjection } from './AiraHistoryTaskpoolTransferCodec';
import { AiraSyncJankProbe } from '../../common/debug/AiraSyncJankProbe';

const HISTORY_HUAWEI_ENROLLMENT_BATCH_SIZE: number = 500;
const HISTORY_HUAWEI_MAX_ENROLLMENT_ROUNDS: number = 200;

export interface HuaweiSpaceHistorySyncIdentity {
  accountUid: string;
  clientId: string;
  deviceName: string;
}

export type HuaweiSpaceHistoryRemoteStoreFactory = (
  uid: string,
  clientId: string
) => HuaweiSpaceHistoryRemoteStore;

const HISTORY_HUAWEI_LOG_DOMAIN: number = 0x0000;
const HISTORY_HUAWEI_LOG_TAG: string = 'HuaweiHistorySync';

export function shouldSkipUnchangedHuaweiHistoryRemote(
  enrolledCount: number,
  hasPendingLocalMutations: boolean,
  knownChecksum: string,
  remoteHeadChecksum: string
): boolean {
  const known = knownChecksum.trim();
  const remote = remoteHeadChecksum.trim();
  return enrolledCount <= 0 && !hasPendingLocalMutations && known.length > 0 && known === remote;
}

export function shouldLoadUnchangedHuaweiHistoryReplica(
  enrolledCount: number,
  hasPendingLocalMutations: boolean,
  knownChecksum: string,
  remoteHeadChecksum: string
): boolean {
  const known = knownChecksum.trim();
  const remote = remoteHeadChecksum.trim();
  return (enrolledCount > 0 || hasPendingLocalMutations) && known.length > 0 && known === remote;
}

export type HuaweiHistoryRemoteReadPlan = 'skip' | 'replica' | 'cloud';

export function hasHuaweiHistoryLocalWork(
  enrolledCount: number,
  hasOutbox: boolean,
  hasRecentTombstones: boolean,
  headMatches: boolean
): boolean {
  return enrolledCount > 0 || hasOutbox || (headMatches && hasRecentTombstones);
}

export function resolveHuaweiHistoryRemoteReadPlan(
  hasLocalWork: boolean,
  headMatches: boolean,
  remoteHeadChecksum: string,
  localReplicaReady: boolean
): HuaweiHistoryRemoteReadPlan {
  if (remoteHeadChecksum.trim().length <= 0) {
    return 'cloud';
  }
  if (!hasLocalWork && (headMatches || localReplicaReady)) {
    return 'skip';
  }
  if (hasLocalWork && (headMatches || localReplicaReady)) {
    return 'replica';
  }
  return 'cloud';
}

export class HuaweiSpaceHistorySyncRunner {
  private readonly database: BrowserDatabase;
  private readonly remoteStoreFactory: HuaweiSpaceHistoryRemoteStoreFactory;
  private readonly computeExecutor: AiraSyncComputeExecutor = new AiraSyncComputeExecutor();

  constructor(
    database: BrowserDatabase,
    remoteStoreFactory?: HuaweiSpaceHistoryRemoteStoreFactory
  ) {
    this.database = database;
    this.remoteStoreFactory = remoteStoreFactory ??
      ((uid: string, clientId: string): HuaweiSpaceHistoryRemoteStore => {
        return new HuaweiSpaceHistoryRemoteStore(uid, clientId);
      });
  }

  async run(
    identity: HuaweiSpaceHistorySyncIdentity,
    clearOutboxAfterSuccess: boolean = true
  ): Promise<HistorySyncRunResult> {
    const runStartedAt = Date.now();
    await this.database.initialize();
    let stageStartedAt = Date.now();
    let appliedChangeCount = await this.database.pruneHistorySyncProjection(identity.accountUid);
    this.logStage('prune', stageStartedAt, `applied=${appliedChangeCount}`);
    stageStartedAt = Date.now();
    const enrolled = await this.enrollLocalVisits(identity);
    this.logStage('enroll', stageStartedAt, `enrolled=${enrolled}`);
    const remoteStore = this.remoteStoreFactory(identity.accountUid, identity.clientId);
    const knownHead = await this.database.readHuaweiHistoryRemoteHead(identity.accountUid);
    const knownChecksum = knownHead.checksum;
    const hasOutbox = await this.database.hasHistorySyncOutbox(identity.accountUid);
    const hasRecentTombstones =
      await this.database.hasHistorySyncTombstonesSince(identity.accountUid, knownHead.updatedAt);
    let remote: HuaweiSpaceHistorySyncState | undefined = undefined;
    stageStartedAt = Date.now();
    const peekedChecksum = await remoteStore.peekHeadChecksum();
    const headMatches = knownChecksum.length > 0 && knownChecksum === peekedChecksum;
    const hasLocalWork = appliedChangeCount > 0 || hasHuaweiHistoryLocalWork(
      enrolled,
      hasOutbox,
      hasRecentTombstones,
      headMatches
    );
    let localReplicaReady = false;
    if (hasLocalWork && headMatches) {
      if (remoteStore.supportsWorkerReplicaPlan()) {
        const databaseLite = await this.tryDatabaseReplicaWrite(identity, remoteStore,
          knownHead.updatedAt, clearOutboxAfterSuccess, appliedChangeCount, runStartedAt);
        if (databaseLite !== undefined) { return databaseLite; }
      }
      localReplicaReady = await remoteStore.preparePackedReplicaRows(true);
    } else if (!(!hasLocalWork && headMatches) && peekedChecksum.length > 0) {
      remote = await remoteStore.tryReadLocalReplicaMatchingHead(peekedChecksum);
      localReplicaReady = remote !== undefined;
    }
    const plan = resolveHuaweiHistoryRemoteReadPlan(
      hasLocalWork,
      headMatches,
      peekedChecksum,
      localReplicaReady
    );
    AiraSyncJankProbe.markExtra(
      'history_read_plan',
      `plan=${plan} headMatches=${headMatches ? 1 : 0} replicaReady=${localReplicaReady ? 1 : 0}` +
        ` localWork=${hasLocalWork ? 1 : 0} enrolled=${enrolled} outbox=${hasOutbox ? 1 : 0}` +
        ` tombstones=${hasRecentTombstones ? 1 : 0}`
    );
    if (plan === 'skip') {
      this.logStage('read-remote', stageStartedAt, 'source=head-unchanged');
      if (peekedChecksum.length > 0) {
        await this.database.writeHuaweiHistoryRemoteHeadChecksum(identity.accountUid, peekedChecksum);
      }
      this.logStage('run-total', runStartedAt, 'applied=0 uploaded=0 skipped=1');
      return {
        ok: true,
        appliedChangeCount: appliedChangeCount,
        uploadedMutationCount: 0,
        message: '历史记录已经是最新。'
      };
    }
    if (plan === 'replica') {
      this.logStage('read-remote', stageStartedAt, 'source=head-unchanged-replica');
      if (headMatches) {
        const lite = await this.tryLiteReplicaWrite(
          identity,
          remoteStore,
          knownHead.updatedAt,
          clearOutboxAfterSuccess,
          appliedChangeCount,
          runStartedAt
        );
        if (lite !== undefined) {
          return lite;
        }
        const packedRows = await remoteStore.repackFreshReplicaRows(true);
        if (packedRows !== undefined && packedRows.byteLength > 0) {
          return await this.runPackedReplica(
            identity,
            remoteStore,
            packedRows,
            clearOutboxAfterSuccess,
            appliedChangeCount,
            runStartedAt
          );
        }
      }
    } else {
      remote = await remoteStore.readCloudBlocksAndDecode();
      this.logStage('read-remote', stageStartedAt, 'source=cloud');
    }
    stageStartedAt = Date.now();
    const local = await this.database.readHuaweiSpaceHistorySyncState(identity.accountUid);
    this.logStage('read-local', stageStartedAt);
    stageStartedAt = Date.now();
    if (remote === undefined) {
      remote = await remoteStore.readState();
      this.logStage('read-remote', stageStartedAt, 'source=cloud');
    }
    if (remote === undefined) {
      throw new Error('华为云空间历史记录读取失败。');
    }
    stageStartedAt = Date.now();
    const initialPlan: AiraHistoryInitialMergePlan =
      await this.computeExecutor.planHuaweiHistoryInitialMerge(remote, local);
    AiraSyncJankProbe.markExtra(
      'history_merge_yield_stats',
      `${this.computeExecutor.takeCooperativeYieldStats()} remoteVisits=${remote.visits.length}` +
        ` localVisits=${local.visits.length}`
    );
    this.logStage(
      'plan-merge',
      stageStartedAt,
      `write=${initialPlan.remoteWriteRequired ? 1 : 0} apply=${initialPlan.localApplyRequired ? 1 : 0}`
    );
    stageStartedAt = Date.now();
    const firstApplied = initialPlan.localApplyRequired
      ? await this.database.applyHuaweiSpaceHistorySyncState(identity.accountUid, initialPlan.merged)
      : 0;
    appliedChangeCount += firstApplied;
    this.logStage('apply-local', stageStartedAt, `applied=${firstApplied}`);
    const desired = initialPlan.merged;
    const remoteMaintenanceRequired = remoteStore.requiresMaintenance();
    const remoteWriteRequired = initialPlan.remoteWriteRequired || remoteMaintenanceRequired;
    stageStartedAt = Date.now();
    const writeResult: HuaweiSpaceHistoryWriteResult = remoteWriteRequired
      ? await remoteStore.writeState(desired)
      : { state: remote, changedRowCount: 0, localApplyRequired: false };
    this.logStage(
      'write-remote',
      stageStartedAt,
      `required=${remoteWriteRequired ? 1 : 0} changed=${writeResult.changedRowCount} cached=0`
    );
    const confirmedState = remoteWriteRequired ? writeResult.state : initialPlan.merged;
    const confirmedLocalApplyRequired = remoteWriteRequired && writeResult.localApplyRequired;
    stageStartedAt = Date.now();
    const confirmedApplied = confirmedLocalApplyRequired
      ? await this.database.applyHuaweiSpaceHistorySyncState(identity.accountUid, confirmedState)
      : 0;
    appliedChangeCount += confirmedApplied;
    this.logStage('apply-confirmed', stageStartedAt, `applied=${confirmedApplied}`);
    stageStartedAt = Date.now();
    const pruned = initialPlan.localApplyRequired || confirmedLocalApplyRequired
      ? await this.database.pruneHistorySyncProjection(identity.accountUid)
      : 0;
    appliedChangeCount += pruned;
    this.logStage('prune-final', stageStartedAt, `pruned=${pruned}`);
    await this.finalizeConfirmedState(identity.accountUid, remoteStore, clearOutboxAfterSuccess);
    this.logStage(
      'run-total',
      runStartedAt,
      `applied=${appliedChangeCount} uploaded=${writeResult.changedRowCount}`
    );
    return {
      ok: true,
      appliedChangeCount,
      uploadedMutationCount: writeResult.changedRowCount,
      message: appliedChangeCount > 0 || writeResult.changedRowCount > 0
        ? '历史记录已完成华为云空间增量同步。'
        : '历史记录已经是最新。'
    };
  }


  private reportDatabaseWorkerFallback(step: string, error: Error): void {
    const candidate = error as BusinessError;
    const code = typeof candidate.code === 'number' ? candidate.code : 0;
    AiraSyncJankProbe.markExtra(
      'history_replica_database_fallback',
      `reason=worker-unavailable step=${step} code=${code}`
    );
    hilog.error(HISTORY_HUAWEI_LOG_DOMAIN, HISTORY_HUAWEI_LOG_TAG, 'history database worker fallback step=%{public}s: %{public}s',
      step, `${candidate.name}: ${candidate.message}`);
  }

  private async tryDatabaseReplicaWrite(
    identity: HuaweiSpaceHistorySyncIdentity, remoteStore: HuaweiSpaceHistoryRemoteStore,
    knownHeadUpdatedAt: number, clearOutboxAfterSuccess: boolean,
    appliedChangeCount: number, runStartedAt: number
  ): Promise<HistorySyncRunResult | undefined> {
    const startedAt = Date.now();
    // Owners initialize/backfill on their existing serialized path before a worker
    // opens either database. Only database names and scalar hints cross into the
    // task; the worker resolves its own context, because a Context is not serializable.
    // Each step reports its own fallback reason so a failed worker is not flattened
    // into one opaque "unavailable".
    let localDatabase: string;
    try {
      localDatabase = await this.database.prepareHuaweiHistoryWorkerRead(identity.accountUid);
    } catch (error) {
      this.reportDatabaseWorkerFallback('prepare-local', error);
      return undefined;
    }
    // The Huawei replica Head/Block tables are DISTRIBUTED_CLOUD tables that a worker
    // connection cannot query, so the caller packs those rows (as the lite path does) and
    // the worker reads only the non-distributed local state itself.
    let rowBuffer: ArrayBuffer | undefined = undefined;
    try {
      const replicaReady = await remoteStore.preparePackedReplicaRows(true);
      rowBuffer = replicaReady ? remoteStore.takePackedReplicaRows() : undefined;
    } catch (error) {
      this.reportDatabaseWorkerFallback('prepare-replica', error);
      return undefined;
    }
    if (rowBuffer === undefined || rowBuffer.byteLength <= 0) {
      AiraSyncJankProbe.markExtra('history_replica_database_fallback', 'reason=replica-not-packed');
      return undefined;
    }
    let plan: HuaweiHistoryDatabasePlan;
    try {
      plan = await this.computeExecutor.planHuaweiHistoryReplicaLiteDatabase(localDatabase, rowBuffer,
        identity.accountUid, identity.clientId, knownHeadUpdatedAt);
    } catch (error) {
      this.reportDatabaseWorkerFallback('dispatch', error);
      return undefined;
    }
    if (plan.projection === undefined || plan.desiredBuffer === undefined || plan.errorMessage.length > 0) {
      hilog.error(HISTORY_HUAWEI_LOG_DOMAIN, HISTORY_HUAWEI_LOG_TAG,
        'history database worker plan error: %{public}s', plan.errorMessage);
      AiraSyncJankProbe.markExtra('history_replica_database_fallback', `reason=${plan.errorMessage}`);
      return undefined;
    }
    this.logStage('plan-merge', startedAt, `write=1 apply=0 database=1 upsert=${plan.projection.rowsToUpsert.length}`);
    // Keep upload/confirmation outside the compute fallback. A transport failure must
    // retain pending mutations and must never trigger another full CPU plan in this run.
    const writeStartedAt = Date.now();
    const result = await remoteStore.writePreparedProjectionDeferred(plan.projection, plan.desiredBuffer);
    this.logStage('write-remote', writeStartedAt, `database=1 changed=${result.changedRowCount}`);
    if (result.localApplyRequired && result.state !== undefined) {
      appliedChangeCount += await this.database.applyHuaweiSpaceHistorySyncState(identity.accountUid, result.state);
      appliedChangeCount += await this.database.pruneHistorySyncProjection(identity.accountUid);
    }
    await this.finalizeConfirmedState(identity.accountUid, remoteStore, clearOutboxAfterSuccess, plan.mutationIds);
    this.logStage('run-total', runStartedAt, `applied=${appliedChangeCount} uploaded=${result.changedRowCount} database=1`);
    return { ok: true, appliedChangeCount, uploadedMutationCount: result.changedRowCount,
      message: result.changedRowCount > 0 ? '历史记录已完成华为云空间增量同步。' : '历史记录已经是最新。' };
  }

  private async tryLiteReplicaWrite(
    identity: HuaweiSpaceHistorySyncIdentity,
    remoteStore: HuaweiSpaceHistoryRemoteStore,
    knownHeadUpdatedAt: number,
    clearOutboxAfterSuccess: boolean,
    appliedChangeCount: number,
    runStartedAt: number
  ): Promise<HistorySyncRunResult | undefined> {
    const rawRows = remoteStore.peekFreshReplicaRows();
    if (rawRows === undefined || rawRows.length <= 0) {
      return undefined;
    }
    let stageStartedAt = Date.now();
    const local = await this.database.readHuaweiSpaceHistorySyncState(identity.accountUid);
    this.logStage('read-local', stageStartedAt);
    const outbox = await this.database.listHistorySyncOutbox(identity.accountUid, 32);
    if (local.visits.length > HISTORY_SYNC_MAX_VISITS) {
      // Enrollment occurs after pruning and can cross the limit; the lite path does not apply
      // a changed local state. Full merge must persist retention before confirming the outbox.
      AiraSyncJankProbe.markExtra('history_replica_lite_skip',
        `reason=retention visits=${local.visits.length}`);
      return undefined;
    }
    const outboxVisitIds: string[] = [];
    const mutationKinds: string[] = [];
    let hasRangeOrClear = false;
    for (let index = 0; index < outbox.length; index += 1) {
      const mutation: HistorySyncMutation = outbox[index];
      mutationKinds.push(mutation.kind);
      if (mutation.kind === 'delete_range' || mutation.kind === 'clear_before') {
        hasRangeOrClear = true;
        break;
      }
      const visitId = mutation.visit?.visitId ?? mutation.visitId ?? '';
      if (visitId.trim().length > 0) {
        outboxVisitIds.push(visitId.trim());
      }
    }
    const codec = new HuaweiSpaceHistorySnapshotCodec(identity.accountUid, identity.clientId);
    const dirty = codec.collectDirtyBucketIndexes(local, knownHeadUpdatedAt, outboxVisitIds, hasRangeOrClear);
    if (dirty === undefined) {
      AiraSyncJankProbe.markExtra(
        'history_replica_lite_skip',
        `reason=no-dirty outbox=${outbox.length} kinds=${mutationKinds.join(',')}` +
          ` rangeOrClear=${hasRangeOrClear ? 1 : 0}` +
          ` outboxVisitIds=${outboxVisitIds.length} tombstones=${local.tombstones.length}` +
          ` frontierUpdatedAt=${local.retentionFrontier.updatedAt} headUpdatedAt=${knownHeadUpdatedAt}`
      );
      return undefined;
    }
    stageStartedAt = Date.now();
    const packedRows = remoteStore.takePackedReplicaRows();
    let projection: AiraHistoryRemoteWriteProjection | undefined = undefined;
    try {
      if (packedRows !== undefined) {
        projection = await this.computeExecutor.planHuaweiHistoryReplicaLitePacked(
          identity.accountUid,
          identity.clientId,
          packedRows,
          local,
          dirty
        );
        if (projection === undefined) {
          return undefined;
        }
      } else {
        projection = AiraHistoryTaskpoolTransferCodec.leanProjection(
          codec.buildProjectionReusingHead(local, rawRows, dirty)
        );
      }
    } catch (error) {
      AiraSyncJankProbe.endExtra(
        'history_replica_lite',
        stageStartedAt,
        `error=1 dirty=${dirty.length}`
      );
      return undefined;
    }
    // Only compute/replica validation failures can benefit from a full plan.
    // Transport or confirmation failure must preserve pending work and reach
    // the caller's retry policy, rather than repeating a large CPU task here.
    AiraSyncJankProbe.endExtra(
      'history_replica_lite',
      stageStartedAt,
      `dirty=${dirty.length} upsert=${projection.rowsToUpsert.length}` +
        ` delete=${projection.rowIdsToDeleteBeforePublish.length} taskpool=${packedRows !== undefined ? 1 : 0}`
    );
    this.logStage(
      'plan-merge',
      stageStartedAt,
      `write=1 apply=0 packed=0 lite=1 dirty=${dirty.length}`
    );
    stageStartedAt = Date.now();
    const writeResult: HuaweiSpaceHistoryWriteResult =
      await remoteStore.writePreparedProjection(projection, local);
    this.logStage(
      'write-remote',
      stageStartedAt,
      `required=1 changed=${writeResult.changedRowCount} packed=0 lite=1`
    );
    await this.finalizeConfirmedState(identity.accountUid, remoteStore, clearOutboxAfterSuccess);
    this.logStage(
      'run-total',
      runStartedAt,
      `applied=${appliedChangeCount} uploaded=${writeResult.changedRowCount} lite=1`
    );
    return {
      ok: true,
      appliedChangeCount: appliedChangeCount,
      uploadedMutationCount: writeResult.changedRowCount,
      message: writeResult.changedRowCount > 0
        ? '历史记录已完成华为云空间增量同步。'
        : '历史记录已经是最新。'
    };
  }

  private async runPackedReplica(
    identity: HuaweiSpaceHistorySyncIdentity,
    remoteStore: HuaweiSpaceHistoryRemoteStore,
    packedRows: ArrayBuffer,
    clearOutboxAfterSuccess: boolean,
    appliedChangeCount: number,
    runStartedAt: number
  ): Promise<HistorySyncRunResult> {
    let stageStartedAt = Date.now();
    const local = await this.database.readHuaweiSpaceHistorySyncState(identity.accountUid);
    this.logStage('read-local', stageStartedAt);
    stageStartedAt = Date.now();
    const packed: HuaweiHistoryReplicaPackedOutcome =
      await this.computeExecutor.planHuaweiHistoryReplicaPacked(
        identity.accountUid,
        identity.clientId,
        packedRows,
        local
      );
    this.logStage(
      'plan-merge',
      stageStartedAt,
      `write=${packed.remoteWriteRequired ? 1 : 0} apply=${packed.localApplyRequired ? 1 : 0} packed=1`
    );
    if (packed.errorMessage.length > 0) {
      throw new Error(packed.errorMessage);
    }
    const desired = packed.mergedBuffer.byteLength > 0
      ? await this.computeExecutor.decodeHuaweiHistoryTransferredState(packed.mergedBuffer)
      : local;
    stageStartedAt = Date.now();
    const firstApplied = packed.localApplyRequired
      ? await this.database.applyHuaweiSpaceHistorySyncState(identity.accountUid, desired)
      : 0;
    appliedChangeCount += firstApplied;
    this.logStage('apply-local', stageStartedAt, `applied=${firstApplied}`);
    stageStartedAt = Date.now();
    const writeResult: HuaweiSpaceHistoryWriteResult = packed.remoteWriteRequired
      ? await remoteStore.writePreparedProjection(packed.projection, desired)
      : { state: desired, changedRowCount: 0, localApplyRequired: false };
    this.logStage(
      'write-remote',
      stageStartedAt,
      `required=${packed.remoteWriteRequired ? 1 : 0} changed=${writeResult.changedRowCount} packed=1`
    );
    stageStartedAt = Date.now();
    const confirmedApplied = writeResult.localApplyRequired
      ? await this.database.applyHuaweiSpaceHistorySyncState(identity.accountUid, writeResult.state)
      : 0;
    appliedChangeCount += confirmedApplied;
    this.logStage('apply-confirmed', stageStartedAt, `applied=${confirmedApplied}`);
    stageStartedAt = Date.now();
    const pruned = packed.localApplyRequired || writeResult.localApplyRequired
      ? await this.database.pruneHistorySyncProjection(identity.accountUid)
      : 0;
    appliedChangeCount += pruned;
    this.logStage('prune-final', stageStartedAt, `pruned=${pruned}`);
    await this.finalizeConfirmedState(identity.accountUid, remoteStore, clearOutboxAfterSuccess);
    this.logStage(
      'run-total',
      runStartedAt,
      `applied=${appliedChangeCount} uploaded=${writeResult.changedRowCount}`
    );
    return {
      ok: true,
      appliedChangeCount: appliedChangeCount,
      uploadedMutationCount: writeResult.changedRowCount,
      message: appliedChangeCount > 0 || writeResult.changedRowCount > 0
        ? '历史记录已完成华为云空间增量同步。'
        : '历史记录已经是最新。'
    };
  }

  private async finalizeConfirmedState(
    accountUid: string,
    remoteStore: HuaweiSpaceHistoryRemoteStore,
    clearOutboxAfterSuccess: boolean,
    confirmedMutationIds?: string[]
  ): Promise<void> {
    if (clearOutboxAfterSuccess) {
      await AiraSyncJankProbe.measure('history_finalize_outbox', async (): Promise<number> => {
        return confirmedMutationIds === undefined
          ? this.database.clearHistorySyncOutbox(accountUid)
          : this.database.deleteHistorySyncOutboxMutations(accountUid, confirmedMutationIds);
      });
    }
    // The account-scoped durable Head already gates unchanged reads. Keeping a second
    // normalized copy of all visits here only repeats URL parsing and retains a full heap.
    const confirmedChecksum = remoteStore.consumeLastHeadChecksum();
    if (confirmedChecksum.length > 0) {
      await AiraSyncJankProbe.measure('history_finalize_head', async (): Promise<void> => {
        await this.database.writeHuaweiHistoryRemoteHeadChecksum(accountUid, confirmedChecksum);
      });
    }
  }

  private logStage(stage: string, startedAt: number, extra: string = ''): void {
    AiraSyncJankProbe.endExtra(`huawei_history_${stage}`, startedAt, extra);
    hilog.info(
      HISTORY_HUAWEI_LOG_DOMAIN,
      HISTORY_HUAWEI_LOG_TAG,
      'Huawei history stage=%{public}s durationMs=%{public}d extra=%{public}s',
      stage,
      Date.now() - startedAt,
      extra
    );
    AiraSyncJankProbe.endExtra(`history_stage_${stage}`, startedAt, extra);
  }

  private async enrollLocalVisits(identity: HuaweiSpaceHistorySyncIdentity): Promise<number> {
    let enrolledTotal = 0;
    for (let round = 0; round < HISTORY_HUAWEI_MAX_ENROLLMENT_ROUNDS; round += 1) {
      const enrolled = await this.database.prepareHistorySyncEnrollment(
        identity.accountUid,
        identity.clientId,
        identity.deviceName,
        HISTORY_HUAWEI_ENROLLMENT_BATCH_SIZE
      );
      enrolledTotal += enrolled;
      if (enrolled < HISTORY_HUAWEI_ENROLLMENT_BATCH_SIZE) {
        return enrolledTotal;
      }
    }
    throw new Error('本机历史记录初始化超过安全上限，请稍后继续同步。');
  }

}
