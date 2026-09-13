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

// The cover is a still frame, so until the reloaded document actually paints the
// browser is showing a picture: taps do nothing and the surface can feel frozen.
// A zoom-and-fade entrance turns that dead time into motion — the frame grows from
// smaller and fades up to full screen while the real document loads behind it — so
// the wait reads as a launch animation instead of a stall.
//
// The entrance must not outlast the load: a local homepage commits in roughly
// 300ms, so a longer entrance would hold the already-ready page back and make the
// handoff later and more noticeable. It is kept short enough that the document
// settle, not the animation, is normally the last term — the reveal then waits on
// the real page, never on decoration.
const HOME_LAUNCH_SNAPSHOT_ZOOM_INITIAL_SCALE: number = 0.8;
const HOME_LAUNCH_SNAPSHOT_ZOOM_INITIAL_OPACITY: number = 0;
const HOME_LAUNCH_SNAPSHOT_ZOOM_DURATION_MS: number = 300;
// Extra room past the entrance before the safety net fires, so a normally
// completed animation is never pre-empted by the timer.
const HOME_LAUNCH_SNAPSHOT_ZOOM_FALLBACK_SLACK_MS: number = 400;
const HOME_LAUNCH_SNAPSHOT_HOLD_MS: number = 90;
const HOME_LAUNCH_SNAPSHOT_REVEAL_DURATION_MS: number = 150;

@Component
export struct CustomHomepageSurface {
  @Prop renderer: BrowserHomeSurfaceRenderer = 'native_home';
  @Prop runtimeState: CustomHomepageRuntimeShellState;
  @Prop wallpaperState: HomeWallpaperPresentationState = DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE;
  @Prop darkModeActive: boolean = false;
  @Prop themeBackgroundColor: ResourceColor | undefined = undefined;
  @Prop privateModeVisible: boolean = false;
  @Prop @Watch('handleLaunchSnapshotUriChanged') launchSnapshotUri: string = '';
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
  @Prop @Watch('handleDocumentSettled') documentSettled: boolean = false;
  @State private launchSnapshotMounted: boolean = false;
  // Reveal opacity on the whole cover (1 -> 0 as the real page takes over) and
  // entrance opacity/scale on the image itself (0 -> 1 and 0.8 -> 1 as it fades
  // and grows into place).
  @State private launchSnapshotRevealOpacity: number = 1;
  @State private launchSnapshotEntranceScale: number = HOME_LAUNCH_SNAPSHOT_ZOOM_INITIAL_SCALE;
  @State private launchSnapshotEntranceOpacity: number = HOME_LAUNCH_SNAPSHOT_ZOOM_INITIAL_OPACITY;
  private launchSnapshotRevealRunId: number = 0;
  private launchSnapshotHoldTimer: number = -1;
  private launchSnapshotZoomTimer: number = -1;
  private launchSnapshotZoomPlaying: boolean = false;
  private launchSnapshotSettled: boolean = false;
  private launchSnapshotRevealScheduled: boolean = false;

  aboutToAppear(): void {
    this.tryMountLaunchSnapshot();
  }

  aboutToDisappear(): void {
    this.clearLaunchSnapshotHold();
    this.clearLaunchSnapshotZoom();
  }

  // The cover stands in for the reloaded document, so mount it whenever one is
  // available and the document has not settled yet — including if the URI arrives
  // a beat after the surface itself, or if the surface is torn down and rebuilt
  // mid-load (a resident re-entry). Deciding this only in `aboutToAppear` is what
  // made the cover, and therefore the flash, intermittent.
  private handleLaunchSnapshotUriChanged(): void {
    this.tryMountLaunchSnapshot();
  }

  private tryMountLaunchSnapshot(): void {
    if (this.launchSnapshotMounted ||
      this.launchSnapshotUri.trim().length <= 0 ||
      this.documentSettled) {
      return;
    }
    this.launchSnapshotMounted = true;
    this.launchSnapshotRevealOpacity = 1;
    this.launchSnapshotEntranceScale = HOME_LAUNCH_SNAPSHOT_ZOOM_INITIAL_SCALE;
    this.launchSnapshotEntranceOpacity = HOME_LAUNCH_SNAPSHOT_ZOOM_INITIAL_OPACITY;
    this.launchSnapshotZoomPlaying = false;
    this.launchSnapshotSettled = false;
    this.launchSnapshotRevealScheduled = false;
    // The entrance is driven from `onAppear`, which fires after layout — later than
    // this mount. This timer is only a safety net: if `onAppear` never ran, snap to
    // the end state so the cover is never left stuck at the smaller, transparent
    // start. It does not gate the reveal; the document does.
    this.clearLaunchSnapshotZoom();
    this.launchSnapshotZoomTimer = setTimeout((): void => {
      this.launchSnapshotZoomTimer = -1;
      if (!this.launchSnapshotZoomPlaying) {
        this.launchSnapshotEntranceScale = 1;
        this.launchSnapshotEntranceOpacity = 1;
      }
    }, HOME_LAUNCH_SNAPSHOT_ZOOM_DURATION_MS + HOME_LAUNCH_SNAPSHOT_ZOOM_FALLBACK_SLACK_MS);
  }

  // Played from `onAppear` so the first laid-out frame is still at the initial
  // scale and opacity, and the growth animates from an actually-drawn smaller,
  // transparent frame.
  private playLaunchSnapshotZoom(): void {
    if (!this.launchSnapshotMounted || this.launchSnapshotZoomPlaying) {
      return;
    }
    this.launchSnapshotZoomPlaying = true;
    // Ease-in-out: the frame starts moving gently, accelerates through the middle
    // of the growth, then settles onto full size — a launch curve rather than the
    // even, mechanical feel of a linear ease.
    animateTo({
      duration: HOME_LAUNCH_SNAPSHOT_ZOOM_DURATION_MS,
      curve: Curve.EaseInOut
    }, (): void => {
      this.launchSnapshotEntranceScale = 1;
      this.launchSnapshotEntranceOpacity = 1;
    });
  }

  private handleDocumentSettled(): void {
    if (!this.documentSettled || !this.launchSnapshotMounted) {
      return;
    }
    this.launchSnapshotSettled = true;
    this.maybeScheduleLaunchSnapshotReveal();
  }

  // The reveal is gated on the document alone: as soon as the real page has
  // actually painted, nothing may hold it back — not the entrance animation, not a
  // hold. Measured cold starts commit a local homepage in roughly 300ms, so making
  // the zoom a gate only delayed the ready page and made the handoff more visible.
  // If the document beats the entrance, the cover simply finishes fading out while
  // it is still growing; the live page takes over either way.
  private maybeScheduleLaunchSnapshotReveal(): void {
    if (!this.launchSnapshotMounted ||
      !this.launchSnapshotSettled ||
      this.launchSnapshotRevealScheduled) {
      return;
    }
    this.launchSnapshotRevealScheduled = true;
    const runId = ++this.launchSnapshotRevealRunId;
    // A short hold still covers a repaint that lands a frame after settle.
    this.clearLaunchSnapshotHold();
    this.launchSnapshotHoldTimer = setTimeout((): void => {
      this.launchSnapshotHoldTimer = -1;
      this.playLaunchSnapshotReveal(runId);
    }, HOME_LAUNCH_SNAPSHOT_HOLD_MS);
  }

  private playLaunchSnapshotReveal(runId: number): void {
    if (this.launchSnapshotRevealRunId !== runId || !this.launchSnapshotMounted) {
      return;
    }
    animateTo({
      duration: HOME_LAUNCH_SNAPSHOT_REVEAL_DURATION_MS,
      curve: Curve.EaseInOut,
      onFinish: (): void => {
        if (this.launchSnapshotRevealRunId === runId) {
          this.launchSnapshotMounted = false;
        }
      }
    }, (): void => {
      if (this.launchSnapshotRevealRunId === runId) {
        this.launchSnapshotRevealOpacity = 0;
      }
    });
  }

  private clearLaunchSnapshotHold(): void {
    if (this.launchSnapshotHoldTimer >= 0) {
      clearTimeout(this.launchSnapshotHoldTimer);
      this.launchSnapshotHoldTimer = -1;
    }
  }

  private clearLaunchSnapshotZoom(): void {
    if (this.launchSnapshotZoomTimer >= 0) {
      clearTimeout(this.launchSnapshotZoomTimer);
      this.launchSnapshotZoomTimer = -1;
    }
  }

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
      // Cold-start cover: the last committed frame for this homepage identity. It
      // sits above the staged node because that node paints its own background,
      // and it is cross-faded out only once the reloaded document has actually
      // painted (`documentSettled`), not at commit — commit can land before the
      // homepage draws itself and would otherwise reveal a blank frame. The staged
      // node is non-interactive, so the cover cannot swallow a real interaction.
      if (this.launchSnapshotMounted) {
        // The themed backplate stays full-size and fully opaque under the image, so
        // neither the fade-in nor the zoom can ever expose the bare (light) Web node
        // behind the cover. Only the image fades and scales, so the entrance grows
        // into the themed backdrop instead of revealing the still-loading page.
        Stack() {
          Image(this.launchSnapshotUri)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .interpolation(ImageInterpolation.Low)
            .scale({ x: this.launchSnapshotEntranceScale, y: this.launchSnapshotEntranceScale })
            .opacity(this.launchSnapshotEntranceOpacity)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.themeBackgroundColor)
        .opacity(this.launchSnapshotRevealOpacity)
        .hitTestBehavior(HitTestMode.None)
        .onAppear((): void => {
          this.playLaunchSnapshotZoom();
        })
      }
      if (this.runtimeState.documentSettled && this.systemEntryButtonVisible) {
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
