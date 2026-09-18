import { AiraFeatureKey } from '../../common/constants/MembershipFeatureKeys';
import {
  EntitlementDecision,
  EntitlementPrimaryAction
} from '../../common/models/MembershipModels';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { EntitlementContext } from '../../services/membership/EntitlementService';
import {
  AIRA_PRO_SELLABLE_IAP_PLANS,
  HuaweiIapProductPlan
} from '../../services/membership/HuaweiIapProductCatalog';
import { BrowserShellRouteCoordinator } from '../browser/BrowserShellRouteCoordinator';
import { BrowserTransientSurfaceCoordinator } from '../browser/BrowserTransientSurfaceCoordinator';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';
import { AIRA_PRO_BENEFITS, AiraProBenefitDefinition } from './AiraProBenefitCatalog';

export type FeatureGateAction = EntitlementPrimaryAction | 'dismiss' | 'purchase_plan';

/**
 * One purchasable option inside the renewal sheet. Prices come from the IAP
 * catalog so the sheet and the membership page can never disagree, and the id
 * is the plan id the purchase flow expects.
 */
export interface FeatureGateRenewalPlanState {
  id: string;
  title: string;
  priceText: string;
  badgeText: string;
}

/**
 * The renewal payload. Present only for a Pro gate, where the sheet can actually
 * complete a purchase; authentication and entitlement gates keep the plain
 * layout because offering a plan there would not be actionable.
 */
export interface FeatureGateRenewalState {
  benefits: string[];
  plans: FeatureGateRenewalPlanState[];
  selectedPlanId: string;
  expiredAt: number;
  agreementText: string;
  restoreLabel: string;
}

export interface FeatureGateSnapshot {
  visible: boolean;
  title: string;
  message: string;
  primaryActionTitle: string;
  secondaryActionTitle: string;
  primaryAction: FeatureGateAction;
  secondaryAction: FeatureGateAction;
  renewal?: FeatureGateRenewalState;
}

export function createHiddenFeatureGateSnapshot(): FeatureGateSnapshot {
  return {
    visible: false,
    title: '',
    message: '',
    primaryActionTitle: '',
    secondaryActionTitle: '',
    primaryAction: 'none',
    secondaryAction: 'none'
  };
}

export class FeatureGateCoordinator {
  private readonly membershipFeature: MembershipFeature;
  private readonly transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator;
  private readonly routeCoordinator: BrowserShellRouteCoordinator;
  private readonly publishSnapshotToShell: (snapshot: FeatureGateSnapshot) => void;
  private readonly revealDelayMs: number;
  private readonly dismissDurationMs: number;
  private snapshot: FeatureGateSnapshot = createHiddenFeatureGateSnapshot();
  private presentationGeneration: number = 0;

  constructor(
    membershipFeature: MembershipFeature,
    transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator,
    routeCoordinator: BrowserShellRouteCoordinator,
    publishSnapshotToShell: (snapshot: FeatureGateSnapshot) => void,
    revealDelayMs: number,
    dismissDurationMs: number
  ) {
    this.membershipFeature = membershipFeature;
    this.transientSurfaceCoordinator = transientSurfaceCoordinator;
    this.routeCoordinator = routeCoordinator;
    this.publishSnapshotToShell = publishSnapshotToShell;
    this.revealDelayMs = revealDelayMs;
    this.dismissDurationMs = dismissDurationMs;
  }

  getSnapshot(): FeatureGateSnapshot {
    return this.snapshot;
  }

  async ensureAccess(featureKey: AiraFeatureKey, context: EntitlementContext): Promise<boolean> {
    const decision = await this.evaluateAccess(featureKey, context);
    if (decision.allowed) {
      return true;
    }
    this.presentDecision(decision);
    return false;
  }

  async evaluateAccess(featureKey: AiraFeatureKey, context: EntitlementContext): Promise<EntitlementDecision> {
    return this.membershipFeature.canUse(featureKey, context);
  }

  presentDecision(decision: EntitlementDecision): void {
    if (decision.allowed) {
      this.resetPresentation();
      return;
    }
    const generation = this.presentationGeneration + 1;
    this.presentationGeneration = generation;
    this.publishSnapshot(this.buildSnapshot(decision));
    this.transientSurfaceCoordinator.present({
      id: 'feature_gate',
      revealDelayMs: this.revealDelayMs,
      dismissDurationMs: this.dismissDurationMs,
      shouldReveal: (): boolean => generation === this.presentationGeneration && this.snapshot.visible
    });
  }

  handleAction(action: FeatureGateAction): void {
    this.transientSurfaceCoordinator.dismiss('feature_gate');
    // `purchase_plan` is completed by the shell, which owns the purchase flow,
    // so this coordinator only has to close the gate for it.
    if (action === 'open_pro' || action === 'restore_purchase' || action === 'login') {
      this.routeCoordinator.openAiraProPage();
    }
  }

  handleSurfaceDismissed(): void {
    this.presentationGeneration += 1;
    this.publishSnapshot(createHiddenFeatureGateSnapshot());
  }

  private resetPresentation(): void {
    this.presentationGeneration += 1;
    this.publishSnapshot(createHiddenFeatureGateSnapshot());
    this.transientSurfaceCoordinator.reset('feature_gate');
  }

  private publishSnapshot(snapshot: FeatureGateSnapshot): void {
    this.snapshot = snapshot;
    this.publishSnapshotToShell(snapshot);
  }

  private buildSnapshot(decision: EntitlementDecision): FeatureGateSnapshot {
    const renewal = this.buildRenewalState(decision);
    // With a renewal payload the sheet can complete the purchase itself, so the
    // primary action buys the selected plan instead of navigating away.
    const primaryAction: FeatureGateAction = renewal === undefined ? decision.primaryAction : 'purchase_plan';
    return {
      visible: true,
      title: decision.title,
      message: decision.message,
      primaryActionTitle: this.resolvePrimaryActionTitle(primaryAction),
      secondaryActionTitle: '稍后',
      primaryAction: primaryAction,
      secondaryAction: 'dismiss',
      renewal: renewal
    };
  }

  /**
   * Builds the renewal payload for a Pro gate. Returns undefined for every other
   * denial so the sheet keeps its plain layout; a login or entitlement gate has
   * no plan to sell.
   */
  private buildRenewalState(decision: EntitlementDecision): FeatureGateRenewalState | undefined {
    if (decision.reason !== 'pro_required' && decision.reason !== 'pro_expired') {
      return undefined;
    }
    // Community distributions have no in-app purchase, so there is nothing this
    // sheet could sell; it falls back to navigating to the membership page.
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_iap')) {
      return undefined;
    }
    const plans: FeatureGateRenewalPlanState[] = AIRA_PRO_SELLABLE_IAP_PLANS.map(
      (plan: HuaweiIapProductPlan): FeatureGateRenewalPlanState => {
        return {
          id: plan.period,
          title: plan.title,
          priceText: plan.displayPrice,
          badgeText: plan.badgeText
        };
      }
    );
    if (plans.length === 0) {
      return undefined;
    }
    const defaultPlan = plans.find((plan: FeatureGateRenewalPlanState): boolean => plan.badgeText.length > 0) ??
      plans[0];
    return {
      benefits: AIRA_PRO_BENEFITS.map((benefit: AiraProBenefitDefinition): string => benefit.title),
      plans: plans,
      selectedPlanId: defaultPlan.id,
      expiredAt: decision.reason === 'pro_expired'
        ? this.membershipFeature.getLapsedProState().expiredAt
        : 0,
      agreementText: '点击开通即代表同意《会员服务协议》与《自动续费服务协议》',
      restoreLabel: '恢复购买'
    };
  }

  /**
   * Selects a different plan in the renewal sheet. Kept on the coordinator so
   * the selection survives the shell re-rendering the sheet.
   */
  selectRenewalPlan(planId: string): void {
    const renewal = this.snapshot.renewal;
    if (renewal === undefined || !this.snapshot.visible) {
      return;
    }
    if (renewal.selectedPlanId === planId) {
      return;
    }
    const nextSnapshot: FeatureGateSnapshot = {
      visible: this.snapshot.visible,
      title: this.snapshot.title,
      message: this.snapshot.message,
      primaryActionTitle: this.snapshot.primaryActionTitle,
      secondaryActionTitle: this.snapshot.secondaryActionTitle,
      primaryAction: this.snapshot.primaryAction,
      secondaryAction: this.snapshot.secondaryAction,
      renewal: {
        benefits: renewal.benefits,
        plans: renewal.plans,
        selectedPlanId: planId,
        expiredAt: renewal.expiredAt,
        agreementText: renewal.agreementText,
        restoreLabel: renewal.restoreLabel
      }
    };
    this.publishSnapshot(nextSnapshot);
  }

  /** The plan id the renewal sheet would purchase right now. */
  resolveSelectedRenewalPlanId(): string {
    return this.snapshot.renewal?.selectedPlanId ?? '';
  }

  /**
   * Presents the unprompted renewal reminder for an already-lapsed account.
   * Returns false when there is no lapsed period to announce, so the caller can
   * tell a real presentation from a no-op before it starts waiting for a reveal.
   *
   * This reuses the gate surface deliberately: how the user arrived at the
   * renewal sheet should not change what the sheet is.
   */
  presentRenewalReminder(): boolean {
    if (this.snapshot.visible) {
      return false;
    }
    const lapsed = this.membershipFeature.getLapsedProState();
    if (lapsed.expiredAt <= 0) {
      return false;
    }
    const decision: EntitlementDecision = {
      featureKey: 'cloud_sync',
      allowed: false,
      reason: 'pro_expired',
      title: 'Aira Pro 已过期',
      message: `你的 Aira Pro 已于 ${this.formatExpiryDate(lapsed.expiredAt)} 到期，续费后云同步等功能立即恢复。`,
      primaryAction: 'open_pro'
    };
    const generation = this.presentationGeneration + 1;
    this.presentationGeneration = generation;
    this.publishSnapshot(this.buildSnapshot(decision));
    this.transientSurfaceCoordinator.present({
      id: 'feature_gate',
      revealDelayMs: this.revealDelayMs,
      dismissDurationMs: this.dismissDurationMs,
      shouldReveal: (): boolean => generation === this.presentationGeneration && this.snapshot.visible
    });
    return true;
  }

  private formatExpiryDate(expiresAt: number): string {
    const date = new Date(expiresAt);
    const month = date.getMonth() + 1;
    const day = date.getDate();
    return `${date.getFullYear()} 年 ${month} 月 ${day} 日`;
  }

  private resolvePrimaryActionTitle(action: FeatureGateAction): string {
    if (action === 'purchase_plan') {
      return this.membershipFeature.getLapsedProState().expiredAt > 0 ? '立即续费' : '立即开通';
    }
    if (action === 'open_pro') {
      return '升级 Aira Pro';
    }
    if (action === 'restore_purchase') {
      return '恢复购买';
    }
    if (action === 'login') {
      return '登录';
    }
    return '知道了';
  }
}
