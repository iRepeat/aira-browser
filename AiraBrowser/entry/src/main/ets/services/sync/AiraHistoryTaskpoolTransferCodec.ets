import {
  HistorySyncDeleteRange,
  HistorySyncExactTombstone,
  HistorySyncRetentionFrontier,
  HistorySyncVisit,
  HuaweiSpaceHistorySyncState
} from '../../common/models/HistorySyncModels';
import {
  HuaweiSpaceHistoryProjection,
  HuaweiSpaceHistoryRecordKind,
  HuaweiSpaceHistoryRow
} from '../../data/sync/HuaweiSpaceHistorySnapshotCodec';
import { util } from '@kit.ArkTS';
import { AiraSyncCooperativeThrottle } from './AiraSyncWorkThrottleService';

export interface AiraHistoryRemoteWriteProjection {
  rowsToUpsert: HuaweiSpaceHistoryRow[];
  rowIdsToDeleteBeforePublish: string[];
  legacyRowIdsToDeleteAfterConfirmation: string[];
  targetHeadRowId: string;
  targetDeviceId: string;
  targetGeneration: number;
  targetStateChecksum: string;
}

function writeU32(target: Uint8Array, offset: number, value: number): void {
  target[offset] = (value >>> 24) & 0xff;
  target[offset + 1] = (value >>> 16) & 0xff;
  target[offset + 2] = (value >>> 8) & 0xff;
  target[offset + 3] = value & 0xff;
}

function readU32(source: Uint8Array, offset: number): number {
  return ((source[offset] << 24) | (source[offset + 1] << 16) |
    (source[offset + 2] << 8) | source[offset + 3]) >>> 0;
}

function writeU64(target: Uint8Array, offset: number, value: number): void {
  const safe = Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
  writeU32(target, offset, Math.floor(safe / 4294967296));
  writeU32(target, offset + 4, safe % 4294967296);
}

function readU64(source: Uint8Array, offset: number): number {
  return readU32(source, offset) * 4294967296 + readU32(source, offset + 4);
}

// State framing is only an in-process TaskPool transfer, never a cloud/storage format. Each
// logical record has its own JSON frame so the caller can yield between parses/stringifies.
const HISTORY_STATE_TRANSFER_MAGIC: number = 0x41485331;
const HISTORY_TRANSFER_COPY_SLICE_BYTES: number = 64 * 1024;

interface HistoryTransferMetadata {
  clearBefore: number;
  retentionFrontier: HistorySyncRetentionFrontier;
}

class HistoryTransferWriter {
  private readonly encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  readonly parts: Uint8Array[] = [];
  byteLength: number = 0;

  appendBytes(bytes: Uint8Array): void {
    this.parts.push(bytes);
    this.byteLength += bytes.byteLength;
  }

  appendString(value: string): void {
    const bytes = this.encoder.encodeInto(value);
    const length = new Uint8Array(4);
    writeU32(length, 0, bytes.byteLength);
    this.appendBytes(length);
    this.appendBytes(bytes);
  }

  appendRow(row: HuaweiSpaceHistoryRow): void {
    this.appendString(row.rowId);
    this.appendString(row.recordKind);
    this.appendString(row.logicalId);
    this.appendString(row.data);
    const timestamp = new Uint8Array(8);
    writeU64(timestamp, 0, row.updatedAt);
    this.appendBytes(timestamp);
  }

  pack(): ArrayBuffer {
    const target = new Uint8Array(this.byteLength);
    let offset = 0;
    for (const part of this.parts) {
      target.set(part, offset);
      offset += part.byteLength;
    }
    return target.buffer;
  }

  async packCooperatively(throttle: AiraSyncCooperativeThrottle): Promise<ArrayBuffer> {
    const target = new Uint8Array(this.byteLength);
    let offset = 0;
    let copied = 0;
    for (const part of this.parts) {
      for (let start = 0; start < part.byteLength; start += HISTORY_TRANSFER_COPY_SLICE_BYTES) {
        const slice = part.subarray(start, Math.min(part.byteLength, start + HISTORY_TRANSFER_COPY_SLICE_BYTES));
        target.set(slice, offset);
        offset += slice.byteLength;
        await throttle.afterBatchItem(++copied);
      }
    }
    return target.buffer;
  }
}

class HistoryTransferReader {
  private readonly bytes: Uint8Array;
  private readonly decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private offset: number = 0;

  constructor(buffer: ArrayBuffer) {
    this.bytes = new Uint8Array(buffer);
  }

  readNumber(): number {
    this.requireBytes(4);
    const value = readU32(this.bytes, this.offset);
    this.offset += 4;
    return value;
  }

  readString(): string {
    const length = this.readNumber();
    this.requireBytes(length);
    const value = this.decoder.decodeToString(this.bytes.subarray(this.offset, this.offset + length));
    this.offset += length;
    return value;
  }

  readRow(): HuaweiSpaceHistoryRow {
    const rowId = this.readString();
    const recordKind = this.readString() as HuaweiSpaceHistoryRecordKind;
    const logicalId = this.readString();
    const data = this.readString();
    this.requireBytes(8);
    const updatedAt = readU64(this.bytes, this.offset);
    this.offset += 8;
    return { rowId, recordKind, logicalId, data, updatedAt };
  }

  assertFinished(): void {
    if (this.offset !== this.bytes.byteLength) {
      throw new Error('Huawei History TaskPool payload has trailing bytes.');
    }
  }

  private requireBytes(count: number): void {
    if (count > this.bytes.byteLength - this.offset) {
      throw new Error('Huawei History TaskPool payload is truncated.');
    }
  }
}

class HistoryStateTransferReader {
  readonly reader: HistoryTransferReader;
  readonly state: HuaweiSpaceHistorySyncState;
  readonly visitCount: number;
  readonly tombstoneCount: number;
  readonly rangeCount: number;

  constructor(buffer: ArrayBuffer) {
    this.reader = new HistoryTransferReader(buffer);
    if (this.reader.readNumber() !== HISTORY_STATE_TRANSFER_MAGIC) {
      throw new Error('Huawei History TaskPool state format is invalid.');
    }
    this.visitCount = this.reader.readNumber();
    this.tombstoneCount = this.reader.readNumber();
    this.rangeCount = this.reader.readNumber();
    const metadata = JSON.parse(this.reader.readString()) as HistoryTransferMetadata;
    this.state = {
      visits: [], tombstones: [], deleteRanges: [],
      clearBefore: metadata.clearBefore, retentionFrontier: metadata.retentionFrontier
    };
  }

  recordCount(): number {
    return this.visitCount + this.tombstoneCount + this.rangeCount;
  }

  readRecord(index: number): void {
    const json = this.reader.readString();
    if (index < this.visitCount) {
      this.state.visits.push(JSON.parse(json) as HistorySyncVisit);
    } else if (index < this.visitCount + this.tombstoneCount) {
      this.state.tombstones.push(JSON.parse(json) as HistorySyncExactTombstone);
    } else {
      this.state.deleteRanges.push(JSON.parse(json) as HistorySyncDeleteRange);
    }
  }
}

export class AiraHistoryTaskpoolTransferCodec {
  static encodeRows(rows: HuaweiSpaceHistoryRow[]): ArrayBuffer {
    const writer = AiraHistoryTaskpoolTransferCodec.rowWriter(rows.length);
    for (const row of rows) {
      writer.appendRow(row);
    }
    return writer.pack();
  }

  static async encodeRowsCooperatively(
    rows: HuaweiSpaceHistoryRow[], throttle: AiraSyncCooperativeThrottle
  ): Promise<ArrayBuffer> {
    await throttle.afterStage();
    const writer = AiraHistoryTaskpoolTransferCodec.rowWriter(rows.length);
    for (let index = 0; index < rows.length; index++) {
      writer.appendRow(rows[index]);
      await throttle.afterBatchItem(index + 1);
    }
    return writer.packCooperatively(throttle);
  }

  static decodeRows(rowBuffer: ArrayBuffer): HuaweiSpaceHistoryRow[] {
    const reader = new HistoryTransferReader(rowBuffer);
    const count = reader.readNumber();
    const rows: HuaweiSpaceHistoryRow[] = [];
    for (let index = 0; index < count; index++) {
      rows.push(reader.readRow());
    }
    reader.assertFinished();
    return rows;
  }

  static async decodeRowsCooperatively(
    rowBuffer: ArrayBuffer, throttle: AiraSyncCooperativeThrottle
  ): Promise<HuaweiSpaceHistoryRow[]> {
    await throttle.afterStage();
    const reader = new HistoryTransferReader(rowBuffer);
    const count = reader.readNumber();
    const rows: HuaweiSpaceHistoryRow[] = [];
    for (let index = 0; index < count; index++) {
      rows.push(reader.readRow());
      await throttle.afterBatchItem(index + 1);
    }
    reader.assertFinished();
    return rows;
  }

  static encodeState(state: HuaweiSpaceHistorySyncState): ArrayBuffer {
    const writer = AiraHistoryTaskpoolTransferCodec.stateWriter(state);
    const count = state.visits.length + state.tombstones.length + state.deleteRanges.length;
    for (let index = 0; index < count; index++) {
      writer.appendString(AiraHistoryTaskpoolTransferCodec.stateRecordJson(state, index));
    }
    return writer.pack();
  }

  static async encodeStateCooperatively(
    state: HuaweiSpaceHistorySyncState, throttle: AiraSyncCooperativeThrottle
  ): Promise<ArrayBuffer> {
    await throttle.afterStage();
    const writer = AiraHistoryTaskpoolTransferCodec.stateWriter(state);
    const count = state.visits.length + state.tombstones.length + state.deleteRanges.length;
    for (let index = 0; index < count; index++) {
      writer.appendString(AiraHistoryTaskpoolTransferCodec.stateRecordJson(state, index));
      await throttle.afterBatchItem(index + 1);
    }
    return writer.packCooperatively(throttle);
  }

  static decodeState(stateBuffer: ArrayBuffer): HuaweiSpaceHistorySyncState {
    const transfer = new HistoryStateTransferReader(stateBuffer);
    for (let index = 0; index < transfer.recordCount(); index++) {
      transfer.readRecord(index);
    }
    transfer.reader.assertFinished();
    return transfer.state;
  }

  static async decodeStateCooperatively(
    stateBuffer: ArrayBuffer, throttle: AiraSyncCooperativeThrottle
  ): Promise<HuaweiSpaceHistorySyncState> {
    await throttle.afterStage();
    const transfer = new HistoryStateTransferReader(stateBuffer);
    for (let index = 0; index < transfer.recordCount(); index++) {
      transfer.readRecord(index);
      await throttle.afterBatchItem(index + 1);
    }
    transfer.reader.assertFinished();
    return transfer.state;
  }

  static copyBuffer(buffer: ArrayBuffer): ArrayBuffer {
    const copy = new ArrayBuffer(buffer.byteLength);
    new Uint8Array(copy).set(new Uint8Array(buffer));
    return copy;
  }

  static async copyBufferCooperatively(
    buffer: ArrayBuffer, throttle: AiraSyncCooperativeThrottle
  ): Promise<ArrayBuffer> {
    const writer = new HistoryTransferWriter();
    writer.appendBytes(new Uint8Array(buffer));
    return writer.packCooperatively(throttle);
  }

  private static rowWriter(count: number): HistoryTransferWriter {
    const writer = new HistoryTransferWriter();
    const header = new Uint8Array(4);
    writeU32(header, 0, count);
    writer.appendBytes(header);
    return writer;
  }

  private static stateWriter(state: HuaweiSpaceHistorySyncState): HistoryTransferWriter {
    const writer = new HistoryTransferWriter();
    const header = new Uint8Array(16);
    writeU32(header, 0, HISTORY_STATE_TRANSFER_MAGIC);
    writeU32(header, 4, state.visits.length);
    writeU32(header, 8, state.tombstones.length);
    writeU32(header, 12, state.deleteRanges.length);
    writer.appendBytes(header);
    const metadata: HistoryTransferMetadata = {
      clearBefore: state.clearBefore, retentionFrontier: state.retentionFrontier
    };
    writer.appendString(JSON.stringify(metadata));
    return writer;
  }

  private static stateRecordJson(state: HuaweiSpaceHistorySyncState, index: number): string {
    if (index < state.visits.length) {
      return JSON.stringify(state.visits[index]);
    }
    const tombstoneIndex = index - state.visits.length;
    return tombstoneIndex < state.tombstones.length
      ? JSON.stringify(state.tombstones[tombstoneIndex])
      : JSON.stringify(state.deleteRanges[tombstoneIndex - state.tombstones.length]);
  }

  static leanProjection(projection: HuaweiSpaceHistoryProjection): AiraHistoryRemoteWriteProjection {
    return {
      rowsToUpsert: projection.rowsToUpsert,
      rowIdsToDeleteBeforePublish: projection.rowIdsToDeleteBeforePublish,
      legacyRowIdsToDeleteAfterConfirmation: projection.legacyRowIdsToDeleteAfterConfirmation,
      targetHeadRowId: projection.targetHeadRowId,
      targetDeviceId: projection.targetDeviceId,
      targetGeneration: projection.targetGeneration,
      targetStateChecksum: projection.targetStateChecksum
    };
  }
}
