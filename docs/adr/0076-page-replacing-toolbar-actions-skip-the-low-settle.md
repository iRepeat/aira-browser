---
status: accepted
supersedes: none
---

# Page-Replacing Toolbar Actions Skip the Low Settle

Accepted 2026-09-14. The Root Bottom-Panel toolbar has two expanded presentations, and both used to hold a
page-replacing action until a collapse finished.

**The expanded action Sheet.** Tapping the Menu slot opens the native Sheet (`openToolbarSystemSheet`). Its grid cards
dispatch through `requestToolbarSystemSheetAction`, which only recorded the action and set
`toolbarSystemSheetVisible = false`; the action ran from `handleToolbarSystemSheetDisappear` after the Sheet's dismiss
animation completed. That is the surface a device log records as
`chrome-intent kind=dispatch-header-action action=bottomChromeMenu slot=menu`.

**The in-panel expanded chrome.** At the `middle` detent, `buildPanelActionTapPlan` collapses the panel to `low`, and
`handleActionTap` either dispatches immediately or defers the action through `pendingActionAfterCollapsedSettle` until
the collapse and the search-backdrop settle have both completed.

## The rule

An expanded-toolbar action whose effect replaces the shell with another page — Settings, History, Bookmarks, Downloads,
Saved Pages, and the Novel Bookshelf, plus the Home-scene User Scripts page — starts its route push in the tap frame and
lets the Sheet dismissal or panel collapse run underneath. An action that opens a surface *inside* the shell — a bottom
sheet, an overlay, an in-page mode such as Page Find, translate, or the Web-scene User Scripts actions sheet — keeps the
gate and still runs only after the Sheet is gone or the `low` settle completes.

The distinction is per dispatch, not per id: `openBookmarks` and `scripts` exist in both Home and Web lanes, and only
the lane that routes away from the shell is exempt. `BrowserRootBottomPanelActionApplication` owns the id list
(`isShellDepartingAction` for the panel lane, `isShellDepartingSheetAction` for the Sheet lane) so the Session owner
keeps timing and the action application keeps the knowledge of what each id does. The Sheet asks the Shell through
`onShouldDispatchSheetActionImmediately` rather than deciding for itself; the UI shell must not acquire this policy.

## Why the gate existed, and why it does not apply here

The gate protects surfaces that compose against the same screen region. A sheet or overlay opened while the expanded
toolbar was still animating away would fight it for that region, so those actions must wait. A full-screen route does
not compose with either surface at all: the pushed page covers the shell, so the collapse it overlaps is never visible.

Waiting only added time to the tap: the Sheet's dismiss animation, or the panel's collapse duration plus the
search-backdrop settle plus the fallback timer bounding them. That delay is what the reported "must wait for the toolbar
to finish retracting before Settings opens" behavior was.

## A second, independent delay in the same path

`BrowserShellRouteCoordinator.pushRoute` deferred the route through `FrameCallback`. The task was placed in `onIdle`,
which fires only when a frame has more than 1ms left before the next VSync; while any collapse animation was running
every frame was busy, so the callback was deferred until the animation ended. The task now runs in `onFrame` (the next
rendered frame), which is what the existing repository convention and the "start after the reset UI turn, not inside it"
requirement actually call for. Both fixes are independent and were needed together.

## Boundaries

`BrowserRootBottomPanelSessionCoordinator` remains the single owner of expanded-panel dispatch timing, and the
classification is an input to that decision, not a second dispatch path — the deferred and immediate branches, the
fallback timer, and `completePanelSettleAfterEffects` are unchanged. On the Sheet path the dismissal bookkeeping
(`onToolbarSystemSheetDismissed`, the instance token, the remount debounce) is untouched; only the action hand-off moved
earlier, and the pending action is cleared first so the later `onDisappear` cannot dispatch twice. The exempt set is
deliberately closed: a new action keeps the gate unless it is added with the same route-replacing justification.

Acceptance requires true-device confirmation that Settings, History, and Bookmarks open promptly from the expanded
toolbar Sheet and from the in-panel chrome, that an action which opens an in-shell surface still waits for the Sheet or
settle, and that returning to the shell shows the panel at `low` rather than mid-collapse. Build evidence alone does not
establish gesture and transition composition; visual capture is required only when separately authorized.

