import { BrowserSystemSheetType } from './BrowserShellRuntimeContracts';
import { DesktopDialogTier } from './BrowserDialogPresentationTokens';

/**
 * Content-shaped tier for a system sheet once the large-screen shell presents
 * it as a centered dialog. Phone sheets do not consult this.
 */
export function resolveSystemSheetDialogTier(type: BrowserSystemSheetType): DesktopDialogTier {
  if (type === 'releaseNotice' || type === 'resourceCandidates' ||
    type === 'readerText' || type === 'readerAppearance' || type === 'readerSettings') {
    return 'l';
  }
  if (type === 'desktopLoginConfirm') {
    return 's';
  }
  if (type === 'novelCatalog') {
    return 'm';
  }
  if (type === 'novelReaderText' || type === 'novelReaderAppearance' || type === 'novelReaderSettings') {
    return 'l';
  }
  return 'm';
}

export function isDedicatedLargeScreenSystemSheet(type: BrowserSystemSheetType): boolean {
  return type === 'homeShortcutSelection' || type === 'homeSettings' ||
    type === 'userScriptInstall' || type === 'novelCatalog' ||
    type === 'novelReaderText' || type === 'novelReaderAppearance' ||
    type === 'novelReaderSettings';
}
