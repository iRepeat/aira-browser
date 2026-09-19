---
status: accepted
supersedes: none
---

# Cross-Device Link Is a First-Level Settings Page, Not a Tutorial

Accepted 2026-09-19. The desktop-browser link (Aira-sync extension) was reachable only from one row inside 同步 that
opened a markdown tutorial. It becomes a first-level settings destination with a real page that reports state, jogs the
user into pairing, and hands every dependent capability to the owner that already implements it.

## Decision

One destination, `cross_device_link`, registered in the settings catalog beside `Aira Pro` and `同步`, and one
content component behind it. It embeds as a settings pane on the PC shell exactly like `同步`, and stays a routed page
on phone and touch two-pane where there is no pane. The page is deliberately a **read-only projection plus deep links**:

- `CrossDeviceLinkViewModel` builds the whole page state from facts: the bookmark and history switches come from
  `SyncExperienceCoordinator`, the online computers come from `CrossDeviceTabPresenceCoordinator`, and the desktop-link
  availability is the existing `aira_cloud` distribution capability. The page never activates sync, never toggles a
  provider, and never keeps its own copy of sync state — `SyncExperienceCoordinator` remains the single state-transition
  owner (ADR 0048), and the frozen Aira-sync contract is untouched.
- Capability rows report on/off only. 书签同步 and 历史记录同步 mirror the real switches, which the user can turn off;
  网页接力 and 跨设备标签页 have no off switch, so where the chosen mode can deliver them they read 已开启 forever.
- The page is provider-aware, because the desktop link is not the same thing on every mode. Aira Cloud and a self-hosted
  server carry the whole link; WebDAV carries bookmarks only; Huawei Space has no desktop browser side at all. The active
  mode is read from the sync owner's own goal options (plus its `historySupported`), never guessed, and a capability the
  mode cannot deliver is greyed to 不可用 rather than hidden, so the page keeps one layout in every state.
- Every state that cannot reach a desktop exits through exactly one primary action: pair the chosen mode (scan for Aira
  Cloud, the pairing code page for a self-hosted server) or switch to a mode that can reach a desktop. Configuration
  stays in the sync owner; this page only deep-links into it.
- Every row jumps to the owner: both sync rows to 同步设置, 网页接力 to the existing help document (which already
  documents the menu 推送 action), and 跨设备标签页 to a sheet that mounts the existing
  `BrowserCrossDeviceTabsSheet`, so the cross-device tab list has exactly one implementation.
- The install-and-pair recipe is a second level, `CrossDeviceLinkSetupPage`, reached from one row. The overview answers
  "can this mode reach a desktop"; the recipe is only needed once, so it does not sit in front of a user who is already
  paired. On phone and touch two-pane that page takes the active mode from its route params; in the PC pane the same
  `CrossDeviceLinkSetupScreen` is embedded with the mode passed as a prop and the scaffold header hidden. Both paths
  derive the steps with a pure function, so the recipe loads no sync state of its own. A tapped install link opens the
  same way on both: on the routed page it goes back to the browser shell, and in the PC pane the settings center asks
  the shell to open it (`open_external_url`) because `router.back` cannot leave a native-route settings scene.
- The PC address bar also offers the same tab list directly: a 跨设备标签页 button sits between the account popover and
  the user-script button and opens `BrowserCrossDeviceTabsSheet` in a popup. Tapping a remote tab reuses the shell's URL
  intent (`open_external_url`), so the two entries share one implementation.
- On the PC shell the page keeps sync inside the settings workspace: 去开启同步 / 更换同步方式 selects the 同步
  destination instead of pushing the routed sync page, whose selection sheets are bottom sheets. The pane's own sheets
  (desktop login confirmation, device tabs) also present as centered dialogs there.
- 添加设备 starts the existing QR scanner with the existing `DesktopLoginConfirmSheetContent` confirmation. Pairing stays
  one-directional: the computer shows a login QR code and the phone scans it. There is still no server flow for the
  reverse, and this page does not invent one.
- 私有化部署 replaces the separate WebDAV row: both are the same "bring your own server" answer, the sync owner already
  exposes them as `webdav` and `self_hosted`, and the row opens the existing self-hosted configuration page rather than
  the sync list.

The markdown tutorial does not disappear; it is demoted to the page's 帮助 action, which keeps a document glyph rather
than the scaffold's default action icon. Icons reuse the settings icon-background token set, so the page reads like the
rest of settings instead of one flat color.

Extension install links get one catalog, `SyncDesktopExtensionCatalog`. Store entries are `copy_link` because a phone
cannot install a desktop extension, while the local package is `open_link` and opens the download page in Aira. The store
entries are Official-only; a Community build offers only the local package.

The local package page is locked. Its password lives in the same catalog entry, and opening it copies the password first
and then tells the user it is ready to paste, so the handoff is one tap: open the page, paste the password.

## Distribution And Privacy

The page is one source tree for both distributions and rewrites itself from the `aira_cloud` capability instead of having
a second page. An Official build can sign in, so its page keeps the account wording, the scan pairing, the store links
and 私有化部署 as the alternative. A Community build cannot sign in at all, so its page is a self-hosted-only story: it
never names Aira Cloud, its steps never mention an account login, its footer asks for 私有化部署 rather than "Aira 云或私有化
部署", its 私有化部署 row is presented as 推荐方式 instead of the escape hatch, and its primary action sends the user straight
at configuring their own server. The install list narrows to the local package the same way.

Entry is gated by the same optional-service check as 同步, so a basic service mode never reaches it.

## Considered Options

- Keep the tutorial and only move its entry. Rejected: the entry was never the whole problem; a document cannot report
  whether the computer is paired, nor open the pairing flow.
- Add the page as a second state owner beside the sync screen. Rejected: two owners would drift, and the sync contract
  guards forbid it.
- Build a dedicated device-and-tab list on this page. Rejected: `BrowserCrossDeviceTabsSheet` already renders exactly
  that from the presence owner, including the open-remote-tab action.
- Show 需 Pro on the rows. Rejected by product: the page reports on/off, and the Pro requirement is stated once in the
  section footer instead of on every row.

## Consequences

- The entry is one settings row with a connection-status value. On the PC shell it embeds in the detail pane
  (`twoPanePresentation: 'desktop_embedded'`, the same presentation as `同步`); on phone and touch two-pane it stays the
  routed page (`CrossDeviceLinkPage`). The embedded pane hosts the same `CrossDeviceLinkScreen`, with the scaffold title
  bar and back button hidden and `onExit` returning to the destination list.
- The page owns no timers and no persistence: it reloads on appear and on the existing `SyncSettingsRefreshSignal`, and
  reflects whatever the sync and presence owners report, including their own empty and error messages.
- The device list stays ephemeral by construction: it shows only what the presence owner currently reports as online.

## Verification

Proportional evidence is a Community build, the Official build, the architecture guardrails, and
`scripts/check-aira-cross-device-link-contract.sh`, which pins the single state builder, the owner-sourced facts, the
read-only rule, the always-on rows, the routed destination registration, the PC-shell embedded pane, and the link
catalog. The pure state builder is
pinned by `AiraBrowser/entry/src/test/CrossDeviceLinkViewModel.test.ets`.
