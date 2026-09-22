import { describe, expect, it } from '@ohos/hypium';
import { AiraMembershipState, buildDefaultMembershipState } from '../main/ets/common/models/MembershipModels';
import { resolveAiraProComplimentaryClaimDecision } from '../main/ets/core/membership/AiraProComplimentaryClaimPolicy';
import {
  AIRA_PRO_ONE_TIME_PRODUCT_ID,
  AIRA_PRO_YEARLY_PRODUCT_ID
} from '../main/ets/services/membership/HuaweiIapProductCatalog';

const NOW: number = Date.UTC(2026, 3, 8);

export default function airaProComplimentaryClaimPolicyTest(): void {
  describe('Aira Pro complimentary claim', () => {
    it('lets a non-member claim, and claim again only after the period ends', 0, () => {
      const guest = buildDefaultMembershipState(NOW);
      expect(resolveAiraProComplimentaryClaimDecision(guest, NOW).actionEnabled).assertTrue();
      expect(resolveAiraProComplimentaryClaimDecision(guest, NOW).availability).assertEqual('available');

      const expiresAt = NOW + 15 * 24 * 60 * 60 * 1000;
      const activeClaim = membership('pro', expiresAt);
      const activeDecision = resolveAiraProComplimentaryClaimDecision(activeClaim, NOW);
      expect(activeDecision.availability).assertEqual('claim_active');
      expect(activeDecision.actionEnabled).assertFalse();
      expect(activeDecision.statusText.indexOf(formatClaimDate(expiresAt)) >= 0).assertTrue();

      const expiredClaim = membership('pro', NOW - 1000);
      expect(resolveAiraProComplimentaryClaimDecision(expiredClaim, NOW).availability).assertEqual('available');
      expect(resolveAiraProComplimentaryClaimDecision(expiredClaim, NOW).actionEnabled).assertTrue();
    });

    it('refuses a permanent member and a live subscription', 0, () => {
      const permanentMember = membership('pro', 0);
      permanentMember.subscriptionProductId = AIRA_PRO_ONE_TIME_PRODUCT_ID;
      const permanentDecision = resolveAiraProComplimentaryClaimDecision(permanentMember, NOW);
      expect(permanentDecision.availability).assertEqual('already_member');
      expect(permanentDecision.actionEnabled).assertFalse();
      expect(permanentDecision.statusText.indexOf('永久会员') >= 0).assertTrue();

      const subscriber = membership('pro', NOW + 30 * 24 * 60 * 60 * 1000);
      subscriber.subscriptionStatus = 'active';
      subscriber.subscriptionProductId = AIRA_PRO_YEARLY_PRODUCT_ID;
      const subscriberDecision = resolveAiraProComplimentaryClaimDecision(subscriber, NOW);
      expect(subscriberDecision.availability).assertEqual('already_member');
      expect(subscriberDecision.actionEnabled).assertFalse();
      expect(subscriberDecision.statusText.indexOf('订阅会员') >= 0).assertTrue();
    });
  });
}

function membership(plan: 'guest' | 'pro', planExpiresAt: number): AiraMembershipState {
  const state = buildDefaultMembershipState(NOW);
  state.plan = plan;
  state.planExpiresAt = planExpiresAt;
  return state;
}

function formatClaimDate(timestamp: number): string {
  const date = new Date(timestamp);
  const month = date.getMonth() + 1;
  const day = date.getDate();
  const monthText = month < 10 ? `0${month}` : `${month}`;
  const dayText = day < 10 ? `0${day}` : `${day}`;
  return `${date.getFullYear()}.${monthText}.${dayText}`;
}
