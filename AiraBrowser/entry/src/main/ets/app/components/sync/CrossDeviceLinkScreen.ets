import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  CrossDeviceLinkActionId,
  CrossDeviceLinkCapabilityRowState,
  CrossDeviceLinkDeviceRowState,
  CrossDeviceLinkViewState
} from '../../../core/sync/CrossDeviceLinkViewModel';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { SettingsContentKind } from '../../../core/settings/SettingsContentLayoutPolicy';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BrowserSettingsIconBackgroundTokenSet,
  BrowserSyncProviderIconBackgroundTokenSet,
  DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS,
  DEFAULT_BROWSER_SYNC_PROVIDER_ICON_BACKGROUND_TOKENS
} from '../../../features/theme/BrowserThemePaletteModels';
import { AiraIcon } from '../common/AiraIcon';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import {
  SettingsActionButton,
  SettingsNavigationRow,
  SettingsRowPosition
} from '../settings/SettingsRows';

const CONNECTION_GLYPH: AiraRenderableIconId = 'browser.toolbar.sendToDesktop';
const DEVICE_GLYPH: AiraRenderableIconId = 'browser.toolbar.tabs';
const EXTENSION_GLYPH: AiraRenderableIconId = 'site.setting.externalActions';
const SELF_HOSTED_GLYPH: AiraRenderableIconId = 'settings.webdav';
const BOOKMARK_GLYPH: AiraRenderableIconId = 'browser.shortcut.bookmarks';
const HISTORY_GLYPH: AiraRenderableIconId = 'browser.shortcut.history';
const PAGE_PUSH_GLYPH: AiraRenderableIconId = 'browser.toolbar.sendToDesktop';
const DEVICE_TABS_GLYPH: AiraRenderableIconId = 'browser.toolbar.tabs';

const STATUS_GLYPH_SIZE: number = 58;
const STATUS_GLYPH_RADIUS: number = 16;
const STATUS_GLYPH_ICON_SIZE: number = 28;
const STATUS_PANEL_HORIZONTAL_PADDING: number = 16;
const STATUS_PANEL_VERTICAL_PADDING: number = 18;

@Component
export struct CrossDeviceLinkScreen {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = DEFAULT_THEME_PALETTE.light.accent;
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
  @Prop state: CrossDeviceLinkViewState;
  @Prop isAddingDevice: boolean = false;
  @Prop isBusy: boolean = false;
  @Prop showBackButton: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop contentKind: SettingsContentKind = 'standard';
  @Prop desktopPresentation: boolean = false;
  @Prop settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet =
    DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS;
  @Prop syncProviderIconBackgrounds: BrowserSyncProviderIconBackgroundTokenSet =
    DEFAULT_BROWSER_SYNC_PROVIDER_ICON_BACKGROUND_TOKENS;
  scrollers: Array<Scroller> = [];
  onBack: () => void = (): void => {};
  onHelp: () => void = (): void => {};
  onAddDevice: () => void = (): void => {};
  onOpenSetup: () => void = (): void => {};
  onOpenDeviceTabs: (deviceId: string) => void = (_deviceId: string): void => {};
  onAction: (action: CrossDeviceLinkActionId) => void = (_action: CrossDeviceLinkActionId) => {};
  private contentScroller: Scroller = new Scroller();

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '跨系统互联',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        showBackButton: this.showBackButton,
        useTopSafeInset: this.useTopSafeInset,
        contentKind: this.contentKind,
        desktopPresentation: this.desktopPresentation,
        menuActionLabel: '帮助',
        menuActionIcon: $r('sys.symbol.doc_text_fill'),
        scrollers: [this.contentScroller],
        onMenuAction: (): void => {
          this.onHelp();
        },
        onBack: (): void => {
          this.onBack();
        }
      }) {
        SettingsPresentationScrollBody({
          desktopPresentation: this.desktopPresentation,
          contentSpace: 16,
          topPadding: 8,
          bottomPadding: 28,
          scroller: this.contentScroller
        }) {
          this.buildStatusSection()
          this.buildDeviceSection()
          this.buildCapabilitySection()
          this.buildSetupSection()
          this.buildSelfHostedSection()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildStatusSection() {
    SettingsGroupCard({
      surfaceColor: this.storedSurfaceBackgroundColor,
      desktopPresentation: this.desktopPresentation
    }) {
      Column({ space: 14 }) {
        Column({ space: 10 }) {
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(STATUS_GLYPH_SIZE)
              .height(STATUS_GLYPH_SIZE)
              .borderRadius(STATUS_GLYPH_RADIUS)
              .backgroundColor(this.settingsIconBackgrounds.sync)

            AiraIcon({
              airaIconId: CONNECTION_GLYPH,
              iconSize: STATUS_GLYPH_ICON_SIZE,
              iconColor: this.storedSettingsIconForegroundColor
            })
          }
          .width(STATUS_GLYPH_SIZE)
          .height(STATUS_GLYPH_SIZE)

          Text(this.state.connectionTitle)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.storedPrimaryTextColor)
            .textAlign(TextAlign.Center)

          Text(this.state.connectionMessage)
            .fontSize(13.5)
            .lineHeight(19)
            .fontColor(this.storedSecondaryTextColor)
            .textAlign(TextAlign.Center)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        if (this.state.providerNotice.length > 0) {
          Text(this.state.providerNotice)
            .width('100%')
            .fontSize(13)
            .lineHeight(19)
            .fontColor(this.storedSecondaryTextColor)
            .textAlign(TextAlign.Center)
        }

        if (this.state.primaryActionVisible) {
          SettingsActionButton({
            title: this.state.primaryActionLabel,
            variant: 'filled',
            isEnabled: !this.isBusy && !this.isAddingDevice,
            accentColor: this.storedAccentColor,
            pressedBackgroundColor: this.storedPressedBackgroundColor,
            onAction: (): void => {
              this.onAction(this.state.primaryAction);
            }
          })

          if (this.state.primaryActionHint.length > 0) {
            Text(this.state.primaryActionHint)
              .width('100%')
              .fontSize(13)
              .lineHeight(19)
              .fontColor(this.storedSecondaryTextColor)
              .textAlign(TextAlign.Center)
          }
        }
      }
      .width('100%')
      .padding({
        left: STATUS_PANEL_HORIZONTAL_PADDING,
        right: STATUS_PANEL_HORIZONTAL_PADDING,
        top: STATUS_PANEL_VERTICAL_PADDING,
        bottom: STATUS_PANEL_VERTICAL_PADDING
      })
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  private buildCapabilitySection() {
    SettingsSection({ title: '可以做什么', secondaryTextColor: this.storedSecondaryTextColor }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        ForEach(this.state.capabilities, (row: CrossDeviceLinkCapabilityRowState, index: number) => {
          if (index > 0) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
          SettingsNavigationRow({
            title: row.title,
            value: row.statusLabel,
            airaIconId: this.resolveCapabilityIcon(row.id),
            iconBackgroundColor: this.resolveCapabilityIconBackground(row.id),
            iconColor: this.storedSettingsIconForegroundColor,
            rowPosition: this.resolveRowPosition(index, this.state.capabilities.length),
            isEnabled: row.available && !this.isBusy,
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            pressedBackgroundColor: this.storedPressedBackgroundColor,
            desktopPresentation: this.desktopPresentation,
            onAction: (): void => {
              this.onAction(row.action);
            }
          })
        }, (row: CrossDeviceLinkCapabilityRowState): string => row.id)
      }

      this.buildSectionFooter(this.state.capabilitiesFooter)
    }
  }

  @Builder
  private buildDeviceSection() {
    SettingsSection({ title: '在线设备', secondaryTextColor: this.storedSecondaryTextColor }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        if (this.state.devices.length === 0) {
          this.buildPlaceholderDeviceRow()
        } else {
          ForEach(this.state.devices, (row: CrossDeviceLinkDeviceRowState, index: number) => {
            if (index > 0) {
              SettingsGroupDivider({ dividerColor: this.storedDividerColor })
            }
            SettingsNavigationRow({
              title: row.title,
              description: row.subtitle,
              airaIconId: DEVICE_GLYPH,
              iconBackgroundColor: this.settingsIconBackgrounds.userAgent,
              iconColor: this.storedSettingsIconForegroundColor,
              rowPosition: this.resolveRowPosition(index, this.state.devices.length),
              isEnabled: !this.isBusy,
              primaryTextColor: this.storedPrimaryTextColor,
              secondaryTextColor: this.storedSecondaryTextColor,
              pressedBackgroundColor: this.storedPressedBackgroundColor,
              desktopPresentation: this.desktopPresentation,
              onAction: (): void => {
                this.onOpenDeviceTabs(row.deviceId);
              }
            })
          }, (row: CrossDeviceLinkDeviceRowState): string => row.deviceId)
        }
      }

      this.buildSectionFooter('这里只显示当前在线或刚刚在线的电脑；电脑关机或退出浏览器后会自动消失。')
    }
  }

  /**
   * The empty list is the very same row the populated list uses, only with different
   * text, and it opens whatever fixes the empty state.
   */
  @Builder
  private buildPlaceholderDeviceRow() {
    SettingsNavigationRow({
      title: this.state.devicesPlaceholderTitle,
      description: this.state.devicesPlaceholderDetail,
      airaIconId: DEVICE_GLYPH,
      iconBackgroundColor: this.settingsIconBackgrounds.userAgent,
      iconColor: this.storedSettingsIconForegroundColor,
      rowPosition: 'single',
      isEnabled: !this.isBusy,
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      pressedBackgroundColor: this.storedPressedBackgroundColor,
      desktopPresentation: this.desktopPresentation,
      onAction: (): void => {
        this.onAction(this.state.devicesPlaceholderAction);
      }
    })
  }

  /**
   * The recipe lives one level down, so the overview stays a status page.
   */
  @Builder
  private buildSetupSection() {
    SettingsSection({ title: '安装与连接', secondaryTextColor: this.storedSecondaryTextColor }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsNavigationRow({
          title: '互联教程',
          value: '查看步骤',
          airaIconId: EXTENSION_GLYPH,
          iconBackgroundColor: this.settingsIconBackgrounds.siteCustomization,
          iconColor: this.storedSettingsIconForegroundColor,
          rowPosition: 'single',
          isEnabled: !this.isBusy,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          desktopPresentation: this.desktopPresentation,
          onAction: (): void => {
            this.onOpenSetup();
          }
        })
      }
    }
  }

  @Builder
  private buildSelfHostedSection() {
    SettingsSection({ title: this.state.selfHostedSectionTitle, secondaryTextColor: this.storedSecondaryTextColor }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsNavigationRow({
          title: this.state.selfHostedTitle,
          airaIconId: SELF_HOSTED_GLYPH,
          iconBackgroundColor: this.syncProviderIconBackgrounds.webdav,
          iconColor: this.storedSettingsIconForegroundColor,
          rowPosition: 'single',
          isEnabled: !this.isBusy,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          desktopPresentation: this.desktopPresentation,
          onAction: (): void => {
            this.onAction(this.state.selfHostedAction);
          }
        })
      }

      this.buildSectionFooter(this.state.selfHostedFooter)
    }
  }

  @Builder
  private buildSectionFooter(text: string) {
    Text(text)
      .width('100%')
      .fontSize(13)
      .lineHeight(19)
      .fontColor(this.storedSecondaryTextColor)
      .padding({ left: 4, right: 4 })
  }

  private resolveCapabilityIcon(id: string): AiraRenderableIconId {
    if (id === 'bookmark_sync') {
      return BOOKMARK_GLYPH;
    }
    if (id === 'history_sync') {
      return HISTORY_GLYPH;
    }
    if (id === 'page_push') {
      return PAGE_PUSH_GLYPH;
    }
    if (id === 'device_tabs') {
      return DEVICE_TABS_GLYPH;
    }
    return CONNECTION_GLYPH;
  }

  /**
   * 多彩图标沿用设置里那套配色 token，四种能力各取一种，和外面的设置页视觉一致。
   */
  private resolveCapabilityIconBackground(id: string): ResourceColor {
    if (id === 'bookmark_sync') {
      return this.settingsIconBackgrounds.webpageTranslation;
    }
    if (id === 'history_sync') {
      return this.settingsIconBackgrounds.siteSettings;
    }
    if (id === 'page_push') {
      return this.settingsIconBackgrounds.sync;
    }
    if (id === 'device_tabs') {
      return this.settingsIconBackgrounds.privacySecurity;
    }
    return this.settingsIconBackgrounds.general;
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
}
