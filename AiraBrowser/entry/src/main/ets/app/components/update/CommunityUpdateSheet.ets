import {
  createIdleCommunityUpdateSnapshot,
  CommunityUpdateAction,
  CommunityUpdateCheckSnapshot
} from '../../../core/update/CommunityUpdateCheckCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BrowserBottomSheetSurface,
  BrowserSheetActionButton
} from '../browser/BrowserModalBottomSheet';

const COMMUNITY_UPDATE_CARD_RADIUS: number = 24;
const COMMUNITY_UPDATE_CARD_PADDING: number = 18;
const COMMUNITY_UPDATE_TITLE_FONT_SIZE: number = 22;
const COMMUNITY_UPDATE_MESSAGE_FONT_SIZE: number = 15;
// The changelog is one block: the release summary and its bullets share one
// inset surface instead of reading as two separate sections.
const COMMUNITY_UPDATE_CHANGELOG_RADIUS: number = 14;
const COMMUNITY_UPDATE_CHANGELOG_PADDING: number = 14;
const COMMUNITY_UPDATE_CHANGELOG_MAX_HEIGHT: number = 260;

/**
 * The Community update notice. It is presentation only: it names the newer release,
 * shows the changelog summary, and offers to open the release page where the user
 * signs and sideloads the unsigned package themselves.
 */
@Component
export struct CommunityUpdateSheet {
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: CommunityUpdateCheckSnapshot = createIdleCommunityUpdateSnapshot();
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onAction: (action: CommunityUpdateAction) => void = (_action: CommunityUpdateAction) => {};

  build() {
    BrowserBottomSheetSurface({
      presentation: 'flat_content',
      horizontalPadding: 16,
      topPadding: 0,
      bottomPadding: 16
    }) {
      Column({ space: 16 }) {
        Column({ space: 6 }) {
          Text('发现新版本')
            .width('100%')
            .fontSize(COMMUNITY_UPDATE_TITLE_FONT_SIZE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.storedPrimaryTextColor)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.buildVersionSubtitle())
            .width('100%')
            .fontSize(COMMUNITY_UPDATE_MESSAGE_FONT_SIZE)
            .lineHeight(22)
            .fontColor(this.storedAccentColor)
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        if (this.state.summary.length > 0 || this.state.items.length > 0) {
          Scroll() {
            Column({ space: 10 }) {
              if (this.state.summary.length > 0) {
                Text(this.state.summary)
                  .width('100%')
                  .fontSize(COMMUNITY_UPDATE_MESSAGE_FONT_SIZE)
                  .lineHeight(22)
                  .fontColor(this.storedPrimaryTextColor)
                  .textAlign(TextAlign.Start)
              }

              ForEach(this.state.items, (item: string) => {
                Row({ space: 8 }) {
                  Text('•')
                    .fontSize(14)
                    .fontColor(this.storedAccentColor)
                    .lineHeight(21)

                  Text(item)
                    .fontSize(14)
                    .fontColor(this.storedSecondaryTextColor)
                    .lineHeight(21)
                    .layoutWeight(1)
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
              }, (item: string) => item)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .constraintSize({ maxHeight: COMMUNITY_UPDATE_CHANGELOG_MAX_HEIGHT })
          .padding(COMMUNITY_UPDATE_CHANGELOG_PADDING)
          .backgroundColor(this.storedControlBackgroundColor)
          .borderRadius(COMMUNITY_UPDATE_CHANGELOG_RADIUS)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        }

        Column({ space: 10 }) {
          Row() {
            BrowserSheetActionButton({
              label: '前往下载',
              emphasis: 'primary',
              accentColor: this.storedAccentColor,
              onAction: () => {
                this.onAction('open_release_page');
              }
            })
          }
          .width('100%')

          Row() {
            BrowserSheetActionButton({
              label: '稍后再说',
              onAction: () => {
                this.onAction('dismiss');
              }
            })
          }
          .width('100%')
        }
        .width('100%')
      }
      .width('100%')
      .padding(COMMUNITY_UPDATE_CARD_PADDING)
      .backgroundColor(this.storedFloatingSurfaceColor)
      .borderRadius(COMMUNITY_UPDATE_CARD_RADIUS)
      .clip(true)
      .alignItems(HorizontalAlign.Center)
    }
  }

  private buildVersionSubtitle(): string {
    if (this.state.currentVersionName.length > 0 && this.state.versionName.length > 0) {
      return `${this.state.currentVersionName} → ${this.state.versionName}`;
    }
    return this.state.versionName;
  }
}
