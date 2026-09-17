import { BrowserHistoryTransition } from './BrowserModels';

export const HISTORY_SYNC_EXCHANGE_BATCH_SIZE: number = 200;
export const HISTORY_SYNC_BOOTSTRAP_PAGE_SIZE: number = 500;
export const HISTORY_SYNC_RETENTION_MS: number = 90 * 24 * 60 * 60 * 1000;
export const HISTORY_SYNC_MAX_VISITS: number = 10000;

/**
 * Limits the personal-server History route enforces on a submitted mutation. These numbers and the
 * visit-id shape belong to the server (`services/personal-server/src/routes/history-routes.js`); this
 * client mirrors them so it never sends a record the route will refuse.
 *
 * The route rejects the whole exchange batch, and the outbox drains in created_at order, so one
 * refused record is retried on every later run and never leaves the queue: a single page whose title
 * exceeds the limit stops History sync from ever completing.
 */
export const HISTORY_SYNC_VISIT_TITLE_MAX_LENGTH: number = 2048;
export const HISTORY_SYNC_VISIT_DEVICE_NAME_MAX_LENGTH: number = 128;
export const HISTORY_SYNC_VISIT_REFERRER_MAX_LENGTH: number = 8192;
export const HISTORY_SYNC_VISIT_SOURCE_MAX_LENGTH: number = 64;
export const HISTORY_SYNC_URL_MAX_LENGTH: number = 8192;
export const HISTORY_SYNC_VISIT_ID_MAX_LENGTH: number = 512;
export const HISTORY_SYNC_MUTATION_ID_MAX_LENGTH: number = 256;

const HISTORY_SYNC_VISIT_ID_PATTERN: RegExp = /^h1:[A-Za-z0-9._-]{1,160}:.+$/;

export type HistorySyncProviderKind = 'aira_cloud' | 'huawei_space' | 'self_hosted';

export type HistorySyncMutationOrigin =
  'local_capture' |
  'user_deletion' |
  'retention' |
  'migration';

export type HistorySyncMutationKind =
  'upsert_visit' |
  'delete_visit' |
  'delete_range' |
  'clear_before';

export type HistorySyncChangeKind = HistorySyncMutationKind | 'retention_prune';

export interface HistorySyncVisit {
  visitId: string;
  clientId: string;
  nativeVisitId: string;
  url: string;
  title: string;
  visitedAt: number;
  transition: BrowserHistoryTransition;
  referrer: string;
  deviceName: string;
  source: string;
}

export interface HistorySyncMutation {
  mutationId: string;
  kind: HistorySyncMutationKind;
  visit?: HistorySyncVisit;
  visitId?: string;
  url?: string;
  startedAt?: number;
  endedAt?: number;
  clearBefore?: number;
}

/**
 * Caps a mutation to the limits above for the personal-server transport, or returns undefined when
 * the record cannot be submitted at all. The Mutation is only reinterpreted for the wire; the
 * outbox keeps the original, and Huawei Space, which shares that outbox, has no such limits.
 *
 * A mutation whose identifying field cannot survive the limit is dropped rather than trimmed. A
 * truncated URL would name a different page, a truncated visit id would name a different visit, and
 * the server compares a delete against the ids it already holds, so an altered value would silently
 * target the wrong history entry instead of being refused.
 */
export function normalizeHistorySyncMutationForTransport(
  mutation: HistorySyncMutation
): HistorySyncMutation | undefined {
  // Kept verbatim: the server echoes this id back in its acknowledgement and the outbox row is
  // deleted by exact match, so a trimmed id would never be reconciled against its own row.
  const mutationId = mutation.mutationId;
  const trimmedMutationId = mutationId.trim();
  if (trimmedMutationId.length <= 0 || mutationId.length > HISTORY_SYNC_MUTATION_ID_MAX_LENGTH) {
    return undefined;
  }
  if (mutation.kind === 'upsert_visit') {
    if (mutation.visit === undefined) {
      return undefined;
    }
    const visit = normalizeHistorySyncVisitForTransport(mutation.visit);
    return visit === undefined ? undefined : { mutationId, kind: mutation.kind, visit };
  }
  if (mutation.kind === 'delete_visit') {
    const visitId = (mutation.visitId ?? '').trim();
    if (!isTransferableHistorySyncVisitId(visitId)) {
      return undefined;
    }
    return { mutationId, kind: mutation.kind, visitId };
  }
  if (mutation.kind === 'delete_range') {
    const url = (mutation.url ?? '').trim();
    if (url.length <= 0 || url.length > HISTORY_SYNC_URL_MAX_LENGTH) {
      return undefined;
    }
    return {
      mutationId,
      kind: mutation.kind,
      url,
      startedAt: mutation.startedAt,
      endedAt: mutation.endedAt
    };
  }
  if (mutation.kind === 'clear_before') {
    return { mutationId, kind: mutation.kind, clearBefore: mutation.clearBefore };
  }
  return undefined;
}

/**
 * Caps a visit to the field limits above for the personal-server transport, or returns undefined
 * when the visit cannot be submitted at all.
 *
 * A visit is dropped rather than trimmed when its URL or visit id is out of range: the URL names the
 * page and the visit id names the record the server compares against, so a truncated value would
 * describe a different visit instead of being refused.
 *
 * `transition` is a closed union whose longest member is far shorter than the limit, so it is passed
 * through rather than truncated into a value the server would reject.
 */
export function normalizeHistorySyncVisitForTransport(
  visit: HistorySyncVisit
): HistorySyncVisit | undefined {
  const visitId = visit.visitId.trim();
  if (!isTransferableHistorySyncVisitId(visitId)) {
    return undefined;
  }
  const url = visit.url.trim();
  if (url.length <= 0 || url.length > HISTORY_SYNC_URL_MAX_LENGTH) {
    return undefined;
  }
  return {
    visitId,
    clientId: visit.clientId,
    nativeVisitId: visit.nativeVisitId,
    url,
    title: capHistorySyncTextField(visit.title, HISTORY_SYNC_VISIT_TITLE_MAX_LENGTH),
    visitedAt: visit.visitedAt,
    transition: visit.transition,
    referrer: capHistorySyncTextField(visit.referrer, HISTORY_SYNC_VISIT_REFERRER_MAX_LENGTH),
    deviceName: capHistorySyncTextField(visit.deviceName, HISTORY_SYNC_VISIT_DEVICE_NAME_MAX_LENGTH),
    source: capHistorySyncTextField(visit.source, HISTORY_SYNC_VISIT_SOURCE_MAX_LENGTH)
  };
}

function isTransferableHistorySyncVisitId(visitId: string): boolean {
  return visitId.length > 0 &&
    visitId.length <= HISTORY_SYNC_VISIT_ID_MAX_LENGTH &&
    HISTORY_SYNC_VISIT_ID_PATTERN.test(visitId);
}

function capHistorySyncTextField(value: string, maxLength: number): string {
  return value.length > maxLength ? value.slice(0, maxLength) : value;
}

export interface HistorySyncOutboxContext {
  accountUid: string;
  clientId: string;
  deviceName: string;
  origin: HistorySyncMutationOrigin;
}

export interface HistorySyncLocalState {
  accountUid: string;
  clientId: string;
  initialized: boolean;
  cursor: number;
  bootstrapHead: number;
  bootstrapAfterUpdatedSeq: number;
  bootstrapAfterVisitId: string;
  updatedAt: number;
}

export interface HistorySyncMutationAcknowledgement {
  mutationId: string;
  acceptedSeq: number;
  applied: boolean;
}

export interface HistorySyncDeleteRange {
  rangeId: string;
  url: string;
  startedAt: number;
  endedAt: number;
  seq: number;
}

export interface HistorySyncExactTombstone {
  visitId: string;
  deletedAt: number;
}

export interface HistorySyncRetentionFrontier {
  cutoffAt: number;
  boundaryVisitedAt: number;
  boundaryVisitId: string;
  updatedAt: number;
}

/** The single visit that anchors the retention window; read on its own without materializing rows. */
export interface HistorySyncRetentionBoundary {
  visitedAt: number;
  syncId: string;
}

export interface HuaweiSpaceHistorySyncState {
  visits: HistorySyncVisit[];
  tombstones: HistorySyncExactTombstone[];
  deleteRanges: HistorySyncDeleteRange[];
  clearBefore: number;
  retentionFrontier: HistorySyncRetentionFrontier;
}

export interface HistorySyncChange {
  seq: number;
  kind: HistorySyncChangeKind;
  visitId: string;
  visit?: HistorySyncVisit;
  rangeId?: string;
  url?: string;
  startedAt?: number;
  endedAt?: number;
  clearBefore?: number;
  visitIds?: string[];
  cutoff?: number;
}

export interface HistorySyncExchangeResponse {
  acknowledgements: HistorySyncMutationAcknowledgement[];
  changes: HistorySyncChange[];
  nextCursor: number;
  headCursor: number;
  hasMore: boolean;
}

export interface HistorySyncBootstrapResponse {
  bootstrapHead: number;
  headCursor: number;
  visits: HistorySyncVisit[];
  deletedVisitIds: string[];
  clearBefore: number;
  deleteRanges: HistorySyncDeleteRange[];
  nextKey?: HistorySyncBootstrapKey;
  hasMore: boolean;
}

export interface HistorySyncBootstrapKey {
  updatedSeq: number;
  visitId: string;
}

export interface HistorySyncRunResult {
  ok: boolean;
  appliedChangeCount: number;
  uploadedMutationCount: number;
  message: string;
}
