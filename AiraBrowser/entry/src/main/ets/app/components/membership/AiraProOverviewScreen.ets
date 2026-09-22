import {
  AiraProOverviewBenefitState,
  AiraProOverviewPlanState,
  AiraProOverviewReachableDeviceState,
  AiraProOverviewViewState
} from '../../../core/membership/AiraProOverviewViewModel';
import { AiraProReachableDeviceGlyph } from '../../../core/membership/AiraProBenefitCatalog';
import {
  BrowserSettingsIconBackgroundTokenSet,
  BrowserSyncProviderIconBackgroundTokenSet,
  DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS,
  DEFAULT_BROWSER_SYNC_PROVIDER_ICON_BACKGROUND_TOKENS
} from '../../../features/theme/BrowserThemePaletteModels';
import { AiraIcon } from '../common/AiraIcon';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsScrollBody
} from '../settings/SettingsLayout';

const AIRA_PRO_HERO_TITLE_FONT_SIZE: number = 30;
const AIRA_PRO_HERO_SUBTITLE_FONT_SIZE: number = 14;

const AIRA_PRO_DEVICE_CHIP_HEIGHT: number = 38;
const AIRA_PRO_DEVICE_CHIP_ICON_SIZE: number = 18;
const AIRA_PRO_DEVICE_CHIP_CORNER_RADIUS: number = 19;

const AIRA_PRO_BENEFIT_ICON_TILE_SIZE: number = 34;
const AIRA_PRO_BENEFIT_ICON_IMAGE_SIZE: number = 18;
const AIRA_PRO_BENEFIT_ROW_HORIZONTAL_PADDING: number = 14;
const AIRA_PRO_BENEFIT_ROW_VERTICAL_PADDING: number = 14;
const AIRA_PRO_BENEFIT_ROW_CORNER_RADIUS: number = 18;

const AIRA_PRO_PLAN_CARD_MIN_HEIGHT: number = 146;
const AIRA_PRO_PLAN_CARD_CORNER_RADIUS: number = 22;
const AIRA_PRO_PLAN_CARD_SELECTED_BORDER_WIDTH: number = 2;
const AIRA_PRO_PLAN_AMOUNT_FONT_SIZE: number = 28;
const AIRA_PRO_PLAN_PERIOD_FONT_SIZE: number = 13;
const AIRA_PRO_PLAN_TITLE_ROW_HEIGHT: number = 22;
const AIRA_PRO_PLAN_BADGE_RIGHT_PADDING: number = 62;

const AIRA_PRO_SUBSCRIBE_BUTTON_HEIGHT: number = 52;
const AIRA_PRO_MANAGE_BUTTON_HEIGHT: number = 48;
const AIRA_PRO_TRANSPARENT_COLOR: string = '#00000000';

@Component
export struct AiraProOverviewScreen {
  @Prop state: AiraProOverviewViewState = {
    title: 'Aira Pro',
    subtitle: '',
    benefits: [],
    reachableDevices: [],
    plans: [],
    showMembershipStatus: false,
    membershipStatusTitle: '',
    membershipStatusDetail: '',
    showManageSubscription: false,
    showPurchaseButton: true,
    complimentaryClaim: {
      entryVisible: false,
      entryTitle: '',
      title: '',
      days: 15,
      message: '',
      statusText: '',
      actionText: '',
      actionEnabled: false,
      availability: 'available'
    },
    proValue: '查看',
    proActivatedActionText: '已开通 Aira Pro',
    proLegalPromptText: '我已阅读并同意',
    proLegalAgreementTitle: '会员服务协议',
    proLegalRenewalTitle: '自动续费服务协议',
    proActionsEnabled: true,
    proSubscribeEnabled: true,
    lifetimeUpgradePrompt: {
      title: '升级长期会员',
      message: '',
      cancelLabel: '暂不升级',
      manageLabel: '前往关闭自动续费'
    }
  };
  @Prop surfaceBackground: ResourceColor = '#FFFFFF';
  @Prop controlBackground: ResourceColor = '#EEF2F7';
  @Prop accentColor: ResourceColor = '#0A59F7';
  @Prop onAccentColor: ResourceColor = '#FFFFFF';
  @Prop primaryTextColor: ResourceColor = '#111318';
  @Prop secondaryTextColor: ResourceColor = '#5F6875';
  @Prop dividerColor: ResourceColor = '#E3E8EF';
  @Prop settingsIconForeground: ResourceColor = '#FFFFFF';
  @Prop settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet =
    DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS;
  @Prop syncProviderIconBackgrounds: BrowserSyncProviderIconBackgroundTokenSet =
    DEFAULT_BROWSER_SYNC_PROVIDER_ICON_BACKGROUND_TOKENS;
  @State private selectedPlanId: string = 'one_time';
  @State private proTermsAccepted: boolean = false;
  scroller?: Scroller;
  onSubscribe?: (planId: string) => void;
  onOpenSelfHostingGuide?: () => void;
  onOpenMembershipTerms?: () => void;
  onOpenAutoRenewalNotice?: () => void;
  onManageSubscription?: () => void;
  onOpenComplimentaryClaim?: () => void;

  build() {
    SettingsScrollBody({
      contentSpace: 18,
      topPadding: 8,
      bottomPadding: 28,
      scroller: this.scroller
    }) {
      this.buildHero()
      this.buildReachableDeviceRail()
      this.buildBenefitCard()
      if (this.state.showMembershipStatus) {
        this.buildMembershipStatusCard()
      }
      this.buildSelfHostingRow()
      if (this.state.plans.length > 0) {
        Column({ space: 14 }) {
          this.buildPlanCards()
          this.buildLegalConsent()
        }
        .width('100%')
      }
      if (this.state.showPurchaseButton) {
        this.buildSubscriptionActions()
      }
    }
  }

  /**
   * The hero carries the page name and one line of positioning. The benefit list
   * below answers "what do I get", so the title does not repeat it.
   */
  @Builder
  private buildHero() {
    Column({ space: 8 }) {
      Text(this.state.title)
        .width('100%')
        .fontSize(AIRA_PRO_HERO_TITLE_FONT_SIZE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.state.subtitle.length > 0) {
        Text(this.state.subtitle)
          .width('100%')
          .fontSize(AIRA_PRO_HERO_SUBTITLE_FONT_SIZE)
          .lineHeight(20)
          .fontColor(this.secondaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding({ top: 16, bottom: 2, left: 12, right: 12 })
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * Which endpoints Pro reaches. It plays the same role as the model logos at
   * the top of a subscription page, and deliberately does not restate the
   * benefit list: the devices scroll, the capabilities live in the card.
   */
  @Builder
  private buildReachableDeviceRail() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.state.reachableDevices, (device: AiraProOverviewReachableDeviceState) => {
          this.buildReachableDeviceChip(device)
        }, (device: AiraProOverviewReachableDeviceState) => device.id)
      }
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  private buildReachableDeviceChip(device: AiraProOverviewReachableDeviceState) {
    Row({ space: 7 }) {
      if (this.isBrowserBrandDevice(device.glyph)) {
        Image(this.resolveBrowserBrandIcon(device.glyph))
          .width(AIRA_PRO_DEVICE_CHIP_ICON_SIZE)
          .height(AIRA_PRO_DEVICE_CHIP_ICON_SIZE)
          .objectFit(ImageFit.Contain)
      } else {
        AiraIcon({
          airaIconId: 'crossDeviceLink.localDevice',
          iconSize: AIRA_PRO_DEVICE_CHIP_ICON_SIZE,
          iconColor: this.accentColor
        })
      }

      Text(device.label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor)
        .maxLines(1)
    }
    .height(AIRA_PRO_DEVICE_CHIP_HEIGHT)
    .padding({ left: 12, right: 14 })
    .backgroundColor(this.surfaceBackground)
    .borderRadius(AIRA_PRO_DEVICE_CHIP_CORNER_RADIUS)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildBenefitCard() {
    SettingsGroupCard({ surfaceColor: this.surfaceBackground }) {
      ForEach(this.state.benefits, (benefit: AiraProOverviewBenefitState, index: number) => {
        this.buildBenefitRow(benefit, index)
        if (index < this.state.benefits.length - 1) {
          SettingsGroupDivider({ dividerColor: this.dividerColor })
        }
      }, (benefit: AiraProOverviewBenefitState) => benefit.id)
    }
  }

  @Builder
  private buildBenefitRow(benefit: AiraProOverviewBenefitState, index: number) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(AIRA_PRO_BENEFIT_ICON_TILE_SIZE)
          .height(AIRA_PRO_BENEFIT_ICON_TILE_SIZE)
          .fill(this.resolveBenefitIconBackgroundColor(index))

        AiraIcon({
          airaIconId: benefit.iconId,
          iconSize: AIRA_PRO_BENEFIT_ICON_IMAGE_SIZE,
          iconColor: this.settingsIconForeground
        })
      }
      .width(AIRA_PRO_BENEFIT_ICON_TILE_SIZE)
      .height(AIRA_PRO_BENEFIT_ICON_TILE_SIZE)

      Text(benefit.title)
        .layoutWeight(1)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({
      left: AIRA_PRO_BENEFIT_ROW_HORIZONTAL_PADDING,
      right: AIRA_PRO_BENEFIT_ROW_HORIZONTAL_PADDING,
      top: AIRA_PRO_BENEFIT_ROW_VERTICAL_PADDING,
      bottom: AIRA_PRO_BENEFIT_ROW_VERTICAL_PADDING
    })
    .borderRadius(AIRA_PRO_BENEFIT_ROW_CORNER_RADIUS)
    .alignItems(VerticalAlign.Center)
  }

  /**
   * Two cards, equal height. The discount badge is pinned to the card's top-right
   * corner instead of sitting in the title row's flow, so a badged card and a
   * plain one keep the same title / price / caption baseline.
   */
  @Builder
  private buildPlanCards() {
    Column({ space: 12 }) {
      ForEach(this.lifetimePlans(), (plan: AiraProOverviewPlanState) => {
        this.buildPlanCard(plan, false)
      }, (plan: AiraProOverviewPlanState) => plan.id)

      Row({ space: 12 }) {
        ForEach(this.subscriptionPlans(), (plan: AiraProOverviewPlanState) => {
          this.buildPlanCard(plan, true)
        }, (plan: AiraProOverviewPlanState) => plan.id)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildPlanCard(plan: AiraProOverviewPlanState, stretch: boolean) {
    Column({ space: 0 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Row() {
          Text(plan.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.secondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ right: plan.discountBadgeText.length > 0 ? AIRA_PRO_PLAN_BADGE_RIGHT_PADDING : 0 })
        }
        .width('100%')
        .height(AIRA_PRO_PLAN_TITLE_ROW_HEIGHT)
        .alignItems(VerticalAlign.Center)

        if (plan.discountBadgeText.length > 0) {
          Text(plan.discountBadgeText)
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.accentColor)
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .backgroundColor(this.controlBackground)
            .borderRadius(7)
            .maxLines(1)
        }
      }
      .width('100%')
      .height(AIRA_PRO_PLAN_TITLE_ROW_HEIGHT)

      // One Text with two Spans, not a Row of two Texts: only inline spans share
      // a baseline, so ¥7.89 and / 年 sit on the same line however the ratio of
      // the two font sizes changes. A Row with alignItems(Bottom) aligns the two
      // text boxes' bottoms, which is not the same thing — the smaller cadence
      // carries descender space the amount does not, so its glyphs floated up.
      Text() {
        Span(plan.amountText)
          .fontSize(AIRA_PRO_PLAN_AMOUNT_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor)

        if (plan.periodText.length > 0) {
          Span(plan.periodText.startsWith('/') ? plan.periodText : ` ${plan.periodText}`)
            .fontSize(AIRA_PRO_PLAN_PERIOD_FONT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.secondaryTextColor)
        }
      }
      .width('100%')
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ top: 10 })

      Text(plan.description)
        .width('100%')
        .fontSize(12)
        .lineHeight(17)
        .fontColor(this.secondaryTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ top: 8 })
    }
    .width(stretch ? 0 : '100%')
    .layoutWeight(stretch ? 1 : 0)
    .constraintSize({ minHeight: stretch ? AIRA_PRO_PLAN_CARD_MIN_HEIGHT : 0 })
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(this.surfaceBackground)
    .borderRadius(AIRA_PRO_PLAN_CARD_CORNER_RADIUS)
    .border(this.resolvePlanCardBorder(plan))
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .enabled(this.canSelectPlan(plan))
    .opacity(this.canSelectPlan(plan) ? 1 : 0.52)
    .onClick(() => {
      if (this.canSelectPlan(plan)) {
        this.selectedPlanId = plan.id;
      }
    })
  }

  /**
   * The free route stays on the page for every membership state. A status card
   * explains the current Pro grant; it does not replace this row.
   */
  @Builder
  private buildSelfHostingRow() {
    SettingsGroupCard({ surfaceColor: this.surfaceBackground }) {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(AIRA_PRO_BENEFIT_ICON_TILE_SIZE)
            .height(AIRA_PRO_BENEFIT_ICON_TILE_SIZE)
            .fill(this.syncProviderIconBackgrounds.webdav)

          AiraIcon({
            airaIconId: 'settings.webdav',
            iconSize: AIRA_PRO_BENEFIT_ICON_IMAGE_SIZE,
            iconColor: this.settingsIconForeground
          })
        }
        .width(AIRA_PRO_BENEFIT_ICON_TILE_SIZE)
        .height(AIRA_PRO_BENEFIT_ICON_TILE_SIZE)

        Column({ space: 2 }) {
          Text('私有化部署')
            .width('100%')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text('免费使用，查看部署教程')
            .width('100%')
            .fontSize(12)
            .lineHeight(17)
            .fontColor(this.secondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text('›')
          .fontSize(20)
          .fontColor(this.secondaryTextColor)
      }
      .width('100%')
      .padding({
        left: AIRA_PRO_BENEFIT_ROW_HORIZONTAL_PADDING,
        right: AIRA_PRO_BENEFIT_ROW_HORIZONTAL_PADDING,
        top: AIRA_PRO_BENEFIT_ROW_VERTICAL_PADDING,
        bottom: AIRA_PRO_BENEFIT_ROW_VERTICAL_PADDING
      })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.onOpenSelfHostingGuide?.();
      })
    }
  }

  /**
   * A member who already holds Pro has no plans to choose, so the same slot
   * becomes a status card with the one action that still applies.
   */
  @Builder
  private buildMembershipStatusCard() {
    Column({ space: 14 }) {
      Column({ space: 4 }) {
        Text(this.state.membershipStatusTitle)
          .width('100%')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.state.membershipStatusDetail.length > 0) {
          Text(this.state.membershipStatusDetail)
            .width('100%')
            .fontSize(13)
            .lineHeight(18)
            .fontColor(this.secondaryTextColor)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.state.showManageSubscription) {
        Button() {
          Text('管理自动续费')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor)
            .maxLines(1)
        }
        .width('100%')
        .height(AIRA_PRO_MANAGE_BUTTON_HEIGHT)
        .type(ButtonType.Normal)
        .buttonStyle(ButtonStyleMode.NORMAL)
        .backgroundColor(AIRA_PRO_TRANSPARENT_COLOR)
        .borderRadius(AIRA_PRO_MANAGE_BUTTON_HEIGHT / 2)
        .border({ width: 1.5, color: this.accentColor })
        .enabled(this.state.proActionsEnabled)
        .opacity(this.state.proActionsEnabled ? 1 : 0.52)
        .stateEffect(this.state.proActionsEnabled)
        .onClick(() => {
          if (this.state.proActionsEnabled) {
            this.onManageSubscription?.();
          }
        })
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
    .backgroundColor(this.surfaceBackground)
    .borderRadius(AIRA_PRO_PLAN_CARD_CORNER_RADIUS)
  }

  @Builder
  private buildLegalConsent() {
    Column({ space: 6 }) {
      if (this.selectedPlanRequiresConsent()) {
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Checkbox()
            .select(this.proTermsAccepted)
            .selectedColor(this.accentColor)
            .enabled(this.canUseSelectedPlan())
            .width(18)
            .height(18)
            .onChange((selected: boolean) => {
              if (this.canUseSelectedPlan()) {
                this.proTermsAccepted = selected;
              }
            })
            .margin({ right: 6, bottom: 4 })

          Text(this.state.proLegalPromptText)
            .fontSize(12)
            .lineHeight(20)
            .fontColor(this.secondaryTextColor)
            .maxLines(1)
            .onClick(() => {
              this.toggleTermsAccepted();
            })
            .margin({ right: 6, bottom: 4 })

          this.buildLegalTextLink(this.state.proLegalAgreementTitle, () => {
            this.onOpenMembershipTerms?.();
          })
          if (this.shouldShowAutoRenewalNotice()) {
            Text('、')
              .fontSize(12)
              .lineHeight(20)
              .fontColor(this.secondaryTextColor)
              .maxLines(1)
              .margin({ right: 2, bottom: 4 })
            this.buildLegalTextLink(this.state.proLegalRenewalTitle, () => {
              this.onOpenAutoRenewalNotice?.();
            })
          }
        }
        .width('100%')
      }

      Text(this.resolveSubscriptionFooterText())
        .width('100%')
        .fontSize(11)
        .lineHeight(16)
        .fontColor(this.secondaryTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 6, right: 6 })
  }

  @Builder
  private buildLegalTextLink(label: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.accentColor)
        .lineHeight(20)
        .maxLines(2)
    }
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .padding(0)
    .margin({ right: 6, bottom: 4 })
    .enabled(this.canOpenLegal())
    .stateEffect(this.canOpenLegal())
    .onClick(action)
  }

  @Builder
  private buildSubscriptionActions() {
    Column({ space: 10 }) {
      Button() {
        Text(this.resolveSubscribeButtonLabel())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.onAccentColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(AIRA_PRO_SUBSCRIBE_BUTTON_HEIGHT)
      .type(ButtonType.Normal)
      .buttonStyle(ButtonStyleMode.NORMAL)
      .backgroundColor(this.accentColor)
      .borderRadius(AIRA_PRO_SUBSCRIBE_BUTTON_HEIGHT / 2)
      .opacity(this.canSubscribe() ? 1 : 0.56)
      .enabled(this.canSubscribe())
      .stateEffect(this.canSubscribe())
      .onClick(() => {
        if (this.canSubscribe()) {
          const selectedPlan = this.resolveSelectedPlan();
          if (selectedPlan === undefined) {
            return;
          }
          if (selectedPlan.action === 'manage_subscription') {
            this.onManageSubscription?.();
            return;
          }
          this.onSubscribe?.(selectedPlan.id);
        }
      })

      if (this.state.complimentaryClaim.entryVisible) {
        Text(this.state.complimentaryClaim.entryTitle)
          .width('100%')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accentColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ top: 6, bottom: 2 })
          .onClick(() => {
            this.onOpenComplimentaryClaim?.();
          })
      }
    }
    .width('100%')
  }

  private resolveBenefitIconBackgroundColor(index: number): ResourceColor {
    const colors: ResourceColor[] = [
      this.settingsIconBackgrounds.sync,
      this.settingsIconBackgrounds.crossDeviceLink,
      this.settingsIconBackgrounds.bookmarks,
      this.settingsIconBackgrounds.history,
      this.settingsIconBackgrounds.siteSettings,
      this.settingsIconBackgrounds.experiments
    ];
    return colors[index % colors.length];
  }

  /**
   * Selection is the border and nothing else. The unselected state keeps the
   * same border width in a transparent colour so switching plans changes no
   * geometry — a wider selected border would otherwise nudge the card's content
   * by a pixel on every tap.
   */
  private resolvePlanCardBorder(plan: AiraProOverviewPlanState): BorderOptions {
    const selected = this.selectedPlanId === plan.id;
    return {
      width: AIRA_PRO_PLAN_CARD_SELECTED_BORDER_WIDTH,
      color: selected ? this.accentColor : AIRA_PRO_TRANSPARENT_COLOR
    };
  }

  private isBrowserBrandDevice(glyph: AiraProReachableDeviceGlyph): boolean {
    return glyph === 'chrome' || glyph === 'edge' || glyph === 'firefox';
  }

  private resolveBrowserBrandIcon(glyph: AiraProReachableDeviceGlyph): Resource {
    if (glyph === 'edge') {
      return $r('app.media.sync_browser_edge');
    }
    if (glyph === 'firefox') {
      return $r('app.media.sync_browser_firefox');
    }
    return $r('app.media.sync_browser_chrome');
  }

  private canSelectPlan(plan: AiraProOverviewPlanState): boolean {
    return this.state.proActionsEnabled && plan.action !== 'unavailable';
  }

  private canUseSelectedPlan(): boolean {
    const selectedPlan = this.resolveSelectedPlan();
    return selectedPlan !== undefined && this.canSelectPlan(selectedPlan);
  }

  private canSubscribe(): boolean {
    const selectedPlan = this.resolveSelectedPlan();
    if (selectedPlan === undefined || !this.canSelectPlan(selectedPlan)) {
      return false;
    }
    return selectedPlan.action !== 'purchase' || this.proTermsAccepted;
  }

  private canOpenLegal(): boolean {
    return true;
  }

  private toggleTermsAccepted(): void {
    if (!this.canUseSelectedPlan() || !this.selectedPlanRequiresConsent()) {
      return;
    }
    this.proTermsAccepted = !this.proTermsAccepted;
  }

  private resolveSubscribeButtonLabel(): string {
    if (!this.state.proActionsEnabled) {
      return '当前会话不可订阅';
    }
    if (!this.state.proSubscribeEnabled) {
      return this.state.proActivatedActionText;
    }
    const selectedPlan = this.resolveSelectedPlan();
    if (selectedPlan?.action === 'purchase' && !this.proTermsAccepted) {
      return selectedPlan?.consentActionText ?? '同意协议后继续';
    }
    return selectedPlan?.actionText ?? '继续';
  }

  private resolveSubscriptionFooterText(): string {
    if (!this.state.proActionsEnabled) {
      return '当前为私密会话，请在普通会话中订阅或恢复购买。';
    }
    if (!this.state.proSubscribeEnabled) {
      return this.state.proValue;
    }
    return this.resolveSelectedPlan()?.footerText ?? '';
  }

  private shouldShowAutoRenewalNotice(): boolean {
    return this.resolveSelectedPlan()?.purchaseKind === 'subscription';
  }

  private selectedPlanRequiresConsent(): boolean {
    return this.resolveSelectedPlan()?.action === 'purchase';
  }

  private lifetimePlans(): AiraProOverviewPlanState[] {
    return this.state.plans.filter((plan: AiraProOverviewPlanState) => plan.purchaseKind === 'one_time');
  }

  private subscriptionPlans(): AiraProOverviewPlanState[] {
    return this.state.plans.filter((plan: AiraProOverviewPlanState) => plan.purchaseKind !== 'one_time');
  }

  private resolveSelectedPlan(): AiraProOverviewPlanState | undefined {
    const selected = this.state.plans.find((plan: AiraProOverviewPlanState) => plan.id === this.selectedPlanId);
    if (selected !== undefined) {
      return selected;
    }
    return this.state.plans.length > 0 ? this.state.plans[0] : undefined;
  }
}
