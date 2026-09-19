---
status: accepted
supersedes: none
---

# The Toolbar Lesson Is Taught Once Per Device

Accepted 2026-09-19. A first-time user who opens their first Web page is told, once, that the phone floating toolbar can
be swiped down out of the way. The lesson is a bounded presentation of an existing gesture: it grants no capability,
stores no toolbar state, and never changes how the toolbar behaves.

## Decision

The lesson is a device-local onboarding announcement, not a feature gate and not a setting.

- `BottomToolbarGuideRepository` owns the only persisted facts: that this device already showed the lesson
  (`shownAt`) and that the user asked not to be shown it again (`completedAt`). Both live in one preferences store,
  `aira_bottom_toolbar_guide`. The record deliberately does not model gesture mechanics — no detent, no swipe distance,
  no toolbar visibility flag — because those belong to the bottom panel owner and duplicating them here would create a
  second, drifting answer to "can the toolbar be hidden".
- `BottomToolbarGuideCoordinator` owns eligibility and presentation. It is armed by the active phone tab finishing a
  Web page load, and it presents a centered modal through the shared transient surface id `bottom_toolbar_guide`, exactly
  like the welcome-gift notice.
- The lesson is spent at reveal, not at arm. A custom bottom surface mounts asynchronously, so a presentation that is
  abandoned before its reveal must not consume the one-time guide. This mirrors the welcome-gift rule: the memory
  records that the user was told, and losing the notice costs only the notice.

Arming and presenting are separate decisions. The lane that automatic prompts share can be held by a release notice, an
app-review prompt, the welcome-gift notice, a site prompt, or a tabs sheet at the moment the first page finishes
loading. Deciding once at that instant would silently lose the lesson, so the coordinator keeps a pending lesson armed
and re-decides whenever a Web page finishes loading or the lane clears, and only a card that reached the user ends the
question.

The lesson is phone-only. The large-screen shell has its own toolbar that is not swiped away, so presenting this copy
there would teach a gesture the user cannot perform.

## Alternatives Considered

- Teach the gesture from the existing top floating prompt (`BrowserGestureOnboardingPromptCoordinator`). Rejected: that
  owner explains the bottom-edge capsule gestures in a passive top banner, has its own once-per-device key, and offers
  no room for the recorded clip or the explicit dismissal actions this lesson needs.
- Reuse the local record to model the gesture, so the lesson could be skipped when the gesture is unavailable.
  Rejected: peek/detent availability is session state owned by the bottom panel, and a persisted copy would go stale.
- Show the lesson at any Web page load until the user performs the swipe. Rejected: the goal is to inform, not to
  enforce, and an un-dismissed instruction that keeps returning is hostile.
- Gate the lesson on the distribution. Rejected: it teaches a gesture that exists in every distribution, so it is not an
  Official capability like the gift or the Pro gate.

## Consequences

- The card is a floating surface on the shared theme tokens, so it is white in light mode and black in dark mode: the bundled clip
  at its top, a title that states the gesture, and two stacked full-width actions: `我知道了` closes it, `不再提示` closes it and
  records the permanent opt-out. Back and an outside tap close it as an acknowledgement through the same transient-surface
  dismissal path.
- The clip is a bundled `rawfile` asset (`bottom_toolbar_guide.mp4`), muted, looping, and control-less. It is decoration:
  if it fails to load the copy still teaches the gesture.
- Because the announcement is device-local and presentation-only, it survives provider switches, account changes, and
  Private Browsing Sessions untouched. A Private Browsing Session is refused at presentation, and the pending lesson
  stays armed for a later ordinary session.

## Verification

Proportional evidence is a Community build plus `scripts/check-aira-bottom-toolbar-guide-contract.sh`, which pins the
single owner, the fixed transient surface, the page-load arming, the reveal-time spend, the phone-only gate, the
lane-blocking rule, the shell registration, and the absence of lesson copy in the shell. Behaviour is pinned by
`AiraBrowser/entry/src/test/BottomToolbarGuideCoordinator.test.ets`.
