import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { HISTORY_SYNC_MAX_VISITS, HistorySyncMutation, HuaweiSpaceHistorySyncState } from '../../common/models/HistorySyncModels';
import { HistorySyncSnapshotReader, HISTORY_SYNC_OUTBOX_TABLE } from '../database/HistorySyncSnapshotReader';
import { HuaweiSpaceHistorySnapshotCodec } from './HuaweiSpaceHistorySnapshotCodec';
import { AiraHistoryRemoteWriteProjection,
  AiraHistoryTaskpoolTransferCodec } from '../../services/sync/AiraHistoryTaskpoolTransferCodec';

export interface HuaweiHistoryDatabasePlan {
  projection?: AiraHistoryRemoteWriteProjection;
  desiredBuffer?: ArrayBuffer;
  mutationIds: string[];
  errorMessage: string;
  computeDetail?: string;
}

interface HistoryReplicaPendingSnapshot {
  mutationIds: string[];
  visitIds: string[];
  hasRangeOrClear: boolean;
}

// Called only inside TaskPool, after the database owner has finished opening and
// initializing. Never creates schema, registers distributed tables, or starts cloud sync.
//
// TaskPool's `@Concurrent` entry runs synchronously (a returned Promise is rejected with
// "Can't return Promise in pending state"), so this reader uses the *Sync RDB APIs the
// platform recommends for a taskpool thread. The owner keeps the async, yielding reads.
//
// Only the local (non-distributed) database is read here. The Huawei replica Head/Block
// tables are DISTRIBUTED_CLOUD tables, and a plain worker connection cannot query them
// (generic SQLite error with both predicates and raw SQL), so the caller packs those rows
// and hands over a transferable buffer.
export class HuaweiHistoryReplicaReader {
  static plan(
    context: common.ApplicationContext | common.UIAbilityContext,
    localDatabaseName: string,
    rowBuffer: ArrayBuffer,
    uid: string,
    deviceId: string,
    knownHeadUpdatedAt: number
  ): HuaweiHistoryDatabasePlan {
    const startedAt = Date.now();
    let store: relationalStore.RdbStore | undefined = undefined;
    let phase = 'open-local';
    try {
      store = relationalStore.getRdbStoreSync(context, {
        name: localDatabaseName, securityLevel: relationalStore.SecurityLevel.S1
      });
      // Capture IDs before reading state; edits arriving during/after the read remain pending.
      phase = 'read-pending';
      const pending = HuaweiHistoryReplicaReader.readPending(store, uid);
      const mutationIds = pending.mutationIds;
      phase = 'read-state';
      const local: HuaweiSpaceHistorySyncState = HistorySyncSnapshotReader.readStateSync(store, uid);
      store.close();
      store = undefined;
      const localReadAt = Date.now();
      if (local.visits.length > HISTORY_SYNC_MAX_VISITS) {
        return { mutationIds: [], errorMessage: 'retention' };
      }
      const codec = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId);
      const dirty = codec.collectDirtyBucketIndexes(local, knownHeadUpdatedAt, pending.visitIds, pending.hasRangeOrClear);
      if (dirty === undefined) {
        return { mutationIds: [], errorMessage: 'no-dirty' };
      }
      phase = 'decode-rows';
      const rows = AiraHistoryTaskpoolTransferCodec.decodeRows(rowBuffer);
      const decodedAt = Date.now();
      if (rows.length === 0 || codec.needsBlockCloudSync(rows, deviceId)) {
        return { mutationIds: [], errorMessage: 'incomplete-own-replica' };
      }
      phase = 'project';
      const projection = AiraHistoryTaskpoolTransferCodec.leanProjection(
        codec.buildProjectionReusingHead(local, rows, dirty)
      );
      const projectedAt = Date.now();
      // Retain the exact planned state solely for the rare changed-Head confirmation.
      // ArrayBuffer results move out of TaskPool; the normal caller never parses this buffer.
      phase = 'reserve';
      const desiredBuffer = AiraHistoryTaskpoolTransferCodec.encodeState(local);
      return {
        projection, desiredBuffer, mutationIds, errorMessage: '',
        computeDetail: `localReadMs=${localReadAt - startedAt} decodeMs=${decodedAt - localReadAt}` +
          ` projectionMs=${projectedAt - decodedAt} reserveMs=${Date.now() - projectedAt}` +
          ` rows=${rows.length} visits=${local.visits.length} upsert=${projection.rowsToUpsert.length}` +
          ` deferredBytes=${desiredBuffer.byteLength} totalMs=${Date.now() - startedAt}`
      };
    } catch (error) {
      const candidate = error as Error;
      return { mutationIds: [], errorMessage: `${phase}: ${candidate.message ?? 'database-plan-failed'}` };
    } finally {
      if (store !== undefined) {
        store.close();
      }
    }
  }

  private static readPending(
    store: relationalStore.RdbStore, uid: string
  ): HistoryReplicaPendingSnapshot {
    const predicates = new relationalStore.RdbPredicates(HISTORY_SYNC_OUTBOX_TABLE);
    predicates.equalTo('account_uid', uid);
    predicates.orderByAsc('created_at');
    predicates.orderByAsc('mutation_id');
    const result = store.queryWithoutRowCountSync(predicates, ['mutation_id', 'payload_json']);
    const pending: HistoryReplicaPendingSnapshot = { mutationIds: [], visitIds: [], hasRangeOrClear: false };
    try {
      const index = result.getColumnIndex('mutation_id');
      const payload = result.getColumnIndex('payload_json');
      while (result.goToNextRow()) {
        pending.mutationIds.push(result.getString(index));
        if (pending.mutationIds.length > 32) { continue; }
        const mutation = JSON.parse(result.getString(payload)) as HistorySyncMutation;
        if (mutation.kind === 'delete_range' || mutation.kind === 'clear_before') {
          pending.hasRangeOrClear = true;
        }
        const visitId = (mutation.visit?.visitId ?? mutation.visitId ?? '').trim();
        if (visitId.length > 0) { pending.visitIds.push(visitId); }
      }
    } finally { result.close(); }
    return pending;
  }
}
