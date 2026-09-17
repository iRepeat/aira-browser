import { describe, expect, it } from '@ohos/hypium';
import {
  HISTORY_SYNC_VISIT_DEVICE_NAME_MAX_LENGTH,
  HISTORY_SYNC_VISIT_TITLE_MAX_LENGTH,
  HistorySyncMutation,
  HistorySyncVisit,
  normalizeHistorySyncMutationForTransport
} from '../main/ets/common/models/HistorySyncModels';

function repeat(text: string, times: number): string {
  let out = '';
  for (let index = 0; index < times; index += 1) {
    out += text;
  }
  return out;
}

function buildVisit(
  title: string = 'short',
  deviceName: string = 'Aira HarmonyOS',
  url: string = 'https://example.com/',
  visitId: string = 'h1:dev-1:visit-1'
): HistorySyncVisit {
  return {
    visitId: visitId,
    clientId: 'dev-1',
    nativeVisitId: 'visit-1',
    url: url,
    title: title,
    visitedAt: 1700000000000,
    transition: 'link',
    referrer: '',
    deviceName: deviceName,
    source: 'app'
  };
}

function buildUpsert(visit: HistorySyncVisit, mutationId: string = 'm1'): HistorySyncMutation {
  return { mutationId: mutationId, kind: 'upsert_visit', visit: visit };
}

export default function historySyncTransportContractTest(): void {
  describe('History sync personal-server transport contract', () => {
    // The personal server refuses an over-long title with history_field_too_long and rejects the
    // whole exchange batch. The queue drains oldest first and the row is never acknowledged, so one
    // such page used to stop History sync from ever completing.
    it('caps a title that the personal server would refuse', 0, () => {
      const overLong = repeat('a', HISTORY_SYNC_VISIT_TITLE_MAX_LENGTH + 1);
      const normalized = normalizeHistorySyncMutationForTransport(buildUpsert(buildVisit(overLong)));

      expect(normalized !== undefined).assertTrue();
      expect(normalized?.visit?.title.length).assertEqual(HISTORY_SYNC_VISIT_TITLE_MAX_LENGTH);
    });

    it('leaves a conforming title untouched', 0, () => {
      const normalized = normalizeHistorySyncMutationForTransport(buildUpsert(buildVisit('正常标题')));

      expect(normalized?.visit?.title).assertEqual('正常标题');
    });

    it('keeps a title exactly at the limit', 0, () => {
      const atLimit = repeat('a', HISTORY_SYNC_VISIT_TITLE_MAX_LENGTH);
      const normalized = normalizeHistorySyncMutationForTransport(buildUpsert(buildVisit(atLimit)));

      expect(normalized?.visit?.title.length).assertEqual(HISTORY_SYNC_VISIT_TITLE_MAX_LENGTH);
    });

    it('caps the device name that the personal server limits to 128', 0, () => {
      const overLong = repeat('d', HISTORY_SYNC_VISIT_DEVICE_NAME_MAX_LENGTH + 1);
      const normalized = normalizeHistorySyncMutationForTransport(
        buildUpsert(buildVisit('short', overLong))
      );

      expect(normalized?.visit?.deviceName.length).assertEqual(HISTORY_SYNC_VISIT_DEVICE_NAME_MAX_LENGTH);
    });

    // A truncated URL or visit id names a different page or visit, and the server matches a deletion
    // against the ids it holds. Capping those would silently address the wrong record, so the
    // mutation must be withheld instead.
    it('withholds a visit whose URL cannot be sent as-is', 0, () => {
      const overLongUrl = 'https://example.com/' + repeat('a', 8192);
      const normalized = normalizeHistorySyncMutationForTransport(
        buildUpsert(buildVisit('short', 'Aira HarmonyOS', overLongUrl))
      );

      expect(normalized === undefined).assertTrue();
    });

    it('withholds a delete whose visit id exceeds the server limit', 0, () => {
      const mutation: HistorySyncMutation = {
        mutationId: 'm1',
        kind: 'delete_visit',
        visitId: 'h1:dev-1:' + repeat('a', 600)
      };

      expect(normalizeHistorySyncMutationForTransport(mutation) === undefined).assertTrue();
    });

    // The acknowledgement carries this id back and the outbox row is deleted by exact match, so a
    // trimmed id could never be reconciled against its own row.
    it('keeps the mutation id verbatim so its acknowledgement still matches', 0, () => {
      const mutationId = ' h1m_dev-1_upsert_abc ';
      const normalized = normalizeHistorySyncMutationForTransport(
        buildUpsert(buildVisit(), mutationId)
      );

      expect(normalized?.mutationId).assertEqual(mutationId);
    });

    // Huawei Space shares this outbox and has no such limits; its path never calls this normalizer.
    it('accepts every mutation kind the server understands', 0, () => {
      const deletion: HistorySyncMutation = {
        mutationId: 'a',
        kind: 'delete_visit',
        visitId: 'h1:dev-1:visit-1'
      };
      const range: HistorySyncMutation = {
        mutationId: 'b',
        kind: 'delete_range',
        url: 'https://example.com/',
        startedAt: 1,
        endedAt: 2
      };
      const clear: HistorySyncMutation = { mutationId: 'c', kind: 'clear_before', clearBefore: 1 };

      expect(normalizeHistorySyncMutationForTransport(deletion) !== undefined).assertTrue();
      expect(normalizeHistorySyncMutationForTransport(range) !== undefined).assertTrue();
      expect(normalizeHistorySyncMutationForTransport(clear) !== undefined).assertTrue();
    });

    it('withholds an upsert that carries no visit payload', 0, () => {
      const mutation: HistorySyncMutation = { mutationId: 'm1', kind: 'upsert_visit' };

      expect(normalizeHistorySyncMutationForTransport(mutation) === undefined).assertTrue();
    });
  });
}
