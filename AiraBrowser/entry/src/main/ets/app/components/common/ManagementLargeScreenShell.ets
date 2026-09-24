import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { AiraIcon } from './AiraIcon';

const MANAGEMENT_LARGE_SCREEN_SIDEBAR_WIDTH: number = 238;
const MANAGEMENT_LARGE_SCREEN_TOOLBAR_HEIGHT: number = 60;
const MANAGEMENT_LARGE_SCREEN_CONTROL_HEIGHT: number = 34;
const MANAGEMENT_LARGE_SCREEN_CONTROL_RADIUS: number = 9;
const MANAGEMENT_LARGE_SCREEN_NAV_ROW_HEIGHT: number = 34;
export const MANAGEMENT_LARGE_SCREEN_ROW_INSET: number = 14;
export const MANAGEMENT_LARGE_SCREEN_ROW_RADIUS: number = 10;
export const MANAGEMENT_LARGE_SCREEN_ROW_GAP: number = 2;

@Component
export struct ManagementLargeScreenNavSection {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = DEFAULT_THEME_PALETTE.light.textSecondary;
  @Prop title: string = '';

  build() {
    Text(this.title)
      .width('100%')
      .height(28)
      .padding({ left: 10, right: 10 })
      .fontSize(12)
      .fontColor(this.storedSecondaryTextColor)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }
}

@Component
export struct ManagementLargeScreenNavItem {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY)
  private storedPressedBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = DEFAULT_THEME_PALETTE.light.textSecondary;
  @Prop title: string = '';
  @Prop count: string = '';
  @Prop selected: boolean = false;
  @Prop iconId: AiraRenderableIconId = 'settings.general';
  @Prop showIcon: boolean = true;
  @State private hovered: boolean = false;
  onSelect: () => void = (): void => {};

  build() {
    Row({ space: 8 }) {
      if (this.showIcon) {
        AiraIcon({
          airaIconId: this.iconId,
          iconSize: 16,
          iconColor: this.storedSecondaryTextColor
        })
      }

      Text(this.title)
        .layoutWeight(1)
        .fontSize(14)
        .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)

      if (this.count.length > 0) {
        Text(this.count)
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
      }
    }
    .width('100%')
    .height(MANAGEMENT_LARGE_SCREEN_NAV_ROW_HEIGHT)
    .padding({ left: 10, right: 10 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.resolveBackground())
    .borderRadius(MANAGEMENT_LARGE_SCREEN_CONTROL_RADIUS)
    .clip(true)
    .onHover((hovered: boolean): void => {
      this.hovered = hovered;
    })
    .onClick((): void => {
      this.onSelect();
    })
  }

  private resolveBackground(): ResourceColor {
    if (this.selected || this.hovered) {
      return this.selected ? this.storedPressedBackgroundColor : this.storedControlBackgroundColor;
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }
}

@Component
export struct ManagementLargeScreenIconButton {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY)
  private storedPressedBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = DEFAULT_THEME_PALETTE.light.textPrimary;
  @Prop iconId: AiraRenderableIconId = 'settings.general';
  @Prop label: string = '';
  @Prop isEnabled: boolean = true;
  @Prop grouped: boolean = false;
  @State private hovered: boolean = false;
  onAction: () => void = (): void => {};

  build() {
    Button() {
      AiraIcon({
        airaIconId: this.iconId,
        iconSize: 16,
        iconColor: this.storedPrimaryTextColor
      })
    }
    .width(MANAGEMENT_LARGE_SCREEN_CONTROL_HEIGHT)
    .height(MANAGEMENT_LARGE_SCREEN_CONTROL_HEIGHT)
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .stateEffect(false)
    .enabled(this.isEnabled)
    .backgroundColor(this.resolveBackground())
    .borderRadius(MANAGEMENT_LARGE_SCREEN_CONTROL_RADIUS)
    .accessibilityText(this.label)
    .onHover((hovered: boolean): void => {
      this.hovered = hovered;
    })
    .onClick((): void => {
      if (this.isEnabled) {
        this.onAction();
      }
    })
  }

  private resolveBackground(): ResourceColor {
    if (this.grouped) {
      return this.hovered && this.isEnabled
        ? this.storedPressedBackgroundColor
        : $r('sys.color.ohos_id_color_background_transparent');
    }
    if (this.hovered && this.isEnabled) {
      return this.storedPressedBackgroundColor;
    }
    return this.storedControlBackgroundColor;
  }
}

@Component
export struct ManagementLargeScreenTextButton {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY)
  private storedPressedBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = DEFAULT_THEME_PALETTE.light.textPrimary;
  @Prop label: string = '';
  @Prop isEnabled: boolean = true;
  @State private hovered: boolean = false;
  onAction: () => void = (): void => {};

  build() {
    Button(this.label)
      .height(MANAGEMENT_LARGE_SCREEN_CONTROL_HEIGHT)
      .padding({ left: 12, right: 12 })
      .fontSize(13)
      .fontColor(this.storedPrimaryTextColor)
      .type(ButtonType.Normal)
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .stateEffect(false)
      .enabled(this.isEnabled)
      .backgroundColor(this.hovered && this.isEnabled
        ? this.storedPressedBackgroundColor
        : this.storedControlBackgroundColor)
      .borderRadius(MANAGEMENT_LARGE_SCREEN_CONTROL_RADIUS)
      .onHover((hovered: boolean): void => {
        this.hovered = hovered;
      })
      .onClick((): void => {
        if (this.isEnabled) {
          this.onAction();
        }
      })
  }
}

@Component
export struct ManagementLargeScreenActionGroup {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = DEFAULT_THEME_PALETTE.light.controlBackground;
  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Row({ space: 2 }) {
      this.content()
    }
    .height(MANAGEMENT_LARGE_SCREEN_CONTROL_HEIGHT)
    .padding({ left: 3, right: 3 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.storedControlBackgroundColor)
    .borderRadius(MANAGEMENT_LARGE_SCREEN_CONTROL_RADIUS)
  }

  @Builder
  private emptyBuilder() {
  }
}

@Component
export struct ManagementLargeScreenShell {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY)
  private storedAccentColor: string = DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = DEFAULT_THEME_PALETTE.light.divider;
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY)
  private storedSurfaceBackgroundColor: string = DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = DEFAULT_THEME_PALETTE.light.textSecondary;
  @Prop title: string = '';
  @Prop badge: string = '';
  @Prop searchPlaceholder: string = '';
  @Prop searchQuery: string = '';
  @Prop searchFocusKey: string = '';
  @Prop showSidebar: boolean = true;
  @Prop showSearch: boolean = true;
  @Prop contentRevision: number = 0;
  onSearchChange: (value: string) => void = (_value: string): void => {};
  @BuilderParam sidebar: () => void = this.emptyBuilder;
  @BuilderParam toolbarActions: () => void = this.emptyBuilder;
  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Row({ space: 0 }) {
      if (this.showSidebar) {
        Scroll() {
          Column({ space: 2 }) {
            this.sidebar()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ top: 14, bottom: 14, left: 12, right: 12 })
        }
        .width(MANAGEMENT_LARGE_SCREEN_SIDEBAR_WIDTH)
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .align(Alignment.TopStart)
        .backgroundColor(this.storedPageBackgroundColor)

        Divider()
          .width(1)
          .height('100%')
          .color(this.storedDividerColor)
          .vertical(true)
      }

      Column({ space: 0 }) {
        this.buildToolbar()

        Divider()
          .width('100%')
          .height(1)
          .color(this.storedDividerColor)

        Column() {
          if (this.contentRevision >= 0) {
            this.content()
          }
        }
        .layoutWeight(1)
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Start)
        .clip(true)
      }
      .layoutWeight(1)
      .height('100%')
      .backgroundColor(this.storedSurfaceBackgroundColor)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .clip(true)
  }

  @Builder
  private buildToolbar() {
    Row({ space: 8 }) {
      Text(this.title)
        .fontSize(19)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .flexShrink(1)

      if (this.badge.length > 0) {
        Text(this.badge)
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
          .flexShrink(0)
      }

      Blank()
        .layoutWeight(1)

      this.toolbarActions()

      if (this.showSearch) {
        this.buildSearchField()
      }
    }
    .width('100%')
    .height(MANAGEMENT_LARGE_SCREEN_TOOLBAR_HEIGHT)
    .padding({ left: 22, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.storedSurfaceBackgroundColor)
  }

  @Builder
  private buildSearchField() {
    Row({ space: 8 }) {
      AiraIcon({
        airaIconId: 'settings.search',
        iconSize: 15,
        iconColor: this.storedSecondaryTextColor
      })

      TextInput({ text: this.searchQuery, placeholder: this.searchPlaceholder })
        .key(this.searchFocusKey)
        .layoutWeight(1)
        .height(30)
        .fontSize(13)
        .fontColor(this.storedPrimaryTextColor)
        .placeholderColor(this.storedSecondaryTextColor)
        .placeholderFont({ size: 13 })
        .caretColor(this.storedAccentColor)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .padding({ left: 0, right: 0 })
        .onChange((value: string): void => {
          this.onSearchChange(value);
        })
    }
    .width(220)
    .height(MANAGEMENT_LARGE_SCREEN_CONTROL_HEIGHT)
    .padding({ left: 10, right: 10 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.storedControlBackgroundColor)
    .borderRadius(17)
    .flexShrink(0)
  }

  @Builder
  private emptyBuilder() {
  }
}
