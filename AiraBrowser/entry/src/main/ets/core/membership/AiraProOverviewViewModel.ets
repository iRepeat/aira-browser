import { AiraMembershipState } from '../../common/models/MembershipModels';
import {
  AIRA_PRO_ONE_TIME_PLAN,
  isAiraProLifetimeProductId,
  AIRA_PRO_SELLABLE_IAP_PLANS,
  HuaweiIapProductPlan,
  findAiraProIapPlanByProductId
} from '../../services/membership/HuaweiIapProductCatalog';
import { MembershipPresentationService } from '../../services/membership/MembershipPresentationService';
import {
  AiraProPlanPurchaseAction,
  AiraProPurchaseAvailability,
  AiraProPurchasePolicyService
} from '../../services/membership/AiraProPurchasePolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';
import {
  BrowserPrivacyEffectIntent,
  BrowserPrivacyEffectPolicyService
} from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';
import {
  AIRA_PRO_BENEFITS,
  AIRA_PRO_REACHABLE_DEVICES,
  AiraProBenefitDefinition,
  AiraProReachableDeviceDefinition,
  AiraProReachableDeviceGlyph
} from './AiraProBenefitCatalog';
import { AiraRenderableIconId } from '../resources/GeneratedAiraIconCatalog';
import {
  AIRA_PRO_COMPLIMENTARY_CLAIM_DAYS,
  AiraProComplimentaryClaimAvailability,
  AiraProComplimentaryClaimDecision,
  resolveAiraProComplimentaryClaimDecision
} from './AiraProComplimentaryClaimPolicy';
const AIRA_PRO_SUBSCRIPTION_ACTION_TEXT: string = '立即订阅';
const AIRA_PRO_SUBSCRIPTION_CONSENT_ACTION_TEXT: string = '同意协议后立即订阅';
const AIRA_PRO_SUBSCRIPTION_FOOTER_TEXT: string =
  '订阅为自动续费服务，实际扣费与取消规则以华为支付页面为准。';

export type AiraProOverviewPlanAction = AiraProPlanPurchaseAction;

export interface AiraProOverviewBenefitState {
  id: string;
  title: string;
  /**
   * The benefit's own glyph, so the page draws a colourful icon per row instead
   * of a generic check mark. The colour comes from the theme's settings icon
   * background set, keyed by the same id.
   */
  iconId: AiraRenderableIconId;
}

/** One endpoint Aira Pro reaches, rendered as a chip in the header rail. */
export interface AiraProOverviewReachableDeviceState {
  id: string;
  label: string;
  glyph: AiraProReachableDeviceGlyph;
}

export interface AiraProOverviewViewState {
  title: string;
  subtitle: string;
  benefits: AiraProOverviewBenefitState[];
  reachableDevices: AiraProOverviewReachableDeviceState[];
  plans: AiraProOverviewPlanState[];
  /** A current Pro holder sees this instead of, or above, the storefront. */
  showMembershipStatus: boolean;
  membershipStatusTitle: string;
  membershipStatusDetail: string;
  /** Only a live Huawei subscription has an auto-renewal page to open. */
  showManageSubscription: boolean;
  /** Hidden once there is nothing left to buy, including permanent membership. */
  showPurchaseButton: boolean;
  complimentaryClaim: AiraProComplimentaryClaimState;
  proValue: string;
  proActivatedActionText: string;
  proLegalPromptText: string;
  proLegalAgreementTitle: string;
  proLegalRenewalTitle: string;
  proActionsEnabled: boolean;
  proSubscribeEnabled: boolean;
  lifetimeUpgradePrompt: AiraProLifetimeUpgradePromptState;
}

export interface AiraProComplimentaryClaimState {
  entryVisible: boolean;
  entryTitle: string;
  title: string;
  /** The grant length, shown as the dialog's large numeral. */
  days: number;
  message: string;
  statusText: string;
  actionText: string;
  actionEnabled: boolean;
  availability: AiraProComplimentaryClaimAvailability;
}

export interface AiraProOverviewPlanState {
  id: string;
  purchaseKind: 'subscription' | 'one_time';
  title: string;
  priceText: string;
  /** Amount only, for the price card's large line: `¥7.89`. */
  amountText: string;
  /** Cadence only, for the price card's small suffix: `/ 年`. */
  periodText: string;
  /** Period-end discount badge; empty when the plan has no discount. */
  discountBadgeText: string;
  originalPriceText: string;
  description: string;
  badgeText: string;
  actionText: string;
  consentActionText: string;
  footerText: string;
  action: AiraProOverviewPlanAction;
}

interface AiraProMembershipPresentation {
  showMembershipStatus: boolean;
  membershipStatusTitle: string;
  membershipStatusDetail: string;
  showManageSubscription: boolean;
  showPurchaseButton: boolean;
}

export interface AiraProLifetimeUpgradePromptState {
  title: string;
  message: string;
  cancelLabel: string;
  manageLabel: string;
}

export class AiraProOverviewViewModel {
  private membershipPresentationService: MembershipPresentationService = new MembershipPresentationService();
  private purchasePolicyService: AiraProPurchasePolicyService = new AiraProPurchasePolicyService();
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService();
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  buildState(
    membershipState: AiraMembershipState,
    dataScope: string,
    privacyMode: string
  ): AiraProOverviewViewState {
    if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity()) {
      return this.buildCommunityState();
    }
    const purchaseAllowed = this.isEffectAllowed('membership_purchase', dataScope, privacyMode);
    const restoreAllowed = this.isEffectAllowed('membership_restore_purchase', dataScope, privacyMode);
    const subscriptionManagementAllowed = this.isEffectAllowed(
      'membership_subscription_management',
      dataScope,
      privacyMode
    );
    const plans: AiraProOverviewPlanState[] = this.buildVisiblePlans(
      membershipState,
      purchaseAllowed
    );
    const presentation = this.resolveMembershipPresentation(membershipState, plans, purchaseAllowed);
    const actionsEnabled = purchaseAllowed && restoreAllowed && subscriptionManagementAllowed;
    return {
      title: this.resolveHeroTitle(membershipState),
      subtitle: this.resolveHeroSubtitle(membershipState),
      benefits: this.buildBenefitStates(),
      reachableDevices: this.buildReachableDeviceStates(),
      plans: plans,
      showMembershipStatus: presentation.showMembershipStatus,
      membershipStatusTitle: presentation.membershipStatusTitle,
      membershipStatusDetail: presentation.membershipStatusDetail,
      showManageSubscription: presentation.showManageSubscription,
      showPurchaseButton: presentation.showPurchaseButton,
      complimentaryClaim: this.buildComplimentaryClaimState(
        membershipState,
        plans.length > 0 && actionsEnabled
      ),
      proValue: this.resolveProValue(membershipState),
      proActivatedActionText: this.resolveActivatedActionText(membershipState),
      proLegalPromptText: '我已阅读并同意',
      proLegalAgreementTitle: '会员服务协议',
      proLegalRenewalTitle: '自动续费服务协议',
      proActionsEnabled: actionsEnabled,
      proSubscribeEnabled: plans.some((plan: AiraProOverviewPlanState) => plan.action !== 'unavailable'),
      lifetimeUpgradePrompt: this.buildLifetimeUpgradePrompt(membershipState)
    };
  }

  private buildCommunityState(): AiraProOverviewViewState {
    return {
      title: 'Aira',
      subtitle: '本地浏览能力全部免费，无需会员或登录。',
      benefits: [
        {
          id: 'offline_page_save',
          title: '离线页面',
          iconId: 'browser.toolbar.offline'
        },
        {
          id: 'userscript_install',
          title: '用户脚本',
          iconId: 'membership.benefit.userScripts'
        },
        {
          id: 'manual_element_hide',
          title: '网页元素隐藏',
          iconId: 'browser.toolbar.manualElementHide'
        },
        {
          id: 'local_theme_and_search',
          title: '主题与搜索',
          iconId: 'membership.benefit.appearance'
        }
      ],
      plans: [],
      reachableDevices: this.buildReachableDeviceStates(),
      showMembershipStatus: false,
      membershipStatusTitle: '',
      membershipStatusDetail: '',
      showManageSubscription: false,
      showPurchaseButton: false,
      complimentaryClaim: this.buildHiddenComplimentaryClaim(),
      proValue: '本地功能已全部开启',
      proActivatedActionText: '无需会员',
      proLegalPromptText: '',
      proLegalAgreementTitle: '',
      proLegalRenewalTitle: '',
      proActionsEnabled: false,
      proSubscribeEnabled: false,
      lifetimeUpgradePrompt: {
        title: '',
        message: '',
        cancelLabel: '',
        manageLabel: ''
      }
    };
  }

  private resolveHeroTitle(state: AiraMembershipState): string {
    if (state.plan !== 'pro') {
      return 'Aira Pro';
    }
    if (this.membershipPresentationService.isLongTermMember(state) &&
      !this.membershipPresentationService.hasInsiderRecognition(state)) {
      return '永久会员已开通';
    }
    return 'Aira Pro 已开通';
  }

  private resolveHeroSubtitle(state: AiraMembershipState): string {
    if (state.plan !== 'pro') {
      return '本地功能永久免费，Pro 只用于 Aira 官方托管云服务。';
    }
    if (this.membershipPresentationService.isLongTermMember(state)) {
      if (this.membershipPresentationService.hasInsiderRecognition(state)) {
        return 'INSIDER 长期会员权益已生效。感谢你帮助测试和改进 Aira。';
      }
      return '你可以永久使用全部 Aira 官方托管云服务。';
    }
    const until = state.planExpiresAt > 0 ? this.formatDate(state.planExpiresAt) : '';
    if (this.isCurrentSubscriptionMember(state)) {
      if (state.subscriptionStatus === 'cancelled') {
        return until.length > 0 ? `自动续费已关闭，权益保留至 ${until}。` : '自动续费已关闭，当前周期结束后失效。';
      }
      const productTitle = this.resolveIapProductTitle(state.subscriptionProductId);
      const planName = productTitle.length > 0 ? productTitle : '订阅';
      return until.length > 0 ? `${planName}已生效，权益至 ${until}。` : `${planName}已生效。`;
    }
    return until.length > 0
      ? `当前会员至 ${until}，到期后可购买永久会员或订阅。`
      : '当前会员生效中，到期后可购买永久会员或订阅。';
  }

  private buildVisiblePlans(
    state: AiraMembershipState,
    purchaseAllowed: boolean
  ): AiraProOverviewPlanState[] {
    if (this.membershipPresentationService.isLongTermMember(state)) {
      return [];
    }
    const lifetimePlan = this.buildOneTimePlanState(state, purchaseAllowed);
    if (this.isCurrentSubscriptionMember(state)) {
      return [lifetimePlan];
    }
    const subscriptionPlans: AiraProOverviewPlanState[] = AIRA_PRO_SELLABLE_IAP_PLANS.map(
      (plan: HuaweiIapProductPlan) => this.buildSubscriptionPlanState(plan, state, purchaseAllowed)
    );
    return [lifetimePlan].concat(subscriptionPlans);
  }

  private resolveMembershipPresentation(
    state: AiraMembershipState,
    plans: AiraProOverviewPlanState[],
    purchaseAllowed: boolean
  ): AiraProMembershipPresentation {
    const permanent = this.membershipPresentationService.isLongTermMember(state);
    const subscription = this.isCurrentSubscriptionMember(state);
    const timed = state.plan === 'pro' && !permanent && !subscription;
    const hasPurchasablePlan = plans.some((plan: AiraProOverviewPlanState) => plan.action === 'purchase');
    return {
      showMembershipStatus: permanent || subscription || timed,
      membershipStatusTitle: this.resolveMembershipStatusTitle(state, permanent, subscription),
      membershipStatusDetail: this.resolveMembershipStatusDetail(state, permanent, subscription, timed),
      showManageSubscription: subscription,
      showPurchaseButton: hasPurchasablePlan || (!purchaseAllowed && plans.length > 0)
    };
  }

  private resolveMembershipStatusTitle(
    state: AiraMembershipState,
    permanent: boolean,
    subscription: boolean
  ): string {
    if (permanent && this.membershipPresentationService.hasInsiderRecognition(state)) {
      return 'INSIDER 长期会员';
    }
    if (permanent) {
      return '永久会员';
    }
    if (subscription) {
      const productTitle = this.resolveIapProductTitle(state.subscriptionProductId);
      return productTitle.length > 0 ? productTitle : '订阅会员';
    }
    return '会员生效中';
  }

  private resolveMembershipStatusDetail(
    state: AiraMembershipState,
    permanent: boolean,
    subscription: boolean,
    timed: boolean
  ): string {
    if (permanent) {
      return '永久有效，无需续费';
    }
    const until = state.planExpiresAt > 0 ? this.formatDate(state.planExpiresAt) : '';
    if (subscription) {
      if (state.subscriptionStatus === 'cancelled') {
        return until.length > 0 ? `已关闭自动续费 · ${until} 到期` : '已关闭自动续费';
      }
      return until.length > 0 ? `自动续费中 · ${until} 到期` : '自动续费中';
    }
    if (timed) {
      return until.length > 0 ? `至 ${until}` : '到期后可购买';
    }
    return '';
  }

  private isCurrentSubscriptionMember(state: AiraMembershipState): boolean {
    if (state.plan !== 'pro' || this.membershipPresentationService.isLongTermMember(state)) {
      return false;
    }
    return state.subscriptionStatus === 'active' ||
      state.subscriptionStatus === 'grace_period' ||
      state.subscriptionStatus === 'cancelled' ||
      state.subscriptionStatus === 'unknown';
  }

  private buildOneTimePlanState(
    state: AiraMembershipState,
    purchaseAllowed: boolean
  ): AiraProOverviewPlanState {
    const action = this.resolveOneTimePlanAction(state, this.resolvePurchaseAvailability(purchaseAllowed));
    return {
      id: AIRA_PRO_ONE_TIME_PLAN.planId,
      purchaseKind: 'one_time',
      title: AIRA_PRO_ONE_TIME_PLAN.title,
      priceText: AIRA_PRO_ONE_TIME_PLAN.displayPrice,
      amountText: AIRA_PRO_ONE_TIME_PLAN.amountText,
      periodText: AIRA_PRO_ONE_TIME_PLAN.periodText,
      discountBadgeText: '',
      originalPriceText: '',
      description: this.buildOneTimePlanDescription(state),
      badgeText: AIRA_PRO_ONE_TIME_PLAN.badgeText,
      actionText: action === 'manage_subscription'
        ? '前往关闭自动续费'
        : `${AIRA_PRO_ONE_TIME_PLAN.displayPrice} 立即购买`,
      consentActionText: action === 'manage_subscription' ? '前往关闭自动续费' : '同意协议后立即购买',
      footerText: this.buildOneTimePlanFooter(state),
      action: action
    };
  }

  private buildBenefitStates(): AiraProOverviewBenefitState[] {
    return AIRA_PRO_BENEFITS.map((benefit: AiraProBenefitDefinition): AiraProOverviewBenefitState => {
      return {
        id: benefit.id,
        title: benefit.title,
        iconId: benefit.iconId
      };
    });
  }

  private buildReachableDeviceStates(): AiraProOverviewReachableDeviceState[] {
    return AIRA_PRO_REACHABLE_DEVICES.map(
      (device: AiraProReachableDeviceDefinition): AiraProOverviewReachableDeviceState => {
        return {
          id: device.id,
          label: device.label,
          glyph: device.glyph
        };
      });
  }

  private buildSubscriptionPlanState(
    plan: HuaweiIapProductPlan,
    state: AiraMembershipState,
    purchaseAllowed: boolean
  ): AiraProOverviewPlanState {
    const action = this.purchasePolicyService.resolveSubscriptionPlanAction(
      state,
      this.resolvePurchaseAvailability(purchaseAllowed)
    );
    return {
      id: plan.period,
      purchaseKind: 'subscription',
      title: plan.title,
      priceText: plan.displayPrice,
      amountText: plan.amountText,
      periodText: plan.periodText,
      discountBadgeText: plan.discountBadgeText,
      originalPriceText: '',
      description: plan.description,
      badgeText: plan.badgeText,
      actionText: AIRA_PRO_SUBSCRIPTION_ACTION_TEXT,
      consentActionText: AIRA_PRO_SUBSCRIPTION_CONSENT_ACTION_TEXT,
      footerText: AIRA_PRO_SUBSCRIPTION_FOOTER_TEXT,
      action: action
    };
  }

  private resolveOneTimePlanAction(
    state: AiraMembershipState,
    availability: AiraProPurchaseAvailability
  ): AiraProOverviewPlanAction {
    return this.purchasePolicyService.resolveOneTimePlanAction(state, availability);
  }

  private resolvePurchaseAvailability(purchaseAllowed: boolean): AiraProPurchaseAvailability {
    return purchaseAllowed ? 'available' : 'privacy_restricted';
  }

  private isEffectAllowed(intent: BrowserPrivacyEffectIntent, dataScope: string, privacyMode: string): boolean {
    if ((dataScope !== 'profile_persistent' && dataScope !== 'session_ephemeral') ||
      (privacyMode !== 'regular' && privacyMode !== 'private')) {
      return false;
    }
    const requestingBoundary = this.profileBoundaryService.buildBoundary({
      dataScope: dataScope,
      privacyMode: privacyMode
    });
    return this.privacyEffectPolicy.decide({
      intent: intent,
      requestingBoundary: requestingBoundary,
      targetScope: 'remote_account_sync_state',
      targetIsClear: true
    }).outcome === 'allow';
  }

  private buildOneTimePlanDescription(state: AiraMembershipState): string {
    if (this.purchasePolicyService.resolveOneTimePlanAction(state) === 'manage_subscription') {
      return `升级前先关闭自动续费${this.buildCurrentPeriodSuffix(state)}`;
    }
    if (state.plan === 'pro' && state.subscriptionStatus === 'cancelled') {
      return `自动续费已关闭${this.buildCurrentPeriodSuffix(state)}`;
    }
    return AIRA_PRO_ONE_TIME_PLAN.description;
  }

  private buildOneTimePlanFooter(state: AiraMembershipState): string {
    if (this.purchasePolicyService.resolveOneTimePlanAction(state) === 'manage_subscription') {
      return '购买长期会员不会自动取消华为订阅。请先关闭自动续费，避免下个周期继续扣费。';
    }
    if (state.plan === 'pro' && state.subscriptionStatus === 'cancelled') {
      return '自动续费已关闭，可立即购买长期会员；当前订阅剩余时间不折现、不退款。';
    }
    return '一次购买，不自动续费；权益不设固定到期日。';
  }

  private buildComplimentaryClaimState(
    membershipState: AiraMembershipState,
    entryVisible: boolean
  ): AiraProComplimentaryClaimState {
    if (!entryVisible) {
      return this.buildHiddenComplimentaryClaim();
    }
    const decision: AiraProComplimentaryClaimDecision =
      resolveAiraProComplimentaryClaimDecision(membershipState, Date.now());
    return {
      entryVisible: true,
      entryTitle: '我不想订阅，免费领取会员',
      title: '免费领取会员',
      days: AIRA_PRO_COMPLIMENTARY_CLAIM_DAYS,
      message: '',
      statusText: decision.statusText,
      actionText: decision.actionText,
      actionEnabled: decision.actionEnabled,
      availability: decision.availability
    };
  }

  private buildHiddenComplimentaryClaim(): AiraProComplimentaryClaimState {
    return {
      entryVisible: false,
      entryTitle: '',
      title: '',
      days: AIRA_PRO_COMPLIMENTARY_CLAIM_DAYS,
      message: '',
      statusText: '',
      actionText: '',
      actionEnabled: false,
      availability: 'available'
    };
  }

  private buildLifetimeUpgradePrompt(state: AiraMembershipState): AiraProLifetimeUpgradePromptState {
    return {
      title: '升级长期会员',
      message: `购买长期会员不会自动取消当前华为订阅。请先关闭自动续费，避免下个周期继续扣费。取消后，当前已付款权益仍保留${this.buildCurrentPeriodPromptSuffix(state)}。`,
      cancelLabel: '暂不升级',
      manageLabel: '前往关闭自动续费'
    };
  }

  private buildCurrentPeriodSuffix(state: AiraMembershipState): string {
    return state.planExpiresAt > 0 ? ` · 权益至 ${this.formatDate(state.planExpiresAt)}` : '';
  }

  private buildCurrentPeriodPromptSuffix(state: AiraMembershipState): string {
    return state.planExpiresAt > 0 ? `至 ${this.formatDate(state.planExpiresAt)}` : '到当前周期结束';
  }

  private resolveProValue(state: AiraMembershipState): string {
    if (state.plan !== 'pro') {
      return '查看';
    }
    if (this.membershipPresentationService.isLongTermMember(state)) {
      return 'Aira 长期会员权益有效';
    }
    const productTitle = this.resolveIapProductTitle(state.subscriptionProductId);
    if (state.planExpiresAt > 0) {
      return productTitle.length > 0
        ? `${productTitle} · ${this.formatDate(state.planExpiresAt)} 到期`
        : `${this.formatDate(state.planExpiresAt)} 到期`;
    }
    return productTitle.length > 0 ? `${productTitle} · 长期有效` : '长期有效';
  }

  private resolveActivatedActionText(state: AiraMembershipState): string {
    return state.plan === 'pro'
      ? `已开通 ${this.membershipPresentationService.resolveVersionLabel(state)}`
      : '已开通 Aira Pro';
  }

  private resolveIapProductTitle(productId: string): string {
    const normalized = productId.trim();
    if (isAiraProLifetimeProductId(normalized)) {
      return AIRA_PRO_ONE_TIME_PLAN.title;
    }
    return findAiraProIapPlanByProductId(normalized)?.title ?? '';
  }

  private formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = this.padTwoDigits(date.getMonth() + 1);
    const day = this.padTwoDigits(date.getDate());
    return `${year}.${month}.${day}`;
  }

  private padTwoDigits(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}
