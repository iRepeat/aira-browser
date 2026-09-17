import { describe, expect, it } from '@ohos/hypium';
import { shouldClearHistoryAccountBinding } from '../main/ets/core/sync/HistoryAccountBindingPolicy';

// Regression guard for the history-sync toggle turning itself off. History is the only sync domain
// bound to an account (local history rows carry `sync_account_uid`), so an account switch must drop
// the previous selection. Signing out empties the account, and that was being read as a switch: the
// toggle was cleared on every sign-out and, because a cleared selection short-circuits
// reconciliation, stayed off after signing back in.
//
// The same misreading had a second, worse consequence on the delete path:
// detachHistorySyncRemoteProjectionsExcept matches `sync_account_uid <> ?`, which selects every
// remote row when the uid is empty, so a sign-out wiped the user's synchronized history. That guard
// lives in BrowserDatabase and is enforced by the History Sync contract check.
export default function historyAccountBindingPolicyTest(): void {
  describe('History account binding policy', () => {
    it('keeps the selection when the user signs out', 0, () => {
      // Signed out: a real bound account with no current account is a pause, not a switch.
      expect(shouldClearHistoryAccountBinding('uid-a', '')).assertFalse();
    });

    it('keeps the selection when the same account signs back in', 0, () => {
      expect(shouldClearHistoryAccountBinding('uid-a', 'uid-a')).assertFalse();
    });

    it('clears the selection when a different account replaces the bound one', 0, () => {
      expect(shouldClearHistoryAccountBinding('uid-a', 'uid-b')).assertTrue();
    });

    it('clears the selection when the provider identity changes', 0, () => {
      // self_hosted binds to the Personal Server instance id, so a different instance is a switch.
      expect(shouldClearHistoryAccountBinding('instance-1', 'instance-2')).assertTrue();
    });

    it('does nothing for an unbound selection', 0, () => {
      expect(shouldClearHistoryAccountBinding('', 'uid-a')).assertFalse();
      expect(shouldClearHistoryAccountBinding('', '')).assertFalse();
    });

    it('ignores surrounding whitespace on either side', 0, () => {
      expect(shouldClearHistoryAccountBinding(' uid-a ', 'uid-a')).assertFalse();
      expect(shouldClearHistoryAccountBinding('uid-a', '  ')).assertFalse();
      expect(shouldClearHistoryAccountBinding(' uid-a ', ' uid-b ')).assertTrue();
    });
  });
}
