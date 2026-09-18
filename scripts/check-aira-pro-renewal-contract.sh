#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
failures=0

fail() {
  printf 'Pro renewal contract violation: %s\n' "$1" >&2
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

COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/membership/RenewalReminderCoordinator.ets"
GATE_REL="AiraBrowser/entry/src/main/ets/core/membership/FeatureGateCoordinator.ets"
REPOSITORY_REL="AiraBrowser/entry/src/main/ets/data/membership/RenewalReminderRepository.ets"
SHEET_REL="AiraBrowser/entry/src/main/ets/app/components/membership/FeatureGateSheet.ets"
BENEFITS_REL="AiraBrowser/entry/src/main/ets/core/membership/AiraProBenefitCatalog.ets"
OVERVIEW_REL="AiraBrowser/entry/src/main/ets/core/membership/AiraProOverviewViewModel.ets"
FEATURE_REL="AiraBrowser/entry/src/main/ets/features/membership/MembershipFeature.ets"
ENTITLEMENT_REL="AiraBrowser/entry/src/main/ets/services/membership/EntitlementService.ets"
MODELS_REL="AiraBrowser/entry/src/main/ets/common/models/MembershipModels.ets"
STATE_REL="AiraBrowser/entry/src/main/ets/services/membership/AiraMembershipStateFunctionService.ets"
SHELL_PAGE_REL="AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets"
TAB_HOME_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTabHomeCoordinator.ets"

for rel_path in "${COORDINATOR_REL}" "${GATE_REL}" "${REPOSITORY_REL}" "${SHEET_REL}" \
  "${BENEFITS_REL}" "${OVERVIEW_REL}" "${FEATURE_REL}" "${ENTITLEMENT_REL}" "${MODELS_REL}" \
  "${STATE_REL}" "${SHELL_PAGE_REL}" "${TAB_HOME_REL}"; do
  if [ ! -f "${REPO_ROOT}/${rel_path}" ]; then
    fail "missing ${rel_path}"
  fi
done

# A lapsed IAP subscription deletes the membership grant, so the distinction
# between "used to pay" and "never paid" has to come from the server.
require_pattern "${MODELS_REL}" "interface AiraLapsedProStateRecord" \
  "the client model must carry the server-owned lapsed-Pro descriptor."
require_pattern "${STATE_REL}" "lapsedPro\\?: AiraLapsedProStateRecord \\| null" \
  "the membership state response must carry the lapsed-Pro descriptor."
require_pattern "${FEATURE_REL}" "getLapsedProState\\(\\)" \
  "the feature must expose the lapsed-Pro view."
require_pattern "${FEATURE_REL}" "this\\.lapsedPro\\.uid !== uid" \
  "lapsed-Pro state must be discarded when the resolved account changes."
require_pattern "${FEATURE_REL}" "captureLapsedProState\\(" \
  "the feature must capture the descriptor from the authoritative read."

# An ended period must not be reported as a first-time upsell.
require_pattern "${MODELS_REL}" "'pro_expired'" \
  "a lapsed period must be a distinct denial reason."
require_pattern "${ENTITLEMENT_REL}" "'pro_expired'" \
  "the entitlement decision must distinguish an expired member."
require_pattern "${ENTITLEMENT_REL}" "lapsedPro\\.expiredAt > 0" \
  "the expired framing must be driven by a real lapsed period."

# One renewal sheet, reached three ways: feature gate, sync page, reminder.
require_pattern "${GATE_REL}" "FeatureGateRenewalState" \
  "the gate snapshot must carry a renewal payload."
require_pattern "${GATE_REL}" "presentRenewalReminder\\(\\)" \
  "the reminder must present through the shared gate surface."
require_pattern "${GATE_REL}" "planId === undefined|renewal === undefined" \
  "the gate must keep a plain layout when it has no plan to sell."
require_pattern "${SHEET_REL}" "this\\.state\\.renewal !== undefined" \
  "the sheet must render the renewal layout only when a renewal payload exists."
require_pattern "${SHEET_REL}" "onSelectPlan" \
  "plan selection must be reported, never applied by the sheet."

# Both surfaces advertise one benefit list, so they cannot drift apart.
require_pattern "${BENEFITS_REL}" "AIRA_PRO_BENEFITS" \
  "the Pro benefit list must have one owner."
require_pattern "${OVERVIEW_REL}" "AIRA_PRO_BENEFITS" \
  "the membership page must consume the shared benefit list."
reject_pattern "${OVERVIEW_REL}" "id: 'cross_system_bookmark_sync'" \
  "the membership page must not keep a second copy of the benefit list."

# Do-not-disturb: once per lapse, keyed by the expiry instant, and only spent
# after the sheet actually revealed.
require_pattern "${REPOSITORY_REL}" "remindedForExpiredAt" \
  "the reminder record must be keyed by the expiry instant, not a shown flag."
reject_pattern "${REPOSITORY_REL}" "shownAt|dismissedAt|reminded: boolean" \
  "a permanent shown flag would suppress a later lapse."
require_pattern "${REPOSITORY_REL}" "remindedForExpiredAt >= normalizedExpiredAt" \
  "a later lapse must remain announceable."
require_pattern "${COORDINATOR_REL}" "handleSurfaceRevealed\\(\\)" \
  "the reminder must be recorded only after the surface reveals."
require_pattern "${COORDINATOR_REL}" "markReminded\\(lapsed\\.uid, lapsed\\.expiredAt\\)" \
  "the reminder must be recorded against the lapse it announced."
# A user who touches a Pro feature is asking to renew and must never be muted.
reject_pattern "${COORDINATOR_REL}" "handleAction\\(action: FeatureGateAction\\)" \
  "the reminder must not intercept user-triggered gate actions."
require_pattern "${SHELL_PAGE_REL}" "renewalReminderCoordinator\\.handleSurfaceRevealed\\(\\)" \
  "the shell must report the gate reveal to the reminder owner."
require_pattern "${TAB_HOME_REL}" "resolveRenewalReminderCoordinator\\(\\)\\.scheduleEvaluation\\(\\)" \
  "the reminder must be evaluated at the shared prompt-evaluation point."

# The renewal sheet can complete a purchase without leaving the surface.
require_pattern "${GATE_REL}" "'purchase_plan'" \
  "the gate must expose an in-sheet purchase action."
require_pattern "${SHELL_PAGE_REL}" "startFeatureGatePurchase\\(\\)" \
  "the shell must own the in-sheet purchase flow."
require_pattern "${GATE_REL}" "AIRA_PRO_SELLABLE_IAP_PLANS" \
  "plan options must come from the IAP catalog, not local literals."

if [ "${failures}" -gt 0 ]; then
  exit 1
fi

echo "Pro renewal contract guard passed."
