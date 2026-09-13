import { BookmarkStorageScope } from '../../../common/models/BrowserModels';
import {
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { SegmentedTabOption, SegmentedTabs } from '../common/SegmentedTabs';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { HdsImmersiveMaterialSurface } from '../common/HdsImmersiveMaterialSurface';
import { isHdsMaterialAvailable } from '../common/HdsImmersiveMaterialTokens';
import { resolveFloatingGlassMaterialTintForMode } from '../common/FloatingGlassMaterialTokens';
import {
  BOOKMARK_OTHER_ROOT_ID,
  BOOKMARK_TOOLBAR_ROOT_ID,
  PRIVATE_BOOKMARK_OTHER_ROOT_ID,
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID
} from '../../../data/repositories/BookmarkRepositoryCore';

const BOOKMARK_ROOT_TAB_BAR_HEIGHT: number = 36;
const BOOKMARK_ROOT_TAB_BAR_HORIZONTAL_PADDING: number = 16;

/** Shared root-folder tab chrome for the phone bookmark manager. */
@Component
export struct BookmarkRootTabs {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @Prop scope: BookmarkStorageScope = 'regular';
  @Prop selectedId: string = '';
  @Prop tabsTopInset: number = 0;
  @State private rootTabBarWidth: number = 1;
  onSelect: (id: string) => void = (_id: string): void => {};
  @BuilderParam content: () => void = this.emptyBuilder;
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()

      Column() {
        this.buildRootTabBar()
      }
      .width('100%')
      .padding({
        left: BOOKMARK_ROOT_TAB_BAR_HORIZONTAL_PADDING,
        right: BOOKMARK_ROOT_TAB_BAR_HORIZONTAL_PADDING,
        top: 0,
        bottom: 8
      })
      .position({ x: 0, y: this.tabsTopInset })
      .zIndex(2)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        // The HDS floating bar needs a concrete width; guard against a zero measurement,
        // which would collapse it.
        this.rootTabBarWidth = Math.max(1,
          Number(newArea.width) - BOOKMARK_ROOT_TAB_BAR_HORIZONTAL_PADDING * 2);
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildRootTabBar() {
    FloatingGlassMaterialSurface({
      surfaceWidth: '100%',
      surfaceHeight: BOOKMARK_ROOT_TAB_BAR_HEIGHT,
      surfaceRadius: BOOKMARK_ROOT_TAB_BAR_HEIGHT / 2,
      tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
      fallbackColor: this.storedControlBackgroundColor,
      hostMaterialActive: isHdsMaterialAvailable(),
      backgroundBlurEnabled: false
    }) {
      if (isHdsMaterialAvailable()) {
        HdsImmersiveMaterialSurface({
          plateWidth: this.rootTabBarWidth,
          plateHeight: BOOKMARK_ROOT_TAB_BAR_HEIGHT,
          plateRadius: BOOKMARK_ROOT_TAB_BAR_HEIGHT / 2
        })
      }
      SegmentedTabs({
        options: this.buildOptions(),
        selectedId: this.selectedId,
        barHeight: BOOKMARK_ROOT_TAB_BAR_HEIGHT,
        itemHeight: BOOKMARK_ROOT_TAB_BAR_HEIGHT - 6,
        fontSize: 14,
        barPadding: 3,
        fallbackColor: $r('sys.color.ohos_id_color_background_transparent'),
        barMaterialEnabled: false,
        onSelect: (id: string): void => {
          this.onSelect(id);
        }
      })
        .width('100%')
        .height(BOOKMARK_ROOT_TAB_BAR_HEIGHT)
    }
  }

  @Builder
  private emptyBuilder() {
    Blank();
  }

  private buildOptions(): SegmentedTabOption[] {
    return [
      {
        id: this.resolveToolbarRootId(),
        title: this.scope === 'private' ? '隐私书签栏' : '书签栏'
      },
      {
        id: this.resolveOtherRootId(),
        title: this.scope === 'private' ? '其他隐私书签' : '其他书签'
      }
    ];
  }

  private resolveToolbarRootId(): string {
    return this.scope === 'private' ? PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : BOOKMARK_TOOLBAR_ROOT_ID;
  }

  private resolveOtherRootId(): string {
    return this.scope === 'private' ? PRIVATE_BOOKMARK_OTHER_ROOT_ID : BOOKMARK_OTHER_ROOT_ID;
  }
}
