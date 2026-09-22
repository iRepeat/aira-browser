import { describe, expect, it } from '@ohos/hypium';
import {
  AIRA_PRO_ONE_TIME_PLAN,
  AIRA_PRO_SELLABLE_IAP_PLANS,
  isAiraProSellablePlanId,
  resolveAiraProPlanPeriodText
} from '../main/ets/services/membership/HuaweiIapProductCatalog';

export default function huaweiIapProductCatalogTest(): void {
  describe('Aira Pro storefront catalog', () => {
    it('sells only monthly and yearly subscriptions on the Aira Pro page', 0, () => {
      expect(AIRA_PRO_SELLABLE_IAP_PLANS.length).assertEqual(2);
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[0].period).assertEqual('monthly');
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[0].title).assertEqual('连续包月');
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[0].displayPrice).assertEqual('¥1 / 月自动续费');
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[1].period).assertEqual('yearly');
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[1].title).assertEqual('连续包年');
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[1].displayPrice).assertEqual('¥7.89 / 年自动续费');
      expect(isAiraProSellablePlanId('monthly')).assertTrue();
      expect(isAiraProSellablePlanId('yearly')).assertTrue();
      expect(isAiraProSellablePlanId('quarterly')).assertFalse();
      expect(isAiraProSellablePlanId('one_time')).assertFalse();
    });

    // The membership page's price cards render the amount and the cadence as two
    // separate runs, so the catalog has to own the split rather than let the page
    // re-parse the single-line displayPrice.
    it('splits each plan price into an amount and a cadence for the price cards', 0, () => {
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[0].amountText).assertEqual('¥1');
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[0].periodText).assertEqual('/ 月');
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[1].amountText).assertEqual('¥7.89');
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[1].periodText).assertEqual('/ 年');
      expect(resolveAiraProPlanPeriodText('monthly')).assertEqual('/ 月');
      expect(resolveAiraProPlanPeriodText('quarterly')).assertEqual('/ 季');
      expect(resolveAiraProPlanPeriodText('yearly')).assertEqual('/ 年');
    });

    // Only the yearly plan carries a discount, and it is a period-end badge on
    // the card rather than part of the price string.
    it('carries the discount badge on the yearly plan only', 0, () => {
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[0].discountBadgeText).assertEqual('');
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[1].discountBadgeText).assertEqual('−34%');
    });

    // The permanent card is shown on the page, but it is not one of the two
    // auto-renewing plans the renewal sheet sells.
    it('prices permanent membership at 68.8 without selling it as a subscription', 0, () => {
      expect(AIRA_PRO_ONE_TIME_PLAN.productId).assertEqual('aira_pro_lifetime');
      expect(AIRA_PRO_ONE_TIME_PLAN.title).assertEqual('永久会员');
      expect(AIRA_PRO_ONE_TIME_PLAN.amountText).assertEqual('¥68.8');
      expect(AIRA_PRO_ONE_TIME_PLAN.periodText).assertEqual('永久');
      expect(AIRA_PRO_ONE_TIME_PLAN.displayPrice).assertEqual('¥68.8 永久');
      expect(isAiraProSellablePlanId('one_time')).assertFalse();
    });
  });
}
