---
status: accepted
supersedes: none
---

# New User Gift Is Server-Authoritative and Automatically Granted

Accepted 2026-09-18. Every new account receives one month of Aira Pro. The grant is issued by the hosted Aira service
without depending on a user action, and the client shows a one-time notice that tells the user it happened. The prompt
is informational: dismissing it never withholds the entitlement.

## Decision

The New User Gift is an Official-only capability. It depends on Huawei Account sign-in and on the Aira Cloud control
plane, both of which the Community distribution deliberately does not carry, so a Community build never grants or
announces it.

The hosted membership service owns the grant:

- `POST /membership/state` returns an optional `newUserGift` descriptor with `eligible`, `grantedAt`, and `grantDays`.
  The service derives `eligible` from the account's recorded first-seen time. The client stores the descriptor unchanged
  as a resolved `AiraNewUserGiftView` and discards it whenever the resolved account changes.
- `POST /membership/new-user-gift` is an idempotent ensure, not a user-triggered award. It is authenticated with the
  account access token, grants the month of Pro for an eligible new account, and is safe to call repeatedly. Success
  returns a `membershipGrant` shaped like the existing entitlement grant plus an optional `entitlementProof`, and sets
  `grantedAt`.

The client commits the returned `membershipGrant` through the existing grant path and writes no plan literal of its own.
A locally invented Pro grant was rejected: the next authoritative membership read overwrites it and it could be
replayed per device. Gating the grant behind the prompt button was rejected for a different reason — the product
promises the month to every new user, so the notice must not be the thing that decides whether they receive it. The
notice only reports what the service already did.

Granting is a separately classified Privacy Effect, `membership_gift_grant`, classified as a remote account/Sync
mutation. That reuses the existing catalog rule rather than adding a private-mode boolean, so a Private Browsing Session
cannot perform the grant and the notice is not presented there. The grant is unaffected by that refusal: it is a
server-side consequence of the account being new.

## Product Behavior

- After a successful sign-in the client resolves the descriptor, best-effort nudges the idempotent ensure, and then
  announces the result once. The month of Pro is present whether or not the user interacts with the notice.
- Dismissing the notice records a device-local acknowledgement in a per-account record so it is not shown again on this
  device. Losing or never showing the notice never loses the entitlement; the local record suppresses repetition only.
- A different device or a reinstall may announce again, which is acceptable because the announcement is not a grant and
  the service refuses a duplicate grant.
- The notice is a transient bottom surface like the Feature Gate, so back dismisses it and it composes with the existing
  prompt-blocking facts instead of competing with the release notice or the app-review prompt.

## Server Contract

`POST /membership/state` adds:

```text
newUserGift?: { eligible?: boolean; grantedAt?: number; grantDays?: number } | null
```

`POST /membership/new-user-gift` accepts `{ uid, source: 'app', authToken? }` and returns:

```text
ok, code, message,
newUserGift?: { eligible?: boolean; grantedAt?: number; grantDays?: number },
membershipGrant?: { uid, plan: 'pro', source: 'gift', expiresAt, subscriptionStatus },
entitlementProof?: string
```

This is the contract the client adapter implements; the endpoint itself lives in Aira's private control plane and is not
part of this monorepo. Until it is deployed the client fails closed: an unavailable or erroring service produces no
notice and no local grant, and the announcement simply does not appear.

## Migration And Verification

The offer is additive: no existing membership, subscription, or restore-purchase path changes.
`AiraNewUserGiftFunctionService` mirrors the existing IAP verification adapter, `NewUserGiftRepository` mirrors the
existing preferences-backed per-account repositories, and `NewUserGiftCoordinator` mirrors the release-notice
presentation owner. Proportional evidence is a Community build plus the New User Gift contract guard, which pins the
server-authoritative endpoint, the capability gate, the account-scope guard, the privacy classification, the
announcement-only action, and the single presentation owner. True end-to-end acceptance requires Official credentials
and the deployed private endpoint, which this repository cannot exercise.

## Considered Options

- Grant Pro locally on first sign-in. Rejected because the authoritative membership read would overwrite it and because
  the client cannot enforce one-time issuance.
- Grant only when the user presses the prompt button. Rejected because the month is promised to every new account; a
  button would turn an entitlement into an opt-in and lose it for anyone who dismisses the notice.
- Reuse the retired invite/referral redemption endpoint. Rejected because referral growth flows are retired and their
  authorization model required a user-supplied code, which this offer does not have.
- Gate presentation with a dedicated private-mode check. Rejected because the existing Privacy Effect Catalog already
  expresses "remote account mutation" and a second boolean would create a bypass.
