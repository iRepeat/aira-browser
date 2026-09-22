#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
failures=0

fail() {
  printf 'Cross Device Link contract violation: %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_pattern() {
  local rel_path="$1"
  local pattern="$2"
  local message="$3"
  if ! grep -Eq "${pattern}" "${REPO_ROOT}/${rel_path}"; then
    fail "${message}"
  fi
}

reject_pattern() {
  local rel_path="$1"
  local pattern="$2"
  local message="$3"
  if grep -Eqi "${pattern}" "${REPO_ROOT}/${rel_path}"; then
    fail "${message}"
  fi
}

ETS_DIR="AiraBrowser/entry/src/main/ets"
VIEW_MODEL_REL="${ETS_DIR}/core/sync/CrossDeviceLinkViewModel.ets"
SCREEN_REL="${ETS_DIR}/app/components/sync/CrossDeviceLinkScreen.ets"
HOST_REL="${ETS_DIR}/app/components/sync/CrossDeviceLinkHost.ets"
PAGE_REL="${ETS_DIR}/app/pages/CrossDeviceLinkPage.ets"
SETUP_PAGE_REL="${ETS_DIR}/app/pages/CrossDeviceLinkSetupPage.ets"
SETUP_SCREEN_REL="${ETS_DIR}/app/components/sync/CrossDeviceLinkSetupScreen.ets"
PERSONAL_SERVER_PAGE_REL="${ETS_DIR}/app/pages/SyncPersonalServerConfigPage.ets"
CATALOG_SERVICE_REL="${ETS_DIR}/services/sync/SyncDesktopExtensionCatalog.ets"
DESTINATIONS_REL="${ETS_DIR}/core/settings/SettingsDestinationCatalog.ets"
CENTER_VIEW_MODEL_REL="${ETS_DIR}/core/settings/SettingsCenterViewModel.ets"
NAV_COORDINATOR_REL="${ETS_DIR}/app/router/SettingsNavigationCoordinator.ets"
EMBEDDED_DETAIL_REL="${ETS_DIR}/app/components/settings/SettingsEmbeddedDetailPanel.ets"
SETTINGS_CENTER_REL="${ETS_DIR}/app/components/settings/SettingsCenterScreen.ets"
LARGE_SCREEN_INTENT_REL="${ETS_DIR}/core/browser/BrowserLargeScreenShellIntentApplication.ets"
LARGE_SCREEN_TOOLBAR_REL="${ETS_DIR}/app/components/browser/BrowserLargeScreenNavigationToolbarSurface.ets"
ROUTES_REL="${ETS_DIR}/app/router/AppRoutes.ets"
MAIN_PAGES_REL="AiraBrowser/entry/src/main/resources/base/profile/main_pages.json"
BROWSER_TABS_SHEET_REL="${ETS_DIR}/app/components/browser/BrowserCrossDeviceTabsOverlay.ets"
TEST_REL="AiraBrowser/entry/src/test/CrossDeviceLinkViewModel.test.ets"
CATALOG_REL="resources/icon-sources/aira/icon-catalog.json"
ADR_REL="docs/adr/0080-cross-device-link-is-a-first-level-settings-page.md"

for rel_path in "${VIEW_MODEL_REL}" "${SCREEN_REL}" "${HOST_REL}" "${PAGE_REL}" "${SETUP_PAGE_REL}" \
  "${SETUP_SCREEN_REL}" \
  "${CATALOG_SERVICE_REL}" \
  "${DESTINATIONS_REL}" "${CENTER_VIEW_MODEL_REL}" "${NAV_COORDINATOR_REL}" "${ROUTES_REL}" \
  "${MAIN_PAGES_REL}" "${TEST_REL}" "${ADR_REL}"; do
  if [ ! -f "${REPO_ROOT}/${rel_path}" ]; then
    fail "missing ${rel_path}"
  fi
done

# The page is a read-only projection: it reads sync and presence state, and every
# dependent capability is reached by jumping to the owner that already implements it.
require_pattern "${VIEW_MODEL_REL}" "class CrossDeviceLinkViewModel" \
  "the page state must have one builder."
# 数据同步 and 跨设备互联 are two separate channels: this page owns the cross-device switch
# (tab handoff and page push) and only links to the sync owner for data sync. It must never
# carry a second data-sync master switch, or pausing bookmarks would look like it also
# stopped devices from talking.
require_pattern "${VIEW_MODEL_REL}" "LINK_SWITCH_TITLE: string = '跨设备互联'" \
  "the page's own switch must be the cross-device link, not data sync."
require_pattern "${VIEW_MODEL_REL}" "linkEnabled: facts.linkEnabled" \
  "the link switch must come from the presence owner, not the sync owner."
require_pattern "${HOST_REL}" "sharedCrossDeviceTabPresenceCoordinator.setCrossDeviceLinkEnabled\\(" \
  "flipping the link switch must go through the presence owner."
require_pattern "${HOST_REL}" "isCrossDeviceLinkEnabled\\(\\)" \
  "the link switch state must be read from the presence owner."
reject_pattern "${SCREEN_REL}" "同步所有内容" \
  "the data-sync master switch must not be duplicated on this page."
reject_pattern "${HOST_REL}" "setMasterEnabled" \
  "this page must not write data-sync state at all."
require_pattern "${SCREEN_REL}" "onChange: \\(checked: boolean\\): void =>" \
  "the switch must forward the intent instead of writing state."
require_pattern "${SCREEN_REL}" "switchSettledRevision: number = 0" \
  "the screen must accept a settle signal for the switch."
require_pattern "${SCREEN_REL}" "linkEnabled.*switchSettledRevision" \
  "the switch row must be rebuilt from the authoritative value, not left on its flipped look."
require_pattern "${SCREEN_REL}" "this.onAction\\('open_sync_settings'\\)" \
  "the 同步设置 row must be the way out to the sync owner."
reject_pattern "${VIEW_MODEL_REL}" "UNAVAILABLE_LABEL|buildCapabilityRow" \
  "the per-capability rows must not come back beside the one switch."
reject_pattern "${SCREEN_REL}" "SettingsSection\(\{ title: '可以做什么'" \
  "the old capability section title must not come back."
# The device list always ends with the way to grow it.
require_pattern "${SCREEN_REL}" "this.onAction\\('add_device'\\)" \
  "the last device row must always start the pairing handshake."
require_pattern "${VIEW_MODEL_REL}" "ADD_DEVICE_ROW_TITLE: string = '添加设备'" \
  "the always-last row must read 添加设备."
require_pattern "${HOST_REL}" "option.isSelected" \
  "the active mode must come from the sync owner's goal options."
require_pattern "${VIEW_MODEL_REL}" "providerKind === 'self_hosted'" \
  "a self-hosted server carries the full desktop link."
require_pattern "${VIEW_MODEL_REL}" "providerKind === 'webdav'" \
  "a WebDAV mode must be reported as bookmark-only."
reject_pattern "${VIEW_MODEL_REL}" "requiresPro|needPro|paywall" \
  "the page must not carry its own paywall wording; it reports state only."

require_pattern "${HOST_REL}" "sharedSyncExperienceCoordinator.load\\(\\)" \
  "the host must read sync state from its owner rather than keeping its own copy."
require_pattern "${VIEW_MODEL_REL}" "selfHostedAction: 'open_personal_server'" \
  "the self-hosted row must open the existing self-hosted page, not the sync list."
require_pattern "${HOST_REL}" "openSyncPersonalServerConfig\\(this.boundary\\)" \
  "the host must delegate the self-hosted jump to the navigation owner."
require_pattern "${HOST_REL}" "sharedCrossDeviceTabPresenceCoordinator.loadPanelState\\(\\)" \
  "online computers must come from the presence owner."
require_pattern "${HOST_REL}" "isAvailable\\('aira_cloud'\\)" \
  "the desktop link availability must be the Aira Cloud capability, not a local literal."
reject_pattern "${HOST_REL}" "bookmarkSyncEnabled =|historySelected =|remoteKind =" \
  "the page must never write sync state."
reject_pattern "${HOST_REL}" "https://" \
  "install links belong to the extension catalog service, not the host."

require_pattern "${CATALOG_SERVICE_REL}" "resolveSyncDesktopExtensionEntries" \
  "the extension install entries must have one catalog."
require_pattern "${CATALOG_SERVICE_REL}" "action === 'open_link' \\? '查看' : '复制'" \
  "the local package opens in Aira; the store links are copied for a computer."
require_pattern "${SETUP_SCREEN_REL}" "resolveSyncDesktopExtensionEntryActionLabel\\(entry\\)" \
  "the install sub-page must render the catalog's action label."
reject_pattern "${SETUP_SCREEN_REL}" "chromewebstore|addons.mozilla|microsoftedge|github.com|lanzou" \
  "the install sub-page must not hardcode install URLs."
reject_pattern "${SCREEN_REL}" "不重复实现|直达对应功能|未连接时这段是空态|实现口径" \
  "user-facing copy only: no implementation notes on the page."
# The recipe is a second level: the overview only links to it, and the sub-page derives
# its steps from the mode the overview passes instead of loading sync state again.
reject_pattern "${SCREEN_REL}" "连接步骤|在电脑上安装 Aira-sync|点扩展图标" \
  "the overview must not carry the steps or the install list any more."
reject_pattern "${SCREEN_REL}" "buildStepRow|installEntries" \
  "the overview must not build step rows or install rows."
# A device row opens that computer's tabs only: the overview already listed the
# computers, so the sheet must not list them all over again.
require_pattern "${SCREEN_REL}" "this.onOpenDeviceTabs\\(row.deviceId\\)" \
  "a device row must open that device's tabs."
require_pattern "${HOST_REL}" "deviceIdFilter: this.deviceTabsFilter" \
  "the sheet must be narrowed to the device the user tapped."
require_pattern "${HOST_REL}" "this.openDeviceTabs\\(\'\'\\)" \
  "the capability row must keep listing every online computer."
require_pattern "${BROWSER_TABS_SHEET_REL}" "resolveVisibleDevices\\(\\)" \
  "the shared device-tab list must support a single-device filter."
require_pattern "${SCREEN_REL}" "this.onOpenSetup\\(\\)" \
  "the overview must link to the install sub-page."
require_pattern "${HOST_REL}" "openCrossDeviceLinkSetup\\(this.boundary, this.providerKind\\)" \
  "the overview must hand the current mode to the install sub-page."
require_pattern "${VIEW_MODEL_REL}" "export function buildCrossDeviceLinkSteps" \
  "the recipe must be a pure function of the mode."
require_pattern "${SETUP_SCREEN_REL}" "buildCrossDeviceLinkSteps\\(" \
  "the sub-page must derive its steps from that function."
require_pattern "${SETUP_SCREEN_REL}" "router.getParams" \
  "the sub-page must read the mode from its route instead of loading sync state."
reject_pattern "${SETUP_SCREEN_REL}" "sharedSyncExperienceCoordinator" \
  "the sub-page must not load sync state of its own."
require_pattern "${SETUP_PAGE_REL}" "@Entry" \
  "the install and pairing recipe must keep its own routed page for phone and touch."
require_pattern "${SETUP_SCREEN_REL}" "export struct CrossDeviceLinkSetupScreen" \
  "that page must stay a shell and delegate to the component."
require_pattern "${SETUP_SCREEN_REL}" "embedded: boolean = false" \
  "the recipe component must also be embeddable for the PC settings pane."
require_pattern "${SETUP_SCREEN_REL}" "this\\.embedded" \
  "the embedded recipe must take its mode from the host instead of the route."
require_pattern "${HOST_REL}" "this\\.showSetupInline = true" \
  "the large-screen overview must open the recipe inline instead of routing."
# The three browser rows show the vendor mark itself, not a colorable glyph inside the
# shared round badge, because the store brands are third-party artwork.
require_pattern "${SETUP_SCREEN_REL}" "app\\.media\\.sync_browser_chrome" \
  "the Chrome row must use the Chrome brand mark."
require_pattern "${SETUP_SCREEN_REL}" "app\\.media\\.sync_browser_edge" \
  "the Edge row must use the Edge brand mark."
require_pattern "${SETUP_SCREEN_REL}" "app\\.media\\.sync_browser_firefox" \
  "the Firefox row must use the Firefox brand mark."
require_pattern "${SETUP_SCREEN_REL}" "useCustomLeading: this\\.isBrowserBrandEntry" \
  "browser rows must bypass the round icon badge."
reject_pattern "${SETUP_SCREEN_REL}" "buildBrowserBrandLeading[^)]*\\{[\\s\\S]{0,200}Circle\(" \
  "the brand mark must not sit inside another circle."

require_pattern "${HOST_REL}" "CrossDeviceLinkSetupScreen\\(" \
  "the host must render the recipe component it embeds."
# On the PC shell the settings live in the tab's native route, so router.back cannot bring
# the page forward; a tapped install link must go through the shell's own opener.
require_pattern "${SETUP_SCREEN_REL}" "onOpenExternalUrl" \
  "the embedded recipe must accept the shell's link opener."
require_pattern "${HOST_REL}" "this\\.onOpenExternalUrl" \
  "the host must pass the shell opener into the embedded recipe."
require_pattern "${EMBEDDED_DETAIL_REL}" "this\\.onOpenExternalUrl\\?\\.\\(url" \
  "the embedded pane must forward the link opener."
require_pattern "${SETTINGS_CENTER_REL}" "openExternalUrlFromPane" \
  "the settings center must route an embedded pane link to the shell opener."
require_pattern "${LARGE_SCREEN_INTENT_REL}" "'open_external_url'" \
  "the PC shell must implement opening a pane link in its own tab."
# The PC address bar offers the cross-device tab list between the account popover and the
# user-script button, reusing the one cross-device list component the cross-device-link page
# already shows. That component serves two presentations (sheet and tabs-overview page), so
# a rename of its symbol must land in both places at once rather than forking a second list.
require_pattern "${LARGE_SCREEN_TOOLBAR_REL}" "buildCrossDeviceTabsButton" \
  "the PC address bar must offer a cross-device tabs button."
require_pattern "${LARGE_SCREEN_TOOLBAR_REL}" "BrowserCrossDeviceTabsSheet" \
  "that button must reuse the existing cross-device tabs sheet."
require_pattern "${LARGE_SCREEN_TOOLBAR_REL}" "kind: 'open_external_url'" \
  "opening a remote tab from the address bar must reuse the shell's URL intent."
# PC keeps the user inside the settings workspace so the sync dialogs stay centered. The
# routed sync page is the phone presentation; its sheets are bottom sheets by design.
require_pattern "${EMBEDDED_DETAIL_REL}" "onSelectDestination\\('sync'\\)" \
  "the PC pane must select the 同步 destination instead of pushing the routed sync page."
require_pattern "${HOST_REL}" "onOpenSyncSettings" \
  "the host must prefer the PC pane over the routed sync page."
require_pattern "${HOST_REL}" "this\\.desktopPresentation \\? SheetType\\.CENTER : SheetType\\.BOTTOM" \
  "the PC pane must present its own sheets as centered dialogs."
require_pattern "${SETUP_PAGE_REL}" "CrossDeviceLinkSetupScreen" \
  "that page must stay a shell and delegate to the component."
require_pattern "${ROUTES_REL}" "CROSS_DEVICE_LINK_SETUP_ROUTE" \
  "the sub-page must have a route constant."
require_pattern "${NAV_COORDINATOR_REL}" "openCrossDeviceLinkSetup" \
  "the navigation owner must open the sub-page."
require_pattern "${MAIN_PAGES_REL}" "app/pages/CrossDeviceLinkSetupPage" \
  "the sub-page must be registered as a routable page."

# Icons follow the rest of settings: varied token colors, and a document glyph for the
# help action instead of whatever default the scaffold would fall back to.
require_pattern "${SCREEN_REL}" "settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet" \
  "the screen must take the settings icon color tokens."
require_pattern "${SCREEN_REL}" "buildSyncSection\\(\\)" \
  "the sync section must have one builder."
reject_pattern "${SCREEN_REL}" "iconBackgroundColor: this.storedAccentColor" \
  "capability and list icons must not all collapse to one flat color."
# The header carries no help action: a document icon in the title bar competed with the
# back action and duplicated an entry that now lives on the surfaces it belongs to.
reject_pattern "${SCREEN_REL}" "menuActionLabel|menuActionAiraIconId|onMenuAction" \
  "the link page must not keep a title-bar help action."
reject_pattern "${SETUP_SCREEN_REL}" "menuActionLabel|menuActionIcon|onMenuAction" \
  "the setup sub-page must not keep a title-bar help action."
# Removing the header icon must not remove the guide: the private-deployment config page
# is where a self-hosting user lands, so it carries the remaining entry point.
require_pattern "${PERSONAL_SERVER_PAGE_REL}" "查看私有化部署教程" \
  "the private-deployment page must offer the deployment guide."
require_pattern "${PERSONAL_SERVER_PAGE_REL}" "openSyncDesktopBookmarkGuide" \
  "the private-deployment guide entry must open the shared guide route."

# The local package page is password protected: opening it copies the password first and
# tells the user it is ready to paste, so the password stays in the catalog.
require_pattern "${CATALOG_SERVICE_REL}" "password: string" \
  "the install catalog must carry the page password."
require_pattern "${SETUP_SCREEN_REL}" "openLockedPage\\(entry\\)" \
  "a locked install page must go through the password handoff."
require_pattern "${SETUP_SCREEN_REL}" "访问密码已复制，粘贴即可" \
  "opening a locked page must tell the user the password is on the clipboard."
require_pattern "${HOST_REL}" "openBrowserUrlFromGuide" \
  "a tapped link must return to the browser shell and open in front of the user."
require_pattern "${SETUP_SCREEN_REL}" "openBrowserUrlFromGuide\\(url, this.boundary\\)" \
  "the install sub-page must open a link the same way."
reject_pattern "${HOST_REL}" "stageLaunchPayload" \
  "a staged launch payload opens the page behind the settings instead of showing it."
reject_pattern "${SETUP_SCREEN_REL}" "stageLaunchPayload" \
  "a staged launch payload opens the page behind the settings instead of showing it."
reject_pattern "${HOST_REL}" "wwbgv|lanzou" \
  "the download host belongs to the catalog, not the host."

# A build without Aira Cloud cannot sign in, so that page must be a self-hosted-only
# story: no account wording, no Aira Cloud wording, and one route to a desktop.
require_pattern "${VIEW_MODEL_REL}" "NO_PROVIDER_NOTICE_COMMUNITY" \
  "a build without Aira Cloud must explain the self-hosted route, not a missing cloud."
require_pattern "${VIEW_MODEL_REL}" "SELF_HOSTED_FOOTER_COMMUNITY" \
  "a build without Aira Cloud must keep a self-hosted footer that does not promise it."
require_pattern "${VIEW_MODEL_REL}" "SELF_HOSTED_SECTION_TITLE_COMMUNITY: string = '推荐方式'" \
  "the self-hosted row is the recommended path, not the alternate one, on that build."
require_pattern "${VIEW_MODEL_REL}" "STEPS_SELF_HOSTED" \
  "the steps must not describe an account login that build cannot perform."
# The page has no separate action bar for a working link, and the header carries no
# provider wording beyond one notice line.
reject_pattern "${VIEW_MODEL_REL}" "ADD_DEVICE_HINT|PAIR_HINT" \
  "the pairing helper sentences belong to the device row, not a header button."
reject_pattern "${SCREEN_REL}" "capabilitiesFooter" \
  "the capability list must not carry a footer again."

require_pattern "${SETUP_SCREEN_REL}" "ForEach\\(this\\.steps" \
  "the steps must come from the owner's state instead of the screen."

# An empty device list is the same row component as a populated one, only reworded.
require_pattern "${SCREEN_REL}" "private buildPlaceholderDeviceRow\\(\\)" \
  "the empty device list must still render a row."
require_pattern "${SCREEN_REL}" "this.onAction\\(this.state.devicesPlaceholderAction\\)" \
  "the empty device row must open whatever fixes the empty state."
reject_pattern "${SCREEN_REL}" "private buildPlaceholderDeviceRow\\(\\) \\{\n\\s+Row\\(\{ space: 12 \\)" \
  "the empty device row must reuse the settings row component, not a hand-built one."

# This phone is the one device the page can never be wrong about, so it is always listed.
require_pattern "${VIEW_MODEL_REL}" "localDeviceRow: this\\.buildLocalDeviceRow\\(facts\\.localDevice\\)" \
  "the device list must always lead with this phone."
require_pattern "${VIEW_MODEL_REL}" "LOCAL_DEVICE_VALUE: string = '当前设备'" \
  "this phone's row must say it is the current device."
require_pattern "${SCREEN_REL}" "this\\.state\\.localDeviceRow\\.title" \
  "the always-present row must come from the state, not a literal."
require_pattern "${SCREEN_REL}" "airaIconId: LOCAL_DEVICE_GLYPH" \
  "the current device row must carry the app's own phone glyph."
require_pattern "${SCREEN_REL}" "iconBackgroundColor: this\\.settingsIconBackgrounds\\.userAgent" \
  "the current device row must use the same round badge as the computer rows."
require_pattern "${SCREEN_REL}" "this\\.onAction\\('open_sync_settings'\\)" \
  "the 同步设置 row must be the way out to the sync owner."
# 同步设置 is a pointer, not a capability: it takes no leading badge of its own.
reject_pattern "${SCREEN_REL}" "title: '同步设置',\\n\\s+value: this\\.state\\.syncSettingsValue,\\n\\s+airaIconId" \
  "the 同步设置 row must not carry an icon."
require_pattern "${HOST_REL}" "sharedCrossDeviceTabPresencePreferencesRepository\\.readLocalDevice\\(\\)" \
  "this phone must name itself from the presence owner's own installation record."
require_pattern "${TEST_REL}" "always lists this phone as the current device" \
  "the always-present row must be pinned by a test."

# The PC shell embeds it as a settings pane like 同步; phone and touch two-pane keep the
# routed page, so a large-screen click never opens a bare full-window page.
require_pattern "${DESTINATIONS_REL}" "target\\('cross_device_link', 'cross_device_link', 'cross_device_link', '跨设备互联'" \
  "the settings catalog must register the first-level destination."
require_pattern "${DESTINATIONS_REL}" "true, true, 'desktop_embedded'\\)" \
  "the destination must embed on the PC shell and route only where there is no pane."
reject_pattern "${DESTINATIONS_REL}" "'cross_device_link',[^)]*'routed'\\)" \
  "the destination must not stay routed on every shell."
require_pattern "${EMBEDDED_DETAIL_REL}" "this\\.selectedDestination === 'cross_device_link'" \
  "the large-screen detail panel must route the destination to its embedded pane."
require_pattern "${EMBEDDED_DETAIL_REL}" "CrossDeviceLinkHost\\(\\{" \
  "the embedded pane must host the cross-device-link content, not a blank detail."
require_pattern "${HOST_REL}" "desktopPresentation: boolean = false" \
  "the host must be embeddable in the large-screen workspace."
require_pattern "${HOST_REL}" "onExit\\?" \
  "an embedded host must exit the pane instead of popping the router."
require_pattern "${SCREEN_REL}" "showTitleBar: this\\.showTitleBar" \
  "the embedded pane must hide the scaffold title bar."
require_pattern "${CENTER_VIEW_MODEL_REL}" "'cross_device_link'" \
  "the settings center must show the row."
require_pattern "${NAV_COORDINATOR_REL}" "destination === 'cross_device_link'" \
  "the navigation owner must map the destination to its route."
require_pattern "${NAV_COORDINATOR_REL}" "CROSS_DEVICE_LINK_ROUTE" \
  "the routeted destination must use the declared route constant."
require_pattern "${ROUTES_REL}" "CROSS_DEVICE_LINK_ROUTE: string = 'app/pages/CrossDeviceLinkPage'" \
  "the route constant must point at the new page."
require_pattern "${MAIN_PAGES_REL}" "app/pages/CrossDeviceLinkPage" \
  "the page must be registered as a routable page."

# Behaviour of the pure state builder is pinned by tests.
require_pattern "${TEST_REL}" "desktopLinkAvailable = false" \
  "the test must pin the narrowed distribution shape."
require_pattern "${TEST_REL}" "describes online computers by their browser alone" \
  "the test must pin that a device row carries no status readout."

# The header names the person, not the page: phone on the left, account in the middle,
# computers on the right, and the connectors only light up against a live desktop.
require_pattern "${VIEW_MODEL_REL}" "account: CrossDeviceLinkAccountFact" \
  "the header identity must come from the host's account fact."
require_pattern "${VIEW_MODEL_REL}" "SIGNED_OUT_TITLE: string = '未登录'" \
  "a header without an account must say so instead of naming one."
require_pattern "${VIEW_MODEL_REL}" "ACCOUNT_ID_PREFIX: string = '账号 ID '" \
  "the account id must be labelled, not shown as a bare string."
require_pattern "${VIEW_MODEL_REL}" "onlineComputerCount: facts.devices.length" \
  "the computer side must follow the presence owner's own list."
require_pattern "${HOST_REL}" "resolveAiraHuaweiAccountIdentity" \
  "the header identity must come from the sync owner's settings."
# The page's own chrome uses the app's Operational font icons, never the system symbol set:
# its own phone and its paired computer each have a semantic id. The help glyph is gone
# with the header action, so only the two header peers remain.
require_pattern "${SCREEN_REL}" "LOCAL_DEVICE_GLYPH: AiraRenderableIconId = 'crossDeviceLink.localDevice'" \
  "the phone side of the header must be the app's own device font icon."
require_pattern "${SCREEN_REL}" "PEER_COMPUTER_GLYPH: AiraRenderableIconId = 'crossDeviceLink.peerComputer'" \
  "the computer side of the header must be the app's own computer font icon."
reject_pattern "${SCREEN_REL}" "HELP_GLYPH|crossDeviceLink\.help" \
  "the removed header help action must not linger as a glyph constant."
reject_pattern "${SCREEN_REL}" "sys\\.symbol\\.doc_text_fill" \
  "the link page must not fall back to the system document glyph."
reject_pattern "${SCREEN_REL}" "sys\\.symbol\\.phone_fill|sys\\.symbol\\.desktop_fill" \
  "the header peers must not fall back to the system device glyphs."
require_pattern "${CATALOG_REL}" "crossDeviceLink.localDevice" \
  "the catalog must own the page's device glyph."
require_pattern "${CATALOG_REL}" "crossDeviceLink.peerComputer" \
  "the catalog must own the page's computer glyph."
require_pattern "${SCREEN_REL}" "this\\.buildConnector\\(this\\.isComputerOnline\\(\\)\\)" \
  "only the computer connector may follow the online state."
reject_pattern "${SCREEN_REL}" "connectionTitle|connectionMessage" \
  "the old connection block must not come back beside the account header."

# The tabs-overview cross-device segment stays on that section. Sign-in, Pro, a closed
# link, and an empty device list are empty pages inside it, not a jump to the Pro page.
TABS_OVERLAY_REL="${ETS_DIR}/app/components/browser/BrowserTabsFloatingOverlay.ets"
SHELL_REL="${ETS_DIR}/app/pages/BrowserShellPage.ets"
EMPTY_PRESENTATION_REL="${ETS_DIR}/core/deviceTabs/CrossDeviceTabsEmptyPresentation.ets"
PRESENCE_COORDINATOR_REL="${ETS_DIR}/core/deviceTabs/CrossDeviceTabPresenceCoordinator.ets"
require_pattern "${EMPTY_PRESENTATION_REL}" "登录后查看跨设备标签页" \
  "the signed-out empty page must stay in the cross-device section."
require_pattern "${EMPTY_PRESENTATION_REL}" "跨设备标签页需要 Aira Pro" \
  "a non-Pro account must see the Pro empty page instead of being routed away."
require_pattern "${EMPTY_PRESENTATION_REL}" "跨设备互联未开启" \
  "a closed link must have its own empty page."
require_pattern "${EMPTY_PRESENTATION_REL}" "当前没有在线电脑" \
  "no online computer must stay an empty page, not a route."
require_pattern "${PRESENCE_COORDINATOR_REL}" "resolveCloudProEmptyKind" \
  "Pro is classified after sign-in, inside the panel state."
require_pattern "${SHELL_REL}" "section: 'devices'" \
  "choosing the cross-device segment must enter that section."
reject_pattern "${SHELL_REL}" "requestOpenPanel" \
  "the cross-device segment must not leave the tabs overview for Pro or sync settings."
require_pattern "${BROWSER_TABS_SHEET_REL}" "buildEmptyPresentation" \
  "the shared device-tab list must render the empty pages."
require_pattern "${TABS_OVERLAY_REL}" "onCrossDeviceNavigate" \
  "the tabs overview must forward empty-page navigation to the shell."
require_pattern "${LARGE_SCREEN_TOOLBAR_REL}" "handleCrossDeviceEmptyNavigate" \
  "the PC address-bar list must share the empty-page actions."
require_pattern "${HOST_REL}" "handleDeviceTabsNavigate" \
  "the settings sheet must share the empty-page actions."
require_pattern "${EMPTY_PRESENTATION_REL}" "secondaryAction: 'open_guide'" \
  "private deployment from a non-member empty page opens the guide, not sync settings."
reject_pattern "${EMPTY_PRESENTATION_REL}" "secondaryAction: 'open_sync_settings'" \
  "the private-deployment text link must not open the sync dialog."
require_pattern "${SHELL_REL}" "SYNC_DESKTOP_BOOKMARK_GUIDE_ROUTE" \
  "the shell opens the cross-device guide for that empty-page action."
require_pattern "${BROWSER_TABS_SHEET_REL}" "SYNC_DESKTOP_BOOKMARK_GUIDE_ROUTE" \
  "the device-tab sheet falls back to the cross-device guide route."
require_pattern "${HOST_REL}" "openSyncDesktopBookmarkGuide" \
  "the settings sheet opens the same guide."
require_pattern "${VIEW_MODEL_REL}" "cloudEntitlement === 'pro_expired'" \
  "an expired account gets its own notice on the link page."
require_pattern "${VIEW_MODEL_REL}" "cloudEntitlement === 'pro_required'" \
  "a never-subscribed account stays distinct from an expired one."
require_pattern "${VIEW_MODEL_REL}" "cloudEntitlement === 'active'" \
  "the official-cloud switch stays usable only while Pro is active."
require_pattern "${HOST_REL}" "resolveCloudEntitlement" \
  "the link page reads membership before enabling its switch."
require_pattern "${HOST_REL}" "!this.viewState.linkSwitchEnabled" \
  "a grayed switch must not write the saved preference."
QR_COORDINATOR_REL="${ETS_DIR}/core/browser/BrowserQrScanCoordinator.ets"
require_pattern "${HOST_REL}" "requestAccountSignIn" \
  "an unsigned add-device scan stays on the page and asks for login."
require_pattern "${HOST_REL}" "requestForegroundSheet" \
  "the login sheet waits until the page is foreground after the scanner returns."
require_pattern "${QR_COORDINATOR_REL}" "resumeDesktopLoginAfterSignIn" \
  "a staged desktop-login payload is confirmed after the in-place sign-in."
require_pattern "${PAGE_REL}" "onPageHide" \
  "the link page tells the host when the scanner covers it."
bind_sheet_count="$(grep -c '\.bindSheet(' "${REPO_ROOT}/${HOST_REL}" || true)"
if [ "${bind_sheet_count}" -ne 3 ]; then
  fail "CrossDeviceLinkHost must bind each sheet on its own node, found ${bind_sheet_count}."
fi

if [ "${failures}" -gt 0 ]; then
  exit 1
fi

echo "Cross Device Link contract guard passed."