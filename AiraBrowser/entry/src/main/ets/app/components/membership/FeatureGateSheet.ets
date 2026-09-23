import {
  createHiddenFeatureGateSnapshot,
  FeatureGateAction,
  FeatureGateRenewalPlanState,
  FeatureGateRenewalState,
  FeatureGateSnapshot
} from '../../../core/membership/FeatureGateCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BrowserBottomSheetSurface,
  BrowserSheetActionButton
} from '../browser/BrowserModalBottomSheet';

const FEATURE_GATE_BENEFIT_CHECK_SIZE: number = 18;
const FEATURE_GATE_PLAN_RADIUS: number = 14;
const FEATURE_GATE_PLAN_BORDER_WIDTH: number = 1;
const FEATURE_GATE_PLAN_SELECTED_BORDER_WIDTH: number = 2;

@Component
export struct FeatureGateSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F7';
  @Prop state: FeatureGateSnapshot = createHiddenFeatureGateSnapshot();
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onAction: (action: FeatureGateAction) => void = (_action: FeatureGateAction) => {};
  onSelectPlan: (planId: string) => void = (_planId: string) => {};

  build() {
    BrowserBottomSheetSurface({
      presentation: this.layoutMode === 'large_screen' ? 'flat_content' : 'bottom_sheet'
    }) {
      Column({ space: 20 }) {
        Column({ space: 8 }) {
          if (this.layoutMode === 'phone') {
            Text(this.state.title)
              .width('100%')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.storedPrimaryTextColor)
              .textAlign(TextAlign.Center)
              .maxLines(1)
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

        // A Pro gate can complete a purchase here, so it carries the benefit
        // list and plan choice. Other gates stay a plain announcement.
        if (this.state.renewal !== undefined) {
          this.buildRenewalBody(this.state.renewal)
        }

        Row({ space: 12 }) {
          BrowserSheetActionButton({
            label: this.state.primaryActionTitle,
            emphasis: 'primary',
            accentColor: this.storedAccentColor,
            onAction: () => {
              this.onAction(this.state.primaryAction);
            }
          })

          BrowserSheetActionButton({
            label: this.state.secondaryActionTitle,
            onAction: () => {
              this.onAction(this.state.secondaryAction);
            }
          })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private buildRenewalBody(renewal: FeatureGateRenewalState) {
    Column({ space: 16 }) {
      Column({ space: 9 }) {
        ForEach(renewal.benefits, (benefit: string) => {
          Row({ space: 10 }) {
            Text('\u2713')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.storedAccentColor)
              .width(FEATURE_GATE_BENEFIT_CHECK_SIZE)

            Text(benefit)
              .layoutWeight(1)
              .fontSize(14)
              .lineHeight(20)
              .fontColor(this.storedPrimaryTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }, (benefit: string) => benefit)
      }
      .width('100%')

      // Stacked plan rows, each a full-width target: the selection is carried by
      // the border alone, so the choice stays legible without a filled surface
      // that would compete with the primary button for attention.
      Column({ space: 10 }) {
        ForEach(renewal.plans, (plan: FeatureGateRenewalPlanState) => {
          this.buildPlanOption(plan, renewal.selectedPlanId === plan.id)
        }, (plan: FeatureGateRenewalPlanState) => plan.id)
      }
      .width('100%')

      Text(renewal.agreementText)
        .width('100%')
        .fontSize(12)
        .lineHeight(17)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }

  @Builder
  private buildPlanOption(plan: FeatureGateRenewalPlanState, selected: boolean) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(plan.title)
            .fontSize(15)
            .fontWeight(selected ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (plan.badgeText.length > 0) {
            Text(plan.badgeText)
              .fontSize(11)
              .fontColor(this.storedAccentColor)
          }
        }
        .alignItems(VerticalAlign.Center)

        Text(plan.priceText)
          .fontSize(13)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(20)
          .height(20)
          .fill(selected ? this.storedAccentColor : Color.Transparent)
          .stroke(selected ? this.storedAccentColor : this.storedDividerColor)
          .strokeWidth(FEATURE_GATE_PLAN_BORDER_WIDTH)

        if (selected) {
          Text('\u2713')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
      }
      .width(20)
      .height(20)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .borderRadius(FEATURE_GATE_PLAN_RADIUS)
    .backgroundColor(this.storedControlBackgroundColor)
    .border({
      width: selected ? FEATURE_GATE_PLAN_SELECTED_BORDER_WIDTH : FEATURE_GATE_PLAN_BORDER_WIDTH,
      color: selected ? this.storedAccentColor : this.storedDividerColor
    })
    .onClick(() => {
      this.onSelectPlan(plan.id);
    })
  }
}
