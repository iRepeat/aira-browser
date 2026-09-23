import { BROWSER_THEME_STORAGE_PALETTE_ID_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import {
  buildSettingsIconHighlightColor,
  buildSettingsIconShadeColor,
  formatSettingsIconHexColor,
  parseSettingsIconHexColor,
  SettingsIconRgbColor
} from '../../../core/theme/SettingsIconGradientColors';
import { DEFAULT_BROWSER_THEME_PALETTE_ID } from '../../../features/theme/BrowserThemePalettes';

/**
 * Settings tiles are rounded rectangles. The default theme keeps the colorful
 * fill, but gives each one a shallow top-left highlight so it reads as a small
 * material instead of a flat swatch. Every other palette stays on its solid color.
 */
const SETTINGS_COLORED_ICON_CORNER_RADIUS_RATIO: number = 0.34;

@Component
export struct SettingsColoredIconBackground {
  @StorageProp(BROWSER_THEME_STORAGE_PALETTE_ID_KEY) private storedPaletteId: string =
    DEFAULT_BROWSER_THEME_PALETTE_ID;
  @Prop color: ResourceColor = '';
  @Prop iconSize: number = 34;

  build() {
    if (this.usesDefaultThemeGradient()) {
      Column()
        .width(this.iconSize)
        .height(this.iconSize)
        .borderRadius(this.resolveCornerRadius())
        .clip(true)
        .linearGradient({
          direction: GradientDirection.RightBottom,
          colors: [
            [this.resolveHighlightColor(), 0],
            [this.resolveBaseColor(), 0.5],
            [this.resolveShadeColor(), 1]
          ]
        })
    } else {
      Column()
        .width(this.iconSize)
        .height(this.iconSize)
        .borderRadius(this.resolveCornerRadius())
        .clip(true)
        .backgroundColor(this.color)
    }
  }

  private resolveCornerRadius(): number {
    return Math.round(this.iconSize * SETTINGS_COLORED_ICON_CORNER_RADIUS_RATIO);
  }

  private usesDefaultThemeGradient(): boolean {
    return this.storedPaletteId === DEFAULT_BROWSER_THEME_PALETTE_ID && this.resolveParsedColor() !== undefined;
  }

  private resolveParsedColor(): SettingsIconRgbColor | undefined {
    return parseSettingsIconHexColor(`${this.color}`);
  }

  private resolveHighlightColor(): string {
    const parsed = this.resolveParsedColor();
    return parsed === undefined ? '#FFFFFF' : buildSettingsIconHighlightColor(parsed);
  }

  private resolveBaseColor(): string {
    const parsed = this.resolveParsedColor();
    return parsed === undefined ? '#FFFFFF' : formatSettingsIconHexColor(parsed);
  }

  private resolveShadeColor(): string {
    const parsed = this.resolveParsedColor();
    return parsed === undefined ? '#FFFFFF' : buildSettingsIconShadeColor(parsed);
  }
}
