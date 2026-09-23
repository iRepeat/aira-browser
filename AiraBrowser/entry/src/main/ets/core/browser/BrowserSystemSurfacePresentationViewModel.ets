import { BrowserSystemSheetSnapshot } from './BrowserTransientSurfaceCoordinator';
import { BrowserSystemSheetType } from './BrowserShellRuntimeContracts';
import { isDedicatedLargeScreenSystemSheet } from './DesktopDialogSheetPolicy';

export function isNovelReaderSystemSurfaceType(type: BrowserSystemSheetType): boolean {
  return type === 'novelCatalog' || type === 'novelReaderText' ||
    type === 'novelReaderAppearance' || type === 'novelReaderSettings';
}

export function resolveNovelReaderSystemSurfaceTitle(type: BrowserSystemSheetType): string {
  if (type === 'novelCatalog') {
    return '目录';
  }
  if (type === 'novelReaderAppearance') {
    return '亮度与主题';
  }
  if (type === 'novelReaderSettings') {
    return '阅读设置';
  }
  if (type === 'novelReaderText') {
    return '文字';
  }
  return '';
}

export interface BrowserSystemSurfacePresentation {
  phoneSheetVisible: boolean;
  largeScreenCenteredContentVisible: boolean;
  largeScreenHomeShortcutDialogVisible: boolean;
  largeScreenHomeSettingsDialogVisible: boolean;
  largeScreenUserScriptInstallDialogVisible: boolean;
  largeScreenNovelReaderDialogVisible: boolean;
  largeScreenNovelReaderDialogTitle: string;
}

export class BrowserSystemSurfacePresentationViewModel {
  resolve(
    systemSheet: BrowserSystemSheetSnapshot,
    shellFamily: 'phone' | 'large_screen'
  ): BrowserSystemSurfacePresentation {
    const largeScreenHomeShortcutDialogVisible = systemSheet.visible &&
      systemSheet.type === 'homeShortcutSelection' &&
      shellFamily === 'large_screen';
    const largeScreenHomeSettingsDialogVisible = systemSheet.visible &&
      systemSheet.type === 'homeSettings' &&
      shellFamily === 'large_screen';
    const largeScreenUserScriptInstallDialogVisible = systemSheet.visible &&
      systemSheet.type === 'userScriptInstall' &&
      shellFamily === 'large_screen';
    const largeScreenNovelReaderDialogVisible = systemSheet.visible &&
      isNovelReaderSystemSurfaceType(systemSheet.type) &&
      shellFamily === 'large_screen';
    const largeScreenCenteredContentVisible = systemSheet.visible &&
      systemSheet.type !== 'none' &&
      shellFamily === 'large_screen' &&
      !isDedicatedLargeScreenSystemSheet(systemSheet.type);
    return {
      phoneSheetVisible: systemSheet.visible &&
        systemSheet.type !== 'none' &&
        shellFamily !== 'large_screen',
      largeScreenCenteredContentVisible: largeScreenCenteredContentVisible,
      largeScreenHomeShortcutDialogVisible: largeScreenHomeShortcutDialogVisible,
      largeScreenHomeSettingsDialogVisible: largeScreenHomeSettingsDialogVisible,
      largeScreenUserScriptInstallDialogVisible: largeScreenUserScriptInstallDialogVisible,
      largeScreenNovelReaderDialogVisible: largeScreenNovelReaderDialogVisible,
      largeScreenNovelReaderDialogTitle: resolveNovelReaderSystemSurfaceTitle(systemSheet.type)
    };
  }
}
