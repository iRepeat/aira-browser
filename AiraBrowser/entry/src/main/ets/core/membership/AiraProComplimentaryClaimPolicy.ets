import { AiraMembershipState } from '../../common/models/MembershipModels';
import {
  AIRA_PRO_MONTHLY_PRODUCT_ID,
  isAiraProLifetimeProductId,
  AIRA_PRO_QUARTERLY_PRODUCT_ID,
  AIRA_PRO_YEARLY_PRODUCT_ID
} from '../../services/membership/HuaweiIapProductCatalog';

export const AIRA_PRO_COMPLIMENTARY_CLAIM_DAYS: number = 15;

export type AiraProComplimentaryClaimAvailability = 'available' | 'already_member' | 'claim_active';

export interface AiraProComplimentaryClaimDecision {
  availability: AiraProComplimentaryClaimAvailability;
  actionEnabled: boolean;
  actionText: string;
  statusText: string;
}

const AIRA_PRO_COMPLIMENTARY_CLAIM_ACTION_TEXT: string = '领取会员';

/**
 * Who may open the free 15-day claim. A current Pro holder cannot claim: a
 * permanent or store subscription is already a member, and an unexpired
 * complimentary period has to run out before the same account can claim again.
 * Once that period is over, the account is no longer Pro and can claim again.
 */
export function resolveAiraProComplimentaryClaimDecision(
  membership: AiraMembershipState,
  now: number
): AiraProComplimentaryClaimDecision {
  if (isPermanentMember(membership, now)) {
    return blocked('already_member', '你已是永久会员，无法领取。');
  }
  if (isCurrentSubscriptionMember(membership, now)) {
    return blocked('already_member', '你已开通订阅会员，无法领取。');
  }
  if (membership.plan === 'pro' && membership.planExpiresAt > now) {
    return blocked(
      'claim_active',
      `当前会员至 ${formatClaimDate(membership.planExpiresAt)} 到期，到期前不能再次领取。`
    );
  }
  return {
    availability: 'available',
    actionEnabled: true,
    actionText: AIRA_PRO_COMPLIMENTARY_CLAIM_ACTION_TEXT,
    statusText: ''
  };
}

function blocked(
  availability: AiraProComplimentaryClaimAvailability,
  statusText: string
): AiraProComplimentaryClaimDecision {
  return {
    availability: availability,
    actionEnabled: false,
    actionText: AIRA_PRO_COMPLIMENTARY_CLAIM_ACTION_TEXT,
    statusText: statusText
  };
}

function isPermanentMember(membership: AiraMembershipState, now: number): boolean {
  if (membership.plan !== 'pro') {
    return false;
  }
  if (membership.planExpiresAt === 0) {
    return true;
  }
  return isAiraProLifetimeProductId(membership.subscriptionProductId) &&
    membership.planExpiresAt > now;
}

function isCurrentSubscriptionMember(membership: AiraMembershipState, now: number): boolean {
  if (membership.plan !== 'pro') {
    return false;
  }
  if (membership.planExpiresAt > 0 && membership.planExpiresAt <= now) {
    return false;
  }
  const productId = membership.subscriptionProductId.trim();
  if (productId.length === 0 || isAiraProLifetimeProductId(productId)) {
    return false;
  }
  return isKnownSubscriptionProduct(productId) || isLiveSubscriptionStatus(membership);
}

function isKnownSubscriptionProduct(productId: string): boolean {
  return productId === AIRA_PRO_MONTHLY_PRODUCT_ID ||
    productId === AIRA_PRO_QUARTERLY_PRODUCT_ID ||
    productId === AIRA_PRO_YEARLY_PRODUCT_ID;
}

function isLiveSubscriptionStatus(membership: AiraMembershipState): boolean {
  return membership.subscriptionStatus === 'active' ||
    membership.subscriptionStatus === 'grace_period' ||
    membership.subscriptionStatus === 'cancelled' ||
    membership.subscriptionStatus === 'unknown';
}

function formatClaimDate(timestamp: number): string {
  const date = new Date(timestamp);
  const month = padTwoDigits(date.getMonth() + 1);
  const day = padTwoDigits(date.getDate());
  return `${date.getFullYear()}.${month}.${day}`;
}

function padTwoDigits(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}
