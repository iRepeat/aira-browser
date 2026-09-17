/**
 * Whether a stored history-sync account binding must be discarded because the app is now bound to a
 * different account.
 *
 * History is the only sync domain whose selection is bound to an account: local history rows carry a
 * `sync_account_uid`, so an account switch has to drop the previous account's selection rather than
 * push one account's history into another. Bookmarks and personalization hold no such binding.
 *
 * The distinction that matters here is "signed out" versus "switched account". Signing out makes the
 * current account empty; that is a pause, not a switch, so the user's choice has to survive it.
 * Treating the empty account as a different account is what silently turned the toggle off on every
 * sign-out and, because a cleared selection short-circuits reconciliation, kept it off after signing
 * back in.
 */
export function shouldClearHistoryAccountBinding(
  boundAccountUid: string,
  currentAccountUid: string
): boolean {
  const bound = boundAccountUid.trim();
  const current = currentAccountUid.trim();
  // An unbound selection has nothing to discard, and an empty current account is a sign-out rather
  // than a switch. Only a real account replacing a different real account invalidates the binding.
  if (bound.length <= 0 || current.length <= 0) {
    return false;
  }
  return bound !== current;
}
