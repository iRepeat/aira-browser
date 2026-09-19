import { relationalStore } from '@kit.ArkData';
import { HistorySyncVisit, HistorySyncExactTombstone, HistorySyncDeleteRange,
  HistorySyncRetentionFrontier, HuaweiSpaceHistorySyncState } from '../../common/models/HistorySyncModels';

export const HISTORY_SYNC_CANONICAL_VISITS_TABLE = 'history_sync_canonical_visits_v1';
export const HISTORY_SYNC_TOMBSTONES_TABLE = 'history_sync_tombstones_v1';
export const HISTORY_SYNC_DELETE_RANGES_TABLE = 'history_sync_delete_ranges_v1';
export const HISTORY_SYNC_FRONTIERS_TABLE = 'history_sync_frontiers_v1';
export const HISTORY_SYNC_RETENTION_TABLE = 'history_sync_retention_v1';
export const HISTORY_SYNC_OUTBOX_TABLE = 'history_sync_outbox_v1';

const HISTORY_SYNC_CANONICAL_READ_BATCH_SIZE: number = 128;

// Shared read-only mapping for the database owner and TaskPool. Schema creation/backfill
// belongs to BrowserDatabase and must complete before a worker is dispatched.
//
// Two access styles exist for a reason: the owner reads on the caller thread and yields
// periodically so a large state does not block the event loop, while the TaskPool worker
// runs a synchronous `@Concurrent` function and must therefore use the *Sync query APIs
// (which the platform explicitly recommends running on a taskpool thread). Row mapping is
// shared so both paths agree on identity/validation rules.
export class HistorySyncSnapshotReader {
  static async readState(store: relationalStore.RdbStore, uid: string): Promise<HuaweiSpaceHistorySyncState> {
    return {
      visits: await HistorySyncSnapshotReader.readVisits(store, uid, 0),
      tombstones: await HistorySyncSnapshotReader.readTombstones(store, uid),
      deleteRanges: await HistorySyncSnapshotReader.readDeleteRanges(store, uid),
      clearBefore: await HistorySyncSnapshotReader.readClearBefore(store, uid),
      retentionFrontier: await HistorySyncSnapshotReader.readRetentionFrontier(store, uid)
    };
  }

  static readStateSync(store: relationalStore.RdbStore, uid: string): HuaweiSpaceHistorySyncState {
    return {
      visits: HistorySyncSnapshotReader.readVisitsSync(store, uid, 0),
      tombstones: HistorySyncSnapshotReader.readTombstonesSync(store, uid),
      deleteRanges: HistorySyncSnapshotReader.readDeleteRangesSync(store, uid),
      clearBefore: HistorySyncSnapshotReader.readClearBeforeSync(store, uid),
      retentionFrontier: HistorySyncSnapshotReader.readRetentionFrontierSync(store, uid)
    };
  }

  static async readVisits(
    store: relationalStore.RdbStore,
    accountUid: string,
    updatedAfter: number,
    yieldBatch?: () => Promise<void>
  ): Promise<HistorySyncVisit[]> {
    const resultSet = await store.queryWithoutRowCount(
      HistorySyncSnapshotReader.visitPredicates(accountUid, updatedAfter),
      ['visit_id', 'payload_json']
    );
    const rowVisitIds: string[] = [];
    const rowPayloads: string[] = [];
    try {
      const visitIdIndex = resultSet.getColumnIndex('visit_id');
      const payloadIndex = resultSet.getColumnIndex('payload_json');
      while (resultSet.goToNextRow()) {
        rowVisitIds.push(resultSet.getString(visitIdIndex).trim());
        rowPayloads.push(resultSet.getString(payloadIndex));
        if (rowVisitIds.length % HISTORY_SYNC_CANONICAL_READ_BATCH_SIZE === 0) {
          if (yieldBatch !== undefined) { await yieldBatch(); }
        }
      }
    } finally {
      resultSet.close();
    }
    return await HistorySyncSnapshotReader.buildVisitsCooperatively(rowVisitIds, rowPayloads, yieldBatch);
  }

  static readVisitsSync(
    store: relationalStore.RdbStore,
    accountUid: string,
    updatedAfter: number
  ): HistorySyncVisit[] {
    const resultSet = store.queryWithoutRowCountSync(
      HistorySyncSnapshotReader.visitPredicates(accountUid, updatedAfter),
      ['visit_id', 'payload_json']
    );
    const rowVisitIds: string[] = [];
    const rowPayloads: string[] = [];
    try {
      const visitIdIndex = resultSet.getColumnIndex('visit_id');
      const payloadIndex = resultSet.getColumnIndex('payload_json');
      while (resultSet.goToNextRow()) {
        rowVisitIds.push(resultSet.getString(visitIdIndex).trim());
        rowPayloads.push(resultSet.getString(payloadIndex));
      }
    } finally {
      resultSet.close();
    }
    return HistorySyncSnapshotReader.buildVisits(rowVisitIds, rowPayloads);
  }

  static async readTombstones(
    store: relationalStore.RdbStore,
    accountUid: string
  ): Promise<HistorySyncExactTombstone[]> {
    const resultSet = await store.queryWithoutRowCount(
      HistorySyncSnapshotReader.accountPredicates(HISTORY_SYNC_TOMBSTONES_TABLE, accountUid, 'deleted_at'),
      ['visit_id', 'deleted_at']
    );
    const values: HistorySyncExactTombstone[] = [];
    try {
      const visitIdIndex = resultSet.getColumnIndex('visit_id');
      const deletedAtIndex = resultSet.getColumnIndex('deleted_at');
      while (resultSet.goToNextRow()) {
        values.push({
          visitId: resultSet.getString(visitIdIndex),
          deletedAt: resultSet.getLong(deletedAtIndex)
        });
      }
    } finally {
      resultSet.close();
    }
    return values;
  }

  static readTombstonesSync(
    store: relationalStore.RdbStore,
    accountUid: string
  ): HistorySyncExactTombstone[] {
    const resultSet = store.queryWithoutRowCountSync(
      HistorySyncSnapshotReader.accountPredicates(HISTORY_SYNC_TOMBSTONES_TABLE, accountUid, 'deleted_at'),
      ['visit_id', 'deleted_at']
    );
    const values: HistorySyncExactTombstone[] = [];
    try {
      const visitIdIndex = resultSet.getColumnIndex('visit_id');
      const deletedAtIndex = resultSet.getColumnIndex('deleted_at');
      while (resultSet.goToNextRow()) {
        values.push({
          visitId: resultSet.getString(visitIdIndex),
          deletedAt: resultSet.getLong(deletedAtIndex)
        });
      }
    } finally {
      resultSet.close();
    }
    return values;
  }

  static async readDeleteRanges(
    store: relationalStore.RdbStore,
    accountUid: string
  ): Promise<HistorySyncDeleteRange[]> {
    const resultSet = await store.queryWithoutRowCount(
      HistorySyncSnapshotReader.accountPredicates(HISTORY_SYNC_DELETE_RANGES_TABLE, accountUid),
      ['range_id', 'url', 'started_at', 'ended_at', 'seq']
    );
    const ranges: HistorySyncDeleteRange[] = [];
    try {
      while (resultSet.goToNextRow()) {
        ranges.push({
          rangeId: resultSet.getString(resultSet.getColumnIndex('range_id')),
          url: resultSet.getString(resultSet.getColumnIndex('url')),
          startedAt: resultSet.getLong(resultSet.getColumnIndex('started_at')),
          endedAt: resultSet.getLong(resultSet.getColumnIndex('ended_at')),
          seq: resultSet.getLong(resultSet.getColumnIndex('seq'))
        });
      }
    } finally {
      resultSet.close();
    }
    return ranges;
  }

  static readDeleteRangesSync(
    store: relationalStore.RdbStore,
    accountUid: string
  ): HistorySyncDeleteRange[] {
    const resultSet = store.queryWithoutRowCountSync(
      HistorySyncSnapshotReader.accountPredicates(HISTORY_SYNC_DELETE_RANGES_TABLE, accountUid),
      ['range_id', 'url', 'started_at', 'ended_at', 'seq']
    );
    const ranges: HistorySyncDeleteRange[] = [];
    try {
      while (resultSet.goToNextRow()) {
        ranges.push({
          rangeId: resultSet.getString(resultSet.getColumnIndex('range_id')),
          url: resultSet.getString(resultSet.getColumnIndex('url')),
          startedAt: resultSet.getLong(resultSet.getColumnIndex('started_at')),
          endedAt: resultSet.getLong(resultSet.getColumnIndex('ended_at')),
          seq: resultSet.getLong(resultSet.getColumnIndex('seq'))
        });
      }
    } finally {
      resultSet.close();
    }
    return ranges;
  }

  static async readClearBefore(
    store: relationalStore.RdbStore,
    accountUid: string
  ): Promise<number> {
    const resultSet = await store.query(
      HistorySyncSnapshotReader.accountPredicates(HISTORY_SYNC_FRONTIERS_TABLE, accountUid, undefined, 1),
      ['clear_before']
    );
    try {
      return resultSet.goToNextRow() ? resultSet.getLong(resultSet.getColumnIndex('clear_before')) : 0;
    } finally {
      resultSet.close();
    }
  }

  static readClearBeforeSync(
    store: relationalStore.RdbStore,
    accountUid: string
  ): number {
    const resultSet = store.querySync(
      HistorySyncSnapshotReader.accountPredicates(HISTORY_SYNC_FRONTIERS_TABLE, accountUid, undefined, 1),
      ['clear_before']
    );
    try {
      return resultSet.goToNextRow() ? resultSet.getLong(resultSet.getColumnIndex('clear_before')) : 0;
    } finally {
      resultSet.close();
    }
  }

  static async readRetentionFrontier(
    store: relationalStore.RdbStore,
    accountUid: string
  ): Promise<HistorySyncRetentionFrontier> {
    const resultSet = await store.query(
      HistorySyncSnapshotReader.accountPredicates(HISTORY_SYNC_RETENTION_TABLE, accountUid, undefined, 1),
      ['cutoff_at', 'boundary_visited_at', 'boundary_visit_id', 'updated_at']
    );
    try {
      if (!resultSet.goToNextRow()) {
        return HistorySyncSnapshotReader.emptyRetentionFrontier();
      }
      return {
        cutoffAt: resultSet.getLong(resultSet.getColumnIndex('cutoff_at')),
        boundaryVisitedAt: resultSet.getLong(resultSet.getColumnIndex('boundary_visited_at')),
        boundaryVisitId: resultSet.getString(resultSet.getColumnIndex('boundary_visit_id')),
        updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at'))
      };
    } finally {
      resultSet.close();
    }
  }

  static readRetentionFrontierSync(
    store: relationalStore.RdbStore,
    accountUid: string
  ): HistorySyncRetentionFrontier {
    const resultSet = store.querySync(
      HistorySyncSnapshotReader.accountPredicates(HISTORY_SYNC_RETENTION_TABLE, accountUid, undefined, 1),
      ['cutoff_at', 'boundary_visited_at', 'boundary_visit_id', 'updated_at']
    );
    try {
      if (!resultSet.goToNextRow()) {
        return HistorySyncSnapshotReader.emptyRetentionFrontier();
      }
      return {
        cutoffAt: resultSet.getLong(resultSet.getColumnIndex('cutoff_at')),
        boundaryVisitedAt: resultSet.getLong(resultSet.getColumnIndex('boundary_visited_at')),
        boundaryVisitId: resultSet.getString(resultSet.getColumnIndex('boundary_visit_id')),
        updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at'))
      };
    } finally {
      resultSet.close();
    }
  }

  private static accountPredicates(
    table: string,
    accountUid: string,
    orderByDesc?: string,
    limit?: number
  ): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(table);
    predicates.equalTo('account_uid', accountUid);
    if (orderByDesc !== undefined) {
      predicates.orderByDesc(orderByDesc);
    }
    if (limit !== undefined) {
      predicates.limitAs(limit);
    }
    return predicates;
  }

  private static visitPredicates(accountUid: string, updatedAfter: number): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(HISTORY_SYNC_CANONICAL_VISITS_TABLE);
    predicates.equalTo('account_uid', accountUid);
    const normalizedUpdatedAfter = Math.max(0, Math.floor(updatedAfter));
    if (normalizedUpdatedAfter > 0) {
      predicates.greaterThan('updated_at', normalizedUpdatedAfter - 1);
    }
    predicates.orderByDesc('visited_at');
    predicates.orderByDesc('visit_id');
    return predicates;
  }

  private static buildVisits(rowVisitIds: string[], rowPayloads: string[]): HistorySyncVisit[] {
    const visits: HistorySyncVisit[] = [];
    for (let index = 0; index < rowVisitIds.length; index += 1) {
      visits.push(HistorySyncSnapshotReader.parseVisit(rowVisitIds[index], rowPayloads[index]));
    }
    return visits;
  }

  private static async buildVisitsCooperatively(
    rowVisitIds: string[],
    rowPayloads: string[],
    yieldBatch?: () => Promise<void>
  ): Promise<HistorySyncVisit[]> {
    const visits: HistorySyncVisit[] = [];
    for (let index = 0; index < rowVisitIds.length; index += 1) {
      visits.push(HistorySyncSnapshotReader.parseVisit(rowVisitIds[index], rowPayloads[index]));
      if ((index + 1) % HISTORY_SYNC_CANONICAL_READ_BATCH_SIZE === 0 && yieldBatch !== undefined) {
        await yieldBatch();
      }
    }
    return visits;
  }

  private static parseVisit(visitId: string, payload: string): HistorySyncVisit {
    const visit = JSON.parse(payload) as HistorySyncVisit;
    if (visitId.length <= 0 || visit.visitId?.trim() !== visitId) {
      throw new Error('History canonical visit identity mismatch.');
    }
    return visit;
  }

  private static emptyRetentionFrontier(): HistorySyncRetentionFrontier {
    return { cutoffAt: 0, boundaryVisitedAt: 0, boundaryVisitId: '', updatedAt: 0 };
  }
}
