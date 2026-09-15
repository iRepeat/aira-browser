import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AIRA_SYNC_SCHEMA_VERSION,
  AiraBookmarkHistoryDescriptor,
  AiraSyncSnapshot
} from '../../common/models/AiraSyncModels';
import { AiraBookmarkSnapshotValidationService } from '../../services/sync/AiraBookmarkSnapshotValidationService';
import { AiraBookmarkTombstoneLifecycleService } from '../../services/sync/AiraBookmarkTombstoneLifecycleService';
import {
  HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE,
  HUAWEI_SPACE_BOOKMARK_HEAD_TABLE
} from './HuaweiSpaceRdbStoreOwner';
import {
  HuaweiBookmarkBlockWire,
  HuaweiBookmarkProjectionOffload,
  HuaweiBookmarkProjectionRequest,
  HuaweiBookmarkProjectionWire
} from '../../services/sync/AiraHuaweiSpaceBookmarkTaskpoolTransferCodec';
import {
  HUAWEI_SPACE_BOOKMARK_FORMAT_VERSION,
  HuaweiSpaceBookmarkBlockCodec,
  HuaweiSpaceBookmarkChunk,
  HuaweiSpaceBookmarkChunkRecordData,
  HuaweiSpaceBookmarkChunkReferenceData,
  HuaweiSpaceBookmarkIndex,
  HuaweiSpaceBookmarkIndexReferenceData,
  HuaweiSpaceBookmarkManifest,
  HuaweiSpaceBookmarkManifestData
} from './HuaweiSpaceBookmarkBlockCodec';

const HUAWEI_SPACE_G8_LOG_DOMAIN: number = 0x0000;
const HUAWEI_SPACE_G8_LOG_TAG: string = 'AiraHuaweiSpace';

type HuaweiSpaceBookmarkBlockKind = 'index' | 'chunk';

const HUAWEI_SPACE_BOOKMARK_BATCH_SIZE: number = 200;
const HUAWEI_SPACE_BOOKMARK_QUERY_ID_BATCH_SIZE: number = 400;
// Physical G8 storage-epoch bucket width. It sets how often an epoch rolls over and therefore
// how often superseded Heads and older Blocks become eligible for physical GC (still gated by
// the quarantine below). Seven days matches the shared bookmark tombstone window so logical and
// physical cleanup move on the same cadence. A device offline past an epoch plus quarantine
// loses only superseded physical rows and rebootsstraps from a complete current-epoch Head, which
// is preservation-first: it may duplicate, never silently delete.
const HUAWEI_SPACE_BOOKMARK_STORAGE_EPOCH_MS: number = 7 * 24 * 60 * 60 * 1000;
const HUAWEI_SPACE_BOOKMARK_STORAGE_EPOCH_QUARANTINE_MS: number = 7 * 24 * 60 * 60 * 1000;

interface HuaweiSpaceBookmarkCatalog {
  manifestsById: Map<string, HuaweiSpaceBookmarkManifest>;
  indexesById: Map<string, HuaweiSpaceBookmarkIndex>;
  chunksById: Map<string, HuaweiSpaceBookmarkChunk>;
  physicallyCompleteManifestIds: Set<string>;
  hasAnyRows: boolean;
}

interface HuaweiSpaceBookmarkManifestReadResult {
  manifestsById: Map<string, HuaweiSpaceBookmarkManifest>;
  hasAnyRows: boolean;
}

export interface HuaweiSpaceBookmarkChunkGeneration {
  commitId: string;
  snapshot: AiraSyncSnapshot;
  history: AiraBookmarkHistoryDescriptor;
  updatedAt: number;
}

export interface HuaweiSpaceBookmarkChunkHeadReadResult {
  heads: HuaweiSpaceBookmarkChunkGeneration[];
  hasAnyRows: boolean;
  needsBlockSync: boolean;
}

export interface HuaweiSpaceBookmarkHeadSummary {
  commitId: string;
  storageEpoch: number;
  updatedAt: number;
  bookmarkFolders: number;
  bookmarkItems: number;
}

export interface HuaweiSpaceBookmarkHeadSummaryReadResult {
  heads: HuaweiSpaceBookmarkHeadSummary[];
  hasAnyRows: boolean;
}

export interface HuaweiSpaceBookmarkChunkWriteParams {
  commitId: string;
  parentCommitIds: string[];
  snapshot: AiraSyncSnapshot;
  history: AiraBookmarkHistoryDescriptor;
  deviceId: string;
  generatedAt: string;
  updatedAt: number;
}

export interface HuaweiSpaceBookmarkChunkWriteResult {
  writtenChunkCount: number;
  reusedChunkCount: number;
  totalChunkCount: number;
  writtenIndexCount: number;
  reusedIndexCount: number;
  totalIndexCount: number;
  publication: HuaweiSpaceBookmarkHeadPublication;
}

export interface HuaweiSpaceBookmarkHeadPublication {
  commitId: string;
  slotId: string;
  storageEpoch: number;
  encoded: string;
  updatedAt: number;
}

export interface HuaweiSpaceBookmarkPhysicalGcPlan {
  storageEpoch: number;
  supersededHeadRowIds: string[];
}

/**
 * The RDB half of the Huawei Space bookmark G8 format: storage epoch resolution, block/head
 * existence probes, batch insert, catalog reads and physical GC.
 *
 * The pure block format (chunking, per-chunk hashing, manifest/index encoding and validation) lives
 * in `HuaweiSpaceBookmarkBlockCodec`, which imports no relationalStore so a TaskPool worker can run
 * the write projection off the main thread. Everything here needs the store, so it stays on the one
 * thread that owns it.
 */
export class HuaweiSpaceBookmarkChunkRepository {
  private uid: string;
  private snapshotValidationService: AiraBookmarkSnapshotValidationService;
  private historyService: AiraBookmarkTombstoneLifecycleService =
    new AiraBookmarkTombstoneLifecycleService();
  private blockCodec: HuaweiSpaceBookmarkBlockCodec = new HuaweiSpaceBookmarkBlockCodec();
  // Set when a TaskPool executor is available. Left undefined otherwise, in which case every
  // projection is built on the calling thread exactly as before.
  private projectionOffload?: HuaweiBookmarkProjectionOffload;

  constructor(uid: string, snapshotValidationService: AiraBookmarkSnapshotValidationService) {
    this.uid = uid.trim();
    this.snapshotValidationService = snapshotValidationService;
  }

  /**
   * Injects the TaskPool executor for write projections. Kept as injection rather than a direct
   * import so the store never depends on the executor: the executor imports the codec to run the
   * same projection inside its worker, and an import here would put this file (which owns
   * relationalStore) into the worker's load graph by construction.
   */
  setProjectionOffload(offload: HuaweiBookmarkProjectionOffload): void {
    this.projectionOffload = offload;
  }

  getHeadCloudTableNames(): string[] {
    return [HUAWEI_SPACE_BOOKMARK_HEAD_TABLE];
  }

  getBlockCloudTableNames(): string[] {
    return [HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE];
  }

  getCloudTableNames(): string[] {
    return [HUAWEI_SPACE_BOOKMARK_HEAD_TABLE, HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE];
  }

  async describeLocalHeadRows(store: relationalStore.RdbStore): Promise<string> {
    const predicates = new relationalStore.RdbPredicates(HUAWEI_SPACE_BOOKMARK_HEAD_TABLE);
    predicates.equalTo('accountUid', this.uid);
    const resultSet = await store.queryWithoutRowCount(
      predicates,
      ['recordKind', 'logicalId', 'storageEpoch', 'data', 'updatedAt']
    );
    const kinds: string[] = [];
    const epochs: string[] = [];
    const dataBytes: string[] = [];
    let rowCount = 0;
    let maxDataBytes = 0;
    let emptyStorageEpochCount = 0;
    try {
      const kindIndex = resultSet.getColumnIndex('recordKind');
      const logicalIdIndex = resultSet.getColumnIndex('logicalId');
      const storageEpochIndex = resultSet.getColumnIndex('storageEpoch');
      const dataIndex = resultSet.getColumnIndex('data');
      while (resultSet.goToNextRow()) {
        rowCount += 1;
        const encoded = resultSet.getString(dataIndex) ?? '';
        const bytes = this.blockCodec.byteCount(encoded);
        maxDataBytes = Math.max(maxDataBytes, bytes);
        const storageEpoch = resultSet.getLong(storageEpochIndex);
        if (storageEpoch <= 0) {
          emptyStorageEpochCount += 1;
        }
        if (kinds.length < 8) {
          kinds.push((resultSet.getString(kindIndex) ?? '').trim() || 'empty');
          epochs.push(String(storageEpoch));
          dataBytes.push(`${bytes}b/${(resultSet.getString(logicalIdIndex) ?? '').trim().length}id`);
        }
      }
    } finally {
      resultSet.close();
    }
    return `rows=${rowCount} maxDataBytes=${maxDataBytes} emptyEpoch=${emptyStorageEpochCount}` +
      ` kinds=${kinds.join(',') || 'none'} epochs=${epochs.join(',') || 'none'} data=${dataBytes.join(',') || 'none'}`;
  }

  async readMaterializedHeads(store: relationalStore.RdbStore): Promise<HuaweiSpaceBookmarkChunkHeadReadResult> {
    const catalog = await this.readCatalog(store);
    const viableIds = new Set<string>(catalog.physicallyCompleteManifestIds);
    const heads = this.materializeViableHeads(catalog, viableIds);
    return {
      heads,
      hasAnyRows: catalog.hasAnyRows,
      needsBlockSync: catalog.physicallyCompleteManifestIds.size < catalog.manifestsById.size
    };
  }

  async readHeadSummaries(store: relationalStore.RdbStore): Promise<HuaweiSpaceBookmarkHeadSummaryReadResult> {
    const manifestRead = await this.readManifests(store);
    const manifests = this.selectCurrentHistoryManifests(manifestRead.manifestsById);
    const headIds = this.blockCodec.findHeadManifestIds(manifests, new Set<string>(manifests.keys()));
    const heads: HuaweiSpaceBookmarkHeadSummary[] = [];
    headIds.forEach((commitId: string): void => {
      const manifest = manifests.get(commitId);
      if (manifest !== undefined) {
        heads.push({
          commitId,
          storageEpoch: manifest.storageEpoch,
          updatedAt: manifest.updatedAt,
          bookmarkFolders: manifest.counts.folderCount,
          bookmarkItems: manifest.counts.itemCount
        });
      }
    });
    return { heads, hasAnyRows: manifestRead.hasAnyRows };
  }

  async writeSnapshotBlocks(
    store: relationalStore.RdbStore,
    params: HuaweiSpaceBookmarkChunkWriteParams
  ): Promise<HuaweiSpaceBookmarkChunkWriteResult> {
    const snapshot = this.snapshotValidationService.validate(params.snapshot, '华为云空间');
    const storageEpoch = await this.resolveWriteStorageEpoch(store);
    const projection = await this.buildWriteProjection({
      storageEpoch,
      commitId: params.commitId,
      parentCommitIds: params.parentCommitIds,
      snapshot,
      history: params.history,
      deviceId: params.deviceId,
      generatedAt: params.generatedAt,
      updatedAt: params.updatedAt
    });
    const existingChunks = await this.readStoredDataByLogicalIds(
      store,
      'chunk',
      projection.storageEpoch,
      projection.chunks.map((chunk: HuaweiBookmarkBlockWire): string => chunk.id)
    );
    const missingChunks: HuaweiBookmarkBlockWire[] = [];
    projection.chunks.forEach((chunk: HuaweiBookmarkBlockWire): void => {
      const existing = existingChunks.get(chunk.id);
      if (existing === undefined) {
        missingChunks.push(chunk);
      } else if (existing !== chunk.encoded) {
        throw new Error('华为云空间书签内容寻址 chunk 与本机已有记录不一致。');
      }
    });
    const existingIndexes = await this.readStoredDataByLogicalIds(
      store,
      'index',
      projection.storageEpoch,
      projection.indexes.map((index: HuaweiBookmarkBlockWire): string => index.id)
    );
    const missingIndexes: HuaweiBookmarkBlockWire[] = [];
    projection.indexes.forEach((index: HuaweiBookmarkBlockWire): void => {
      const existing = existingIndexes.get(index.id);
      if (existing === undefined) {
        missingIndexes.push(index);
      } else if (existing !== index.encoded) {
        throw new Error('华为云空间书签内容寻址 index 与本机已有记录不一致。');
      }
    });
    let transactionStarted = false;
    try {
      if (missingChunks.length > 0 || missingIndexes.length > 0) {
        store.beginTransaction();
        transactionStarted = true;
        for (let offset = 0; offset < missingChunks.length; offset += HUAWEI_SPACE_BOOKMARK_BATCH_SIZE) {
          const batch = missingChunks.slice(offset, offset + HUAWEI_SPACE_BOOKMARK_BATCH_SIZE)
            .map((chunk: HuaweiBookmarkBlockWire): relationalStore.ValuesBucket => {
              return this.buildValuesBucket(
                'chunk',
                projection.storageEpoch,
                chunk.id,
                chunk.encoded,
                params.updatedAt
              );
            });
          const inserted = await store.batchInsert(HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE, batch);
          if (inserted !== batch.length) {
            throw new Error('华为云空间书签 chunk 本机写入不完整。');
          }
        }
        for (let offset = 0; offset < missingIndexes.length; offset += HUAWEI_SPACE_BOOKMARK_BATCH_SIZE) {
          const batch = missingIndexes.slice(offset, offset + HUAWEI_SPACE_BOOKMARK_BATCH_SIZE)
            .map((index: HuaweiBookmarkBlockWire): relationalStore.ValuesBucket => {
              return this.buildValuesBucket(
                'index',
                projection.storageEpoch,
                index.id,
                index.encoded,
                params.updatedAt
              );
            });
          const inserted = await store.batchInsert(HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE, batch);
          if (inserted !== batch.length) {
            throw new Error('华为云空间书签 index 本机写入不完整。');
          }
        }
        store.commit();
        transactionStarted = false;
      }
      return {
        writtenChunkCount: missingChunks.length,
        reusedChunkCount: projection.chunks.length - missingChunks.length,
        totalChunkCount: projection.chunks.length,
        writtenIndexCount: missingIndexes.length,
        reusedIndexCount: projection.indexes.length - missingIndexes.length,
        totalIndexCount: projection.indexes.length,
        publication: {
          commitId: projection.commitId,
          slotId: this.buildHeadSlotId(projection.deviceId),
          storageEpoch: projection.storageEpoch,
          encoded: projection.manifestJson,
          updatedAt: projection.updatedAt
        }
      };
    } catch (error) {
      if (transactionStarted) {
        try {
          store.rollBack();
        } catch (_rollbackError) {
        }
      }
      throw this.normalizeError(error as Object);
    }
  }

  async confirmPublicationBlocks(
    store: relationalStore.RdbStore,
    publication: HuaweiSpaceBookmarkHeadPublication
  ): Promise<boolean> {
    try {
      const manifest = this.blockCodec.parseManifest(
        publication.commitId,
        publication.encoded,
        publication.updatedAt
      );
      if (this.buildHeadSlotId(manifest.deviceId) !== publication.slotId ||
        manifest.storageEpoch !== publication.storageEpoch) {
        return false;
      }
      const indexIds = manifest.indexes.map((value: HuaweiSpaceBookmarkIndexReferenceData): string => value.h);
      const indexes = await this.readIndexes(store, publication.storageEpoch, indexIds);
      const chunkIds = new Set<string>();
      indexes.forEach((index: HuaweiSpaceBookmarkIndex): void => {
        index.chunks.forEach((value: HuaweiSpaceBookmarkChunkReferenceData): void => {
          chunkIds.add(value.h);
        });
      });
      const chunks = await this.readChunks(store, publication.storageEpoch, Array.from(chunkIds));
      return this.blockCodec.isManifestPhysicallyComplete(manifest, indexes, chunks) &&
        this.materializeManifest(manifest, indexes, chunks).commitId === publication.commitId;
    } catch (_error) {
      return false;
    }
  }

  async publishHead(
    store: relationalStore.RdbStore,
    publication: HuaweiSpaceBookmarkHeadPublication
  ): Promise<void> {
    const manifest = this.blockCodec.parseManifest(
      publication.commitId,
      publication.encoded,
      publication.updatedAt
    );
    if (this.buildHeadSlotId(manifest.deviceId) !== publication.slotId ||
      manifest.storageEpoch !== publication.storageEpoch) {
      throw new Error('华为云空间书签 G8 Head 槽位与设备身份不匹配。');
    }
    await store.insert(
      HUAWEI_SPACE_BOOKMARK_HEAD_TABLE,
      {
        rowId: this.buildPublicationHeadRowId(publication.slotId, publication.commitId),
        accountUid: this.uid,
        recordKind: 'head',
        logicalId: publication.commitId,
        storageEpoch: publication.storageEpoch,
        data: publication.encoded,
        updatedAt: publication.updatedAt
      },
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
    );
  }

  async hasPublishedHead(
    store: relationalStore.RdbStore,
    publication: HuaweiSpaceBookmarkHeadPublication
  ): Promise<boolean> {
    const predicates = new relationalStore.RdbPredicates(HUAWEI_SPACE_BOOKMARK_HEAD_TABLE);
    predicates.equalTo('rowId', this.buildPublicationHeadRowId(publication.slotId, publication.commitId));
    predicates.equalTo('accountUid', this.uid);
    predicates.equalTo('recordKind', 'head');
    const resultSet = await store.queryWithoutRowCount(
      predicates,
      ['logicalId', 'storageEpoch', 'data', 'updatedAt']
    );
    try {
      if (!resultSet.goToNextRow()) {
        return false;
      }
      return resultSet.getString(resultSet.getColumnIndex('logicalId')) === publication.commitId &&
        resultSet.getLong(resultSet.getColumnIndex('storageEpoch')) === publication.storageEpoch &&
        resultSet.getString(resultSet.getColumnIndex('data')) === publication.encoded &&
        resultSet.getLong(resultSet.getColumnIndex('updatedAt')) === publication.updatedAt &&
        !resultSet.goToNextRow();
    } finally {
      resultSet.close();
    }
  }

  async hasCompleteManifest(store: relationalStore.RdbStore, commitId: string): Promise<boolean> {
    const normalizedCommitId = commitId.trim();
    if (normalizedCommitId.length <= 0) {
      return false;
    }
    const catalog = await this.readCatalog(store);
    if (!catalog.physicallyCompleteManifestIds.has(normalizedCommitId)) {
      return false;
    }
    try {
      const manifest = catalog.manifestsById.get(normalizedCommitId);
      return manifest !== undefined &&
        this.materializeManifest(manifest, catalog.indexesById, catalog.chunksById).commitId === normalizedCommitId;
    } catch (_error) {
      return false;
    }
  }

  async buildPhysicalGcPlan(store: relationalStore.RdbStore): Promise<HuaweiSpaceBookmarkPhysicalGcPlan | undefined> {
    const manifestRead = await this.readManifests(store);
    const currentHistoryManifests = this.selectCurrentHistoryManifests(manifestRead.manifestsById);
    let storageEpoch = 0;
    currentHistoryManifests.forEach((manifest: HuaweiSpaceBookmarkManifest): void => {
      storageEpoch = Math.max(storageEpoch, manifest.storageEpoch);
    });
    if (storageEpoch <= 1 || !this.hasStorageEpochClearedQuarantine(storageEpoch)) {
      return undefined;
    }
    const catalog = await this.readCatalog(store);
    const viableIds = new Set<string>(catalog.physicallyCompleteManifestIds);
    const headIds = this.blockCodec.findHeadManifestIds(catalog.manifestsById, viableIds);
    if (headIds.length <= 0 || headIds.some((commitId: string): boolean => {
      return catalog.manifestsById.get(commitId)?.storageEpoch !== storageEpoch;
    })) {
      return undefined;
    }
    const supersededHeadRowIds: string[] = [];
    manifestRead.manifestsById.forEach((manifest: HuaweiSpaceBookmarkManifest): void => {
      if (manifest.storageEpoch < storageEpoch && manifest.headRowId !== undefined) {
        supersededHeadRowIds.push(manifest.headRowId);
      }
    });
    return {
      storageEpoch,
      supersededHeadRowIds: supersededHeadRowIds.sort()
    };
  }

  async deleteSupersededHeads(
    store: relationalStore.RdbStore,
    plan: HuaweiSpaceBookmarkPhysicalGcPlan
  ): Promise<number> {
    let deleted = 0;
    for (let offset = 0; offset < plan.supersededHeadRowIds.length;
      offset += HUAWEI_SPACE_BOOKMARK_QUERY_ID_BATCH_SIZE) {
      const predicates = new relationalStore.RdbPredicates(HUAWEI_SPACE_BOOKMARK_HEAD_TABLE);
      predicates.equalTo('accountUid', this.uid);
      predicates.in(
        'rowId',
        plan.supersededHeadRowIds.slice(offset, offset + HUAWEI_SPACE_BOOKMARK_QUERY_ID_BATCH_SIZE)
      );
      deleted += await store.delete(predicates);
    }
    return deleted;
  }

  async confirmSupersededHeadsRemoved(
    store: relationalStore.RdbStore,
    plan: HuaweiSpaceBookmarkPhysicalGcPlan
  ): Promise<boolean> {
    for (let offset = 0; offset < plan.supersededHeadRowIds.length;
      offset += HUAWEI_SPACE_BOOKMARK_QUERY_ID_BATCH_SIZE) {
      const predicates = new relationalStore.RdbPredicates(HUAWEI_SPACE_BOOKMARK_HEAD_TABLE);
      predicates.equalTo('accountUid', this.uid);
      predicates.in(
        'rowId',
        plan.supersededHeadRowIds.slice(offset, offset + HUAWEI_SPACE_BOOKMARK_QUERY_ID_BATCH_SIZE)
      );
      const resultSet = await store.queryWithoutRowCount(predicates, ['rowId']);
      try {
        if (resultSet.goToNextRow()) {
          return false;
        }
      } finally {
        resultSet.close();
      }
    }
    return true;
  }

  async deleteBlocksBeforeStorageEpoch(
    store: relationalStore.RdbStore,
    storageEpoch: number
  ): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE);
    predicates.equalTo('accountUid', this.uid);
    predicates.lessThan('storageEpoch', storageEpoch);
    return store.delete(predicates);
  }

  async confirmNoBlocksBeforeStorageEpoch(
    store: relationalStore.RdbStore,
    storageEpoch: number
  ): Promise<boolean> {
    const predicates = new relationalStore.RdbPredicates(HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE);
    predicates.equalTo('accountUid', this.uid);
    predicates.lessThan('storageEpoch', storageEpoch);
    const resultSet = await store.queryWithoutRowCount(predicates, ['rowId']);
    try {
      return !resultSet.goToNextRow();
    } finally {
      resultSet.close();
    }
  }

  private async buildWriteProjection(
    request: HuaweiBookmarkProjectionRequest
  ): Promise<HuaweiBookmarkProjectionWire> {
    if (this.projectionOffload === undefined) {
      const startedAt = Date.now();
      const projection = this.blockCodec.buildWriteProjection(request);
      hilog.info(
        HUAWEI_SPACE_G8_LOG_DOMAIN,
        HUAWEI_SPACE_G8_LOG_TAG,
        'G8 projection path=inline computeMs=%{public}d chunks=%{public}d indexes=%{public}d',
        Date.now() - startedAt,
        projection.chunks.length,
        projection.indexes.length
      );
      return projection;
    }
    try {
      return await this.projectionOffload.buildWriteProjection(request);
    } catch (error) {
      const candidate = error as Error;
      // Falling back is intentional, but it silently moves this build back onto the caller's thread.
      // Log it so a log read can tell an offloaded pass from a degraded one instead of assuming the
      // TaskPool path always ran.
      const startedAt = Date.now();
      const projection = this.blockCodec.buildWriteProjection(request);
      hilog.warn(
        HUAWEI_SPACE_G8_LOG_DOMAIN,
        HUAWEI_SPACE_G8_LOG_TAG,
        'G8 projection path=inline-fallback computeMs=%{public}d chunks=%{public}d' +
          ' indexes=%{public}d reason=%{public}s',
        Date.now() - startedAt,
        projection.chunks.length,
        projection.indexes.length,
        candidate.message ?? JSON.stringify(error)
      );
      return projection;
    }
  }

  private async readCatalog(store: relationalStore.RdbStore): Promise<HuaweiSpaceBookmarkCatalog> {
    const manifestRead = await this.readManifests(store);
    const manifestsById = this.selectCurrentHistoryManifests(manifestRead.manifestsById);
    const hasAnyRows = manifestRead.hasAnyRows;
    const referencedIndexIdsByEpoch = new Map<number, Set<string>>();
    manifestsById.forEach((manifest: HuaweiSpaceBookmarkManifest): void => {
      const referencedIndexIds = referencedIndexIdsByEpoch.get(manifest.storageEpoch) ?? new Set<string>();
      manifest.indexes.forEach((reference: HuaweiSpaceBookmarkIndexReferenceData): void => {
        referencedIndexIds.add(reference.h);
      });
      referencedIndexIdsByEpoch.set(manifest.storageEpoch, referencedIndexIds);
    });
    const indexesById = new Map<string, HuaweiSpaceBookmarkIndex>();
    const indexEpochs = Array.from(referencedIndexIdsByEpoch.keys()).sort((left: number, right: number): number => {
      return left - right;
    });
    for (let epochIndex = 0; epochIndex < indexEpochs.length; epochIndex += 1) {
      const storageEpoch = indexEpochs[epochIndex];
      const epochIndexes = await this.readIndexes(
        store,
        storageEpoch,
        Array.from(referencedIndexIdsByEpoch.get(storageEpoch) ?? new Set<string>())
      );
      epochIndexes.forEach((value: HuaweiSpaceBookmarkIndex, key: string): void => {
        indexesById.set(key, value);
      });
    }
    const referencedChunkIdsByEpoch = new Map<number, Set<string>>();
    indexesById.forEach((index: HuaweiSpaceBookmarkIndex): void => {
      const referencedChunkIds = referencedChunkIdsByEpoch.get(index.storageEpoch) ?? new Set<string>();
      index.chunks.forEach((reference: HuaweiSpaceBookmarkChunkReferenceData): void => {
        referencedChunkIds.add(reference.h);
      });
      referencedChunkIdsByEpoch.set(index.storageEpoch, referencedChunkIds);
    });
    const chunksById = new Map<string, HuaweiSpaceBookmarkChunk>();
    const chunkEpochs = Array.from(referencedChunkIdsByEpoch.keys()).sort((left: number, right: number): number => {
      return left - right;
    });
    for (let epochIndex = 0; epochIndex < chunkEpochs.length; epochIndex += 1) {
      const storageEpoch = chunkEpochs[epochIndex];
      const epochChunks = await this.readChunks(
        store,
        storageEpoch,
        Array.from(referencedChunkIdsByEpoch.get(storageEpoch) ?? new Set<string>())
      );
      epochChunks.forEach((value: HuaweiSpaceBookmarkChunk, key: string): void => {
        chunksById.set(key, value);
      });
    }
    const physicallyCompleteManifestIds = new Set<string>();
    manifestsById.forEach((manifest: HuaweiSpaceBookmarkManifest, commitId: string): void => {
      if (this.blockCodec.isManifestPhysicallyComplete(manifest, indexesById, chunksById)) {
        physicallyCompleteManifestIds.add(commitId);
      }
    });
    return {
      manifestsById,
      indexesById,
      chunksById,
      physicallyCompleteManifestIds,
      hasAnyRows
    };
  }

  private selectCurrentHistoryManifests(
    candidates: Map<string, HuaweiSpaceBookmarkManifest>
  ): Map<string, HuaweiSpaceBookmarkManifest> {
    let newestRetainedFrom = -1;
    candidates.forEach((manifest: HuaweiSpaceBookmarkManifest): void => {
      newestRetainedFrom = Math.max(newestRetainedFrom, Date.parse(manifest.history.retainedFrom));
    });
    if (newestRetainedFrom < 0) {
      return candidates;
    }
    const selected = new Map<string, HuaweiSpaceBookmarkManifest>();
    candidates.forEach((manifest: HuaweiSpaceBookmarkManifest, commitId: string): void => {
      if (Date.parse(manifest.history.retainedFrom) === newestRetainedFrom) {
        selected.set(commitId, manifest);
      }
    });
    return selected;
  }

  private async readIndexes(
    store: relationalStore.RdbStore,
    storageEpoch: number,
    indexIds: string[]
  ): Promise<Map<string, HuaweiSpaceBookmarkIndex>> {
    const indexes = new Map<string, HuaweiSpaceBookmarkIndex>();
    const normalizedIds = indexIds.slice().sort();
    for (let offset = 0; offset < normalizedIds.length; offset += HUAWEI_SPACE_BOOKMARK_QUERY_ID_BATCH_SIZE) {
      const batch = normalizedIds.slice(offset, offset + HUAWEI_SPACE_BOOKMARK_QUERY_ID_BATCH_SIZE);
      const predicates = new relationalStore.RdbPredicates(HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE);
      predicates.equalTo('accountUid', this.uid);
      predicates.equalTo('recordKind', 'index');
      predicates.equalTo('storageEpoch', storageEpoch);
      predicates.in('logicalId', batch);
      const resultSet = await store.queryWithoutRowCount(predicates, ['logicalId', 'data']);
      try {
        const logicalIdIndex = resultSet.getColumnIndex('logicalId');
        const dataIndex = resultSet.getColumnIndex('data');
        while (resultSet.goToNextRow()) {
          const indexId = resultSet.getString(logicalIdIndex).trim();
          const blockKey = this.blockCodec.buildBlockMapKey(storageEpoch, indexId);
          if (indexId.length <= 0 || indexes.has(blockKey)) {
            continue;
          }
          const encoded = resultSet.getString(dataIndex);
          try {
            if (this.blockCodec.sha256Hex(encoded) !== indexId) {
              continue;
            }
            indexes.set(blockKey, this.blockCodec.parseIndex(storageEpoch, indexId, encoded));
          } catch (_error) {
          }
        }
      } finally {
        resultSet.close();
      }
    }
    return indexes;
  }

  private async readManifests(
    store: relationalStore.RdbStore
  ): Promise<HuaweiSpaceBookmarkManifestReadResult> {
    const predicates = new relationalStore.RdbPredicates(HUAWEI_SPACE_BOOKMARK_HEAD_TABLE);
    predicates.equalTo('accountUid', this.uid);
    predicates.equalTo('recordKind', 'head');
    const resultSet = await store.queryWithoutRowCount(
      predicates,
      ['rowId', 'logicalId', 'storageEpoch', 'data', 'updatedAt']
    );
    const manifests = new Map<string, HuaweiSpaceBookmarkManifest>();
    let hasAnyRows = false;
    try {
      const rowIdIndex = resultSet.getColumnIndex('rowId');
      const logicalIdIndex = resultSet.getColumnIndex('logicalId');
      const storageEpochIndex = resultSet.getColumnIndex('storageEpoch');
      const dataIndex = resultSet.getColumnIndex('data');
      const updatedAtIndex = resultSet.getColumnIndex('updatedAt');
      while (resultSet.goToNextRow()) {
        hasAnyRows = true;
        const commitId = resultSet.getString(logicalIdIndex).trim();
        if (commitId.length <= 0 || manifests.has(commitId)) {
          continue;
        }
        const encoded = resultSet.getString(dataIndex);
        try {
          const manifest = this.blockCodec.parseManifest(
            commitId,
            encoded,
            resultSet.getLong(updatedAtIndex)
          );
          const rowStorageEpoch = resultSet.getLong(storageEpochIndex);
          const rowId = resultSet.getString(rowIdIndex);
          if (rowStorageEpoch !== manifest.storageEpoch) {
            throw new Error('华为云空间书签 G8 Head 槽位标识不匹配。');
          }
          if (!this.isRecognizedHeadRowId(rowId, manifest.deviceId, commitId)) {
            hilog.warn(
              HUAWEI_SPACE_G8_LOG_DOMAIN,
              HUAWEI_SPACE_G8_LOG_TAG,
              'G8 head rowId skipped uid=%{public}s commit=%{public}s rowId=%{public}s',
              this.uid.substring(0, 8),
              commitId,
              rowId
            );
            continue;
          }
          manifest.headRowId = rowId;
          manifests.set(commitId, manifest);
        } catch (error) {
          if (this.declaresCurrentManifestFormat(encoded)) {
            throw error as Error;
          }
        }
      }
    } finally {
      resultSet.close();
    }
    return { manifestsById: manifests, hasAnyRows };
  }

  private declaresCurrentManifestFormat(encoded: string): boolean {
    try {
      const value = JSON.parse(encoded) as HuaweiSpaceBookmarkManifestData;
      return value !== undefined && value !== null &&
        value.formatVersion === HUAWEI_SPACE_BOOKMARK_FORMAT_VERSION;
    } catch (_error) {
      return encoded.indexOf(`\"formatVersion\":${HUAWEI_SPACE_BOOKMARK_FORMAT_VERSION}`) >= 0;
    }
  }

  private async readChunks(
    store: relationalStore.RdbStore,
    storageEpoch: number,
    chunkIds: string[]
  ): Promise<Map<string, HuaweiSpaceBookmarkChunk>> {
    const chunks = new Map<string, HuaweiSpaceBookmarkChunk>();
    const normalizedIds = chunkIds.slice().sort();
    for (let offset = 0; offset < normalizedIds.length; offset += HUAWEI_SPACE_BOOKMARK_QUERY_ID_BATCH_SIZE) {
      const batch = normalizedIds.slice(offset, offset + HUAWEI_SPACE_BOOKMARK_QUERY_ID_BATCH_SIZE);
      const predicates = new relationalStore.RdbPredicates(HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE);
      predicates.equalTo('accountUid', this.uid);
      predicates.equalTo('recordKind', 'chunk');
      predicates.equalTo('storageEpoch', storageEpoch);
      predicates.in('logicalId', batch);
      const resultSet = await store.queryWithoutRowCount(predicates, ['logicalId', 'data']);
      try {
        const logicalIdIndex = resultSet.getColumnIndex('logicalId');
        const dataIndex = resultSet.getColumnIndex('data');
        while (resultSet.goToNextRow()) {
          const chunkId = resultSet.getString(logicalIdIndex).trim();
          const blockKey = this.blockCodec.buildBlockMapKey(storageEpoch, chunkId);
          if (chunkId.length <= 0 || chunks.has(blockKey)) {
            continue;
          }
          const encoded = resultSet.getString(dataIndex);
          try {
            if (this.blockCodec.sha256Hex(encoded) !== chunkId) {
              continue;
            }
            chunks.set(blockKey, this.blockCodec.parseChunk(storageEpoch, chunkId, encoded));
          } catch (_error) {
          }
        }
      } finally {
        resultSet.close();
      }
    }
    return chunks;
  }

  private materializeViableHeads(
    catalog: HuaweiSpaceBookmarkCatalog,
    viableIds: Set<string>
  ): HuaweiSpaceBookmarkChunkGeneration[] {
    while (viableIds.size > 0) {
      const headIds = this.blockCodec.findHeadManifestIds(catalog.manifestsById, viableIds);
      const heads: HuaweiSpaceBookmarkChunkGeneration[] = [];
      const invalidHeadIds: string[] = [];
      headIds.forEach((commitId: string): void => {
        const manifest = catalog.manifestsById.get(commitId);
        if (manifest === undefined) {
          invalidHeadIds.push(commitId);
          return;
        }
        try {
          heads.push(this.materializeManifest(manifest, catalog.indexesById, catalog.chunksById));
        } catch (_error) {
          invalidHeadIds.push(commitId);
        }
      });
      if (invalidHeadIds.length <= 0) {
        return heads;
      }
      invalidHeadIds.forEach((commitId: string): void => {
        viableIds.delete(commitId);
      });
    }
    return [];
  }

  private materializeManifest(
    manifest: HuaweiSpaceBookmarkManifest,
    indexesById: Map<string, HuaweiSpaceBookmarkIndex>,
    chunksById: Map<string, HuaweiSpaceBookmarkChunk>
  ): HuaweiSpaceBookmarkChunkGeneration {
    const records: HuaweiSpaceBookmarkChunkRecordData[] = [];
    const recordKeys = new Set<string>();
    manifest.indexes.forEach((indexReference: HuaweiSpaceBookmarkIndexReferenceData): void => {
      const index = indexesById.get(this.blockCodec.buildBlockMapKey(manifest.storageEpoch, indexReference.h));
      if (index === undefined || index.shardIndex !== indexReference.s ||
        index.chunks.length !== indexReference.n) {
        throw new Error('华为云空间书签 manifest 引用的 index 尚未完整到达。');
      }
      index.chunks.forEach((reference: HuaweiSpaceBookmarkChunkReferenceData): void => {
        const chunk = chunksById.get(this.blockCodec.buildBlockMapKey(manifest.storageEpoch, reference.h));
        if (chunk === undefined || chunk.bucketIndex !== reference.b || chunk.lane !== reference.l ||
          chunk.segmentIndex !== reference.s || chunk.records.length !== reference.n) {
          throw new Error('华为云空间书签 index 引用的 chunk 尚未完整到达。');
        }
        chunk.records.forEach((record: HuaweiSpaceBookmarkChunkRecordData): void => {
          const recordKey = this.blockCodec.buildStableRecordKey(record);
          if (recordKeys.has(recordKey)) {
            throw new Error('华为云空间书签完整快照含重复记录。');
          }
          recordKeys.add(recordKey);
          records.push(record);
        });
      });
    });
    const orderedRecords = this.blockCodec.sortChunkRecordsByStableKey(records);
    const shared = this.blockCodec.buildDataSet(orderedRecords, 'shared');
    const snapshot: AiraSyncSnapshot = {
      meta: {
        version: AIRA_SYNC_SCHEMA_VERSION,
        deviceId: manifest.deviceId,
        generatedAt: manifest.generatedAt
      },
      bookmarkFolders: shared.bookmarkFolders,
      bookmarkItems: shared.bookmarkItems,
      bookmarkOrders: shared.bookmarkOrders,
      tombstones: shared.tombstones
    };
    if (manifest.hasPrivateData) {
      snapshot.appPrivateBookmarks = this.blockCodec.buildDataSet(orderedRecords, 'appPrivate');
    }
    const validated = this.snapshotValidationService.validate(snapshot, '华为云空间');
    this.historyService.assertSnapshotWithinHistory(validated, manifest.history, '华为云空间');
    if (!this.blockCodec.sameCounts(this.blockCodec.countSnapshotRecords(validated), manifest.counts)) {
      throw new Error('华为云空间书签 manifest 记录数量不匹配。');
    }
    return {
      commitId: manifest.commitId,
      snapshot: validated,
      history: manifest.history,
      updatedAt: manifest.updatedAt
    };
  }

  private async readStoredDataByLogicalIds(
    store: relationalStore.RdbStore,
    recordKind: HuaweiSpaceBookmarkBlockKind,
    storageEpoch: number,
    logicalIds: string[]
  ): Promise<Map<string, string>> {
    const values = new Map<string, string>();
    const normalizedIds = logicalIds.slice().sort();
    for (let offset = 0; offset < normalizedIds.length; offset += HUAWEI_SPACE_BOOKMARK_QUERY_ID_BATCH_SIZE) {
      const batch = normalizedIds.slice(offset, offset + HUAWEI_SPACE_BOOKMARK_QUERY_ID_BATCH_SIZE);
      const predicates = new relationalStore.RdbPredicates(HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE);
      predicates.equalTo('accountUid', this.uid);
      predicates.equalTo('recordKind', recordKind);
      predicates.equalTo('storageEpoch', storageEpoch);
      predicates.in('logicalId', batch);
      const resultSet = await store.queryWithoutRowCount(predicates, ['logicalId', 'data']);
      try {
        const logicalIdIndex = resultSet.getColumnIndex('logicalId');
        const dataIndex = resultSet.getColumnIndex('data');
        while (resultSet.goToNextRow()) {
          const logicalId = resultSet.getString(logicalIdIndex).trim();
          if (logicalId.length <= 0 || values.has(logicalId)) {
            throw new Error('华为云空间书签本机记录标识无效或重复。');
          }
          values.set(logicalId, resultSet.getString(dataIndex));
        }
      } finally {
        resultSet.close();
      }
    }
    return values;
  }

  private buildValuesBucket(
    recordKind: HuaweiSpaceBookmarkBlockKind,
    storageEpoch: number,
    logicalId: string,
    data: string,
    updatedAt: number
  ): relationalStore.ValuesBucket {
    return {
      rowId: this.buildRowId(recordKind, storageEpoch, logicalId),
      accountUid: this.uid,
      recordKind,
      logicalId,
      storageEpoch,
      data,
      updatedAt
    };
  }

  private buildRowId(recordKind: HuaweiSpaceBookmarkBlockKind, storageEpoch: number, logicalId: string): string {
    return [this.uid, 'g8', String(storageEpoch), recordKind, logicalId]
      .map((value: string): string => `${value.length}:${value}`).join('|');
  }

  private async resolveWriteStorageEpoch(store: relationalStore.RdbStore): Promise<number> {
    let storageEpoch = this.resolveCurrentStorageEpoch();
    const manifestRead = await this.readManifests(store);
    manifestRead.manifestsById.forEach((manifest: HuaweiSpaceBookmarkManifest): void => {
      storageEpoch = Math.max(storageEpoch, manifest.storageEpoch);
    });
    return storageEpoch;
  }

  private resolveCurrentStorageEpoch(now: number = Date.now()): number {
    return Math.floor(Math.max(0, now) / HUAWEI_SPACE_BOOKMARK_STORAGE_EPOCH_MS) + 1;
  }

  private hasStorageEpochClearedQuarantine(storageEpoch: number, now: number = Date.now()): boolean {
    const epochStartedAt = (storageEpoch - 1) * HUAWEI_SPACE_BOOKMARK_STORAGE_EPOCH_MS;
    return now >= epochStartedAt + HUAWEI_SPACE_BOOKMARK_STORAGE_EPOCH_QUARANTINE_MS;
  }

  private buildHeadSlotId(deviceId: string): string {
    return this.blockCodec.sha256Hex(this.blockCodec.requireString(deviceId, 'deviceId'));
  }

  private isRecognizedHeadRowId(rowId: string, deviceId: string, commitId: string): boolean {
    const slotId = this.buildHeadSlotId(deviceId);
    return rowId === this.buildPublicationHeadRowId(slotId, commitId) ||
      rowId === this.buildReplaceableHeadRowId(slotId);
  }

  private buildReplaceableHeadRowId(slotId: string): string {
    return [this.uid, 'g8', 'head', this.blockCodec.requireHash(slotId, 'slotId')]
      .map((value: string): string => `${value.length}:${value}`).join('|');
  }

  private buildPublicationHeadRowId(slotId: string, commitId: string): string {
    return [this.uid, 'g8', 'head', this.blockCodec.requireHash(slotId, 'slotId'),
      this.blockCodec.requireString(commitId, 'commitId')]
      .map((value: string): string => `${value.length}:${value}`).join('|');
  }

  private normalizeError(error: Object): Error {
    const candidate = error as Error;
    return new Error(candidate.message !== undefined && candidate.message.length > 0
      ? candidate.message
      : JSON.stringify(error));
  }
}
