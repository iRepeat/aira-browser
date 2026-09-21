import {
  BrowserBottomChromePresentation,
  BrowserBottomChromeTapIntent,
  BrowserBottomChromeTapTarget
} from '../../../core/browser/BrowserBottomChromePresentationViewModel';
import { AiraIcon } from '../common/AiraIcon';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';

/**
 * A static picture of the bottom bar for 工具栏设置.
 *
 * The settings page used to mount the real `BrowserBottomChromeRenderer` here. That renderer exists to
 * drive the *live* bar, and previewing it cost a first paint the real bar never pays: it mounts both
 * rails (the expanded clusters and the collapsed capsule, one of which a preview never shows),
 * materialises several system-material surfaces through `HdsTabs` with an adaptive `hdsMaterial`, and
 * arms every button's press animation and pan gesture. On a phone that subtree's first layout was the
 * whole stutter of opening the page — the JavaScript around it measures at under a millisecond.
 *
 * A preview only has to show *which button is where and what it does*, so it draws the same geometry
 * with flat surfaces and no gestures beyond the taps that open a button's settings. Material, the
 * second rail, and press/drag motion stay on the real bar, on the real page, where they are needed.
 *
 * Geometry comes from the same `BrowserBottomChromePresentation` the real bar renders, so the preview
 * keeps the real proportions instead of approximating them.
 */
const PREVIEW_ICON_SIZE: number = 22;
const PREVIEW_TEXT_SIZE: number = 15;
const PREVIEW_TEXT_LINE_HEIGHT: number = 20;
/**
 * The rim the real bar's material carries, at the same width the real renderer uses.
 *
 * The two entries are the same tokens the live bar's edge highlight reads, so the preview's outline
 * matches the material's instead of being a hand-picked colour that would drift from it.
 */
const PREVIEW_EDGE_HIGHLIGHT_WIDTH: number = 0.5;
const PREVIEW_LIGHT_EDGE_HIGHLIGHT_COLOR: ResourceColor = '#33000000';
const PREVIEW_DARK_EDGE_HIGHLIGHT_COLOR: ResourceColor = '#33FFFFFF';

@Component
export struct BrowserToolbarPreview {
  @Prop presentation: BrowserBottomChromePresentation;
  @Prop surfaceColor: ResourceColor = '';
  @Prop iconColor: ResourceColor = '';
  @Prop textColor: ResourceColor = '';
  @Prop viewportColor: ResourceColor = '';
  @Prop edgeHighlightColor: ResourceColor = PREVIEW_LIGHT_EDGE_HIGHLIGHT_COLOR;
  onIntent: (intent: BrowserBottomChromeTapIntent) => void = (_intent: BrowserBottomChromeTapIntent) => {};

  build() {
    Row({ space: 0 }) {
      this.buildOuterSlot('leading-outer')

      Blank()
        .width(this.presentation.frame.leadingGap)
        .height(1)
        .hitTestBehavior(HitTestMode.None)

      this.buildCenterRail()

      Blank()
        .width(this.presentation.frame.trailingGap)
        .height(1)
        .hitTestBehavior(HitTestMode.None)

      this.buildOuterSlot('trailing-outer')
    }
    .width('100%')
    .height(this.presentation.frame.centerHeight)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  /**
   * One round outer button.
   *
   * Drawn at the slot's own width, which is how the real pair shrinks before the centre cluster does
   * on a narrow window.
   */
  @Builder
  private buildOuterSlot(targetKey: string) {
    Stack({ alignContent: Alignment.Center }) {
      AiraIcon({
        airaIconId: this.resolveOuterIconId(targetKey),
        iconSize: PREVIEW_ICON_SIZE,
        iconColor: this.iconColor
      })
        .hitTestBehavior(HitTestMode.None)
    }
    .width(this.resolveOuterSize(targetKey))
    .height(this.resolveOuterSize(targetKey))
    .borderRadius(this.resolveOuterSize(targetKey) / 2)
    .backgroundColor(this.surfaceColor)
    .border({
      width: PREVIEW_EDGE_HIGHLIGHT_WIDTH,
      color: this.edgeHighlightColor
    })
    .hitTestBehavior(HitTestMode.Default)
    .onClick((): void => {
      this.emit(targetKey);
    })
  }

  @Builder
  private buildCenterRail() {
    Row({ space: 0 }) {
      this.buildSlot('center-leading', this.presentation.centerLeadingIconId,
        this.presentation.frame.centerLeadingWidth)
      this.buildViewport()
      this.buildSlot('center-primary', this.presentation.centerPrimaryIconId,
        this.presentation.frame.centerPrimaryWidth)
      // The accessory row is the address-focus layout: a copy and an edit button. Neither belongs to
      // the resting bar the preview shows, and both are laid out at zero width there, so building them
      // would put two extra icons on the capsule that the real bar never draws at rest.
    }
    .width(this.presentation.frame.centerWidth)
    .height(this.presentation.frame.centerHeight)
    .borderRadius(this.presentation.frame.centerRadius)
    .backgroundColor(this.surfaceColor)
    .border({
      width: PREVIEW_EDGE_HIGHLIGHT_WIDTH,
      color: this.edgeHighlightColor
    })
    .padding({
      left: this.presentation.frame.centerHorizontalPadding,
      right: this.presentation.frame.centerHorizontalPadding,
      top: this.presentation.frame.centerVerticalPadding,
      bottom: this.presentation.frame.centerVerticalPadding
    })
    .alignItems(VerticalAlign.Center)
  }

  /**
   * The middle capsule: the bar's own part, which has no configurable slot. Tapping it therefore opens
   * the middle-bar question rather than a slot's actions, exactly as the real bar's capsule does.
   */
  @Builder
  private buildViewport() {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.presentation.centerContent.displayText)
        .width(this.presentation.frame.centerViewportWidth)
        .height(PREVIEW_TEXT_LINE_HEIGHT)
        .fontSize(PREVIEW_TEXT_SIZE)
        .lineHeight(PREVIEW_TEXT_LINE_HEIGHT)
        .halfLeading(true)
        .textVerticalAlign(TextVerticalAlign.CENTER)
        .fontColor(this.textColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .hitTestBehavior(HitTestMode.None)
    }
    .width(this.presentation.frame.centerViewportWidth)
    .height(this.presentation.frame.centerViewportHeight)
    .borderRadius(this.presentation.frame.centerViewportHeight / 2)
    .backgroundColor(this.viewportColor)
    .hitTestBehavior(HitTestMode.Default)
    .onClick((): void => {
      this.emit('center-body');
    })
  }

  /**
   * One of the configurable buttons inside the centre cluster.
   *
   * They sit on the cluster's own surface rather than on a plate each, so this is an icon in a
   * tap-sized box and not a second surface.
   */
  @Builder
  private buildSlot(targetKey: string, iconId: AiraRenderableIconId, slotWidth: number) {
    Stack({ alignContent: Alignment.Center }) {
      AiraIcon({
        airaIconId: iconId,
        iconSize: PREVIEW_ICON_SIZE,
        iconColor: this.iconColor
      })
        .hitTestBehavior(HitTestMode.None)
    }
    .width(Math.max(1, slotWidth))
    .height(this.presentation.frame.centerViewportHeight)
    .hitTestBehavior(HitTestMode.Default)
    .onClick((): void => {
      this.emit(targetKey);
    })
  }

  private emit(targetKey: string): void {
    const target = this.resolveTarget(targetKey);
    if (target === undefined || !target.enabled) {
      return;
    }
    this.onIntent(target.intent);
  }

  private resolveTarget(targetKey: string): BrowserBottomChromeTapTarget | undefined {
    if (targetKey === 'leading-outer') {
      return this.presentation.leadingOuterTarget;
    }
    if (targetKey === 'trailing-outer') {
      return this.presentation.trailingOuterTarget;
    }
    if (targetKey === 'center-leading') {
      return this.presentation.centerLeadingTarget;
    }
    if (targetKey === 'center-primary') {
      return this.presentation.centerPrimaryTarget;
    }
    if (targetKey === 'center-body') {
      return this.presentation.centerBodyTarget;
    }
    return undefined;
  }

  private resolveOuterIconId(targetKey: string): AiraRenderableIconId {
    return targetKey === 'leading-outer' ?
      this.presentation.leadingOuterIconId : this.presentation.trailingOuterIconId;
  }

  /** A round button is as wide as the slot it fills, so the pair stays in step with the frame. */
  private resolveOuterSize(targetKey: string): number {
    const slotWidth = targetKey === 'leading-outer' ?
      this.presentation.frame.leadingOuterWidth : this.presentation.frame.trailingOuterWidth;
    return Math.max(PREVIEW_ICON_SIZE, slotWidth);
  }
}
