import { AiraProOverviewViewState } from '../../../core/membership/AiraProOverviewViewModel';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_ON_ACCENT_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';
import {
  CENTERED_DIALOG_CORNER_RADIUS_VP,
  CENTERED_DIALOG_HORIZONTAL_MARGIN_VP,
  CENTERED_DIALOG_MAX_WIDTH_VP,
  resolveCenteredDialogSurfaceColor
} from '../common/CenteredDialogSurface';

const CLAIM_ART_ASPECT_RATIO: number = 1125 / 500;
const CLAIM_DAYS_FONT_SIZE: number = 64;
const CLAIM_DAYS_UNIT_FONT_SIZE: number = 20;

@CustomDialog
export struct AiraProComplimentaryClaimDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_ON_ACCENT_KEY) private storedOnAccentColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link state: AiraProOverviewViewState;
  onClaim: () => void = () => {};

  build() {
    Column() {
      Image($r('app.media.membership_reward_card'))
        .width('100%')
        .aspectRatio(CLAIM_ART_ASPECT_RATIO)
        .objectFit(ImageFit.Cover)
        .draggable(false)

      Column({ space: 16 }) {
        Column({ space: 0 }) {
          this.buildDaysMark()

          Text('免费领取 Aira Pro')
            .width('100%')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.storedSecondaryTextColor)
            .textAlign(TextAlign.Center)
            .margin({ top: 2 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        if (this.state.complimentaryClaim.statusText.length > 0) {
          Text(this.state.complimentaryClaim.statusText)
            .width('100%')
            .fontSize(13)
            .lineHeight(18)
            .fontColor(this.storedSecondaryTextColor)
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Column({ space: 8 }) {
          BrowserSheetActionButton({
            stacked: true,
            label: this.resolveActionText(),
            emphasis: 'primary',
            actionEnabled: this.state.complimentaryClaim.actionEnabled,
            accentColor: this.storedAccentColor,
            textColor: this.storedOnAccentColor,
            buttonHeight: 44,
            fontSize: 15,
            onAction: () => {
              if (!this.state.complimentaryClaim.actionEnabled) {
                return;
              }
              this.onClaim();
            }
          })

          BrowserSheetActionButton({
            stacked: true,
            label: '取消',
            buttonHeight: 44,
            fontSize: 15,
            onAction: () => {
              this.controller?.close();
            }
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding({
        left: 20,
        right: 20,
        top: 16,
        bottom: 16
      })
    }
    .width(`calc(100% - ${CENTERED_DIALOG_HORIZONTAL_MARGIN_VP * 2}vp)`)
    .constraintSize({ maxWidth: CENTERED_DIALOG_MAX_WIDTH_VP })
    .backgroundColor(resolveCenteredDialogSurfaceColor())
    .borderRadius(CENTERED_DIALOG_CORNER_RADIUS_VP)
    .clip(true)
  }

  @Builder
  private buildDaysMark() {
    Row() {
      Text(this.resolveDaysText())
        .fontSize(CLAIM_DAYS_FONT_SIZE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .lineHeight(CLAIM_DAYS_FONT_SIZE)

      Text('天')
        .fontSize(CLAIM_DAYS_UNIT_FONT_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .margin({ left: 2, bottom: 10 })
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Bottom)
  }

  private resolveActionText(): string {
    return this.state.complimentaryClaim.actionText.length > 0 ?
      this.state.complimentaryClaim.actionText : '领取会员';
  }

  private resolveDaysText(): string {
    const days = this.state.complimentaryClaim.days;
    return `${days > 0 ? days : 15}`;
  }
}
