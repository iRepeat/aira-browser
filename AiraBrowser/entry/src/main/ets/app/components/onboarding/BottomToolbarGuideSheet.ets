import {
  createHiddenBottomToolbarGuideSnapshot,
  BottomToolbarGuideAction,
  BottomToolbarGuideSnapshot
} from '../../../core/onboarding/BottomToolbarGuideCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BrowserBottomSheetSurface,
  BrowserSheetActionButton
} from '../browser/BrowserModalBottomSheet';

// A floating card, so the surface and its text come from the shared theme tokens:
// white in light mode, black in dark mode, never a fixed brand color.
const BOTTOM_TOOLBAR_GUIDE_CARD_RADIUS: number = 24;
const BOTTOM_TOOLBAR_GUIDE_CARD_PADDING: number = 18;
const BOTTOM_TOOLBAR_GUIDE_ART_RADIUS: number = 14;
// A hairline only: the clip is mostly white, so without it the card edge disappears
// into a light surface. `browser_top_address_edge` is the lightest adaptive hairline
// the theme carries: 7% black in light mode, 14% white in dark mode.
const BOTTOM_TOOLBAR_GUIDE_ART_BORDER_WIDTH: number = 1;
// The clip is the bundled 720x426 recording of the toolbar being swiped away.
const BOTTOM_TOOLBAR_GUIDE_ART_ASPECT_RATIO: number = 720 / 426;
const BOTTOM_TOOLBAR_GUIDE_TITLE_FONT_SIZE: number = 22;
const BOTTOM_TOOLBAR_GUIDE_MESSAGE_FONT_SIZE: number = 15;

@Component
export struct BottomToolbarGuideSheet {
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: BottomToolbarGuideSnapshot = createHiddenBottomToolbarGuideSnapshot();
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onAction: (action: BottomToolbarGuideAction) => void = (_action: BottomToolbarGuideAction) => {};
  private readonly videoController: VideoController = new VideoController();

  build() {
    BrowserBottomSheetSurface({
      presentation: 'flat_content',
      horizontalPadding: 16,
      topPadding: 0,
      bottomPadding: 16
    }) {
      Column({ space: 18 }) {
        // The rounding, the clip, and the stroke cannot live on one node: the Video
        // paints its own square frame above that node's stroke and a clip on the same
        // node shaves the stroke at the corners. So the stroke sits on an unclipped
        // outer box, and the clip is an inset child whose radius stays concentric.
        Stack() {
          Stack() {
            // Decoration only: a one-second illustration, so it just runs forever with
            // no controls and no sound. Muted is also what lets it autoplay.
            Video({
              src: $rawfile('bottom_toolbar_guide.mp4'),
              controller: this.videoController
            })
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .muted(true)
              .controls(false)
              .loop(true)
              .autoPlay(true)
              .onPrepared((): void => {
                // Autoplay is the documented path; this keeps the loop running when the
                // platform holds the first start until the surface settles.
                this.videoController.start();
              })
          }
          .width('100%')
          .height('100%')
          .borderRadius(BOTTOM_TOOLBAR_GUIDE_ART_RADIUS - BOTTOM_TOOLBAR_GUIDE_ART_BORDER_WIDTH)
          .clip(true)
        }
        .width('100%')
        .aspectRatio(BOTTOM_TOOLBAR_GUIDE_ART_ASPECT_RATIO)
        .padding(BOTTOM_TOOLBAR_GUIDE_ART_BORDER_WIDTH)
        .borderRadius(BOTTOM_TOOLBAR_GUIDE_ART_RADIUS)
        .border({
          width: BOTTOM_TOOLBAR_GUIDE_ART_BORDER_WIDTH,
          color: $r('app.color.browser_top_address_edge')
        })

        Column({ space: 8 }) {
          Text(this.state.title)
            .width('100%')
            .fontSize(BOTTOM_TOOLBAR_GUIDE_TITLE_FONT_SIZE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.storedPrimaryTextColor)
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.state.message)
            .width('100%')
            .fontSize(BOTTOM_TOOLBAR_GUIDE_MESSAGE_FONT_SIZE)
            .lineHeight(22)
            .fontColor(this.storedSecondaryTextColor)
            .textAlign(TextAlign.Center)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        // Stacked, not side by side: the two actions are a commitment and its
        // escape hatch, so they read better as a full-width pair. Each button is
        // wrapped in a Row because the shared button sizes itself with
        // layoutWeight, which would stretch it vertically inside a Column.
        Column({ space: 10 }) {
          Row() {
            BrowserSheetActionButton({
              label: this.state.primaryActionTitle,
              emphasis: 'primary',
              accentColor: this.storedAccentColor,
              onAction: () => {
                this.onAction('acknowledge');
              }
            })
          }
          .width('100%')

          Row() {
            BrowserSheetActionButton({
              label: this.state.secondaryActionTitle,
              onAction: () => {
                this.onAction('never_show_again');
              }
            })
          }
          .width('100%')
        }
        .width('100%')
      }
      .width('100%')
      .padding(BOTTOM_TOOLBAR_GUIDE_CARD_PADDING)
      .backgroundColor(this.storedFloatingSurfaceColor)
      .borderRadius(BOTTOM_TOOLBAR_GUIDE_CARD_RADIUS)
      .clip(true)
      .alignItems(HorizontalAlign.Center)
    }
  }
}
