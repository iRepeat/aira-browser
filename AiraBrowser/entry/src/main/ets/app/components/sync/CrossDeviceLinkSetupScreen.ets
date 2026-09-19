import router from '@ohos.router';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  CrossDeviceLinkProviderKind,
  buildCrossDeviceLinkSteps
} from '../../../core/sync/CrossDeviceLinkViewModel';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../../common/config/AiraDistributionCapabilityOwner';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState
} from '../../../common/utils/RouteParamUtils';
import {
  SyncDesktopExtensionEntry,
  SyncDesktopExtensionEntryId,
  resolveSyncDesktopExtensionEntries,
  resolveSyncDesktopExtensionEntryActionLabel
} from '../../../services/sync/SyncDesktopExtensionCatalog';
import { BrowserClipboardService } from '../../../services/share/BrowserClipboardService';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BrowserSettingsIconBackgroundTokenSet,
  DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS
} from '../../../features/theme/BrowserThemePaletteModels';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import { SettingsNavigationRow, SettingsRowPosition } from '../settings/SettingsRows';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AppServiceModeGateService } from '../../../services/settings/AppServiceModeGateService';
import { sharedPreferencesRepository } from '../../bootstrap/BrowserAppRuntime';

const EXTENSION_GLYPH: AiraRenderableIconId = 'site.setting.externalActions';
const LOCAL_PACKAGE_GLYPH: AiraRenderableIconId = 'settings.downloads';
const STEP_BADGE_SIZE: number = 22;
// Browser store rows show the vendor mark itself, so it keeps the same leading width as
// the round glyph it replaces without drawing a second, brand-less circle behind it.
const BROWSER_BRAND_LEADING_SIZE: number = 34;
const BROWSER_BRAND_ICON_SIZE: number = 26;
const STEP_ROW_HORIZONTAL_PADDING: number = 16;
const STEP_ROW_VERTICAL_PADDING: number = 14;

const LOCKED_PAGE_TOAST: string = '访问密码已复制，粘贴即可';

/**
 * The install and pairing recipe, one level below 跨设备互联 so the overview stays a
 * status page. The mode arrives through the route, so this surface needs no sync state
 * of its own, and the page it lives in stays a shell.
 */
@Component
export struct CrossDeviceLinkSetupScreen {
  /** Bumped by the owning page's onPageShow, which only an @Entry component receives. */
  @Prop @Watch('handlePageShowRefresh') refreshToken: number = 0;
  /** Embedded in the large-screen settings pane instead of its own routed page. */
  @Prop embedded: boolean = false;
  @Prop desktopPresentation: boolean = false;
  @Prop @Watch('handleEmbeddedProviderChange') providerKind: CrossDeviceLinkProviderKind = 'none';
  /** When embedded, back exits the workspace pane instead of popping the router. */
  onExit?: () => void;
  /** Provided by the PC shell, which opens the link in the browser instead of routing. */
  onOpenExternalUrl?: (url: string) => void;
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = DEFAULT_THEME_PALETTE.light.divider;
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY) private storedSettingsIconForegroundColor: string =
    DEFAULT_THEME_PALETTE.light.settingsIconForeground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textSecondary;
  @State private steps: string[] = [];
  @State private installEntries: SyncDesktopExtensionEntry[] = resolveSyncDesktopExtensionEntries();
  @State private settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet =
    DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS;
  private readonly navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private readonly clipboardService: BrowserClipboardService = new BrowserClipboardService();
  private readonly appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private boundary: BrowserBoundaryRouteState = {
    dataScope: '',
    privacyMode: '',
    boundarySource: ''
  };

  aboutToAppear(): void {
    this.refresh();
  }

  private handlePageShowRefresh(): void {
    this.refresh();
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '互联教程',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        showBackButton: !this.embedded,
        showTitleBar: !this.embedded,
        useTopSafeInset: !this.embedded,
        desktopPresentation: this.desktopPresentation,
        menuActionLabel: '帮助',
        menuActionIcon: $r('sys.symbol.doc_text_fill'),
        onMenuAction: (): void => {
          this.navigationCoordinator.openSyncDesktopBookmarkGuide(this.boundary);
        },
        onBack: (): void => {
          this.handleBack();
        }
      }) {
        SettingsPresentationScrollBody({
          desktopPresentation: this.desktopPresentation,
          contentSpace: 16,
          topPadding: 8,
          bottomPadding: 28
        }) {
          this.buildStepsSection()
          this.buildInstallSection()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildStepsSection() {
    SettingsSection({ title: '连接步骤', secondaryTextColor: this.storedSecondaryTextColor }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor
      }) {
        ForEach(this.steps, (step: string, index: number) => {
          this.buildStepRow(`${index + 1}`, step, index > 0)
        }, (step: string, index: number): string => `${index}-${step}`)
      }
    }
  }

  @Builder
  private buildStepRow(step: string, title: string, withDivider: boolean) {
    Column({ space: 0 }) {
      if (withDivider) {
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
      }

      Row({ space: 12 }) {
        // Neutral numerals, not a brand-colored badge: the steps are structure, not
        // an action, so they read as plain black on white.
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(STEP_BADGE_SIZE)
            .height(STEP_BADGE_SIZE)
            .borderRadius(STEP_BADGE_SIZE / 2)
            .backgroundColor(this.storedPrimaryTextColor)

          Text(step)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.storedSurfaceBackgroundColor)
        }
        .width(STEP_BADGE_SIZE)
        .height(STEP_BADGE_SIZE)

        Text(title)
          .layoutWeight(1)
          .fontSize(15)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({
        left: STEP_ROW_HORIZONTAL_PADDING,
        right: STEP_ROW_HORIZONTAL_PADDING,
        top: STEP_ROW_VERTICAL_PADDING,
        bottom: STEP_ROW_VERTICAL_PADDING
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }

  @Builder
  private buildInstallSection() {
    SettingsSection({ title: '安装 Aira-sync', secondaryTextColor: this.storedSecondaryTextColor }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor
      }) {
        ForEach(this.installEntries, (entry: SyncDesktopExtensionEntry, index: number) => {
          if (index > 0) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
          SettingsNavigationRow({
            title: entry.title,
            value: resolveSyncDesktopExtensionEntryActionLabel(entry),
            useCustomLeading: this.isBrowserBrandEntry(entry.id),
            airaIconId: this.isBrowserBrandEntry(entry.id)
              ? undefined
              : (entry.action === 'open_link' ? LOCAL_PACKAGE_GLYPH : EXTENSION_GLYPH),
            iconBackgroundColor: this.isBrowserBrandEntry(entry.id)
              ? undefined
              : (entry.action === 'open_link'
                ? this.settingsIconBackgrounds.downloads
                : this.settingsIconBackgrounds.siteCustomization),
            iconColor: this.storedSettingsIconForegroundColor,
            rowPosition: this.resolveRowPosition(index, this.installEntries.length),
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            pressedBackgroundColor: this.storedPressedBackgroundColor,
            onAction: (): void => {
              this.handleInstallEntry(entry);
            },
            customLeading: () => {
              this.buildBrowserBrandLeading(entry.id);
            }
          })
        }, (entry: SyncDesktopExtensionEntry): string => entry.id)
      }

      Text('手机上装不了电脑浏览器的扩展：把链接发到电脑，在电脑上安装。')
        .width('100%')
        .fontSize(13)
        .lineHeight(19)
        .fontColor(this.storedSecondaryTextColor)
        .padding({ left: 4, right: 4 })
    }
  }

  private refresh(): void {
    if (!this.appServiceModeGateService.canUseOptionalService()) {
      this.handleBack();
      return;
    }
    const params = router.getParams() as Record<string, string | undefined> | undefined;
    this.boundary = readBrowserBoundaryRouteState(this.boundary);
    // Embedded, the owning host already resolved the mode and passes it as a prop; the
    // routed page keeps reading it from its own route instead.
    const providerKind = this.embedded
      ? this.providerKind
      : this.resolveProviderKind(params?.crossDeviceLinkProvider ?? '');
    this.steps = buildCrossDeviceLinkSteps(
      providerKind,
      AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')
    );
  }

  private handleEmbeddedProviderChange(): void {
    if (this.embedded) {
      this.refresh();
    }
  }

  private handleBack(): void {
    if (this.onExit !== undefined) {
      this.onExit();
      return;
    }
    this.navigationCoordinator.back();
  }

  private resolveProviderKind(value: string): CrossDeviceLinkProviderKind {
    if (value === 'aira_cloud' || value === 'self_hosted' || value === 'webdav' ||
      value === 'huawei_space' || value === 'none') {
      return value;
    }
    return 'none';
  }

  private resolveRowPosition(index: number, total: number): SettingsRowPosition {
    if (total <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    return index === total - 1 ? 'last' : 'middle';
  }

  @Builder
  private buildBrowserBrandLeading(id: SyncDesktopExtensionEntryId) {
    Stack({ alignContent: Alignment.Center }) {
      Image(this.resolveBrowserBrandIcon(id))
        .width(BROWSER_BRAND_ICON_SIZE)
        .height(BROWSER_BRAND_ICON_SIZE)
        .objectFit(ImageFit.Contain)
    }
    .width(BROWSER_BRAND_LEADING_SIZE)
    .height(BROWSER_BRAND_LEADING_SIZE)
  }

  private isBrowserBrandEntry(id: SyncDesktopExtensionEntryId): boolean {
    return id === 'chrome' || id === 'edge' || id === 'firefox';
  }

  private resolveBrowserBrandIcon(id: SyncDesktopExtensionEntryId): Resource {
    if (id === 'edge') {
      return $r('app.media.sync_browser_edge');
    }
    if (id === 'firefox') {
      return $r('app.media.sync_browser_firefox');
    }
    return $r('app.media.sync_browser_chrome');
  }

  private handleInstallEntry(entry: SyncDesktopExtensionEntry): void {
    if (entry.action === 'open_link') {
      this.openLockedPage(entry);
      return;
    }
    void this.clipboardService.copyText({
      value: entry.url,
      emptyMessage: '链接暂时不可用',
      successMessage: '已复制，粘贴到电脑浏览器里打开',
      failureMessage: '复制失败，请稍后重试。'
    }).catch((): undefined => undefined).then((result): void => {
      if (result !== undefined) {
        this.showToast(result.message);
      }
    });
  }

  /**
   * The download page is password protected, so the password lands on the clipboard
   * first and a light toast says it is ready to paste as the page opens.
   */
  private openLockedPage(entry: SyncDesktopExtensionEntry): void {
    if (entry.password.length === 0) {
      this.openUrlInBrowser(entry.url);
      return;
    }
    void this.clipboardService.copyText({
      value: entry.password,
      emptyMessage: '访问密码暂时不可用',
      successMessage: LOCKED_PAGE_TOAST,
      failureMessage: '访问密码复制失败，请稍后重试。'
    }).catch((): undefined => undefined).then((result): void => {
      this.showToast(result !== undefined ? result.message : LOCKED_PAGE_TOAST);
      this.openUrlInBrowser(entry.url);
    });
  }

  private openUrlInBrowser(url: string): void {
    if (url.length === 0) {
      return;
    }
    // The PC shell hosts settings in the tab's native route, where router.back cannot bring
    // the page forward; it hands us its own opener so the link really opens.
    if (this.onOpenExternalUrl !== undefined) {
      this.onOpenExternalUrl(url);
      return;
    }
    this.navigationCoordinator.openBrowserUrlFromGuide(url, this.boundary);
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      duration: 1800
    });
  }
}
