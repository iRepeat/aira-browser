#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
failures=0

fail() {
  printf 'Community Update contract violation: %s\n' "$1" >&2
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

FEED_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/update/CommunityReleaseFeedService.ets"
CHECK_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/update/CommunityUpdateCheckService.ets"
REPOSITORY_REL="AiraBrowser/entry/src/main/ets/data/update/CommunityUpdateCheckRepository.ets"
COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/update/CommunityUpdateCheckCoordinator.ets"
SHEET_REL="AiraBrowser/entry/src/main/ets/app/components/update/CommunityUpdateSheet.ets"
OVERLAY_REL="AiraBrowser/entry/src/main/ets/app/components/update/CommunityUpdateOverlay.ets"
LINKS_REL="AiraBrowser/entry/src/main/ets/common/constants/AiraCommunityProjectLinks.ets"
TRANSIENT_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTransientSurfaceCoordinator.ets"
BOTTOM_PANEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserRootBottomPanelSessionCoordinator.ets"
SHELL_BACK_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserShellBackCoordinator.ets"
MAIN_BACK_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserMainBackCoordinator.ets"
TAB_HOME_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTabHomeCoordinator.ets"
SHELL_PAGE_REL="AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets"
SETTINGS_DETAIL_REL="AiraBrowser/entry/src/main/ets/core/settings/SettingsDetailViewModel.ets"
SETTINGS_ACTION_REL="AiraBrowser/entry/src/main/ets/app/router/SettingsDetailNavigationActionCoordinator.ets"
RUNTIME_REL="AiraBrowser/entry/src/main/ets/app/bootstrap/BrowserAppRuntime.ets"
TEST_REL="AiraBrowser/entry/src/test/CommunityUpdateCheckCoordinator.test.ets"
TEST_LIST_REL="AiraBrowser/entry/src/test/List.test.ets"
ADR_REL="docs/adr/0081-community-updates-are-announced-from-the-public-release-feed.md"

for rel_path in "${FEED_SERVICE_REL}" "${CHECK_SERVICE_REL}" "${REPOSITORY_REL}" "${COORDINATOR_REL}" \
  "${SHEET_REL}" "${OVERLAY_REL}" "${TRANSIENT_REL}" "${BOTTOM_PANEL_REL}" "${SHELL_BACK_REL}" \
  "${MAIN_BACK_REL}" "${TAB_HOME_REL}" "${SHELL_PAGE_REL}" "${SETTINGS_DETAIL_REL}" \
  "${SETTINGS_ACTION_REL}" "${RUNTIME_REL}" "${TEST_REL}" "${TEST_LIST_REL}" "${ADR_REL}"; do
  if [ ! -f "${REPO_ROOT}/${rel_path}" ]; then
    fail "missing ${rel_path}"
  fi
done

# The Community distribution's only release channel is the public GitHub repo, and
# the feed URL must be derived from the one shared repository constant rather than
# hard-coded a second time.
require_pattern "${FEED_SERVICE_REL}" "AIRA_COMMUNITY_REPOSITORY_URL" \
  "the feed URL must derive from the shared Community repository constant."
reject_pattern "${FEED_SERVICE_REL}" "AIRA_HOSTED_API_BASE_URL|mason173/aira-browser" \
  "the Community update feed must not reach the hosted API or duplicate the repo URL."
# The feed is public and unauthenticated, so it must never carry credentials.
reject_pattern "${FEED_SERVICE_REL}" "Authorization|accessToken|apiKey|Bearer" \
  "the public release feed must not attach credentials."
# Checking for updates is best effort: a network problem must stay invisible.
require_pattern "${FEED_SERVICE_REL}" "catch \(_error\)" \
  "a feed transport or parse failure must stay silent."
require_pattern "${FEED_SERVICE_REL}" "releases\.atom" \
  "the feed must be the token-free GitHub Releases atom feed."
require_pattern "${FEED_SERVICE_REL}" "request\.destroy\(\)" \
  "the release request must release its HTTP handle."

# Transport, comparison, and persistence are not presentation: the service owns
# them so the About page can reuse the check without any browser surface.
require_pattern "${CHECK_SERVICE_REL}" "class CommunityUpdateCheckService" \
  "the check must keep one fetch/compare/persist owner."
require_pattern "${CHECK_SERVICE_REL}" "isCommunity\(\)" \
  "the check must be gated to the Community distribution."
reject_pattern "${CHECK_SERVICE_REL}" "present\(|openSystemSheet|TransientSurface|publishState" \
  "the check service must not present or touch browser surfaces."
require_pattern "${REPOSITORY_REL}" "lastNotifiedVersionCode" \
  "the local record must remember which remote version was already announced."

# One presentation owner decides when the notice may show.
require_pattern "${COORDINATOR_REL}" "class CommunityUpdateCheckCoordinator" \
  "the notice must keep one eligibility and presentation owner."
require_pattern "${COORDINATOR_REL}" "'community_update'" \
  "the coordinator must present through the fixed transient surface."
require_pattern "${COORDINATOR_REL}" "handleSurfaceRevealed\(\)" \
  "the notice must be spent only once the card actually reveals."
require_pattern "${COORDINATOR_REL}" "facts\.privacyMode === 'private'" \
  "a Private Browsing Session must never surface the update notice."
require_pattern "${COORDINATOR_REL}" "isReleaseNoticeBlocked\(facts\.promptBlockingFacts\)" \
  "the notice must yield the lane to prompts that already hold it."
# A custom bottom surface mounts asynchronously, so the reveal guard must key off
# this coordinator's own presentation generation and the available snapshot. A
# guard that rejects the available snapshot abandons every presentation.
require_pattern "${COORDINATOR_REL}" "presentationGeneration === this\.presentationGeneration && this\.snapshot\.available" \
  "the reveal guard must require the published available snapshot, not reject it."
require_pattern "${COORDINATOR_REL}" "scheduleEvaluation\(\)" \
  "the notice must re-decide presentation instead of deciding once."
require_pattern "${COORDINATOR_REL}" "lastNotifiedVersionCode >= release\.versionCode" \
  "the notice must not repeat for a release that was already announced."
# The Community package is unsigned, so the browser can only point at the release.
reject_pattern "${COORDINATOR_REL}" "install|download\(|submitRequest|startAbility" \
  "the notice must never download or install anything itself."
reject_pattern "${SHELL_PAGE_REL}" "发现新版本|前往下载|稍后再说" \
  "the shell must not own the notice copy."

# The card is a shell: it renders the owner's copy and emits one typed action.
require_pattern "${SHEET_REL}" "onAction: \(action: CommunityUpdateAction\)" \
  "the sheet must emit one typed presentation action callback."
# The changelog reads as one block: the summary and the bullet list share a single
# inset surface, and the card carries no separate sign-and-sideload disclaimer.
require_pattern "${SHEET_REL}" "COMMUNITY_UPDATE_CHANGELOG_" \
  "the changelog summary and items must render in one shared block."
reject_pattern "${SHEET_REL}" "未签名 HAP" \
  "the card must not carry a separate sign-and-sideload disclaimer."
require_pattern "${OVERLAY_REL}" "BrowserAdaptiveModalOverlay" \
  "the notice must reuse the shared adaptive modal overlay."

# Shell integration is registration plus a signal, never policy.
require_pattern "${TRANSIENT_REL}" "'community_update'" \
  "the transient surface coordinator must know the update surface."
require_pattern "${BOTTOM_PANEL_REL}" "'community_update'" \
  "the bottom panel owner must know the update surface."
require_pattern "${SHELL_BACK_REL}" "'dismiss_community_update'" \
  "back must dismiss the update notice."
require_pattern "${MAIN_BACK_REL}" "dismiss_community_update" \
  "back must delegate the notice dismissal to its owner."
require_pattern "${TAB_HOME_REL}" "resolveCommunityUpdateCheckCoordinator\(\)\.scheduleEvaluation\(\)" \
  "the home coordinator must arm the notice on the home prompt cadence."
require_pattern "${SHELL_PAGE_REL}" "handleSurfaceRevealed\(\)" \
  "the shell must record the notice only when the card reveals."
require_pattern "${SHELL_PAGE_REL}" "openReleasePage" \
  "the shell must open the release page through the app URL opener."
require_pattern "${SETTINGS_DETAIL_REL}" "'check_community_update'" \
  "the About page must expose a manual check action."
require_pattern "${SETTINGS_ACTION_REL}" "handlers\.checkCommunityUpdate\(\)" \
  "the manual check must route through the shared navigation action handler."
require_pattern "${RUNTIME_REL}" "sharedCommunityUpdateCheckRepository" \
  "the update-check repository must be a runtime singleton."
require_pattern "${RUNTIME_REL}" "sharedCommunityUpdateCheckService" \
  "the update-check service must be a runtime singleton."
require_pattern "${LINKS_REL}" "AIRA_COMMUNITY_REPOSITORY_URL" \
  "the Community repository constant must remain the single source for the feed URL."

# The behaviour is pinned by tests.
require_pattern "${TEST_REL}" "does not announce the same release twice" \
  "the test must pin the once-per-release announcement."
require_pattern "${TEST_REL}" "never announces inside a private session" \
  "the test must pin the private-session gate."
require_pattern "${TEST_LIST_REL}" "communityUpdateCheckCoordinatorTest" \
  "the suite must register the Community update test."

if [ "${failures}" -gt 0 ]; then
  exit 1
fi

echo "Community Update contract guard passed."
