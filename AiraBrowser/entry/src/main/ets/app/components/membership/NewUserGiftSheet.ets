import {
  createHiddenNewUserGiftSnapshot,
  NewUserGiftAction,
  NewUserGiftSnapshot
} from '../../../core/membership/NewUserGiftCoordinator';
import {
  BrowserBottomSheetSurface,
  BrowserSheetActionButton
} from '../browser/BrowserModalBottomSheet';

// The announcement is a branded dark card, so its surface and on-surface text are
// fixed instead of themed; the action keeps the shared brand token so the button
// follows the app primary color in both light and dark mode.
const NEW_USER_GIFT_CARD_RADIUS: number = 24;
const NEW_USER_GIFT_CARD_PADDING: number = 18;
const NEW_USER_GIFT_CARD_BACKGROUND: string = '#16151A';
const NEW_USER_GIFT_CARD_TITLE_COLOR: string = '#EBEBEB';
const NEW_USER_GIFT_CARD_MESSAGE_COLOR: string = '#BEBDC2';
const NEW_USER_GIFT_ART_RADIUS: number = 14;
const NEW_USER_GIFT_ART_ASPECT_RATIO: number = 1125 / 500;
const NEW_USER_GIFT_TITLE_FONT_SIZE: number = 24;
const NEW_USER_GIFT_MESSAGE_FONT_SIZE: number = 15;

@Component
export struct NewUserGiftSheet {
  @Prop state: NewUserGiftSnapshot = createHiddenNewUserGiftSnapshot();
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onAction: (action: NewUserGiftAction) => void = (_action: NewUserGiftAction) => {};

  build() {
    BrowserBottomSheetSurface({
      presentation: 'flat_content',
      horizontalPadding: 16,
      topPadding: 0,
      bottomPadding: 16
    }) {
      Column({ space: 18 }) {
        Image($r('app.media.membership_reward_card'))
          .width('100%')
          .aspectRatio(NEW_USER_GIFT_ART_ASPECT_RATIO)
          .objectFit(ImageFit.Cover)
          .borderRadius(NEW_USER_GIFT_ART_RADIUS)
          .clip(true)

        Column({ space: 8 }) {
          Text(this.state.title)
            .width('100%')
            .fontSize(NEW_USER_GIFT_TITLE_FONT_SIZE)
            .fontWeight(FontWeight.Bold)
            .fontColor(NEW_USER_GIFT_CARD_TITLE_COLOR)
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.state.message)
            .width('100%')
            .fontSize(NEW_USER_GIFT_MESSAGE_FONT_SIZE)
            .lineHeight(22)
            .fontColor(NEW_USER_GIFT_CARD_MESSAGE_COLOR)
            .textAlign(TextAlign.Center)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        Row({ space: 12 }) {
          BrowserSheetActionButton({
            label: this.state.actionTitle,
            emphasis: 'primary',
            accentColor: $r('app.color.browser_brand_primary'),
            textColor: $r('app.color.browser_brand_on_primary'),
            onAction: () => {
              this.onAction('dismiss');
            }
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding(NEW_USER_GIFT_CARD_PADDING)
      .backgroundColor(NEW_USER_GIFT_CARD_BACKGROUND)
      .borderRadius(NEW_USER_GIFT_CARD_RADIUS)
      .clip(true)
      .alignItems(HorizontalAlign.Center)
    }
  }
}
