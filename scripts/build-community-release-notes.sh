#!/usr/bin/env bash
#
# Builds the GitHub release notes for a Community release, and can publish and
# verify them.
#
# A Community release body carries install instructions, the artifact record, and
# the changelog. The changelog part must be the *current* version's section only:
# pasting the whole `community-changelog.md` buries the new release under every
# version that shipped before it. This script extracts the one section, refuses to
# run when the HAP, the app config and the changelog disagree on the version, and
# can re-check an already published release body.
#
# Usage:
#   scripts/build-community-release-notes.sh [--hap <path>] [--out <path>]
#   scripts/build-community-release-notes.sh --publish [--tag <tag>] [--hap <path>]
#   scripts/build-community-release-notes.sh --verify <tag>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_CONFIG="${REPO_ROOT}/AiraBrowser/AppScope/app.json5"
COMMUNITY_CHANGELOG="${REPO_ROOT}/AiraBrowser/entry/src/main/resources/rawfile/community-changelog.md"
DEFAULT_HAP="${REPO_ROOT}/AiraBrowser/entry/build/default/outputs/default/entry-default-unsigned.hap"
RELEASE_STAGING_DIR="${REPO_ROOT}/dist/packages"
NOTES_DIR="${REPO_ROOT}/.tmp/community-release"
COMMUNITY_BUNDLE_NAME="org.aira.browser"
COMMUNITY_BUILD_COMMAND="AIRA_DISTRIBUTION=community AIRA_ALLOW_UNSIGNED_BUILD=1 SKIP_INSTALL=1 ./scripts/build-aira-browser.sh"

fail() {
  printf 'Community release notes: %s\n' "$1" >&2
  exit 1
}

command -v node >/dev/null 2>&1 || fail "node is required (see .nvmrc)."

MODE="generate"
VERIFY_TAG=""
PUBLISH=0
TAG=""
HAP_PATH="${DEFAULT_HAP}"
OUT_PATH=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --hap)
      [ "$#" -ge 2 ] || fail "--hap needs a path."
      HAP_PATH="$2"
      shift 2
      ;;
    --out)
      [ "$#" -ge 2 ] || fail "--out needs a path."
      OUT_PATH="$2"
      shift 2
      ;;
    --tag)
      [ "$#" -ge 2 ] || fail "--tag needs a tag."
      TAG="$2"
      shift 2
      ;;
    --publish)
      MODE="publish"
      PUBLISH=1
      shift
      ;;
    --verify)
      [ "$#" -ge 2 ] || fail "--verify needs a release tag."
      MODE="verify"
      VERIFY_TAG="$2"
      shift 2
      ;;
    -h|--help)
      awk 'NR >= 3 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

# Reads the app identity the release must carry. The changelog, the HAP and this
# config are three independent copies of one version, and a release is only
# coherent when all three agree.
read_app_version() {
  node - "${APP_CONFIG}" <<'NODE'
const fs = require('fs');
const source = fs.readFileSync(process.argv[2], 'utf8');
const appConfig = new Function(`return (${source});`)();
const versionName = `${appConfig.app?.versionName ?? ''}`.trim();
const versionCode = `${appConfig.app?.versionCode ?? ''}`.trim();
if (versionName.length === 0 || versionCode.length === 0) {
  throw new Error(`Could not read app.versionName / app.versionCode from ${process.argv[2]}`);
}
process.stdout.write(`${versionName} ${versionCode}`);
NODE
}

read_hap_module_json() {
  local hap_path="$1"
  if command -v unzip >/dev/null 2>&1; then
    unzip -p "${hap_path}" module.json 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys,zipfile;sys.stdout.write(zipfile.ZipFile(sys.argv[1]).read("module.json").decode("utf-8"))' \
      "${hap_path}" 2>/dev/null || true
  else
    fail "unzip or python3 is required to read ${hap_path}."
  fi
}

read_hap_identity() {
  read_hap_module_json "$1" | node -e '
let raw = "";
process.stdin.on("data", (chunk) => { raw += chunk; });
process.stdin.on("end", () => {
  const moduleJson = JSON.parse(raw);
  const app = moduleJson.app || {};
  process.stdout.write(`${app.bundleName || ""} ${app.versionName || ""} ${app.versionCode || ""}`);
});
'
}

# Prints the newest `## <versionName> (<versionCode>)` section of the changelog,
# stopping at the next `## ` heading, so a release body can only ever carry one.
read_current_changelog_section() {
  node - "${COMMUNITY_CHANGELOG}" <<'NODE'
const fs = require('fs');
const path = process.argv[2];
const lines = fs.readFileSync(path, 'utf8').split(/\r?\n/);
const startIndex = lines.findIndex((line) => /^##\s+/.test(line.trim()));
if (startIndex < 0) {
  throw new Error(`${path} has no "## <versionName> (<versionCode>)" section.`);
}
let endIndex = lines.length;
for (let index = startIndex + 1; index < lines.length; index += 1) {
  if (/^##\s+/.test(lines[index].trim())) {
    endIndex = index;
    break;
  }
}
process.stdout.write(lines.slice(startIndex, endIndex).join('\n').trim());
NODE
}

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

# A published body is correct when the `更新日志` section holds exactly one version
# heading, that heading is the release's own version, and the section has bullets.
verify_body() {
  local tag="$1"
  command -v gh >/dev/null 2>&1 || fail "gh is required for --verify."
  local release_json
  release_json="$(gh release view "${tag}" --json name,body,url,assets)" ||
    fail "Could not read release ${tag} through gh."
  node - "${release_json}" "${tag}" <<'NODE'
const release = JSON.parse(process.argv[2]);
const tag = process.argv[3];
const body = `${release.body ?? ''}`;
const lines = body.split(/\r?\n/);
const headings = lines.filter((line) => /^#\s+/.test(line));
const changelogIndex = lines.findIndex((line) => /^##\s+更新日志\s*$/.test(line.trim()));
const problems = [];
if (changelogIndex < 0) {
  problems.push('the body has no "## 更新日志" section');
}
const sectionLines = changelogIndex < 0 ? [] : lines.slice(changelogIndex + 1);
const versionHeadings = sectionLines
  .filter((line) => /^#{2,4}\s+\d+\.\d+\.\d+\s*[（(]\s*\d+\s*[)）]\s*$/.test(line.trim()))
  .map((line) => line.trim());
if (versionHeadings.length === 0) {
  problems.push('the changelog section has no "<versionName> (<versionCode>)" heading');
} else if (versionHeadings.length > 1) {
  problems.push(`the changelog section lists ${versionHeadings.length} versions: ${versionHeadings.join(', ')}`);
}
const titleVersion = /(\d+\.\d+\.\d+)\s*[（(]\s*(\d+)\s*[)）]/.exec(`${release.name ?? ''}`);
if (versionHeadings.length === 1 && titleVersion !== null) {
  const expected = `${titleVersion[1]} (${titleVersion[2]})`;
  const actual = versionHeadings[0].replace(/^#+\s+/, '').replace(/[（(]/g, ' (').replace(/[)）]/g, ')').replace(/\s+/g, ' ').trim();
  if (actual !== expected) {
    problems.push(`the changelog section says ${actual} while the release title says ${expected}`);
  }
}
const items = sectionLines.filter((line) => line.trim().startsWith('- ')).length;
if (items === 0) {
  problems.push('the changelog section has no bullet items');
}
const assets = Array.isArray(release.assets) ? release.assets : [];
if (assets.length === 0) {
  problems.push('the release carries no asset');
}
if (problems.length > 0) {
  console.error(`Community release notes: release ${tag} is not publishable:`);
  problems.forEach((problem) => console.error(`  - ${problem}`));
  process.exit(1);
}
console.log(`Checked release ${tag}: one version section (${versionHeadings[0].replace(/^#+\s+/, '')}), ${items} items, ${assets.length} asset(s).`);
console.log(`  headings: ${headings.map((line) => line.trim()).join(' | ')}`);
console.log(`  url: ${release.url ?? ''}`);
NODE
}

if [ "${MODE}" = "verify" ]; then
  verify_body "${VERIFY_TAG}"
  exit 0
fi

read -r APP_VERSION_NAME APP_VERSION_CODE <<<"$(read_app_version)"
[ -n "${APP_VERSION_NAME}" ] && [ -n "${APP_VERSION_CODE}" ] ||
  fail "Could not resolve the app version from ${APP_CONFIG}."

[ -f "${HAP_PATH}" ] ||
  fail "HAP not found at ${HAP_PATH}. Build it first: ${COMMUNITY_BUILD_COMMAND}"
HAP_IDENTITY="$(read_hap_identity "${HAP_PATH}" 2>/dev/null || true)"
[ -n "${HAP_IDENTITY}" ] ||
  fail "${HAP_PATH} is not a readable HAP with a module.json; pass the built Community HAP."
read -r HAP_BUNDLE_NAME HAP_VERSION_NAME HAP_VERSION_CODE <<<"${HAP_IDENTITY}"
[ "${HAP_BUNDLE_NAME}" = "${COMMUNITY_BUNDLE_NAME}" ] ||
  fail "${HAP_PATH} is ${HAP_BUNDLE_NAME}; a Community release must be ${COMMUNITY_BUNDLE_NAME}."
[ "${HAP_VERSION_NAME}" = "${APP_VERSION_NAME}" ] && [ "${HAP_VERSION_CODE}" = "${APP_VERSION_CODE}" ] ||
  fail "${HAP_PATH} is ${HAP_VERSION_NAME} (${HAP_VERSION_CODE}) while ${APP_CONFIG} is ${APP_VERSION_NAME} (${APP_VERSION_CODE})."

CHANGELOG_SECTION="$(read_current_changelog_section)" ||
  fail "Could not read the current section of $(basename "${COMMUNITY_CHANGELOG}") (see the error above)."
[ -n "${CHANGELOG_SECTION}" ] ||
  fail "$(basename "${COMMUNITY_CHANGELOG}") has no readable current section."
CHANGELOG_HEADING="$(printf '%s\n' "${CHANGELOG_SECTION}" | sed -n '1p' | sed 's/^##[[:space:]]*//')"
EXPECTED_HEADING="${APP_VERSION_NAME} (${APP_VERSION_CODE})"
[ "${CHANGELOG_HEADING}" = "${EXPECTED_HEADING}" ] ||
  fail "the newest section of $(basename "${COMMUNITY_CHANGELOG}") is '${CHANGELOG_HEADING}' while the app is ${EXPECTED_HEADING}. Add the current version's section first."

VERSION_HEADING_COUNT="$(printf '%s\n' "${CHANGELOG_SECTION}" | grep -cE '^#{2,4}[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+' || true)"
[ "${VERSION_HEADING_COUNT}" = "1" ] ||
  fail "the current changelog section carries ${VERSION_HEADING_COUNT} version headings; exactly one version may appear."

ITEM_COUNT="$(printf '%s\n' "${CHANGELOG_SECTION}" | grep -c '^- ' || true)"
[ "${ITEM_COUNT}" -ge 1 ] ||
  fail "the current changelog section has no bullet items."

SUMMARY_LINE="$(printf '%s\n' "${CHANGELOG_SECTION}" | grep -vE '^(##|- |[0-9]{4}-[0-9]{2}-[0-9]{2})' | grep -v '^$' | sed -n '1p')"
[ -n "${SUMMARY_LINE}" ] ||
  fail "the current changelog section has no summary line above its bullets."

if [ -z "${OUT_PATH}" ]; then
  OUT_PATH="${NOTES_DIR}/RELEASE_NOTES_${APP_VERSION_NAME}_${APP_VERSION_CODE}.md"
fi
mkdir -p "$(dirname "${OUT_PATH}")"

ASSET_NAME="Aira-community-v${APP_VERSION_NAME}-${APP_VERSION_CODE}-default-unsigned.hap"
ASSET_PATH="${RELEASE_STAGING_DIR}/${ASSET_NAME}"
if [ ! -f "${ASSET_PATH}" ]; then
  mkdir -p "${RELEASE_STAGING_DIR}"
  cp "${HAP_PATH}" "${ASSET_PATH}"
fi
ASSET_SHA256="$(sha256_of "${ASSET_PATH}")"

RELEASE_TITLE="Aira Community ${APP_VERSION_NAME} (${APP_VERSION_CODE})"
if [ -z "${TAG}" ]; then
  TAG="v${APP_VERSION_NAME}"
fi

# The changelog is demoted one level so the body keeps `## 安装 / ## 产物 /
# ## 更新日志` as its own sections.
SECTION_FOR_BODY="$(printf '%s\n' "${CHANGELOG_SECTION}" | sed 's/^##[[:space:]]/### /')"

{
  printf '# %s\n\n' "${RELEASE_TITLE}"
  printf '这是 **Community 未签名 HAP**，包名 `%s`。不是华为应用市场里的 Official 商店包（`com.aira.browser`）。\n\n' "${COMMUNITY_BUNDLE_NAME}"
  printf '下载后需要你自己用 `%s` 的 HarmonyOS 签名材料签名，再侧载安装。未签名包不能直接装到设备上。\n\n' "${COMMUNITY_BUNDLE_NAME}"
  printf '## 安装\n\n'
  printf '1. 用 DevEco Studio 打开本仓库的 `AiraBrowser/`，为 `%s` 配置你自己的签名。\n' "${COMMUNITY_BUNDLE_NAME}"
  printf '2. 对这个 HAP 签名（DevEco 或 HarmonyOS `hap-sign-tool`）。\n'
  printf '3. 用 `hdc` 安装到已开启开发者调试的设备。\n\n'
  printf 'Community 默认没有官方云、华为账号、华为云空间和 IAP。本地浏览、WebDAV 和自建 Personal Server 可用。\n\n'
  printf '## 产物\n\n'
  printf -- '- 文件：`%s`\n' "${ASSET_NAME}"
  printf -- '- 包名：`%s`\n' "${COMMUNITY_BUNDLE_NAME}"
  printf -- '- versionName：`%s`\n' "${APP_VERSION_NAME}"
  printf -- '- versionCode：`%s`\n' "${APP_VERSION_CODE}"
  printf -- '- SHA-256：`%s`\n\n' "${ASSET_SHA256}"
  printf '## 更新日志\n\n'
  printf '%s\n' "${SECTION_FOR_BODY}"
} > "${OUT_PATH}"

printf 'Release notes: %s\n' "${OUT_PATH}"
printf 'Asset: %s (%s)\n' "${ASSET_NAME}" "${ASSET_SHA256}"
printf 'Title: %s\n' "${RELEASE_TITLE}"
printf 'Tag: %s\n' "${TAG}"

if [ "${PUBLISH}" = "1" ]; then
  command -v gh >/dev/null 2>&1 || fail "gh is required for --publish."
  if gh release view "${TAG}" >/dev/null 2>&1; then
    fail "Release ${TAG} already exists. Move it with gh release edit/upload instead of re-creating it."
  fi
  gh release create "${TAG}" \
    --title "${RELEASE_TITLE}" \
    --notes-file "${OUT_PATH}" \
    "${ASSET_PATH}"
  # The published body is what readers and the in-app update notice see, so it is
  # checked after upload rather than trusted from the file on disk.
  verify_body "${TAG}"
else
  printf '\nPublish with:\n  gh release create %s --title "%s" --notes-file %s %s\n' \
    "${TAG}" "${RELEASE_TITLE}" "${OUT_PATH}" "${ASSET_PATH}"
  printf 'Then check the published body with:\n  %s --verify %s\n' "${BASH_SOURCE[0]}" "${TAG}"
fi
