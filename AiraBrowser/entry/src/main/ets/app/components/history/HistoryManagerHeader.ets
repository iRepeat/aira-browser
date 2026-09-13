import { HistoryViewMode } from '../../../features/history/HistoryViewModel';
import { SegmentedTabOption, SegmentedTabs } from '../common/SegmentedTabs';
import {
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { HdsImmersiveMaterialSurface } from '../common/HdsImmersiveMaterialSurface';
import { isHdsMaterialAvailable } from '../common/HdsImmersiveMaterialTokens';
import { resolveFloatingGlassMaterialTintForMode } from '../common/FloatingGlassMaterialTokens';

const HISTORY_VIEW_MODE_BAR_HEIGHT: number = 36;
const HISTORY_VIEW_MODE_BAR_HORIZONTAL_PADDING: number = 16;

const HISTORY_VIEW_MODE_OPTIONS: SegmentedTabOption[] = [
  { id: 'timeline', title: '时间线' },
  { id: 'sites', title: '站点' }
];

@Component
export struct HistoryManagerHeader {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @Prop viewMode: HistoryViewMode = 'timeline';
  @State private viewModeBarWidth: number = 1;
  onChangeViewMode: (mode: HistoryViewMode) => void = (_mode: HistoryViewMode) => {};

  build() {
    Column() {
      this.buildViewModeBar()
    }
    .width('100%')
    .padding({
      left: HISTORY_VIEW_MODE_BAR_HORIZONTAL_PADDING,
      right: HISTORY_VIEW_MODE_BAR_HORIZONTAL_PADDING,
      top: 0,
      bottom: 8
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      // The HDS floating bar needs the plate's concrete width; -1 is its own guard against
      // a zero measurement, which would collapse the bar to nothing.
      this.viewModeBarWidth = Math.max(1,
        Number(newArea.width) - HISTORY_VIEW_MODE_BAR_HORIZONTAL_PADDING * 2);
    })
  }

  @Builder
  private buildViewModeBar() {
    FloatingGlassMaterialSurface({
      surfaceWidth: '100%',
      surfaceHeight: HISTORY_VIEW_MODE_BAR_HEIGHT,
      surfaceRadius: HISTORY_VIEW_MODE_BAR_HEIGHT / 2,
      tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
      fallbackColor: this.storedControlBackgroundColor,
      hostMaterialActive: this.shouldUseHdsMaterial(),
      backgroundBlurEnabled: false
    }) {
      if (this.shouldUseHdsMaterial()) {
        HdsImmersiveMaterialSurface({
          plateWidth: this.viewModeBarWidth,
          plateHeight: HISTORY_VIEW_MODE_BAR_HEIGHT,
          plateRadius: HISTORY_VIEW_MODE_BAR_HEIGHT / 2
        })
      }
      SegmentedTabs({
        options: HISTORY_VIEW_MODE_OPTIONS,
        selectedId: this.viewMode,
        barHeight: HISTORY_VIEW_MODE_BAR_HEIGHT,
        itemHeight: HISTORY_VIEW_MODE_BAR_HEIGHT - 6,
        fontSize: 14,
        barPadding: 3,
        fallbackColor: $r('sys.color.ohos_id_color_background_transparent'),
        barMaterialEnabled: false,
        onSelect: (id: string) => {
          this.onChangeViewMode(id as HistoryViewMode);
        }
      })
        .width('100%')
        .height(HISTORY_VIEW_MODE_BAR_HEIGHT)
    }
  }

  /**
   * Resolves whether the immersive light-sense material can be drawn on this device. Kept as
   * a method so the build reads once per render instead of calling the capability probe twice.
   */
  private shouldUseHdsMaterial(): boolean {
    return isHdsMaterialAvailable();
  }
}
