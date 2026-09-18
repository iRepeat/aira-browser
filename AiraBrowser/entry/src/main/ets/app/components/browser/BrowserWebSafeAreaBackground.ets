import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';

// Shared native paint for the top and bottom reservations. Only color transitions;
// the viewport owner controls geometry and scroll animation independently.
@Component
export struct BrowserWebSafeAreaBackground {
  @Prop surfaceColor: ResourceColor = DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @Prop colorTransitionDurationMs: number = 160;

  build() {
    Column() {
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.surfaceColor)
    .animation({ duration: this.colorTransitionDurationMs, curve: Curve.EaseOut })
  }
}
