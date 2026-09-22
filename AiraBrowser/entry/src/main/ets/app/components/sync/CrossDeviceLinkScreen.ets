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
  CrossDeviceLinkActionId,
  CrossDeviceLinkDeviceRowState,
  CrossDeviceLinkViewState
} from '../../../core/sync/CrossDeviceLinkViewModel';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from '../common/AiraIcon';
import { SettingsContentKind } from '../../../core/settings/SettingsContentLayoutPolicy';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BrowserSettingsIconBackgroundTokenSet,
  BrowserSyncProviderIconBackgroundTokenSet,
  DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS,
  DEFAULT_BROWSER_SYNC_PROVIDER_ICON_BACKGROUND_TOKENS
} from '../../../features/theme/BrowserThemePaletteModels';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import {
  SettingsNavigationRow,
  SettingsRowPosition,
  SettingsStaticValueRow,
  SettingsSwitchRow
} from '../settings/SettingsRows';

const DEVICE_GLYPH: AiraRenderableIconId = 'browser.toolbar.tabs';
const ADD_DEVICE_GLYPH: AiraRenderableIconId = 'browser.toolbar.scanQr';
const EXTENSION_GLYPH: AiraRenderableIconId = 'site.setting.externalActions';
const SELF_HOSTED_GLYPH: AiraRenderableIconId = 'settings.webdav';
const LOCAL_DEVICE_GLYPH: AiraRenderableIconId = 'crossDeviceLink.localDevice';
const PEER_COMPUTER_GLYPH: AiraRenderableIconId = 'crossDeviceLink.peerComputer';
const HELP_GLYPH: AiraRenderableIconId = 'crossDeviceLink.help';

const STATUS_PANEL_HORIZONTAL_PADDING: number = 16;
const STATUS_PANEL_VERTICAL_PADDING: number = 18;

/** The header is phone → account → computer, so the avatar is the anchor in the middle. */
const HEADER_PEER_GLYPH_SIZE: number = 30;
const HEADER_GLYPH_STAGE_SIZE: number = 56;
const HEADER_AVATAR_SIZE: number = 62;
const HEADER_AVATAR_BORDER_WIDTH: number = 2;
const HEADER_AVATAR_ICON_SIZE: number = 32;
const HEADER_CONNECTOR_DOT_SIZE: number = 5;
const HEADER_CONNECTOR_DOT_SPACE: number = 6;
const CONNECTOR_DOT_INDICES: number[] = [0, 1, 2];

@Component
export struct CrossDeviceLinkScreen {
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
  @Prop isBusy: boolean = false;
  /**
   * Bumped once a switch attempt settles. A refused change leaves the authoritative boolean
   * untouched, so without this the toggle would keep the flipped look the user just gave it.
   */
  @Prop switchSettledRevision: number = 0;
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
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
  onOpenSetup: () => void = (): void => {};
  onOpenDeviceTabs: (deviceId: string) => void = (_deviceId: string): void => {};
  /** This page's own cross-device switch; it never writes data-sync state. */
  onToggleLink: (enabled: boolean) => void = (_enabled: boolean): void => {};
  onAction: (action: CrossDeviceLinkActionId) => void = (_action: CrossDeviceLinkActionId) => {};
  private contentScroller: Scroller = new Scroller();

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '跨设备互联',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        showBackButton: this.showBackButton,
        showTitleBar: this.showTitleBar,
        useTopSafeInset: this.useTopSafeInset,
        contentKind: this.contentKind,
        desktopPresentation: this.desktopPresentation,
        menuActionLabel: '帮助',
        menuActionAiraIconId: HELP_GLYPH,
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
          this.buildSyncSection()
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
        this.buildAccountHeader()

        if (this.state.providerNotice.length > 0) {
          Text(this.state.providerNotice)
            .width('100%')
            .fontSize(13)
            .lineHeight(19)
            .fontColor(this.storedSecondaryTextColor)
            .textAlign(TextAlign.Center)
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

  /**
   * The header is the account itself: this phone on the left, the account in the middle,
   * the computers on the right. The connectors light up only when a desktop is really
   * online, so the row answers "am I connected" before any row below is read.
   */
  @Builder
  private buildAccountHeader() {
    Column({ space: 0 }) {
      Row() {
        this.buildPeerGlyph(LOCAL_DEVICE_GLYPH, true)
        this.buildConnector(true)
        this.buildAccountAvatar()
        this.buildConnector(this.isComputerOnline())
        this.buildPeerGlyph(PEER_COMPUTER_GLYPH, this.isComputerOnline())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)

      Text(this.state.accountTitle)
        .width('100%')
        .margin({ top: 16 })
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.state.accountSubtitle)
        .width('100%')
        .margin({ top: 6 })
        .fontSize(13.5)
        .lineHeight(19)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildPeerGlyph(icon: AiraRenderableIconId, isOnline: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      AiraIcon({
        airaIconId: icon,
        iconSize: HEADER_PEER_GLYPH_SIZE,
        iconColor: isOnline ? this.storedPrimaryTextColor : this.storedDividerColor
      })
    }
    .width(HEADER_GLYPH_STAGE_SIZE)
    .height(HEADER_GLYPH_STAGE_SIZE)
  }

  /**
   * The connector is the visual claim that the two sides are talking; the dots and the
   * computer glyph share one state so the header never says "connected" twice differently.
   */
  @Builder
  private buildConnector(isLit: boolean) {
    Row({ space: HEADER_CONNECTOR_DOT_SPACE }) {
      ForEach(CONNECTOR_DOT_INDICES, (_index: number) => {
        Circle()
          .width(HEADER_CONNECTOR_DOT_SIZE)
          .height(HEADER_CONNECTOR_DOT_SIZE)
          .fill(isLit ? this.storedSecondaryTextColor : this.storedDividerColor)
      }, (index: number): string => `${index}`)
    }
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildAccountAvatar() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.state.accountAvatarUri.length > 0) {
        Image(this.state.accountAvatarUri)
          .width(HEADER_AVATAR_SIZE)
          .height(HEADER_AVATAR_SIZE)
          .borderRadius(HEADER_AVATAR_SIZE / 2)
          .objectFit(ImageFit.Cover)
          .clip(true)
      } else {
        SymbolGlyph($r('sys.symbol.person_fill'))
          .fontSize(HEADER_AVATAR_ICON_SIZE)
          .fontColor([
            this.state.accountSignedIn ? this.storedPrimaryTextColor : this.storedSecondaryTextColor
          ])
      }
    }
    .width(HEADER_AVATAR_SIZE)
    .height(HEADER_AVATAR_SIZE)
    .borderRadius(HEADER_AVATAR_SIZE / 2)
    .backgroundColor(this.storedPageBackgroundColor)
    .borderWidth(HEADER_AVATAR_BORDER_WIDTH)
    .borderColor(this.storedDividerColor)
    .clip(true)
  }

  private isComputerOnline(): boolean {
    return this.state.onlineComputerCount > 0;
  }

  /**
   * Two different things, deliberately kept apart: 跨设备互联 is this page's own switch (tab
   * handoff and page push), while 同步设置 only hands the user to the sync owner for data
   * sync. Pausing bookmarks and history must not break tab handoff, so this page never carries
   * a second data-sync master switch of its own.
   */
  @Builder
  private buildSyncSection() {
    SettingsSection({ title: this.state.linkSwitchTitle, secondaryTextColor: this.storedSecondaryTextColor }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        // Rebuilt from the authoritative value whenever an attempt settles, because a refused
        // change cannot move the boolean and ArkUI would not re-apply `isOn` on its own.
        ForEach([`${this.state.linkEnabled}:${this.switchSettledRevision}`], (_key: string) => {
          SettingsSwitchRow({
            title: this.state.linkSwitchTitle,
            checked: this.state.linkEnabled,
            rowPosition: 'first',
            isEnabled: this.state.linkSwitchEnabled && !this.isBusy,
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            desktopPresentation: this.desktopPresentation,
            onChange: (checked: boolean): void => {
              this.onToggleLink(checked);
            }
          })
        }, (key: string): string => key)

        SettingsGroupDivider({ dividerColor: this.storedDividerColor })

        SettingsNavigationRow({
          title: '同步设置',
          value: this.state.syncSettingsValue,
          rowPosition: 'last',
          isEnabled: !this.isBusy,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          desktopPresentation: this.desktopPresentation,
          onAction: (): void => {
            this.onAction('open_sync_settings');
          }
        })
      }

      Text(this.state.linkSwitchDescription)
        .width('100%')
        .fontSize(13)
        .lineHeight(19)
        .fontColor(this.storedSecondaryTextColor)
        .padding({ left: 6, right: 6, top: 8 })
    }
  }

  @Builder
  private buildDeviceSection() {
    SettingsSection({ title: '在线设备', secondaryTextColor: this.storedSecondaryTextColor }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        // This phone is always here, because the user is holding it while reading the row.
        SettingsStaticValueRow({
          title: this.state.localDeviceRow.title,
          value: this.state.localDeviceRow.subtitle,
          airaIconId: LOCAL_DEVICE_GLYPH,
          iconColor: this.storedSettingsIconForegroundColor,
          // Same round badge the computer rows use, so the whole list reads as one list.
          iconBackgroundColor: this.settingsIconBackgrounds.userAgent,
          rowPosition: 'first',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          desktopPresentation: this.desktopPresentation
        })

        SettingsGroupDivider({ dividerColor: this.storedDividerColor })

        if (this.state.devicesPlaceholderVisible) {
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
              rowPosition: this.resolveRowPosition(index + 1, this.state.devices.length + 2),
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

        SettingsGroupDivider({ dividerColor: this.storedDividerColor })

        // The list always ends with the way to grow it, so pairing is never hidden behind
        // an empty state that the user cannot act on.
        SettingsNavigationRow({
          title: this.state.addDeviceTitle,
          description: this.state.addDeviceDetail,
          airaIconId: ADD_DEVICE_GLYPH,
          iconBackgroundColor: this.settingsIconBackgrounds.addDevice,
          iconColor: this.storedSettingsIconForegroundColor,
          rowPosition: 'last',
          isEnabled: !this.isBusy,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          desktopPresentation: this.desktopPresentation,
          onAction: (): void => {
            this.onAction('add_device');
          }
        })
      }
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
      rowPosition: 'middle',
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
