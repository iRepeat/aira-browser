import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const PREFERENCES_NAME: string = 'aira_membership_new_user_gift';
const NEW_USER_GIFT_STATE_KEY: string = 'state_v1';

/**
 * Device-local presentation memory for the new-user gift announcement, scoped
 * per Huawei account. It records only whether this device has already told the
 * user about the welcome gift; the grant itself is applied by the hosted
 * service and never depends on this record.
 */
export interface AiraNewUserGiftLocalRecord {
  acknowledgedAt: number;
}

export function buildEmptyNewUserGiftLocalRecord(): AiraNewUserGiftLocalRecord {
  return {
    acknowledgedAt: 0
  };
}

export class NewUserGiftRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private records: Record<string, AiraNewUserGiftLocalRecord | undefined> = {};

  async initialize(): Promise<void> {
    const store = await this.getStore();
    this.records = this.parseRecords(store.getSync(NEW_USER_GIFT_STATE_KEY, '{}'));
  }

  getRecord(uid: string): AiraNewUserGiftLocalRecord {
    const normalizedUid = uid.trim();
    if (normalizedUid.length === 0) {
      return buildEmptyNewUserGiftLocalRecord();
    }
    return this.cloneRecord(this.records[normalizedUid]);
  }

  async markAcknowledged(uid: string, now: number = Date.now()): Promise<AiraNewUserGiftLocalRecord> {
    const normalizedUid = uid.trim();
    if (normalizedUid.length === 0) {
      return buildEmptyNewUserGiftLocalRecord();
    }
    const current = this.cloneRecord(this.records[normalizedUid]);
    if (current.acknowledgedAt > 0) {
      return current;
    }
    const nextRecord: AiraNewUserGiftLocalRecord = {
      acknowledgedAt: now
    };
    this.records[normalizedUid] = nextRecord;
    const store = await this.getStore();
    store.putSync(NEW_USER_GIFT_STATE_KEY, JSON.stringify(this.serializeRecords()));
    store.flushSync();
    return this.cloneRecord(nextRecord);
  }

  private serializeRecords(): Record<string, AiraNewUserGiftLocalRecord> {
    const serialized: Record<string, AiraNewUserGiftLocalRecord> = {};
    Object.keys(this.records).forEach((uid: string): void => {
      const record = this.records[uid];
      if (record === undefined || record.acknowledgedAt <= 0) {
        return;
      }
      serialized[uid] = this.cloneRecord(record);
    });
    return serialized;
  }

  private parseRecords(value: preferences.ValueType): Record<string, AiraNewUserGiftLocalRecord | undefined> {
    const records: Record<string, AiraNewUserGiftLocalRecord | undefined> = {};
    const raw = String(value ?? '').trim();
    if (raw.length === 0) {
      return records;
    }
    try {
      const parsed = JSON.parse(raw) as Record<string, Object | undefined>;
      Object.keys(parsed).forEach((uid: string): void => {
        const normalizedUid = uid.trim();
        if (normalizedUid.length === 0) {
          return;
        }
        records[normalizedUid] = this.normalizeRecord(parsed[uid]);
      });
    } catch (_error) {
    }
    return records;
  }

  private normalizeRecord(value: Object | undefined): AiraNewUserGiftLocalRecord {
    const raw = value as Record<string, number | undefined> | undefined;
    return {
      acknowledgedAt: this.normalizeTimestamp(raw?.acknowledgedAt)
    };
  }

  private cloneRecord(value: AiraNewUserGiftLocalRecord | undefined): AiraNewUserGiftLocalRecord {
    if (value === undefined) {
      return buildEmptyNewUserGiftLocalRecord();
    }
    return {
      acknowledgedAt: value.acknowledgedAt
    };
  }

  private normalizeTimestamp(value: number | undefined): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.floor(value));
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences): preferences.Preferences => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }
}

export const sharedNewUserGiftRepository: NewUserGiftRepository = new NewUserGiftRepository();
