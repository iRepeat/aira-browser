---
status: accepted
supersedes: none
---

# Community Updates Are Announced From The Public Release Feed

Accepted 2026-09-19. The Community distribution ships as an unsigned HAP through GitHub Releases and has no app-store
update channel, so nobody would ever tell a Community user that a newer build exists. Aira now checks the public release
feed itself and announces a newer Community release once per version.

## Decision

The Community distribution owns a first-party update check that reads GitHub Releases and nothing else.

- `CommunityReleaseFeedService` reads `${AIRA_COMMUNITY_REPOSITORY_URL}/releases.atom`. The atom feed is deliberately
  chosen over the REST API: it needs no token and, unlike anonymous REST calls, is not subject to the per-address rate
  limit that a browsing session can exhaust. The URL derives from the one Community repository constant instead of
  hard-coding the repository a second time.
- `CommunityUpdateCheckService` owns transport, comparison, and persistence. It fetches the newest release, compares its
  `versionCode` against the installed bundle (falling back to a numeric `versionName` comparison when the release was
  tagged without a code), and records the result through `CommunityUpdateCheckRepository`. It is presentation-free, so
  the About page can reuse the exact same check without touching a browser surface.
- `CommunityUpdateCheckCoordinator` owns eligibility and presentation. It announces a newer release once per
  `versionCode` through the shared transient surface id `community_update`, mirroring the welcome-gift and toolbar-lesson
  owners, and it opens the release page on request.
- `CommunityUpdateCheckRepository` stores only presentation facts: when the feed was last read, what it last reported,
  and which remote `versionCode` was already announced. It never stores or derives the installed version, which stays
  owned by the bundle manager.

The notice is spent at reveal, not at arm. A custom bottom surface mounts asynchronously, so an abandoned presentation
must not consume the one-time announcement. Arming and presenting are separate decisions: the shared automatic-prompt
lane may be held by a release notice, an app-review prompt, the welcome-gift notice, the toolbar lesson, a site prompt,
or a tabs sheet when the check returns, so a blocked lane defers the notice instead of losing it.

The check is Community-only and never runs inside a Private Browsing Session. `Official` builds update through Huawei
AppGallery, so the coordinator stays silent there while the manual About entry point reports that the app store owns
updates.

## What The Browser Never Does

The Community package is unsigned, so Aira cannot install an update even when it knows one exists: only the user can sign
and sideload the package. The notice therefore only names the newer release, shows its changelog summary, and offers to
open the matching release page in a new tab. It never downloads a package, never starts an installer, and never touches
Huawei IAP, Aira Cloud, or any credentialed endpoint: the feed is public and requires no authentication.

## Alternatives Considered

- Reuse the existing `ReleaseNoticeCoordinator`. Rejected: that owner answers "what changed in the version I just
  installed" from a bundled rawfile, and is intentionally suppressed for Community. This feature answers "is there a
  version I have not installed yet" and only applies to Community, so the two have different sources, lifecycles, and
  gates.
- Use the GitHub REST releases API. Rejected: it rate-limits anonymous callers, which would make the check fail exactly
  for an active user, and it needs no more information than the feed already carries.
- Check on every app launch. Rejected: a network call per launch is wasteful and the answer changes on the order of
  weeks; the check rides the existing home prompt cadence and re-decides presentation, so a busy lane defers rather than
  drops it.
- Offer an in-app download button. Rejected: the package is unsigned, so a download the browser cannot install would
  promise something it cannot deliver. Pointing at the release page keeps the signing step honestly in the user's hands.

## Consequences

- The card shows the installed and newer versions, then the release summary and its bullet list in one changelog block.
  `前往下载` opens the release page in a new tab and dismisses;
  `稍后再说` dismisses. Back and an outside tap dismiss through the same transient-surface path, and neither spends the
  one-time announcement.
- A release published without a `versionCode` cannot be remembered as announced, so the automatic path falls back to a
  quiet toast instead of a notice that would repeat forever.
- A failed check is silent on the automatic path and reports `检查更新失败，请稍后再试。` from the manual About entry
  point. Losing a check costs only the check.
- Because the announcement is presentation-only and device-local, it survives provider switches, account changes, and
  distribution boundaries untouched.

## Verification

Proportional evidence is a Community build plus `scripts/check-aira-community-update-contract.sh`, which pins the single
feed source, the credential-free and best-effort transport, the split between check service and presentation owner, the
once-per-release rule, the private-session gate, the lane-yielding rule, the shell registration, the manual About entry
point, and the absence of notice copy and installer calls in the shell. Behaviour is pinned by
`AiraBrowser/entry/src/test/CommunityUpdateCheckCoordinator.test.ets`.
