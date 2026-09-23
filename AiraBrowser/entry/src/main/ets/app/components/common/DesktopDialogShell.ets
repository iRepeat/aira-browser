import {
  DESKTOP_DIALOG_ENTER_DURATION_MS,
  DESKTOP_DIALOG_TITLE_FONT_SIZE_FP,
  DesktopDialogTier
} from '../../../core/browser/BrowserDialogPresentationTokens';
import {
  DesktopDialogLayout,
  DesktopDialogWidthViewModel
} from '../../../core/browser/DesktopDialogWidthViewModel';
import { BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import { resolveCenteredDialogSurfaceColor } from './CenteredDialogSurface';

/**
 * The only large-screen centered dialog container.
 *
 * Width, radius, padding, scrim, and Escape live here. Callers declare a tier
 * and content; they do not pass pixel widths.
 */
@Component
export struct DesktopDialogShell {
  @Prop @Watch('syncVisible') visible: boolean = false;
  @Prop tier: DesktopDialogTier = 'm';
  @Prop title: string = '';
  @Prop showHeader: boolean = false;
  @Prop dismissOnOutsideTap: boolean = true;
  @Prop fillHeight: boolean = false;
  onDismiss: () => void = () => {};
  onDidDismiss: () => void = () => {};
  @BuilderParam content: () => void = this.emptyContent;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @State private viewportWidthVp: number = 0;
  @State private viewportHeightVp: number = 0;
  @State private coverVisible: boolean = false;
  @State private presentationVisible: boolean = false;
  private revealTimer: number = -1;
  private dismissTimer: number = -1;
  private dismissRequested: boolean = false;
  private dismissCompletionPending: boolean = false;
  private readonly widthViewModel: DesktopDialogWidthViewModel = new DesktopDialogWidthViewModel();

  aboutToAppear(): void {
    this.syncVisible();
  }

  aboutToDisappear(): void {
    this.clearTimers();
  }

  build() {
    Row()
      .width(0)
      .height(0)
      .hitTestBehavior(HitTestMode.None)
      .bindContentCover($$this.coverVisible, this.buildCover(), {
        modalTransition: ModalTransition.NONE,
        backgroundColor: Color.Transparent,
        onWillDismiss: (_action: DismissContentCoverAction): void => {
          if (this.dismissOnOutsideTap) {
            this.requestDismiss();
          }
        },
        onDisappear: (): void => {
          this.handleCoverDisappear();
        }
      })
  }

  @Builder
  private buildCover() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isViewportMeasured()) {
        Stack()
          .backgroundColor($r('app.color.browser_overlay_scrim'))
          .opacity(this.presentationVisible ? 1 : 0)
          .animation({ duration: DESKTOP_DIALOG_ENTER_DURATION_MS, curve: Curve.EaseOut })
          .width('100%')
          .height('100%')
          .hitTestBehavior(this.presentationVisible ? HitTestMode.Default : HitTestMode.None)
          .onClick((): void => {
            if (this.dismissOnOutsideTap) {
              this.requestDismiss();
            }
          })

        if (this.fillHeight) {
          this.buildFilledCard()
        } else {
          this.buildHugCard()
        }
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.presentationVisible && this.isViewportMeasured()
      ? HitTestMode.Transparent
      : HitTestMode.None)
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.updateViewportSize(newArea);
    })
  }

  private resolveLayout(): DesktopDialogLayout {
    return this.widthViewModel.resolve(this.tier, this.viewportWidthVp, this.viewportHeightVp);
  }

  @Builder
  private buildCardBody() {
    if (this.showHeader && this.title.length > 0) {
      Text(this.title)
        .width('100%')
        .fontSize(DESKTOP_DIALOG_TITLE_FONT_SIZE_FP)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Start)
        .maxLines(2)
        .padding({
          left: this.resolveLayout().paddingVp,
          right: this.resolveLayout().paddingVp,
          top: this.resolveLayout().paddingVp,
          bottom: 0
        })
    }

    Column() {
      this.content()
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private buildFilledCard() {
    Column({ space: 0 }) {
      this.buildCardBody()
    }
    .backgroundColor(resolveCenteredDialogSurfaceColor())
    .borderRadius(this.resolveLayout().cornerRadiusVp)
    .clip(true)
    .shadow({ radius: 28, color: '#21101420', offsetX: 0, offsetY: 8 })
    .opacity(this.presentationVisible ? 1 : 0)
    .animation({ duration: DESKTOP_DIALOG_ENTER_DURATION_MS, curve: Curve.EaseOut })
    .width(this.resolveLayout().widthVp)
    .height(this.resolveLayout().maxHeightVp)
    .constraintSize({ maxHeight: this.resolveLayout().maxHeightVp })
    .hitTestBehavior(this.presentationVisible ? HitTestMode.BLOCK_HIERARCHY : HitTestMode.None)
    .keyboardShortcut(FunctionKey.ESC, [], (): void => {
      if (this.dismissOnOutsideTap) {
        this.requestDismiss();
      }
    })
  }

  @Builder
  private buildHugCard() {
    Column({ space: 0 }) {
      this.buildCardBody()
    }
    .backgroundColor(resolveCenteredDialogSurfaceColor())
    .borderRadius(this.resolveLayout().cornerRadiusVp)
    .clip(true)
    .shadow({ radius: 28, color: '#21101420', offsetX: 0, offsetY: 8 })
    .opacity(this.presentationVisible ? 1 : 0)
    .animation({ duration: DESKTOP_DIALOG_ENTER_DURATION_MS, curve: Curve.EaseOut })
    .width(this.resolveLayout().widthVp)
    .constraintSize({ maxHeight: this.resolveLayout().maxHeightVp })
    .hitTestBehavior(this.presentationVisible ? HitTestMode.BLOCK_HIERARCHY : HitTestMode.None)
    .keyboardShortcut(FunctionKey.ESC, [], (): void => {
      if (this.dismissOnOutsideTap) {
        this.requestDismiss();
      }
    })
  }

  private isViewportMeasured(): boolean {
    return Number.isFinite(this.viewportWidthVp) && this.viewportWidthVp > 0 &&
      Number.isFinite(this.viewportHeightVp) && this.viewportHeightVp > 0;
  }

  private syncVisible(): void {
    this.clearTimers();
    if (!this.visible) {
      this.dismissRequested = false;
      this.dismissCompletionPending = this.coverVisible;
      this.hideCoverAfterTransition();
      return;
    }
    this.dismissRequested = false;
    this.dismissCompletionPending = false;
    this.coverVisible = true;
    this.presentationVisible = false;
    this.revealTimer = setTimeout((): void => {
      this.revealTimer = -1;
      if (this.visible) {
        this.presentationVisible = true;
      }
    }, 0);
  }

  private hideCoverAfterTransition(): void {
    this.presentationVisible = false;
    if (!this.coverVisible) {
      return;
    }
    this.dismissTimer = setTimeout((): void => {
      this.dismissTimer = -1;
      if (!this.visible) {
        this.coverVisible = false;
      }
    }, DESKTOP_DIALOG_ENTER_DURATION_MS);
  }

  private requestDismiss(): void {
    if (!this.visible || !this.presentationVisible || this.dismissRequested) {
      return;
    }
    this.dismissRequested = true;
    this.onDismiss();
  }

  private handleCoverDisappear(): void {
    const shouldNotifyDismissed = this.dismissCompletionPending;
    this.dismissCompletionPending = false;
    this.presentationVisible = false;
    this.viewportWidthVp = 0;
    this.viewportHeightVp = 0;
    if (shouldNotifyDismissed) {
      this.onDidDismiss();
    }
  }

  private clearTimers(): void {
    if (this.revealTimer >= 0) {
      clearTimeout(this.revealTimer);
      this.revealTimer = -1;
    }
    if (this.dismissTimer >= 0) {
      clearTimeout(this.dismissTimer);
      this.dismissTimer = -1;
    }
  }

  private updateViewportSize(area: Area): void {
    const width = Number(area.width);
    const height = Number(area.height);
    if (Number.isFinite(width) && width > 0 && width !== this.viewportWidthVp) {
      this.viewportWidthVp = width;
    }
    if (Number.isFinite(height) && height > 0 && height !== this.viewportHeightVp) {
      this.viewportHeightVp = height;
    }
  }

  @Builder
  private emptyContent() {
  }
}
