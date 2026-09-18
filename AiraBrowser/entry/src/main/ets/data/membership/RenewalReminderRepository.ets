import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const PREFERENCES_NAME: string = 'aira_membership_renewal_reminder';
const RENEWAL_REMINDER_STATE_KEY: string = 'state_v1';

/**
 * Device-local do-not-disturb memory for the Pro renewal reminder, scoped per
 * Huawei account.
 *
 * The reminder is keyed by the instant the previous Pro period ended rather than
 * by a plain "shown" flag. That makes it once per lapse without making it once
 * per device forever: a later period that lapses again has a different expiry
 * timestamp and is therefore announceable again, which is the behavior a user
 * expects from "your membership ran out". The record only ever suppresses the
 * unprompted reminder; it never blocks a reminder the user asked for by tapping
 * a Pro feature.
 */
export interface AiraRenewalReminderLocalRecord {
  remindedForExpiredAt: number;
}

export function buildEmptyRenewalReminderLocalRecord(): AiraRenewalReminderLocalRecord {
  return {
    remindedForExpiredAt: 0
  };
}

export class RenewalReminderRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private records: Record<string, AiraRenewalReminderLocalRecord | undefined> = {};

  async initialize(): Promise<void> {
    const store = await this.getStore();
    this.records = this.parseRecords(store.getSync(RENEWAL_REMINDER_STATE_KEY, '{}'));
  }

  getRecord(uid: string): AiraRenewalReminderLocalRecord {
    const normalizedUid = uid.trim();
    if (normalizedUid.length === 0) {
      return buildEmptyRenewalReminderLocalRecord();
    }
    return this.cloneRecord(this.records[normalizedUid]);
  }

  /**
   * Records that the reminder for this specific lapse was shown. Reminder
   * identity is the expiry instant, so an older lapse never suppresses a newer
   * one and a repeated evaluation of the same lapse stays quiet.
   */
  async markReminded(uid: string, expiredAt: number): Promise<AiraRenewalReminderLocalRecord> {
    const normalizedUid = uid.trim();
    const normalizedExpiredAt = this.normalizeTimestamp(expiredAt);
    if (normalizedUid.length === 0 || normalizedExpiredAt <= 0) {
      return buildEmptyRenewalReminderLocalRecord();
    }
    const current = this.cloneRecord(this.records[normalizedUid]);
    if (current.remindedForExpiredAt >= normalizedExpiredAt) {
      return current;
    }
    const nextRecord: AiraRenewalReminderLocalRecord = {
      remindedForExpiredAt: normalizedExpiredAt
    };
    this.records[normalizedUid] = nextRecord;
    const store = await this.getStore();
    store.putSync(RENEWAL_REMINDER_STATE_KEY, JSON.stringify(this.serializeRecords()));
    store.flushSync();
    return this.cloneRecord(nextRecord);
  }

  private serializeRecords(): Record<string, AiraRenewalReminderLocalRecord> {
    const serialized: Record<string, AiraRenewalReminderLocalRecord> = {};
    Object.keys(this.records).forEach((uid: string): void => {
      const record = this.records[uid];
      if (record === undefined || record.remindedForExpiredAt <= 0) {
        return;
      }
      serialized[uid] = this.cloneRecord(record);
    });
    return serialized;
  }

  private parseRecords(value: preferences.ValueType):
    Record<string, AiraRenewalReminderLocalRecord | undefined> {
    const records: Record<string, AiraRenewalReminderLocalRecord | undefined> = {};
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

  private normalizeRecord(value: Object | undefined): AiraRenewalReminderLocalRecord {
    const raw = value as Record<string, number | undefined> | undefined;
    return {
      remindedForExpiredAt: this.normalizeTimestamp(raw?.remindedForExpiredAt)
    };
  }

  private cloneRecord(value: AiraRenewalReminderLocalRecord | undefined): AiraRenewalReminderLocalRecord {
    if (value === undefined) {
      return buildEmptyRenewalReminderLocalRecord();
    }
    return {
      remindedForExpiredAt: value.remindedForExpiredAt
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

export const sharedRenewalReminderRepository: RenewalReminderRepository = new RenewalReminderRepository();
