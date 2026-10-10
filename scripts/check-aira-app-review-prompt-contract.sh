#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
failures=0

fail() {
  printf 'App Review Prompt contract violation: %s\n' "$1" >&2
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

COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/review/AppReviewPromptCoordinator.ets"
REPOSITORY_REL="AiraBrowser/entry/src/main/ets/data/review/AppReviewPromptRepository.ets"
SERVICE_REL="AiraBrowser/entry/src/main/ets/services/system/SystemSettingsLaunchService.ets"
TEST_REL="AiraBrowser/entry/src/test/AppReviewPromptCoordinator.test.ets"

# The automatic prompt is a background nicety: a dialog that cannot open must stay silent,
# because the affected user often cannot fix anything (already reviewed, not signed in).
reject_pattern "${COORDINATOR_REL}" "showToast" \
  "the automatic review prompt must not surface failure toasts; only the manual settings entry reports errors."

# A failed dialog launch must write state back, otherwise every return to home re-triggers
# the same failing call and spams the user (the reported regression).
require_pattern "${COORDINATOR_REL}" "recordSystemPromptFailure\(result\.errorCode\)" \
  "a failed system dialog launch must be recorded so the prompt backs off."
require_pattern "${COORDINATOR_REL}" "await this\.recordSystemPromptFailure\(undefined\)" \
  "an unexpected launch throw must also be recorded so the prompt backs off."
require_pattern "${COORDINATOR_REL}" "APP_REVIEW_ALREADY_COMMENTED_ERROR_CODES" \
  "already-commented AppGallery errors must map to an accepted invitation."
require_pattern "${COORDINATOR_REL}" "1021500007.*1021500008.*1021500009|1021500007" \
  "the already-commented AppGallery error codes (1021500007/1021500008/1021500009) must stay listed."

# The failure cooldown rides on lastPromptAt; without it the loop returns.
require_pattern "${REPOSITORY_REL}" "async markPromptAttemptFailed" \
  "markPromptAttemptFailed must record a failed dialog launch."
require_pattern "${REPOSITORY_REL}" "lastAction = 'failed'" \
  "the failed attempt must be distinguishable in the stored last action."
require_pattern "${REPOSITORY_REL}" "value === 'failed'" \
  "the 'failed' last action must survive state normalization."

# The service must surface the AppGallery error code so policy can tell already-commented
# users apart from transient failures.
require_pattern "${SERVICE_REL}" "errorCode: \(error as BusinessError\)\.code" \
  "showAppReviewPrompt must surface the AppGallery BusinessError code."

# A manual rate-invitation open counts as accepting the invitation for this version.
require_pattern "${SERVICE_REL}" "sharedAppReviewPromptRepository\.accept\(this\.resolveCurrentVersionName\(\)\)" \
  "opening the manual review flow must record an accepted invitation."

# The regression tests must pin the back-off and the already-commented mapping.
require_pattern "${TEST_REL}" "does not retry per home visit" \
  "the test must pin that a failed launch is not retried on every home return."
require_pattern "${TEST_REL}" "already-commented errors as an accepted invitation" \
  "the test must pin that already-commented errors stop future prompts."

if [ "${failures}" -gt 0 ]; then
  exit 1
fi

echo "App Review Prompt contract guard passed."
