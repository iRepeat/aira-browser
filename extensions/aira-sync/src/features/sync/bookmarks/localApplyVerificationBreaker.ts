import { LEAFTAB_BACKGROUND_STORAGE_KEYS } from '@/features/sync/app/leafTabSyncStorageKeys';
import {
  readExtensionStorageRecord,
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';

// Consecutive local apply/verify failure breaker for background auto-sync. A deterministic
// verification failure on a poisoned local tree used to re-arm forever: every failing round
// still overwrote the remote, never advanced the baseline, and its own bookmark events
// scheduled the next retry, which re-reported the manufactured conflict dialog
// (2026-10 incident, uid 2029059012955225536). After the limit, background auto-sync stops;
// one successful manual sync clears the breaker. This is a sticky failure flag only —
// not an oplog, outbox, journal, or second sync authority.
export const LEAFTAB_LOCAL_APPLY_VERIFICATION_FAILURE_LIMIT = 3;

export const LEAFTAB_LOCAL_APPLY_VERIFICATION_PAUSED_MESSAGE =
  '书签本地落地校验连续失败，自动同步已暂停。请手动执行一次完整同步；若仍失败，请检查本机书签是否被其他工具重复写入。';

export const resolveLeafTabLocalApplyVerificationNextCount = (
  previousCount: number,
): { count: number; paused: boolean } => {
  const count = Number.isFinite(previousCount) && previousCount > 0
    ? Math.floor(previousCount) + 1
    : 1;
  return { count, paused: count >= LEAFTAB_LOCAL_APPLY_VERIFICATION_FAILURE_LIMIT };
};

export async function readLeafTabLocalApplyVerificationPaused(): Promise<boolean> {
  const record = await readExtensionStorageRecord([
    LEAFTAB_BACKGROUND_STORAGE_KEYS.localApplyVerificationPausedAt,
  ]);
  return Boolean(record[LEAFTAB_BACKGROUND_STORAGE_KEYS.localApplyVerificationPausedAt]);
}

// Returns true when this failure trips the breaker.
export async function recordLeafTabLocalApplyVerificationFailure(): Promise<boolean> {
  const countKey = LEAFTAB_BACKGROUND_STORAGE_KEYS.localApplyVerificationFailureCount;
  const [record, nowIso] = await Promise.all([
    readExtensionStorageRecord([countKey]),
    Promise.resolve(new Date().toISOString()),
  ]);
  const { count, paused } = resolveLeafTabLocalApplyVerificationNextCount(
    Number(record[countKey] || 0),
  );
  if (paused) {
    await writeExtensionStorageRecord({
      [countKey]: count,
      [LEAFTAB_BACKGROUND_STORAGE_KEYS.localApplyVerificationPausedAt]: nowIso,
    });
    return true;
  }
  await writeExtensionStorageRecord({ [countKey]: count });
  return false;
}

export async function clearLeafTabLocalApplyVerificationBreaker(): Promise<void> {
  await removeExtensionStorageKeys([
    LEAFTAB_BACKGROUND_STORAGE_KEYS.localApplyVerificationFailureCount,
    LEAFTAB_BACKGROUND_STORAGE_KEYS.localApplyVerificationPausedAt,
  ]);
}
