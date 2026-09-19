#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
failures=0

fail() {
  printf 'Bottom Toolbar Guide contract violation: %s\n' "$1" >&2
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

REPOSITORY_REL="AiraBrowser/entry/src/main/ets/data/onboarding/BottomToolbarGuideRepository.ets"
COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/onboarding/BottomToolbarGuideCoordinator.ets"
SHEET_REL="AiraBrowser/entry/src/main/ets/app/components/onboarding/BottomToolbarGuideSheet.ets"
OVERLAY_REL="AiraBrowser/entry/src/main/ets/app/components/onboarding/BottomToolbarGuideOverlay.ets"
CLIP_REL="AiraBrowser/entry/src/main/resources/rawfile/bottom_toolbar_guide.mp4"
TRANSIENT_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTransientSurfaceCoordinator.ets"
BOTTOM_PANEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserRootBottomPanelSessionCoordinator.ets"
SHELL_BACK_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserShellBackCoordinator.ets"
MAIN_BACK_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserMainBackCoordinator.ets"
SHELL_PAGE_REL="AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets"
RUNTIME_REL="AiraBrowser/entry/src/main/ets/app/bootstrap/BrowserAppRuntime.ets"
TEST_REL="AiraBrowser/entry/src/test/BottomToolbarGuideCoordinator.test.ets"
ADR_REL="docs/adr/0079-the-toolbar-lesson-is-taught-once-per-device.md"

for rel_path in "${REPOSITORY_REL}" "${COORDINATOR_REL}" "${SHEET_REL}" "${OVERLAY_REL}" "${CLIP_REL}" \
  "${TRANSIENT_REL}" "${BOTTOM_PANEL_REL}" "${SHELL_BACK_REL}" "${MAIN_BACK_REL}" "${SHELL_PAGE_REL}" \
  "${RUNTIME_REL}" "${TEST_REL}" "${ADR_REL}"; do
  if [ ! -f "${REPO_ROOT}/${rel_path}" ]; then
    fail "missing ${rel_path}"
  fi
done

# The lesson is presentation memory only: it must never store, gate, or reimplement
# the toolbar gesture it explains.
require_pattern "${REPOSITORY_REL}" "shownAt" \
  "the local record must store that the lesson was shown."
require_pattern "${REPOSITORY_REL}" "completedAt" \
  "the local record must store an explicit opt-out."
reject_pattern "${REPOSITORY_REL}" "gestureEnabled|detent|swipeDistance|toolbarVisible|peekEnabled" \
  "the guide memory must not model toolbar gesture mechanics."

# One owner decides when the lesson may present.
require_pattern "${COORDINATOR_REL}" "class BottomToolbarGuideCoordinator" \
  "the lesson must keep one eligibility and presentation owner."
require_pattern "${COORDINATOR_REL}" "'bottom_toolbar_guide'" \
  "the coordinator must present through the fixed transient surface."
require_pattern "${COORDINATOR_REL}" "handleWebPageLoadCompleted\\(\\)" \
  "the lesson must be armed by a finished Web page load."
require_pattern "${COORDINATOR_REL}" "handleSurfaceRevealed\\(\\)" \
  "the lesson must be spent only once the card actually reveals."
require_pattern "${COORDINATOR_REL}" "facts\\.shellFamily !== 'phone'" \
  "the lesson explains the phone gesture and must not present on the large-screen shell."
require_pattern "${COORDINATOR_REL}" "isReleaseNoticeBlocked\\(facts\\.promptBlockingFacts\\)" \
  "the lesson must yield the lane to prompts that already hold it."
# A custom bottom surface mounts asynchronously, so the reveal guard must key off
# this coordinator's own presentation generation and the visible snapshot. A guard
# that rejects the visible snapshot abandons every presentation.
require_pattern "${COORDINATOR_REL}" "presentationGeneration === this\\.presentationGeneration && this\\.snapshot\\.visible" \
  "the reveal guard must require the published visible snapshot, not reject it."
# The lesson is armed by a page load but may only present once the lane is free, so
# evaluation must be re-runnable instead of one-shot.
require_pattern "${COORDINATOR_REL}" "scheduleEvaluation\\(\\)" \
  "the lesson must re-decide presentation instead of deciding once."
require_pattern "${COORDINATOR_REL}" "never_show_again" \
  "the card must offer an explicit opt-out action."
reject_pattern "${SHELL_PAGE_REL}" "我知道了|不再提示|向下滑动" \
  "the shell must not own the lesson copy."

# The card is a shell: it renders the bundled clip and the owner's copy.
require_pattern "${SHEET_REL}" "\\\$rawfile\\('bottom_toolbar_guide\\.mp4'\\)" \
  "the card must play the bundled clip at its top."
require_pattern "${SHEET_REL}" "autoPlay\\(true\\)" \
  "the clip is decorative and must play on its own."

# Shell integration is registration plus a signal, never policy.
require_pattern "${TRANSIENT_REL}" "'bottom_toolbar_guide'" \
  "the transient surface coordinator must know the guide surface."
require_pattern "${BOTTOM_PANEL_REL}" "'bottom_toolbar_guide'" \
  "the bottom panel owner must know the guide surface."
require_pattern "${SHELL_BACK_REL}" "'dismiss_bottom_toolbar_guide'" \
  "back must dismiss the guide."
require_pattern "${MAIN_BACK_REL}" "bottomToolbarGuideCoordinator" \
  "back must delegate the guide dismissal to its owner."
require_pattern "${SHELL_PAGE_REL}" "handleWebPageLoadCompleted\\(\\)" \
  "the shell must arm the guide when the active Web page finishes loading."
require_pattern "${SHELL_PAGE_REL}" "handleSurfaceRevealed\\(\\)" \
  "the shell must record the guide only when the card reveals."
require_pattern "${RUNTIME_REL}" "sharedBottomToolbarGuideRepository" \
  "the guide repository must be a runtime singleton."

# The lesson is unspent until it is seen, so the behaviour is pinned by tests.
require_pattern "${TEST_REL}" "handleWebPageLoadCompleted" \
  "the test must pin the page-load arming of the lesson."
require_pattern "${TEST_REL}" "handleSurfaceRevealed" \
  "the test must pin that only a revealed card spends the lesson."

if [ "${failures}" -gt 0 ]; then
  exit 1
fi

echo "Bottom Toolbar Guide contract guard passed."
