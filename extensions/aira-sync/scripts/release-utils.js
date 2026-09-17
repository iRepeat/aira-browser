const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const crypto = require('crypto');

const RELEASE_EDITION = 'final';
const RELEASE_MARKER_FILE = '.release-edition';
const RELEASE_PACKAGE_BASENAME = 'aira-sync';
const COMMUNITY_RELEASE_PACKAGE_BASENAME = 'Aira-sync';
const COMMUNITY_MANIFEST_KEY = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvlMkYp7QrqMlAHhIKMXOP3WAhRXMmyEyZwsne4hy5m472qv7IXqCuGb2Zt4ZxCdCCUxs0DVQJEpoGLGlJi9HCIayKOjmyCunpLwqsX4vwjXwvRlNs50NesZ+UniYN6VmRJW+K9hdL/fZ93Y1wU7ZaYD5vMWiOg34ShaLVcyNiRjidxyJWSK2yX4yQ6PWhNg+fOsbaQJWgL9D/Ecw0Iay3mfY2vbaXLgJiDqMmoUX97gNzwZtVOM2s5PFjjvyc2FUCPNJq7u/DB7w6f8I6Ya3n1Jigbl9L+yhlEw/OU+Ld6Ps+HxOYdHLwhiCDWNrYpIdd7vD0HbJrY/da+wTIgPBQQIDAQAB';
const COMMUNITY_EXTENSION_ID = 'efehgppkhnkjamcpbipclfmmofdildji';
// Public manifest identity retained for Official manual-install updates.
const LOCAL_OFFICIAL_MANIFEST_KEY = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqjAoslU3RDPLkH+htp3PaoxQ9gIJaFTHp7ww9ALBpaiFk5vBXlbPMKOs1u1CCWi0t31aDWp59hd1yWYmnUgIJ2DDLkmRobM7I8jOXng8O9S1bLdjFK82lLTYVjHTaPWnWosw8ObtVJfCI1Q62S0p80DmHETLq1sn8/JrMxq8hJuaD1dxzV1sF+fZ1pZpzaNWMsXgxJXti8wg1dBFbGflCsMcOzhRw4fks97sSCbUbX+OaFmupMSLc+47ptYEdg8BgfGtlBnT1wJOA0jF4IgR7bzIG+VBgK4RvIVMjBVALpg+ZtLc3Kdn6gGpqkoDlF4pNU9PiHi4LToRLHOebNZW0QIDAQAB';
const LOCAL_OFFICIAL_EXTENSION_ID = 'plnjjlkaaonbccmjpfljbbbbaahfklem';
// Gecko identity of the existing addons.mozilla.org listing. AMO rejects any upload whose
// browser_specific_settings.gecko.id differs from the published add-on.
const FIREFOX_EXTENSION_ID = 'airatab@cc';
// Firefox has no counterpart for these Chromium-only manifest permissions.
const FIREFOX_UNSUPPORTED_PERMISSIONS = new Set(['permissions', 'favicon']);

// Firefox runs Manifest V3 through a non-persistent background page instead of a service worker,
// so the built background entry is declared as an ES module script.
function prepareFirefoxStoreManifest(dirPath) {
  const manifestPath = path.join(dirPath, 'manifest.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf-8'));
  delete manifest.key;
  manifest.permissions = Array.isArray(manifest.permissions)
    ? manifest.permissions.filter((permission) => !FIREFOX_UNSUPPORTED_PERMISSIONS.has(permission))
    : manifest.permissions;
  manifest.background = {
    scripts: ['background-sw.js'],
    type: 'module',
  };
  manifest.browser_specific_settings = {
    gecko: {
      id: FIREFOX_EXTENSION_ID,
      data_collection_permissions: {
        required: [
          'authenticationInfo',
          'bookmarksInfo',
          'browsingActivity',
        ],
      },
      strict_min_version: '142.0',
    },
  };
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  return manifest;
}

function detectReleaseEditionByManifest(manifest) {
  void manifest;
  return RELEASE_EDITION;
}

function readReleaseMarkerText(raw) {
  const normalized = String(raw || '').trim().toLowerCase();
  return normalized === RELEASE_EDITION ? RELEASE_EDITION : '';
}

function readReleaseMarkerFromDir(dirPath) {
  const markerPath = path.join(dirPath, RELEASE_MARKER_FILE);
  if (!fs.existsSync(markerPath)) return '';
  try {
    return readReleaseMarkerText(fs.readFileSync(markerPath, 'utf-8'));
  } catch {
    return '';
  }
}

function writeReleaseMarkerToDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
  fs.writeFileSync(path.join(dirPath, RELEASE_MARKER_FILE), `${RELEASE_EDITION}\n`);
}

function getCommunityReleasePackageFilename(version) {
  return `${COMMUNITY_RELEASE_PACKAGE_BASENAME}-v${version}.zip`;
}

function getLocalOfficialReleasePackageFilename(version) {
  return `Aira-Sync-Official-v${version}.zip`;
}

function getOfficialFirefoxPackageBasenames(version) {
  const stem = `Aira-Sync-Official-v${version}-firefox-store`;
  return { xpiFilename: `${stem}.xpi`, zipFilename: `${stem}.zip` };
}

function readReleaseMarkerFromZip(zipPath) {
  try {
    const output = execSync(`unzip -p "${zipPath}" ${RELEASE_MARKER_FILE}`, { encoding: 'utf-8' });
    return readReleaseMarkerText(output);
  } catch {
    return '';
  }
}

function computeExtensionIdFromManifestKey(manifestKey) {
  const compactKey = String(manifestKey || '').replace(/\s+/g, '');
  if (!compactKey) return '';
  const pem = [
    '-----BEGIN PUBLIC KEY-----',
    compactKey.match(/.{1,64}/g).join('\n'),
    '-----END PUBLIC KEY-----',
    '',
  ].join('\n');
  const der = crypto.createPublicKey(pem).export({ type: 'spki', format: 'der' });
  const hash = crypto.createHash('sha256').update(der).digest();
  return Array.from(hash.subarray(0, 16), (byte) => (
    String.fromCharCode(97 + (byte >> 4)) + String.fromCharCode(97 + (byte & 15))
  )).join('');
}

module.exports = {
  COMMUNITY_EXTENSION_ID,
  COMMUNITY_MANIFEST_KEY,
  LOCAL_OFFICIAL_EXTENSION_ID,
  LOCAL_OFFICIAL_MANIFEST_KEY,
  FIREFOX_EXTENSION_ID,
  RELEASE_EDITION,
  RELEASE_MARKER_FILE,
  RELEASE_PACKAGE_BASENAME,
  computeExtensionIdFromManifestKey,
  detectReleaseEditionByManifest,
  getCommunityReleasePackageFilename,
  getLocalOfficialReleasePackageFilename,
  getOfficialFirefoxPackageBasenames,
  prepareFirefoxStoreManifest,
  readReleaseMarkerFromDir,
  readReleaseMarkerFromZip,
  writeReleaseMarkerToDir,
};
