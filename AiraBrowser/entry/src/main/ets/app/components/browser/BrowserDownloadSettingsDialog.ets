import {
  BrowserDataScope,
  BrowserSessionPrivacyMode,
  DEFAULT_BROWSER_PROFILE_ID
} from '../../../common/models/BrowserModels';
import { DownloadTaskBoundary } from '../../../domain/download/DownloadTypes';
import { BrowserWindowRuntime } from '../../runtime/BrowserWindowRuntime';
import { CENTERED_DIALOG_SYSTEM_TALL_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';
import { BrowserLargeScreenModalHeader } from './BrowserLargeScreenModalHeader';
import {
  BrowserDownloadSettingsOptionScreen,
  BrowserDownloadSettingsScreen,
  BrowserDownloadSettingsSubpage
} from './BrowserDownloadSettingsScreen';

const DOWNLOAD_SETTINGS_DIALOG_MAIN_SUBPAGE: BrowserDownloadSettingsSubpage = 'main';

@CustomDialog
export struct BrowserDownloadSettingsDialog {
  controller?: CustomDialogController;
  @Link @Watch('applyOpenRevision') openRevision: number;
  resolveBoundary: () => DownloadTaskBoundary = (): DownloadTaskBoundary => {
    return {
      profileId: DEFAULT_BROWSER_PROFILE_ID,
      privacyMode: 'regular',
      dataScope: 'profile_persistent'
    };
  };
  onClose: () => void = (): void => {};
  onChooseCustomLocation: () => void = (): void => {};
  @State private activeSubpage: BrowserDownloadSettingsSubpage = DOWNLOAD_SETTINGS_DIALOG_MAIN_SUBPAGE;
  @State private privacyMode: BrowserSessionPrivacyMode = 'regular';
  @State private dataScope: BrowserDataScope = 'profile_persistent';
  @State private appliedOpenRevision: number = -1;

  aboutToAppear(): void {
    this.applyOpenRevision();
  }

  build() {
    Column() {
      BrowserLargeScreenModalHeader({
        title: this.resolveTitle(),
        dialogMode: true,
        showBackButton: this.activeSubpage !== DOWNLOAD_SETTINGS_DIALOG_MAIN_SUBPAGE,
        onBack: (): void => {
          this.activeSubpage = DOWNLOAD_SETTINGS_DIALOG_MAIN_SUBPAGE;
        },
        onClose: this.onClose
      })
        .zIndex(1)

      Column() {
        if (this.activeSubpage === DOWNLOAD_SETTINGS_DIALOG_MAIN_SUBPAGE) {
          BrowserDownloadSettingsScreen({
            showBackButton: false,
            showTitleBar: false,
            useTopSafeInset: false,
            embeddedInDialog: true,
            boundary: this.currentBoundary(),
            onOpenEmbeddedSubpage: (subpage: BrowserDownloadSettingsSubpage): void => {
              this.activeSubpage = subpage;
            },
            onFolderChangeRequested: (): void => {
              this.onChooseCustomLocation();
            }
          })
            .width('100%')
            .height('100%')
        } else {
          BrowserDownloadSettingsOptionScreen({
            subpage: this.activeSubpage,
            boundary: this.currentBoundary(),
            embeddedInDialog: true,
            showBackButton: false,
            showTitleBar: false,
            useTopSafeInset: false,
            onBack: (): void => {
              this.activeSubpage = DOWNLOAD_SETTINGS_DIALOG_MAIN_SUBPAGE;
            }
          })
            .width('100%')
            .height('100%')
        }
      }
      .width('100%')
      .layoutWeight(1)
      .clip(true)
      .alignItems(HorizontalAlign.Start)
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_TALL_SURFACE_MODIFIER)
    .keyboardShortcut(FunctionKey.ESC, [], (): void => {
      this.onClose();
    })
  }

  private applyOpenRevision(): void {
    if (this.appliedOpenRevision === this.openRevision) {
      return;
    }
    this.appliedOpenRevision = this.openRevision;
    this.activeSubpage = DOWNLOAD_SETTINGS_DIALOG_MAIN_SUBPAGE;
    const boundary = this.resolveBoundary();
    this.privacyMode = boundary.privacyMode;
    this.dataScope = boundary.dataScope;
  }

  private currentBoundary(): DownloadTaskBoundary {
    return {
      windowId: BrowserWindowRuntime.getActiveWindowId(),
      profileId: DEFAULT_BROWSER_PROFILE_ID,
      privacyMode: this.privacyMode,
      dataScope: this.dataScope
    };
  }

  private resolveTitle(): string {
    switch (this.activeSubpage) {
      case 'hls_concurrency':
        return 'HLS 分片并发数';
      case 'auto_clear':
        return '自动清理';
      case 'private_file':
        return '私密下载文件';
      case 'private_record':
        return '私密下载记录';
      default:
        return '下载设置';
    }
  }
}
