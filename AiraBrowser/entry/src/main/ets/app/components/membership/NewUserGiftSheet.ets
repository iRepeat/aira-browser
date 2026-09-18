import {
  createHiddenNewUserGiftSnapshot,
  NewUserGiftAction,
  NewUserGiftSnapshot
} from '../../../core/membership/NewUserGiftCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraIcon } from '../common/AiraIcon';
import {
  BrowserBottomSheetSurface,
  BrowserSheetActionButton
} from '../browser/BrowserModalBottomSheet';

const NEW_USER_GIFT_ICON_SIZE: number = 72;
const NEW_USER_GIFT_ICON_GLYPH_SIZE: number = 34;

@Component
export struct NewUserGiftSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: NewUserGiftSnapshot = createHiddenNewUserGiftSnapshot();
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onAction: (action: NewUserGiftAction) => void = (_action: NewUserGiftAction) => {};

  build() {
    BrowserBottomSheetSurface({
      presentation: this.layoutMode === 'large_screen' ? 'flat_content' : 'bottom_sheet'
    }) {
      Column({ space: 18 }) {
        Column({ space: 14 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle()
              .width(NEW_USER_GIFT_ICON_SIZE)
              .height(NEW_USER_GIFT_ICON_SIZE)
              .fill(this.storedControlBackgroundColor)

            AiraIcon({
              airaIconId: 'membership.gift',
              iconSize: NEW_USER_GIFT_ICON_GLYPH_SIZE,
              iconColor: this.storedAccentColor
            })
          }
          .width(NEW_USER_GIFT_ICON_SIZE)
          .height(NEW_USER_GIFT_ICON_SIZE)

          if (this.layoutMode === 'phone') {
            Text(this.state.title)
              .width('100%')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.storedPrimaryTextColor)
              .textAlign(TextAlign.Center)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          Text(this.state.message)
            .width('100%')
            .fontSize(15)
            .lineHeight(22)
            .fontColor(this.storedSecondaryTextColor)
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
            accentColor: this.storedAccentColor,
            onAction: () => {
              this.onAction('dismiss');
            }
          })
        }
        .width('100%')
      }
      .width('100%')
    }
  }
}
