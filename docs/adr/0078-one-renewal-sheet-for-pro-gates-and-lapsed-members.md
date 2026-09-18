# ADR 0078: One renewal sheet for Pro gates, lapsed members, and the expiry reminder

## Status

Accepted.

## Context

Aira Pro gates already existed: touching a Pro feature presented `FeatureGateSheet`, a title, one
sentence, and a button that navigated to the membership page. Three gaps made that insufficient.

First, the sheet could not complete a purchase. Every renewal meant leaving the surface, so the user
lost the context that told them why they were being asked to pay.

Second, an account that already had Pro could not be told apart from one that never did. When an IAP
subscription lapses, reconciliation deletes the `membership_grants` row, and `getActiveIapBindingByUid`
stops reporting the binding once it is no longer entitled. The `/membership/state` response then reads
`plan: 'club'`, `subscriptionStatus: 'none'`, `productId: ''`, `expiresAt: 0` — byte-identical to an
account that has never paid. Both were reported as `pro_required`, so the client could only offer the
same first-time upsell to a paying customer who had just lapsed. The IAP binding row survives, so the
information existed; it simply was not exposed.

Third, nothing ever told a member their Pro had ended. The only way to discover it was to touch a
feature and be refused.

## Decision

Expose the lapsed period from the service, and let one sheet serve all three entry points.

`POST /membership/state` gains `lapsedPro`, computed as the latest already-ended Pro period across the
membership grant and every IAP binding:

```text
lapsedPro?: { expiresAt: number; source: string; productId: string } | null
```

It is reported in both read modes and only while the current plan is not Pro, because that is exactly
when a base-plan read needs the distinction. `expiresAt: 0` means a permanent grant and never counts as
lapsed; a future value is not lapsed either. The descriptor is additive, so an older client that ignores
it is unaffected and a newer client tolerates its absence.

The entitlement decision gains `pro_expired` beside `pro_required`. An account with a reported lapsed
period is told its Pro ended and that the feature resumes on renewal; an account without one keeps the
first-time framing. The primary action is the same renewal in both cases.

`FeatureGateSheet` carries an optional renewal payload — the benefit list, the plans from the IAP
catalog, the selected plan, and the agreement line — and is rendered only for a Pro gate, where a
purchase is actually actionable. Authentication and entitlement gates keep the plain layout because
there is nothing to sell there. When the payload is present the primary button completes the purchase
through the shell's own `AiraProPurchaseCoordinator` instead of navigating away. Because the sheet now
serves the sync page, the feature gate, and the reminder, all three present one renewal surface rather
than three competing ones.

`AIRA_PRO_BENEFITS` becomes the single owner of the benefit list, consumed by both the membership page
and the sheet, so the two cannot advertise different things.

The unprompted reminder is a separate owner, `RenewalReminderCoordinator`, that presents through the
same gate surface.

## Do-not-disturb

The reminder is announced once per lapse, and the rule has three deliberate parts.

It is keyed by the expiry instant (`remindedForExpiredAt`), not by a permanent shown flag. A later
period that lapses again carries a different instant and is therefore announceable again; a boolean
would silence every future lapse.

It never mutes a gate the user triggered. Touching a Pro feature is a direct request to renew, so that
path bypasses the record entirely. Do-not-disturb governs only the unprompted reminder; if it muted the
gate, the feature would become unrenewable.

The record is written only after the sheet actually reveals. A custom bottom surface mounts
asynchronously, so a presentation abandoned before its reveal must not consume the one-time reminder.
This mirrors the new-user gift (ADR 0077), where acknowledging on request rather than on reveal hid the
notice permanently.

The reminder is not evaluated from a notification service: there is no member-facing push channel, so
"three days before expiry" means "on the next launch that falls inside the window".

## Consequences

An account that lapsed can be addressed as a returning customer rather than a prospect, which is the
population most worth recovering and the one the previous design could not see.

`lapsedPro` reports a past period and is not an entitlement: it never grants access, and the client
treats it purely as presentation input. A restored membership clears it because the descriptor is only
computed for a non-Pro plan.

The reminder's reach is bounded by app launch, so a member who never opens Aira is never reminded.
Adding a push channel would be a separate decision.

Existing Pro gates keep working unchanged: a user-triggered denial always presents, the plan options
come from the IAP catalog rather than local literals, and the sheet still falls back to navigation when
it has no plan to offer (Community distributions, where in-app purchase is unavailable).
