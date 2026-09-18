#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
failures=0

fail() {
  printf 'New User Gift contract violation: %s\n' "$1" >&2
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

# Verifies a line matches and a following line also matches, which grep -E alone
# cannot express because it matches one line at a time.
require_adjacent() {
  local rel_path="$1"
  local first_pattern="$2"
  local next_pattern="$3"
  local message="$4"
  if ! grep -EA1 "${first_pattern}" "${REPO_ROOT}/${rel_path}" | grep -Eq "${next_pattern}"; then
    fail "${message}"
  fi
}

GIFT_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/membership/AiraNewUserGiftFunctionService.ets"
STATE_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/membership/AiraMembershipStateFunctionService.ets"
MODEL_REL="AiraBrowser/entry/src/main/ets/common/models/MembershipModels.ets"
REPOSITORY_REL="AiraBrowser/entry/src/main/ets/data/membership/NewUserGiftRepository.ets"
COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/membership/NewUserGiftCoordinator.ets"
SIGNAL_REL="AiraBrowser/entry/src/main/ets/core/membership/NewUserGiftRefreshSignal.ets"
SHEET_REL="AiraBrowser/entry/src/main/ets/app/components/membership/NewUserGiftSheet.ets"
FEATURE_REL="AiraBrowser/entry/src/main/ets/features/membership/MembershipFeature.ets"
PRIVACY_REL="AiraBrowser/entry/src/main/ets/services/privacy/BrowserPrivacyEffectPolicyService.ets"
TRANSIENT_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTransientSurfaceCoordinator.ets"
SHELL_BACK_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserShellBackCoordinator.ets"
SHELL_PAGE_REL="AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets"
RUNTIME_REL="AiraBrowser/entry/src/main/ets/app/bootstrap/BrowserAppRuntime.ets"
ADR_REL="docs/adr/0077-new-user-gift-is-server-authoritative-and-automatically-granted.md"

for rel_path in "${GIFT_SERVICE_REL}" "${STATE_SERVICE_REL}" "${MODEL_REL}" "${REPOSITORY_REL}" \
  "${COORDINATOR_REL}" "${SIGNAL_REL}" "${SHEET_REL}" "${FEATURE_REL}" "${PRIVACY_REL}" \
  "${TRANSIENT_REL}" "${SHELL_BACK_REL}" "${SHELL_PAGE_REL}" "${RUNTIME_REL}" "${ADR_REL}"; do
  if [ ! -f "${REPO_ROOT}/${rel_path}" ]; then
    fail "missing ${rel_path}"
  fi
done

# The grant is server-issued and never conditional on the user pressing the
# prompt button: a local grant would be overwritten by the next authoritative
# membership read, and a gated grant would withhold an entitlement the product
# promises to every new account.
require_pattern "${GIFT_SERVICE_REL}" "AIRA_HOSTED_API_BASE_URL \\+ '/membership/new-user-gift'" \
  "the grant must be requested from the hosted new-user-gift endpoint, not minted locally."
require_pattern "${GIFT_SERVICE_REL}" "isAvailable\\('aira_cloud'\\)" \
  "the grant path must fail closed when the Aira Cloud capability is unavailable."
require_pattern "${GIFT_SERVICE_REL}" "getCurrentAccessTokenForUid\\(normalizedUid, false\\)" \
  "the grant request must carry the account access token."
require_pattern "${GIFT_SERVICE_REL}" "ensureNewUserGift\\(uid: string\\)" \
  "the grant request must be an idempotent ensure, safe to retry."

# The prompt is presentation only; it never decides whether the user receives
# the month of Pro.
require_pattern "${COORDINATOR_REL}" "class NewUserGiftCoordinator" \
  "the gift must keep one presentation narrative owner."
require_pattern "${COORDINATOR_REL}" "'new_user_gift'" \
  "the coordinator must present through the fixed transient surface."
require_pattern "${COORDINATOR_REL}" "private async ensureGrant" \
  "the coordinator must nudge the idempotent grant before announcing it."
require_pattern "${COORDINATOR_REL}" "export type NewUserGiftAction = 'dismiss'" \
  "the prompt is an announcement; its only action is to dismiss it."
require_pattern "${COORDINATOR_REL}" "handleSurfaceRevealed\\(\\)" \
  "the announcement must be acknowledged only once the surface actually reveals."
require_pattern "${COORDINATOR_REL}" "markAcknowledged\\(uid\\)" \
  "the announcement must be recorded as acknowledged so it shows once."
# A custom bottom surface mounts asynchronously, so the reveal guard must key off
# this coordinator's own presentation generation and the visible snapshot. A
# guard that rejects the visible snapshot abandons every presentation.
require_pattern "${COORDINATOR_REL}" "presentationGeneration === this\\.presentationGeneration && this\\.snapshot\\.visible" \
  "the reveal guard must require the published visible snapshot, not reject it."
require_pattern "${SHELL_PAGE_REL}" "handleSurfaceRevealed\\(\\)" \
  "the shell must acknowledge the announcement when the surface reveals."
require_pattern "${REPOSITORY_REL}" "acknowledgedAt" \
  "the local record stores only that the announcement was seen."
reject_pattern "${REPOSITORY_REL}" "claimedAt|grantedByUser|localGrant" \
  "the local record must not model claiming or a locally granted entitlement."

# The grant comes only from the service response, and the descriptor is
# discarded when the resolved account changes.
require_pattern "${STATE_SERVICE_REL}" "newUserGift\\?: AiraNewUserGiftStateRecord \\| null" \
  "the membership state response must carry the server-owned gift descriptor."
require_pattern "${FEATURE_REL}" "this\\.newUserGift\\.uid !== uid" \
  "gift state must be discarded when the resolved account changes."
require_pattern "${FEATURE_REL}" "ensureNewUserGift\\(boundaryInput: BrowserDataBoundaryInput\\)" \
  "the feature must own the grant entry point."
require_pattern "${FEATURE_REL}" "isCurrentAccountScope\\(accountScope\\)" \
  "the grant commit must be guarded by the account scope it started with."
require_pattern "${FEATURE_REL}" "buildStateFromGrant\\(accountState, response\\.membershipGrant" \
  "the granted plan must come from the service response, never a local literal."

# Claiming/granting is a separately classified privacy effect so a Private
# Browsing Session cannot perform the remote account mutation.
require_pattern "${PRIVACY_REL}" "intent: 'membership_gift_grant'" \
  "the grant must be a separately classified privacy effect."
require_adjacent "${PRIVACY_REL}" "intent: 'membership_gift_grant'," \
  "classification: 'remote_account_sync_mutation'" \
  "the grant writes remote account state and must be classified as such."
require_pattern "${FEATURE_REL}" "isEffectAllowed\\('membership_gift_grant'" \
  "the feature must gate the grant on the privacy effect decision."

# Shell integration is registration plus a signal, never policy.
require_pattern "${TRANSIENT_REL}" "'new_user_gift'" \
  "the transient surface coordinator must know the gift surface."
require_pattern "${SHELL_BACK_REL}" "'dismiss_new_user_gift'" \
  "back must dismiss the gift announcement."
require_pattern "${SIGNAL_REL}" "AIRA_NEW_USER_GIFT_REVISION_KEY" \
  "the account identity change must be observable as one signal."
require_pattern "${SHELL_PAGE_REL}" "handleNewUserGiftRefreshSignal" \
  "the shell must re-evaluate the gift when the identity signal bumps."
reject_pattern "${SHELL_PAGE_REL}" "eligible: true|grantedAt: 1|grantDays: 30" \
  "the shell must not decide gift eligibility or grant values."
require_pattern "${RUNTIME_REL}" "sharedNewUserGiftRepository" \
  "the gift repository must be a runtime singleton."

if [ "${failures}" -gt 0 ]; then
  exit 1
fi

echo "New User Gift contract guard passed."
