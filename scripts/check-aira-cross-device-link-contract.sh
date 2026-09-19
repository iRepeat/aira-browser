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
require_pattern "${VIEW_MODEL_REL}" "bookmarkSyncEnabled: boolean" \
  "the bookmark row must come from the sync owner's own fact."
require_pattern "${VIEW_MODEL_REL}" "historySyncEnabled: boolean" \
  "the history row must come from the sync owner's own fact."
require_pattern "${VIEW_MODEL_REL}" "buildCapabilityRow\\('page_push', PAGE_PUSH_ROW_TITLE, fullDesktopLink, fullDesktopLink," \
  "网页接力 may only light up when the chosen mode can carry it to a desktop."
require_pattern "${VIEW_MODEL_REL}" "buildCapabilityRow\\('device_tabs', DEVICE_TABS_ROW_TITLE, fullDesktopLink, fullDesktopLink," \
  "跨设备标签页 may only light up when the chosen mode can carry it to a desktop."
require_pattern "${VIEW_MODEL_REL}" "UNAVAILABLE_LABEL: string = '不可用'" \
  "a capability the mode cannot deliver must be reported as unavailable."
require_pattern "${SCREEN_REL}" "isEnabled: row.available" \
  "an unavailable capability must be greyed out, not hidden."
# The page reports what the mode the user chose can actually do, and it takes that mode
# from the sync owner instead of guessing.
require_pattern "${HOST_REL}" "option.isSelected" \
  "the active mode must come from the sync owner's goal options."
require_pattern "${HOST_REL}" "historySyncSupported: syncState !== undefined && syncState.historySupported" \
  "history support must come from the sync owner, not a local rule."
require_pattern "${VIEW_MODEL_REL}" "providerKind === 'self_hosted'" \
  "a self-hosted server carries the full desktop link."
require_pattern "${VIEW_MODEL_REL}" "providerKind === 'webdav'" \
  "a WebDAV mode must be reported as bookmark-only."
require_pattern "${SCREEN_REL}" "this.onAction\\(this.state.primaryAction\\)" \
  "every unsupported state must exit through the one primary action."
reject_pattern "${VIEW_MODEL_REL}" "requiresPro|needPro|paywall" \
  "the page must not carry its own paywall wording; the capability rows only report on/off."

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
# user-script button, reusing the sheet the cross-device-link page already shows.
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
require_pattern "${SCREEN_REL}" "resolveCapabilityIconBackground\\(row.id\\)" \
  "capability rows must resolve their own icon color."
reject_pattern "${SCREEN_REL}" "iconBackgroundColor: this.storedAccentColor" \
  "capability and list icons must not all collapse to one flat color."
require_pattern "${SCREEN_REL}" "menuActionIcon: \\\$r\\('sys.symbol.doc_text_fill'\\)" \
  "the help action must use a document glyph."

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
require_pattern "${VIEW_MODEL_REL}" "label: '去配置私有化部署'" \
  "that build must send the user at configuring its own server."
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
require_pattern "${TEST_REL}" "刚在线 · 12 个标签页" \
  "the test must pin the device row wording."

if [ "${failures}" -gt 0 ]; then
  exit 1
fi

echo "Cross Device Link contract guard passed."