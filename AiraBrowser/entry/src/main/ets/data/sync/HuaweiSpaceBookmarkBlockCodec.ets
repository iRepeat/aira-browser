import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import {
  AIRA_BOOKMARK_HISTORY_VERSION,
  AIRA_SYNC_SCHEMA_VERSION,
  AiraBookmarkHistoryDescriptor,
  AiraSyncBookmarkDataSet,
  AiraSyncBookmarkFolderEntity,
  AiraSyncBookmarkItemEntity,
  AiraSyncBookmarkOrder,
  AiraSyncSnapshot,
  AiraSyncTombstone
} from '../../common/models/AiraSyncModels';
import {
  HuaweiBookmarkBlockWire,
  HuaweiBookmarkProjectionRequest,
  HuaweiBookmarkProjectionWire
} from '../../services/sync/AiraHuaweiSpaceBookmarkTaskpoolTransferCodec';

/**
 * The pure half of the Huawei Space bookmark G8 block format.
 *
 * Imports no relationalStore and no runtime service, so an ArkTS TaskPool worker can load it to
 * build a write projection off the main thread. The RDB half (epoch resolution, existence probes,
 * batch insert, catalog reads, GC) stays in `HuaweiSpaceBookmarkChunkRepository`, which owns the
 * only store handle; this module is deliberately the mirror of `HuaweiSpaceHistorySnapshotCodec`,
 * which the History path already splits the same way.
 */

export type HuaweiSpaceBookmarkPartition = 'shared' | 'appPrivate';
export type HuaweiSpaceBookmarkRecordKind = 'folder' | 'item' | 'orderPart' | 'tombstone';
export type HuaweiSpaceBookmarkLane = 'live' | 'order' | 'tombstone';

export const HUAWEI_SPACE_BOOKMARK_FORMAT_VERSION: number = 1;
export const HUAWEI_SPACE_BOOKMARK_BUCKET_COUNT: number = 64;
export const HUAWEI_SPACE_BOOKMARK_INDEX_SHARD_COUNT: number = 64;
export const HUAWEI_SPACE_BOOKMARK_BUCKETS_PER_INDEX_SHARD: number = 1;
export const HUAWEI_SPACE_BOOKMARK_ORDER_IDS_PER_PART: number = 64;
export const HUAWEI_SPACE_BOOKMARK_MAX_CHUNK_REFERENCES_PER_INDEX: number = 128;
export const HUAWEI_SPACE_BOOKMARK_MAX_ROW_JSON_BYTES: number = 12 * 1024;
export const HUAWEI_SPACE_BOOKMARK_MAX_PAGE_JSON_BYTES: number = 10 * 1024;
export const HUAWEI_SPACE_BOOKMARK_LANES: HuaweiSpaceBookmarkLane[] = ['live', 'order', 'tombstone'];

export interface HuaweiSpaceBookmarkChunkRecordData {
  p: HuaweiSpaceBookmarkPartition;
  k: HuaweiSpaceBookmarkRecordKind;
  i: string;
  s: number;
  d: string;
}

export interface HuaweiSpaceBookmarkChunkData {
  formatVersion: number;
  bucketIndex: number;
  lane: HuaweiSpaceBookmarkLane;
  segmentIndex: number;
  records: HuaweiSpaceBookmarkChunkRecordData[];
}

export interface HuaweiSpaceBookmarkChunkReferenceData {
  b: number;
  l: HuaweiSpaceBookmarkLane;
  s: number;
  h: string;
  n: number;
}

export interface HuaweiSpaceBookmarkIndexData {
  formatVersion: number;
  shardIndex: number;
  chunks: HuaweiSpaceBookmarkChunkReferenceData[];
}

export interface HuaweiSpaceBookmarkIndexReferenceData {
  s: number;
  h: string;
  n: number;
}

export interface HuaweiSpaceBookmarkOrderPartData {
  type: 'bookmark-order-part';
  parentId: string | null;
  ids: string[];
  updatedAt: string;
  updatedBy: string;
  revision: number;
  partIndex: number;
  partCount: number;
}

export interface HuaweiSpaceBookmarkRecordCounts {
  folderCount: number;
  itemCount: number;
  orderCount: number;
  tombstoneCount: number;
  privateFolderCount: number;
  privateItemCount: number;
  privateOrderCount: number;
  privateTombstoneCount: number;
}

export interface HuaweiSpaceBookmarkManifestData {
  formatVersion: number;
  schemaVersion: number;
  bucketCount: number;
  storageEpoch: number;
  commitId: string;
  parentCommitIds: string[];
  deviceId: string;
  generatedAt: string;
  history: AiraBookmarkHistoryDescriptor;
  updatedAt: number;
  hasPrivateData: boolean;
  indexes: HuaweiSpaceBookmarkIndexReferenceData[];
  physicalRecordCount: number;
  counts: HuaweiSpaceBookmarkRecordCounts;
  aggregateChecksum: string;
}

export interface HuaweiSpaceBookmarkManifest {
  headRowId?: string;
  storageEpoch: number;
  commitId: string;
  parentCommitIds: string[];
  deviceId: string;
  generatedAt: string;
  history: AiraBookmarkHistoryDescriptor;
  updatedAt: number;
  hasPrivateData: boolean;
  indexes: HuaweiSpaceBookmarkIndexReferenceData[];
  physicalRecordCount: number;
  counts: HuaweiSpaceBookmarkRecordCounts;
  aggregateChecksum: string;
}

export interface HuaweiSpaceBookmarkChunk {
  chunkId: string;
  storageEpoch: number;
  bucketIndex: number;
  lane: HuaweiSpaceBookmarkLane;
  segmentIndex: number;
  records: HuaweiSpaceBookmarkChunkRecordData[];
  encoded: string;
}

export interface HuaweiSpaceBookmarkIndex {
  indexId: string;
  storageEpoch: number;
  shardIndex: number;
  chunks: HuaweiSpaceBookmarkChunkReferenceData[];
  encoded: string;
}

export interface HuaweiSpaceBookmarkProjection {
  manifest: HuaweiSpaceBookmarkManifest;
  manifestJson: string;
  indexes: HuaweiSpaceBookmarkIndex[];
  chunks: HuaweiSpaceBookmarkChunk[];
}

// A chunk record paired with the stable key it is ordered by, so a sort does not rebuild the key on
// every comparison.
interface SortableChunkRecord {
  key: string;
  record: HuaweiSpaceBookmarkChunkRecordData;
}

export class HuaweiSpaceBookmarkBlockCodec {
  private encoder: util.TextEncoder = util.TextEncoder.create('utf-8');

  /**
   * Builds the G8 write projection: canonical records, lane/segment chunking with per-chunk SHA-256
   * ids, index shards and the manifest. Pure, so it runs either on the calling thread or inside a
   * TaskPool worker with identical results.
   */
  buildWriteProjection(request: HuaweiBookmarkProjectionRequest): HuaweiBookmarkProjectionWire {
    const projection = this.buildProjection(request);
    return {
      commitId: projection.manifest.commitId,
      storageEpoch: projection.manifest.storageEpoch,
      deviceId: projection.manifest.deviceId,
      updatedAt: projection.manifest.updatedAt,
      manifestJson: projection.manifestJson,
      chunks: projection.chunks.map((chunk: HuaweiSpaceBookmarkChunk): HuaweiBookmarkBlockWire => {
        return { id: chunk.chunkId, encoded: chunk.encoded };
      }),
      indexes: projection.indexes.map((index: HuaweiSpaceBookmarkIndex): HuaweiBookmarkBlockWire => {
        return { id: index.indexId, encoded: index.encoded };
      })
    };
  }

  buildDataSet(
    records: HuaweiSpaceBookmarkChunkRecordData[],
    partition: HuaweiSpaceBookmarkPartition
  ): AiraSyncBookmarkDataSet {
    const dataSet: AiraSyncBookmarkDataSet = {
      bookmarkFolders: [],
      bookmarkItems: [],
      bookmarkOrders: [],
      tombstones: []
    };
    const orderPartsByLogicalKey = new Map<string, HuaweiSpaceBookmarkOrderPartData[]>();
    records.forEach((record: HuaweiSpaceBookmarkChunkRecordData): void => {
      if (record.p !== partition) {
        return;
      }
      if (record.k === 'folder') {
        const value = this.parseFolder(record.d);
        if (value.id !== record.i) {
          throw new Error('华为云空间书签文件夹逻辑键不匹配。');
        }
        dataSet.bookmarkFolders.push(value);
      } else if (record.k === 'item') {
        const value = this.parseItem(record.d);
        if (value.id !== record.i) {
          throw new Error('华为云空间书签条目逻辑键不匹配。');
        }
        dataSet.bookmarkItems.push(value);
      } else if (record.k === 'orderPart') {
        const value = this.parseOrderPart(record.d);
        if (this.buildOrderPartLogicalKey(value) !== record.i || value.partIndex !== record.s) {
          throw new Error('华为云空间书签排序逻辑键不匹配。');
        }
        const parts = orderPartsByLogicalKey.get(record.i) ?? [];
        parts.push(value);
        orderPartsByLogicalKey.set(record.i, parts);
      } else {
        const value = this.parseTombstone(record.d);
        if (this.buildTombstoneLogicalKey(value) !== record.i) {
          throw new Error('华为云空间书签墓碑逻辑键不匹配。');
        }
        dataSet.tombstones.push(value);
      }
    });
    Array.from(orderPartsByLogicalKey.keys()).sort().forEach((logicalKey: string): void => {
      const parts = orderPartsByLogicalKey.get(logicalKey) ?? [];
      dataSet.bookmarkOrders.push(this.materializeOrderParts(logicalKey, parts));
    });
    dataSet.bookmarkFolders.sort((left: AiraSyncBookmarkFolderEntity, right: AiraSyncBookmarkFolderEntity): number => {
      return left.id.localeCompare(right.id);
    });
    dataSet.bookmarkItems.sort((left: AiraSyncBookmarkItemEntity, right: AiraSyncBookmarkItemEntity): number => {
      return left.id.localeCompare(right.id);
    });
    dataSet.bookmarkOrders.sort((left: AiraSyncBookmarkOrder, right: AiraSyncBookmarkOrder): number => {
      return this.buildOrderLogicalKey(left).localeCompare(this.buildOrderLogicalKey(right));
    });
    dataSet.tombstones.sort((left: AiraSyncTombstone, right: AiraSyncTombstone): number => {
      return this.buildTombstoneLogicalKey(left).localeCompare(this.buildTombstoneLogicalKey(right));
    });
    return dataSet;
  }

  parseManifest(commitId: string, encoded: string, updatedAt: number): HuaweiSpaceBookmarkManifest {
    this.assertEncodedSize(encoded, HUAWEI_SPACE_BOOKMARK_MAX_ROW_JSON_BYTES, 'manifest');
    const value = this.parseObject(encoded, 'manifest') as HuaweiSpaceBookmarkManifestData;
    if (this.requireNonNegativeInteger(value.formatVersion, 'formatVersion') !== HUAWEI_SPACE_BOOKMARK_FORMAT_VERSION ||
      this.requireNonNegativeInteger(value.schemaVersion, 'schemaVersion') !== AIRA_SYNC_SCHEMA_VERSION ||
      this.requireNonNegativeInteger(value.bucketCount, 'bucketCount') !== HUAWEI_SPACE_BOOKMARK_BUCKET_COUNT ||
      this.requireString(value.commitId, 'commitId') !== commitId) {
      throw new Error('华为云空间书签 G8 Head 版本或标识不兼容。');
    }
    if (value.hasPrivateData !== true && value.hasPrivateData !== false) {
      throw new Error('华为云空间书签 manifest 私密分区标记无效。');
    }
    const indexes = this.parseIndexReferences(value.indexes);
    const physicalRecordCount = this.requireNonNegativeInteger(value.physicalRecordCount, 'physicalRecordCount');
    const counts = this.parseCounts(value.counts, value.hasPrivateData);
    const parentCommitIds = this.normalizeStringArray(value.parentCommitIds, '父 commit');
    if (parentCommitIds.indexOf(commitId) >= 0) {
      throw new Error('华为云空间书签 manifest 不能引用自身。');
    }
    const encodedUpdatedAt = this.requireNonNegativeInteger(value.updatedAt, 'updatedAt');
    const rowUpdatedAt = this.requireNonNegativeInteger(updatedAt, 'updatedAt');
    if (encodedUpdatedAt !== rowUpdatedAt) {
      throw new Error('华为云空间书签 manifest 更新时间元数据不匹配。');
    }
    const manifest: HuaweiSpaceBookmarkManifest = {
      storageEpoch: this.requirePositiveInteger(value.storageEpoch, 'storageEpoch'),
      commitId,
      parentCommitIds,
      deviceId: this.requireString(value.deviceId, 'deviceId'),
      generatedAt: this.requireString(value.generatedAt, 'generatedAt'),
      history: this.requireHistory(value.history),
      updatedAt: encodedUpdatedAt,
      hasPrivateData: value.hasPrivateData,
      indexes,
      physicalRecordCount,
      counts,
      aggregateChecksum: this.requireHash(value.aggregateChecksum, 'aggregateChecksum')
    };
    const canonical: HuaweiSpaceBookmarkManifestData = {
      formatVersion: HUAWEI_SPACE_BOOKMARK_FORMAT_VERSION,
      schemaVersion: AIRA_SYNC_SCHEMA_VERSION,
      bucketCount: HUAWEI_SPACE_BOOKMARK_BUCKET_COUNT,
      storageEpoch: manifest.storageEpoch,
      commitId: manifest.commitId,
      parentCommitIds: manifest.parentCommitIds,
      deviceId: manifest.deviceId,
      generatedAt: manifest.generatedAt,
      history: manifest.history,
      updatedAt: manifest.updatedAt,
      hasPrivateData: manifest.hasPrivateData,
      indexes: manifest.indexes,
      physicalRecordCount: manifest.physicalRecordCount,
      counts: manifest.counts,
      aggregateChecksum: manifest.aggregateChecksum
    };
    if (JSON.stringify(canonical) !== encoded) {
      throw new Error('华为云空间书签 manifest 不是规范编码。');
    }
    return manifest;
  }

  parseIndex(storageEpoch: number, indexId: string, encoded: string): HuaweiSpaceBookmarkIndex {
    this.assertEncodedSize(encoded, HUAWEI_SPACE_BOOKMARK_MAX_ROW_JSON_BYTES, 'index');
    const value = this.parseObject(encoded, 'index') as HuaweiSpaceBookmarkIndexData;
    if (this.requireNonNegativeInteger(value.formatVersion, 'formatVersion') !== HUAWEI_SPACE_BOOKMARK_FORMAT_VERSION) {
      throw new Error('华为云空间书签 index 版本不兼容。');
    }
    const shardIndex = this.requireIndexShard(value.shardIndex);
    const chunks = this.parseChunkReferences(value.chunks, shardIndex);
    const canonical: HuaweiSpaceBookmarkIndexData = {
      formatVersion: HUAWEI_SPACE_BOOKMARK_FORMAT_VERSION,
      shardIndex,
      chunks
    };
    if (JSON.stringify(canonical) !== encoded) {
      throw new Error('华为云空间书签 index 不是规范编码。');
    }
    return { indexId, storageEpoch, shardIndex, chunks, encoded };
  }

  parseChunk(storageEpoch: number, chunkId: string, encoded: string): HuaweiSpaceBookmarkChunk {
    this.assertEncodedSize(encoded, HUAWEI_SPACE_BOOKMARK_MAX_PAGE_JSON_BYTES, 'chunk');
    const value = this.parseObject(encoded, 'chunk') as HuaweiSpaceBookmarkChunkData;
    if (this.requireNonNegativeInteger(value.formatVersion, 'formatVersion') !== HUAWEI_SPACE_BOOKMARK_FORMAT_VERSION) {
      throw new Error('华为云空间书签 chunk 版本不兼容。');
    }
    const bucketIndex = this.requireBucketIndex(value.bucketIndex);
    const lane = this.requireLane(value.lane);
    const segmentIndex = this.requireNonNegativeInteger(value.segmentIndex, 'segmentIndex');
    if (!Array.isArray(value.records) || value.records.length <= 0) {
      throw new Error('华为云空间书签 chunk 记录集合无效。');
    }
    const records: HuaweiSpaceBookmarkChunkRecordData[] = [];
    let previousKey = '';
    value.records.forEach((candidate: HuaweiSpaceBookmarkChunkRecordData, index: number): void => {
      const record = this.parseChunkRecord(candidate);
      const key = this.buildStableRecordKey(record);
      if (this.resolveBucketIndex(record) !== bucketIndex || this.resolveRecordLane(record) !== lane ||
        (index > 0 && previousKey.localeCompare(key) >= 0)) {
        throw new Error('华为云空间书签 chunk 分桶或排序无效。');
      }
      previousKey = key;
      records.push(record);
    });
    if (this.encodeChunk(bucketIndex, lane, segmentIndex, records) !== encoded) {
      throw new Error('华为云空间书签 chunk 不是规范编码。');
    }
    return { chunkId, storageEpoch, bucketIndex, lane, segmentIndex, records, encoded };
  }

  isManifestPhysicallyComplete(
    manifest: HuaweiSpaceBookmarkManifest,
    indexesById: Map<string, HuaweiSpaceBookmarkIndex>,
    chunksById: Map<string, HuaweiSpaceBookmarkChunk>
  ): boolean {
    const chunkReferences: HuaweiSpaceBookmarkChunkReferenceData[] = [];
    for (let referenceIndex = 0; referenceIndex < manifest.indexes.length; referenceIndex += 1) {
      const reference = manifest.indexes[referenceIndex];
      const index = indexesById.get(this.buildBlockMapKey(manifest.storageEpoch, reference.h));
      if (index === undefined || index.shardIndex !== reference.s || index.chunks.length !== reference.n) {
        return false;
      }
      index.chunks.forEach((chunkReference: HuaweiSpaceBookmarkChunkReferenceData): void => {
        chunkReferences.push(chunkReference);
      });
    }
    let physicalRecordCount = 0;
    for (let index = 0; index < chunkReferences.length; index += 1) {
      const reference = chunkReferences[index];
      const chunk = chunksById.get(this.buildBlockMapKey(manifest.storageEpoch, reference.h));
      if (chunk === undefined || chunk.bucketIndex !== reference.b || chunk.lane !== reference.l ||
        chunk.segmentIndex !== reference.s || chunk.records.length !== reference.n) {
        return false;
      }
      physicalRecordCount += reference.n;
    }
    if (physicalRecordCount !== manifest.physicalRecordCount) {
      return false;
    }
    const aggregateChecksum = this.buildAggregateChecksum(
      HUAWEI_SPACE_BOOKMARK_BUCKET_COUNT,
      manifest.hasPrivateData,
      manifest.indexes
    );
    if (manifest.aggregateChecksum !== aggregateChecksum) {
      return false;
    }
    return true;
  }

  findHeadManifestIds(
    manifestsById: Map<string, HuaweiSpaceBookmarkManifest>,
    viableIds: Set<string>
  ): string[] {
    const referenced = new Set<string>();
    viableIds.forEach((commitId: string): void => {
      const manifest = manifestsById.get(commitId);
      manifest?.parentCommitIds.forEach((parentId: string): void => {
        if (viableIds.has(parentId)) {
          referenced.add(parentId);
        }
      });
    });
    return Array.from(viableIds).filter((commitId: string): boolean => !referenced.has(commitId)).sort();
  }

  buildBlockMapKey(storageEpoch: number, logicalId: string): string {
    return `${storageEpoch}|${logicalId}`;
  }

  private buildProjection(request: HuaweiBookmarkProjectionRequest): HuaweiSpaceBookmarkProjection {
    const storageEpoch = request.storageEpoch;
    const snapshot = request.snapshot;
    const records = this.buildCanonicalRecords(snapshot);
    const recordsByBucket: HuaweiSpaceBookmarkChunkRecordData[][] = [];
    for (let index = 0; index < HUAWEI_SPACE_BOOKMARK_BUCKET_COUNT; index += 1) {
      recordsByBucket.push([]);
    }
    records.forEach((record: HuaweiSpaceBookmarkChunkRecordData): void => {
      recordsByBucket[this.resolveBucketIndex(record)].push(record);
    });
    const chunks: HuaweiSpaceBookmarkChunk[] = [];
    const chunkReferences: HuaweiSpaceBookmarkChunkReferenceData[] = [];
    recordsByBucket.forEach((bucketRecords: HuaweiSpaceBookmarkChunkRecordData[], bucketIndex: number): void => {
      if (bucketRecords.length <= 0) {
        return;
      }
      const orderedBucketRecords = this.sortChunkRecordsByStableKey(bucketRecords);
      HUAWEI_SPACE_BOOKMARK_LANES.forEach((lane: HuaweiSpaceBookmarkLane): void => {
        const laneRecords = orderedBucketRecords.filter((record: HuaweiSpaceBookmarkChunkRecordData): boolean => {
          return this.resolveRecordLane(record) === lane;
        });
        if (laneRecords.length > 0) {
          this.appendBucketChunks(chunks, chunkReferences, storageEpoch, bucketIndex, lane, laneRecords);
        }
      });
    });
    const indexes: HuaweiSpaceBookmarkIndex[] = [];
    const indexReferences: HuaweiSpaceBookmarkIndexReferenceData[] = [];
    for (let shardIndex = 0; shardIndex < HUAWEI_SPACE_BOOKMARK_INDEX_SHARD_COUNT; shardIndex += 1) {
      const firstBucket = shardIndex * HUAWEI_SPACE_BOOKMARK_BUCKETS_PER_INDEX_SHARD;
      const lastBucket = firstBucket + HUAWEI_SPACE_BOOKMARK_BUCKETS_PER_INDEX_SHARD;
      const shardChunks = chunkReferences.filter((reference: HuaweiSpaceBookmarkChunkReferenceData): boolean => {
        return reference.b >= firstBucket && reference.b < lastBucket;
      });
      if (shardChunks.length > HUAWEI_SPACE_BOOKMARK_MAX_CHUNK_REFERENCES_PER_INDEX) {
        throw new Error(`华为云空间书签 index ${shardIndex} 的 chunk 引用过多。`);
      }
      const indexData: HuaweiSpaceBookmarkIndexData = {
        formatVersion: HUAWEI_SPACE_BOOKMARK_FORMAT_VERSION,
        shardIndex,
        chunks: shardChunks
      };
      const encoded = JSON.stringify(indexData);
      this.assertEncodedSize(encoded, HUAWEI_SPACE_BOOKMARK_MAX_ROW_JSON_BYTES, 'index');
      const indexId = this.sha256Hex(encoded);
      indexes.push({ indexId, storageEpoch, shardIndex, chunks: shardChunks, encoded });
      indexReferences.push({ s: shardIndex, h: indexId, n: shardChunks.length });
    }
    const counts = this.countSnapshotRecords(snapshot);
    const parentCommitIds = this.normalizeStringArray(request.parentCommitIds, '父 commit');
    const manifest: HuaweiSpaceBookmarkManifest = {
      storageEpoch,
      commitId: this.requireString(request.commitId, 'commitId'),
      parentCommitIds,
      deviceId: this.requireString(request.deviceId, 'deviceId'),
      generatedAt: this.requireString(request.generatedAt, 'generatedAt'),
      history: this.requireHistory(request.history),
      updatedAt: request.updatedAt,
      hasPrivateData: snapshot.appPrivateBookmarks !== undefined,
      indexes: indexReferences,
      physicalRecordCount: records.length,
      counts,
      aggregateChecksum: this.buildAggregateChecksum(
        HUAWEI_SPACE_BOOKMARK_BUCKET_COUNT,
        snapshot.appPrivateBookmarks !== undefined,
        indexReferences
      )
    };
    if (parentCommitIds.indexOf(manifest.commitId) >= 0) {
      throw new Error('华为云空间书签 manifest 不能引用自身。');
    }
    const manifestData: HuaweiSpaceBookmarkManifestData = {
      formatVersion: HUAWEI_SPACE_BOOKMARK_FORMAT_VERSION,
      schemaVersion: AIRA_SYNC_SCHEMA_VERSION,
      bucketCount: HUAWEI_SPACE_BOOKMARK_BUCKET_COUNT,
      storageEpoch: manifest.storageEpoch,
      commitId: manifest.commitId,
      parentCommitIds: manifest.parentCommitIds,
      deviceId: manifest.deviceId,
      generatedAt: manifest.generatedAt,
      history: manifest.history,
      updatedAt: manifest.updatedAt,
      hasPrivateData: manifest.hasPrivateData,
      indexes: manifest.indexes,
      physicalRecordCount: manifest.physicalRecordCount,
      counts: manifest.counts,
      aggregateChecksum: manifest.aggregateChecksum
    };
    const manifestJson = JSON.stringify(manifestData);
    this.assertEncodedSize(manifestJson, HUAWEI_SPACE_BOOKMARK_MAX_ROW_JSON_BYTES, 'manifest');
    return { manifest, manifestJson, indexes, chunks };
  }

  private appendBucketChunks(
    chunks: HuaweiSpaceBookmarkChunk[],
    references: HuaweiSpaceBookmarkChunkReferenceData[],
    storageEpoch: number,
    bucketIndex: number,
    lane: HuaweiSpaceBookmarkLane,
    records: HuaweiSpaceBookmarkChunkRecordData[]
  ): void {
    let segmentIndex = 0;
    let segmentRecords: HuaweiSpaceBookmarkChunkRecordData[] = [];
    records.forEach((record: HuaweiSpaceBookmarkChunkRecordData): void => {
      const candidate = segmentRecords.concat([record]);
      const candidateEncoded = this.encodeChunk(bucketIndex, lane, segmentIndex, candidate);
      if (this.byteCount(candidateEncoded) <= HUAWEI_SPACE_BOOKMARK_MAX_PAGE_JSON_BYTES) {
        segmentRecords = candidate;
        return;
      }
      if (segmentRecords.length <= 0) {
        throw new Error('华为云空间书签单条规范记录超过 G8 页面安全上限。');
      }
      this.appendChunk(chunks, references, storageEpoch, bucketIndex, lane, segmentIndex, segmentRecords);
      segmentIndex += 1;
      segmentRecords = [record];
      this.assertEncodedSize(
        this.encodeChunk(bucketIndex, lane, segmentIndex, segmentRecords),
        HUAWEI_SPACE_BOOKMARK_MAX_PAGE_JSON_BYTES,
        'chunk'
      );
    });
    if (segmentRecords.length > 0) {
      this.appendChunk(chunks, references, storageEpoch, bucketIndex, lane, segmentIndex, segmentRecords);
    }
  }

  private appendChunk(
    chunks: HuaweiSpaceBookmarkChunk[],
    references: HuaweiSpaceBookmarkChunkReferenceData[],
    storageEpoch: number,
    bucketIndex: number,
    lane: HuaweiSpaceBookmarkLane,
    segmentIndex: number,
    records: HuaweiSpaceBookmarkChunkRecordData[]
  ): void {
    const encoded = this.encodeChunk(bucketIndex, lane, segmentIndex, records);
    this.assertEncodedSize(encoded, HUAWEI_SPACE_BOOKMARK_MAX_PAGE_JSON_BYTES, 'chunk');
    const chunkId = this.sha256Hex(encoded);
    chunks.push({ chunkId, storageEpoch, bucketIndex, lane, segmentIndex, records, encoded });
    references.push({ b: bucketIndex, l: lane, s: segmentIndex, h: chunkId, n: records.length });
  }

  private encodeChunk(
    bucketIndex: number,
    lane: HuaweiSpaceBookmarkLane,
    segmentIndex: number,
    records: HuaweiSpaceBookmarkChunkRecordData[]
  ): string {
    const data: HuaweiSpaceBookmarkChunkData = {
      formatVersion: HUAWEI_SPACE_BOOKMARK_FORMAT_VERSION,
      bucketIndex,
      lane,
      segmentIndex,
      records
    };
    return JSON.stringify(data);
  }

  private buildCanonicalRecords(snapshot: AiraSyncSnapshot): HuaweiSpaceBookmarkChunkRecordData[] {
    const records: HuaweiSpaceBookmarkChunkRecordData[] = [];
    this.appendDataSetRecords(records, 'shared', snapshot);
    if (snapshot.appPrivateBookmarks !== undefined) {
      this.appendDataSetRecords(records, 'appPrivate', snapshot.appPrivateBookmarks);
    }
    const keys = new Set<string>();
    records.forEach((record: HuaweiSpaceBookmarkChunkRecordData): void => {
      const key = this.buildStableRecordKey(record);
      if (keys.has(key)) {
        throw new Error('华为云空间书签完整快照含重复逻辑键。');
      }
      keys.add(key);
    });
    return this.sortChunkRecordsByStableKey(records);
  }

  /**
   * Orders records by their stable key, building each key once.
   *
   * The obvious comparator rebuilds both keys on every comparison, which is O(n log n) template
   * strings for an n-record snapshot (measured at ~133k key builds for 10k records). Decorating with
   * the key first makes it n, and the comparison itself is unchanged -- still localeCompare over the
   * same two strings -- so the resulting order, and therefore the content-addressed layout that
   * depends on it, is identical.
   */
  sortChunkRecordsByStableKey(
    records: HuaweiSpaceBookmarkChunkRecordData[]
  ): HuaweiSpaceBookmarkChunkRecordData[] {
    const decorated = records.map((record: HuaweiSpaceBookmarkChunkRecordData): SortableChunkRecord => {
      return { key: this.buildStableRecordKey(record), record: record };
    });
    decorated.sort((left: SortableChunkRecord, right: SortableChunkRecord): number => {
      return left.key.localeCompare(right.key);
    });
    return decorated.map((entry: SortableChunkRecord): HuaweiSpaceBookmarkChunkRecordData => entry.record);
  }

  private appendDataSetRecords(
    records: HuaweiSpaceBookmarkChunkRecordData[],
    partition: HuaweiSpaceBookmarkPartition,
    dataSet: AiraSyncBookmarkDataSet | AiraSyncSnapshot
  ): void {
    dataSet.bookmarkFolders.forEach((value: AiraSyncBookmarkFolderEntity): void => {
      records.push({ p: partition, k: 'folder', i: value.id, s: 0, d: this.encodeFolder(value) });
    });
    dataSet.bookmarkItems.forEach((value: AiraSyncBookmarkItemEntity): void => {
      records.push({ p: partition, k: 'item', i: value.id, s: 0, d: this.encodeItem(value) });
    });
    dataSet.bookmarkOrders.forEach((value: AiraSyncBookmarkOrder): void => {
      const partCount = Math.max(1, Math.ceil(value.ids.length / HUAWEI_SPACE_BOOKMARK_ORDER_IDS_PER_PART));
      for (let partIndex = 0; partIndex < partCount; partIndex += 1) {
        const part: HuaweiSpaceBookmarkOrderPartData = {
          type: 'bookmark-order-part',
          parentId: value.parentId,
          ids: value.ids.slice(
            partIndex * HUAWEI_SPACE_BOOKMARK_ORDER_IDS_PER_PART,
            (partIndex + 1) * HUAWEI_SPACE_BOOKMARK_ORDER_IDS_PER_PART
          ),
          updatedAt: value.updatedAt,
          updatedBy: value.updatedBy,
          revision: value.revision,
          partIndex,
          partCount
        };
        records.push({
          p: partition,
          k: 'orderPart',
          i: this.buildOrderPartLogicalKey(part),
          s: partIndex,
          d: this.encodeOrderPart(part)
        });
      }
    });
    dataSet.tombstones.forEach((value: AiraSyncTombstone): void => {
      records.push({
        p: partition,
        k: 'tombstone',
        i: this.buildTombstoneLogicalKey(value),
        s: 0,
        d: this.encodeTombstone(value)
      });
    });
  }

  private encodeFolder(value: AiraSyncBookmarkFolderEntity): string {
    const canonical: AiraSyncBookmarkFolderEntity = {
      id: value.id,
      type: 'bookmark-folder',
      parentId: value.parentId,
      title: value.title,
      createdAt: value.createdAt,
      updatedAt: value.updatedAt,
      updatedBy: value.updatedBy,
      revision: value.revision
    };
    return JSON.stringify(canonical);
  }

  private encodeItem(value: AiraSyncBookmarkItemEntity): string {
    const canonical: AiraSyncBookmarkItemEntity = {
      id: value.id,
      type: 'bookmark-item',
      parentId: value.parentId,
      title: value.title,
      url: value.url,
      createdAt: value.createdAt,
      updatedAt: value.updatedAt,
      updatedBy: value.updatedBy,
      revision: value.revision
    };
    return JSON.stringify(canonical);
  }

  private encodeOrderPart(value: HuaweiSpaceBookmarkOrderPartData): string {
    const canonical: HuaweiSpaceBookmarkOrderPartData = {
      type: 'bookmark-order-part',
      parentId: value.parentId,
      ids: value.ids.slice(),
      updatedAt: value.updatedAt,
      updatedBy: value.updatedBy,
      revision: value.revision,
      partIndex: value.partIndex,
      partCount: value.partCount
    };
    return JSON.stringify(canonical);
  }

  private encodeTombstone(value: AiraSyncTombstone): string {
    const canonical: AiraSyncTombstone = {
      id: value.id,
      type: value.type,
      deletedAt: value.deletedAt,
      deletedBy: value.deletedBy,
      lastKnownRevision: value.lastKnownRevision
    };
    return JSON.stringify(canonical);
  }

  private parseChunkRecord(value: HuaweiSpaceBookmarkChunkRecordData): HuaweiSpaceBookmarkChunkRecordData {
    if (value === undefined || value === null ||
      (value.p !== 'shared' && value.p !== 'appPrivate') ||
      (value.k !== 'folder' && value.k !== 'item' && value.k !== 'orderPart' && value.k !== 'tombstone')) {
      throw new Error('华为云空间书签 chunk 记录类型无效。');
    }
    const record: HuaweiSpaceBookmarkChunkRecordData = {
      p: value.p,
      k: value.k,
      i: this.requireString(value.i, 'logicalKey'),
      s: this.requireNonNegativeInteger(value.s, 'recordSegment'),
      d: this.requireString(value.d, 'recordData')
    };
    if (record.k !== 'orderPart' && record.s !== 0) {
      throw new Error('华为云空间书签非排序记录的 segment 无效。');
    }
    if (record.d !== this.encodeParsedRecord(record)) {
      throw new Error('华为云空间书签 chunk 记录不是规范编码。');
    }
    return record;
  }

  private encodeParsedRecord(record: HuaweiSpaceBookmarkChunkRecordData): string {
    if (record.k === 'folder') {
      return this.encodeFolder(this.parseFolder(record.d));
    }
    if (record.k === 'item') {
      return this.encodeItem(this.parseItem(record.d));
    }
    if (record.k === 'orderPart') {
      return this.encodeOrderPart(this.parseOrderPart(record.d));
    }
    return this.encodeTombstone(this.parseTombstone(record.d));
  }

  private parseIndexReferences(
    values: HuaweiSpaceBookmarkIndexReferenceData[] | undefined
  ): HuaweiSpaceBookmarkIndexReferenceData[] {
    if (!Array.isArray(values) || values.length !== HUAWEI_SPACE_BOOKMARK_INDEX_SHARD_COUNT) {
      throw new Error('华为云空间书签 manifest index 引用集合无效。');
    }
    const references: HuaweiSpaceBookmarkIndexReferenceData[] = [];
    values.forEach((value: HuaweiSpaceBookmarkIndexReferenceData, position: number): void => {
      const shardIndex = this.requireIndexShard(value?.s);
      if (shardIndex !== position) {
        throw new Error('华为云空间书签 manifest index 引用顺序无效。');
      }
      references.push({
        s: shardIndex,
        h: this.requireHash(value?.h, 'indexId'),
        n: this.requireNonNegativeInteger(value?.n, 'chunkReferenceCount')
      });
      if (references[references.length - 1].n > HUAWEI_SPACE_BOOKMARK_MAX_CHUNK_REFERENCES_PER_INDEX) {
        throw new Error('华为云空间书签 manifest index 引用数量无效。');
      }
    });
    return references;
  }

  private parseChunkReferences(
    values: HuaweiSpaceBookmarkChunkReferenceData[] | undefined,
    shardIndex: number
  ): HuaweiSpaceBookmarkChunkReferenceData[] {
    if (!Array.isArray(values) || values.length > HUAWEI_SPACE_BOOKMARK_MAX_CHUNK_REFERENCES_PER_INDEX) {
      throw new Error('华为云空间书签 index chunk 引用集合无效。');
    }
    const references: HuaweiSpaceBookmarkChunkReferenceData[] = [];
    let previousLaneIndex = -1;
    let previousSegment = -1;
    values.forEach((value: HuaweiSpaceBookmarkChunkReferenceData): void => {
      const bucketIndex = this.requireBucketIndex(value?.b);
      const lane = this.requireLane(value?.l);
      const laneIndex = HUAWEI_SPACE_BOOKMARK_LANES.indexOf(lane);
      const segmentIndex = this.requireNonNegativeInteger(value?.s, 'segmentIndex');
      const expectedShard = Math.floor(bucketIndex / HUAWEI_SPACE_BOOKMARK_BUCKETS_PER_INDEX_SHARD);
      if (expectedShard !== shardIndex || bucketIndex !== shardIndex || laneIndex < previousLaneIndex ||
        (laneIndex === previousLaneIndex && segmentIndex !== previousSegment + 1) ||
        (laneIndex > previousLaneIndex && segmentIndex !== 0)) {
        throw new Error('华为云空间书签 index chunk 引用顺序无效。');
      }
      previousLaneIndex = laneIndex;
      previousSegment = segmentIndex;
      references.push({
        b: bucketIndex,
        l: lane,
        s: segmentIndex,
        h: this.requireHash(value?.h, 'chunkId'),
        n: this.requirePositiveInteger(value?.n, 'recordCount')
      });
    });
    return references;
  }

  private parseCounts(
    value: HuaweiSpaceBookmarkRecordCounts | undefined,
    hasPrivateData: boolean
  ): HuaweiSpaceBookmarkRecordCounts {
    if (value === undefined || value === null) {
      throw new Error('华为云空间书签 manifest 记录数量缺失。');
    }
    const counts: HuaweiSpaceBookmarkRecordCounts = {
      folderCount: this.requireNonNegativeInteger(value.folderCount, 'folderCount'),
      itemCount: this.requireNonNegativeInteger(value.itemCount, 'itemCount'),
      orderCount: this.requireNonNegativeInteger(value.orderCount, 'orderCount'),
      tombstoneCount: this.requireNonNegativeInteger(value.tombstoneCount, 'tombstoneCount'),
      privateFolderCount: this.requireNonNegativeInteger(value.privateFolderCount, 'privateFolderCount'),
      privateItemCount: this.requireNonNegativeInteger(value.privateItemCount, 'privateItemCount'),
      privateOrderCount: this.requireNonNegativeInteger(value.privateOrderCount, 'privateOrderCount'),
      privateTombstoneCount: this.requireNonNegativeInteger(value.privateTombstoneCount, 'privateTombstoneCount')
    };
    if (!hasPrivateData && (counts.privateFolderCount > 0 || counts.privateItemCount > 0 ||
      counts.privateOrderCount > 0 || counts.privateTombstoneCount > 0)) {
      throw new Error('华为云空间书签 manifest 私密分区数量无效。');
    }
    return counts;
  }

  countSnapshotRecords(snapshot: AiraSyncSnapshot): HuaweiSpaceBookmarkRecordCounts {
    const privateData = snapshot.appPrivateBookmarks;
    return {
      folderCount: snapshot.bookmarkFolders.length,
      itemCount: snapshot.bookmarkItems.length,
      orderCount: snapshot.bookmarkOrders.length,
      tombstoneCount: snapshot.tombstones.length,
      privateFolderCount: privateData?.bookmarkFolders.length ?? 0,
      privateItemCount: privateData?.bookmarkItems.length ?? 0,
      privateOrderCount: privateData?.bookmarkOrders.length ?? 0,
      privateTombstoneCount: privateData?.tombstones.length ?? 0
    };
  }

  sameCounts(left: HuaweiSpaceBookmarkRecordCounts, right: HuaweiSpaceBookmarkRecordCounts): boolean {
    return left.folderCount === right.folderCount && left.itemCount === right.itemCount &&
      left.orderCount === right.orderCount && left.tombstoneCount === right.tombstoneCount &&
      left.privateFolderCount === right.privateFolderCount && left.privateItemCount === right.privateItemCount &&
      left.privateOrderCount === right.privateOrderCount &&
      left.privateTombstoneCount === right.privateTombstoneCount;
  }

  private buildAggregateChecksum(
    bucketCount: number,
    hasPrivateData: boolean,
    indexes: HuaweiSpaceBookmarkIndexReferenceData[]
  ): string {
    return this.sha256Hex(JSON.stringify({ bucketCount, hasPrivateData, indexes }));
  }

  private resolveBucketIndex(record: HuaweiSpaceBookmarkChunkRecordData): number {
    return parseInt(this.sha256Hex(this.buildStableRecordKey(record)).slice(0, 8), 16) %
      HUAWEI_SPACE_BOOKMARK_BUCKET_COUNT;
  }

  private resolveRecordLane(record: HuaweiSpaceBookmarkChunkRecordData): HuaweiSpaceBookmarkLane {
    if (record.k === 'tombstone') {
      return 'tombstone';
    }
    if (record.k === 'orderPart') {
      return 'order';
    }
    return 'live';
  }

  buildStableRecordKey(record: HuaweiSpaceBookmarkChunkRecordData): string {
    return `${record.p}|${record.k}|${record.i}|${record.s}`;
  }

  private buildOrderLogicalKey(value: AiraSyncBookmarkOrder): string {
    return value.parentId ?? '__root__';
  }

  private buildOrderPartLogicalKey(value: HuaweiSpaceBookmarkOrderPartData): string {
    return value.parentId ?? '__root__';
  }

  private buildTombstoneLogicalKey(value: AiraSyncTombstone): string {
    return `${value.type}|${value.id}`;
  }

  private parseFolder(encoded: string): AiraSyncBookmarkFolderEntity {
    const value = this.parseObject(encoded, 'folder') as AiraSyncBookmarkFolderEntity;
    if (value.type !== 'bookmark-folder') {
      throw new Error('华为云空间书签文件夹类型无效。');
    }
    return {
      id: this.requireString(value.id, 'id'),
      type: 'bookmark-folder',
      parentId: this.requireNullableString(value.parentId, 'parentId'),
      title: this.requireText(value.title, 'title'),
      createdAt: this.requireString(value.createdAt, 'createdAt'),
      updatedAt: this.requireString(value.updatedAt, 'updatedAt'),
      updatedBy: this.requireString(value.updatedBy, 'updatedBy'),
      revision: this.requireNonNegativeInteger(value.revision, 'revision')
    };
  }

  private parseItem(encoded: string): AiraSyncBookmarkItemEntity {
    const value = this.parseObject(encoded, 'item') as AiraSyncBookmarkItemEntity;
    if (value.type !== 'bookmark-item') {
      throw new Error('华为云空间书签条目类型无效。');
    }
    return {
      id: this.requireString(value.id, 'id'),
      type: 'bookmark-item',
      parentId: this.requireNullableString(value.parentId, 'parentId'),
      title: this.requireText(value.title, 'title'),
      url: this.requireText(value.url, 'url'),
      createdAt: this.requireString(value.createdAt, 'createdAt'),
      updatedAt: this.requireString(value.updatedAt, 'updatedAt'),
      updatedBy: this.requireString(value.updatedBy, 'updatedBy'),
      revision: this.requireNonNegativeInteger(value.revision, 'revision')
    };
  }

  private parseOrderPart(encoded: string): HuaweiSpaceBookmarkOrderPartData {
    const value = this.parseObject(encoded, 'orderPart') as HuaweiSpaceBookmarkOrderPartData;
    if (value.type !== 'bookmark-order-part' || !Array.isArray(value.ids)) {
      throw new Error('华为云空间书签排序分片记录无效。');
    }
    const partIndex = this.requireNonNegativeInteger(value.partIndex, 'partIndex');
    const partCount = this.requirePositiveInteger(value.partCount, 'partCount');
    if (partIndex >= partCount || value.ids.length > HUAWEI_SPACE_BOOKMARK_ORDER_IDS_PER_PART ||
      (partIndex < partCount - 1 && value.ids.length !== HUAWEI_SPACE_BOOKMARK_ORDER_IDS_PER_PART) ||
      (partCount > 1 && value.ids.length <= 0)) {
      throw new Error('华为云空间书签排序分片边界无效。');
    }
    const ids: string[] = [];
    value.ids.forEach((id: string): void => {
      const normalized = this.requireString(id, 'orderId');
      if (ids.indexOf(normalized) >= 0) {
        throw new Error('华为云空间书签排序分片子节点重复。');
      }
      ids.push(normalized);
    });
    return {
      type: 'bookmark-order-part',
      parentId: this.requireNullableString(value.parentId, 'parentId'),
      ids,
      updatedAt: this.requireString(value.updatedAt, 'updatedAt'),
      updatedBy: this.requireString(value.updatedBy, 'updatedBy'),
      revision: this.requireNonNegativeInteger(value.revision, 'revision'),
      partIndex,
      partCount
    };
  }

  private materializeOrderParts(
    logicalKey: string,
    parts: HuaweiSpaceBookmarkOrderPartData[]
  ): AiraSyncBookmarkOrder {
    if (parts.length <= 0) {
      throw new Error('华为云空间书签排序分片缺失。');
    }
    parts.sort((left: HuaweiSpaceBookmarkOrderPartData, right: HuaweiSpaceBookmarkOrderPartData): number => {
      return left.partIndex - right.partIndex;
    });
    const first = parts[0];
    if (parts.length !== first.partCount || this.buildOrderPartLogicalKey(first) !== logicalKey) {
      throw new Error('华为云空间书签排序分片数量无效。');
    }
    const ids: string[] = [];
    const idSet = new Set<string>();
    parts.forEach((part: HuaweiSpaceBookmarkOrderPartData, index: number): void => {
      if (part.partIndex !== index || part.partCount !== first.partCount || part.parentId !== first.parentId ||
        part.updatedAt !== first.updatedAt || part.updatedBy !== first.updatedBy || part.revision !== first.revision) {
        throw new Error('华为云空间书签排序分片元数据不一致。');
      }
      part.ids.forEach((id: string): void => {
        if (idSet.has(id)) {
          throw new Error('华为云空间书签排序子节点重复。');
        }
        idSet.add(id);
        ids.push(id);
      });
    });
    return {
      type: 'bookmark-order',
      parentId: first.parentId,
      ids,
      updatedAt: first.updatedAt,
      updatedBy: first.updatedBy,
      revision: first.revision
    };
  }

  private parseTombstone(encoded: string): AiraSyncTombstone {
    const value = this.parseObject(encoded, 'tombstone') as AiraSyncTombstone;
    if (value.type !== 'bookmark-folder' && value.type !== 'bookmark-item') {
      throw new Error('华为云空间书签墓碑类型无效。');
    }
    return {
      id: this.requireString(value.id, 'id'),
      type: value.type,
      deletedAt: this.requireString(value.deletedAt, 'deletedAt'),
      deletedBy: this.requireString(value.deletedBy, 'deletedBy'),
      lastKnownRevision: this.requireNonNegativeInteger(value.lastKnownRevision, 'lastKnownRevision')
    };
  }

  private normalizeStringArray(values: string[] | undefined, label: string): string[] {
    if (!Array.isArray(values)) {
      throw new Error(`华为云空间书签 ${label} 集合无效。`);
    }
    const normalized: string[] = [];
    values.forEach((value: string): void => {
      const item = this.requireString(value, label).trim();
      if (normalized.indexOf(item) >= 0) {
        throw new Error(`华为云空间书签 ${label} 集合重复。`);
      }
      normalized.push(item);
    });
    return normalized.sort();
  }

  private parseObject(value: string, label: string): Object {
    try {
      const parsed = JSON.parse(value) as Object;
      if (parsed === undefined || parsed === null || Array.isArray(parsed)) {
        throw new Error('not-object');
      }
      return parsed;
    } catch (_error) {
      throw new Error(`华为云空间书签 ${label} JSON 无效。`);
    }
  }

  private assertEncodedSize(value: string, maximumBytes: number, label: string): void {
    const bytes = this.byteCount(value);
    if (bytes <= 0 || bytes > maximumBytes) {
      throw new Error(`华为云空间书签 ${label} 大小超出 G8 安全上限（${bytes} 字节）。`);
    }
  }

  byteCount(value: string): number {
    return this.encoder.encodeInto(value).byteLength;
  }

  sha256Hex(value: string): string {
    const md = cryptoFramework.createMd('SHA256');
    md.updateSync({ data: this.encoder.encodeInto(value) });
    const bytes = (md.digestSync() as cryptoFramework.DataBlob).data;
    let result = '';
    for (let index = 0; index < bytes.length; index += 1) {
      result += bytes[index].toString(16).padStart(2, '0');
    }
    return result;
  }

  private requireHistory(value: AiraBookmarkHistoryDescriptor): AiraBookmarkHistoryDescriptor {
    if (value === undefined || value === null || typeof value !== 'object' ||
      value.version !== AIRA_BOOKMARK_HISTORY_VERSION ||
      typeof value.epochId !== 'string' || value.epochId.trim().length <= 0 ||
      typeof value.retainedFrom !== 'string' || !Number.isFinite(Date.parse(value.retainedFrom))) {
      throw new Error('华为云空间书签墓碑历史纪元无效。');
    }
    return {
      version: value.version,
      epochId: value.epochId,
      retainedFrom: value.retainedFrom
    };
  }

  requireString(value: string | undefined, key: string): string {
    if (typeof value !== 'string' || value.trim().length <= 0) {
      throw new Error(`华为云空间书签字段 ${key} 无效。`);
    }
    return value;
  }

  private requireText(value: string | undefined, key: string): string {
    if (typeof value !== 'string') {
      throw new Error(`华为云空间书签字段 ${key} 无效。`);
    }
    return value;
  }

  private requireNullableString(value: string | null | undefined, key: string): string | null {
    if (value === null) {
      return null;
    }
    if (typeof value !== 'string' || value.trim().length <= 0) {
      throw new Error(`华为云空间书签字段 ${key} 无效。`);
    }
    return value;
  }

  private requireNonNegativeInteger(value: number | undefined, key: string): number {
    const candidate = Number(value);
    if (!Number.isFinite(candidate) || candidate < 0 || Math.floor(candidate) !== candidate) {
      throw new Error(`华为云空间书签字段 ${key} 无效。`);
    }
    return candidate;
  }

  private requirePositiveInteger(value: number | undefined, key: string): number {
    const candidate = this.requireNonNegativeInteger(value, key);
    if (candidate <= 0) {
      throw new Error(`华为云空间书签字段 ${key} 无效。`);
    }
    return candidate;
  }

  private requireLane(value: HuaweiSpaceBookmarkLane | undefined): HuaweiSpaceBookmarkLane {
    if (value !== 'live' && value !== 'order' && value !== 'tombstone') {
      throw new Error('华为云空间书签页面 lane 无效。');
    }
    return value;
  }

  private requireBucketIndex(value: number | undefined): number {
    const candidate = this.requireNonNegativeInteger(value, 'bucketIndex');
    if (candidate >= HUAWEI_SPACE_BOOKMARK_BUCKET_COUNT) {
      throw new Error('华为云空间书签 bucket 索引无效。');
    }
    return candidate;
  }

  private requireIndexShard(value: number | undefined): number {
    const candidate = this.requireNonNegativeInteger(value, 'shardIndex');
    if (candidate >= HUAWEI_SPACE_BOOKMARK_INDEX_SHARD_COUNT) {
      throw new Error('华为云空间书签 index shard 索引无效。');
    }
    return candidate;
  }

  requireHash(value: string | undefined, key: string): string {
    const normalized = this.requireString(value, key).trim().toLowerCase();
    if (!/^[0-9a-f]{64}$/.test(normalized)) {
      throw new Error(`华为云空间书签字段 ${key} 无效。`);
    }
    return normalized;
  }
}
