export type CrossDeviceTransportKind = 'account' | 'personal-server' | 'unavailable';

/**
 * Cross-device tabs and page push follow the signed-in account, not the selected
 * data-sync source. Personal Server stays its own paired channel when that source
 * is selected, and does not require the account.
 */
export function resolveCrossDeviceTransportKind(input: {
  selectedSyncSource: string | null | undefined;
  personalServerReady: boolean;
  accountSignedIn: boolean;
}): CrossDeviceTransportKind {
  if (input.selectedSyncSource === 'personal-server' && input.personalServerReady) {
    return 'personal-server';
  }
  if (input.selectedSyncSource === 'personal-server') {
    return 'unavailable';
  }
  if (input.accountSignedIn) {
    return 'account';
  }
  return 'unavailable';
}
