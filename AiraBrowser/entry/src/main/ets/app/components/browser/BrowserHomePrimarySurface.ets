import {
  BrowserHomePagePresentationState
} from '../../../core/browser/BrowserHomePresentationViewModel';
import {
  HOME_CONTENT_SNAPSHOT_ID,
  HOME_SURFACE_SNAPSHOT_ID
} from './BrowserShellPresentationTokens';

/**
 * Presentation owner for the native Home surface frame.
 *
 * The page supplies live Home content while this component owns the visual
 * transforms, hit testing, background, and snapshot boundaries.
 *
 * Layout note: the surface background is painted by a layer that is *outside* the
 * startup entrance's opacity, and only the content above it fades in. A cold start
 * on a third-party homepage waits for the document to commit before playing that
 * entrance, and while it waits the entrance sits at `opacity: 0`. When the
 * background rode along with it, that wait showed the window colour underneath — a
 * blank frame between the splash and the homepage. Painting the background
 * unconditionally turns the same wait into a themed backdrop that the homepage then
 * fades in over, which is the intended reading of a launch.
 */
@Component
export struct BrowserHomePrimarySurface {
  @Prop presentation: BrowserHomePagePresentationState;
  @Prop surfaceBackgroundColor: ResourceColor;
  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // Themed backdrop, outside the entrance's opacity on purpose: it is the colour
      // the page fades in over, so it has to be correct and visible on frame one —
      // including while a third-party homepage is still waiting to commit.
      Stack()
        .width('100%')
        .height('100%')
        .backgroundColor(this.surfaceBackgroundColor)
      Stack({ alignContent: Alignment.Top }) {
        Stack({ alignContent: Alignment.Top }) {
          Stack({ alignContent: Alignment.Top }) {
            this.content()
          }
          .width('100%')
          .height('100%')
          .id(HOME_CONTENT_SNAPSHOT_ID)
        }
        .width('100%')
        .height('100%')
        .id(HOME_SURFACE_SNAPSHOT_ID)
        .backgroundColor(this.surfaceBackgroundColor)
        .scale({
          x: this.presentation.scale,
          y: this.presentation.scale,
          centerX: '50%',
          centerY: '50%'
        })
        .opacity(1)
        .hitTestBehavior(HitTestMode.Default)
        .zIndex(0)
      }
      .width('100%')
      .height('100%')
      .scale({
        x: this.presentation.searchBackdropScale,
        y: this.presentation.searchBackdropScale,
        centerX: '50%',
        centerY: '50%'
      })
      .blur(0)
      .opacity(this.presentation.opacity)
      .hitTestBehavior(this.presentation.hitTestEnabled ? HitTestMode.Default : HitTestMode.None)
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private emptyBuilder() {
  }
}
