import {
  DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE,
  HomeWallpaperPresentationState
} from '../../../common/models/WallpaperModels';
import {
  DEFAULT_BROWSER_BACKDROP_EFFECT_STATE
} from '../../../core/browser/BrowserBackdropEffectViewModel';
import {
  BrowserHomeSurfaceContentPresentationState
} from '../../../core/browser/BrowserHomePresentationViewModel';
import {
  BrowserHomeSurfaceRenderer
} from '../../../core/browser/BrowserHomeSurfaceProfileViewModel';
import {
  CustomHomepageHostedWebNodeController
} from '../../../core/customhome/CustomHomepageHostedWebNode';
import {
  CUSTOM_HOMEPAGE_PREVIEW_TAB_ID,
  CustomHomepageSurfaceAction,
  CustomHomepageRuntimeShellState
} from '../../../core/customhome/CustomHomepageRuntimeCoordinator';
import {
  buildBrowserTabPreviewComponentSnapshotId
} from '../../../services/web/BrowserTabPreviewCaptureService';
import { BrowserWebErrorSurface } from '../browser/BrowserWebErrorSurface';
import { CustomHomepageSystemEntryButton } from '../browser/CustomHomepageSystemEntryButton';
import { HomeSystemSurface } from '../browser/HomeSystemSurface';
import { CustomHomepageUnavailableSurface } from './CustomHomepageUnavailableSurface';

// A third-party homepage has no cold-start cover. It used to be masked by a persisted
// capture of the last committed frame (zoom-and-fade in, cross-fade out once the
// document settled). That machinery is gone: measured cold starts put the document
// load at ~250 ms out of ~1.2 s, so the wait it was hiding was a few hundred
// milliseconds, and every capture, storage slot, render identity, and handoff timer
// behind it was a place to go stale, flash, or show a frame that no longer matched the
// live page. The staged node's own themed backplate now carries that gap.
@Component
export struct CustomHomepageSurface {
  @Prop renderer: BrowserHomeSurfaceRenderer = 'native_home';
  @Prop runtimeState: CustomHomepageRuntimeShellState;
  @Prop wallpaperState: HomeWallpaperPresentationState = DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE;
  @Prop darkModeActive: boolean = false;
  @Prop themeBackgroundColor: ResourceColor | undefined = undefined;
  @Prop privateModeVisible: boolean = false;
  @Prop contentPresentation: BrowserHomeSurfaceContentPresentationState;
  @Prop errorBottomInsetVp: number = 0;
  @Prop systemEntryButtonVisible: boolean = false;
  @Prop viewportWidth: number = 0;
  @Prop viewportHeight: number = 0;
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @BuilderParam systemHome: () => void = this.emptyBuilder;
  resolveHostedWebNode: () => CustomHomepageHostedWebNodeController | undefined = () => undefined;
  onAction: (action: CustomHomepageSurfaceAction) => void = (_action: CustomHomepageSurfaceAction) => {};

  build() {
    if (this.runtimeState.loadFailureState.visible) {
      this.buildLoadFailureSurface()
    } else if (this.renderer === 'web_home') {
      this.buildHostedWebSurface()
    } else if (this.renderer === 'fallback') {
      this.buildUnavailableSurface()
    } else {
      this.systemHome()
    }
  }

  @Builder
  private buildLoadFailureSurface() {
    HomeSystemSurface({
      wallpaperState: this.wallpaperState,
      darkModeActive: this.darkModeActive,
      themeBackgroundColor: this.themeBackgroundColor,
      privateModeVisible: this.privateModeVisible,
      backdropEffectState: DEFAULT_BROWSER_BACKDROP_EFFECT_STATE,
      searchFocused: false,
      contentPresentation: this.contentPresentation
    }) {
      BrowserWebErrorSurface({
        presentation: this.runtimeState.loadFailureState.presentation,
        bottomChromeInsetVp: this.errorBottomInsetVp,
        showDetails: false,
        onReload: () => this.onAction('retry'),
        onSecondaryAction: () => this.onAction('edit_homepage')
      })
        .width('100%')
        .height('100%')
    }
  }

  @Builder
  private buildUnavailableSurface() {
    HomeSystemSurface({
      wallpaperState: this.wallpaperState,
      darkModeActive: this.darkModeActive,
      themeBackgroundColor: this.themeBackgroundColor,
      privateModeVisible: this.privateModeVisible,
      backdropEffectState: DEFAULT_BROWSER_BACKDROP_EFFECT_STATE,
      searchFocused: false,
      contentPresentation: this.contentPresentation
    }) {
      CustomHomepageUnavailableSurface({
        title: this.runtimeState.presentation.unavailableTitle,
        message: this.runtimeState.presentation.unavailableMessage,
        primaryTextColor: this.primaryTextColor,
        secondaryTextColor: this.secondaryTextColor,
        onOpenSettings: () => this.onAction('open_homepage_settings')
      })
    }
  }

  @Builder
  private buildHostedWebSurface() {
    Stack({ alignContent: Alignment.Top }) {
      this.buildHostedWebNode()
      // The system entry button waits for the document to commit so it never floats over
      // a homepage that has not loaded yet.
      if (this.runtimeState.documentCommitted && this.systemEntryButtonVisible) {
        CustomHomepageSystemEntryButton({
          viewportWidth: this.viewportWidth,
          viewportHeight: this.viewportHeight,
          textColor: this.primaryTextColor,
          onOpenTabs: () => this.onAction('open_tabs'),
          onOpenBookmarks: () => this.onAction('open_bookmarks'),
          onOpenHistory: () => this.onAction('open_history'),
          onOpenSettings: () => this.onAction('open_settings_center')
        })
      }
    }
    .id(buildBrowserTabPreviewComponentSnapshotId(CUSTOM_HOMEPAGE_PREVIEW_TAB_ID))
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackgroundColor)
  }

  @Builder
  private buildHostedWebNode() {
    if (this.resolveHostedWebNode() !== undefined) {
      NodeContainer(this.resolveHostedWebNode() as CustomHomepageHostedWebNodeController)
        .id(`custom-home-hosted-node-${this.runtimeState.hostedNodeRevision}`)
        .width('100%')
        .height('100%')
        .clip(true)
        .hitTestBehavior(this.runtimeState.documentCommitted ? HitTestMode.Default : HitTestMode.None)
    }
  }

  @Builder
  private emptyBuilder() {
  }
}
