import {
  BrowserSearchBackdropPresentation,
  BrowserSearchBackdropPresentationChannel,
  BrowserSearchBackdropPresentationListener
} from '../../../core/browser/BrowserSearchBackdropPresentationChannel';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';

@Component
export struct BrowserRootBottomPanelExpandedScrim {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @State private liveScrimOpacity: number = 0;
  @State private surfaceSuppressed: boolean = false;
  private activePresentationRunId: number = 0;
  private disconnectPresentation: () => boolean = (): boolean => false;
  private presentationListener: BrowserSearchBackdropPresentationListener =
    (presentation: BrowserSearchBackdropPresentation): void => {
      this.applyPresentation(presentation);
    };
  @Prop scrimOpacity: number = 0;
  @Prop blockHitTest: boolean = false;
  @Prop surfaceEligible: boolean = true;
  @Prop settledVisible: boolean = false;
  @Prop pageBackgroundVisible: boolean = false;
  presentationChannel?: BrowserSearchBackdropPresentationChannel = undefined;
  onDismiss: () => void = () => {};

  aboutToAppear(): void {
    if (this.presentationChannel === undefined) {
      this.liveScrimOpacity = this.resolveClampedScrimOpacity(this.scrimOpacity);
      return;
    }
    this.disconnectPresentation = this.presentationChannel.connect(this.presentationListener);
  }

  aboutToDisappear(): void {
    this.disconnectPresentation();
    this.disconnectPresentation = (): boolean => false;
  }

  build() {
    Stack() {
      if (this.shouldPaintExpandedPageBackground()) {
        // Full-screen page background for the committed search interface. It does not follow drag
        // progress: a partial page colour behind a capsule that is still moving reads as a veil.
        // Suggestion rows stay transparent and sit on this surface, so the background is the
        // screen, not a plate behind the history block.
        Stack()
          .width('100%')
          .height('100%')
          .backgroundColor(this.storedPageBackgroundColor)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(this.shouldBlockHitTest() ? '100%' : 0)
    .height(this.shouldBlockHitTest() ? '100%' : 0)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .hitTestBehavior(this.shouldBlockHitTest() ? HitTestMode.BLOCK_HIERARCHY : HitTestMode.None)
    .onClick(() => {
      this.onDismiss();
    })
  }

  private applyPresentation(presentation: BrowserSearchBackdropPresentation): void {
    this.activePresentationRunId = presentation.runId;
    this.surfaceSuppressed = presentation.surfaceSuppressed;
    if (presentation.durationMs <= 0) {
      this.liveScrimOpacity = this.resolveClampedScrimOpacity(presentation.progress);
      this.presentationChannel?.finishPresentation(presentation.runId);
      return;
    }
    animateTo({
      duration: presentation.durationMs,
      curve: presentation.curve,
      onFinish: () => {
        if (this.activePresentationRunId !== presentation.runId) {
          return;
        }
        this.presentationChannel?.finishPresentation(presentation.runId);
      }
    }, () => {
      if (this.activePresentationRunId !== presentation.runId) {
        return;
      }
      this.liveScrimOpacity = this.resolveClampedScrimOpacity(presentation.progress);
    });
  }

  private shouldMountScrimSurface(): boolean {
    return !this.surfaceSuppressed && this.surfaceEligible &&
      (this.settledVisible || this.resolveEffectiveScrimOpacity() > 0.01);
  }

  private shouldPaintExpandedPageBackground(): boolean {
    return !this.surfaceSuppressed && this.surfaceEligible && this.pageBackgroundVisible;
  }

  private shouldBlockHitTest(): boolean {
    if (this.surfaceSuppressed || !this.surfaceEligible) {
      return false;
    }
    if (this.settledVisible || this.resolveEffectiveScrimOpacity() > 0.01) {
      return true;
    }
    // The connected channel is the live animation source; parent props can lag behind its completed transition.
    return this.presentationChannel === undefined && this.blockHitTest;
  }

  private resolveEffectiveScrimOpacity(): number {
    if (this.surfaceSuppressed || !this.surfaceEligible) {
      return 0;
    }
    if (this.presentationChannel === undefined) {
      return this.resolveClampedScrimOpacity(this.scrimOpacity);
    }
    return this.resolveClampedScrimOpacity(this.liveScrimOpacity);
  }

  private resolveClampedScrimOpacity(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.min(1, value));
  }
}
