const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const {
  FIREFOX_EXTENSION_ID,
  RELEASE_EDITION,
  getOfficialFirefoxPackageBasenames,
  prepareFirefoxStoreManifest,
  readReleaseMarkerFromDir,
} = require('./release-utils');

const root = path.resolve(__dirname, '..');
const buildDir = path.join(root, 'build', 'official');
const packWorkDir = path.join(root, '.tmp-firefox-official-pack');
const packageJsonPath = path.join(root, 'package.json');
const manifestFinalPath = path.join(root, 'public', 'manifest.final.json');
const verifyScript = path.join(root, 'scripts', 'verify-release.js');
const PLACEHOLDER_HOST = 'example.invalid';

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function assertReleaseVersionLocked() {
  const packageVersion = String(readJson(packageJsonPath).version || '');
  const manifest = readJson(manifestFinalPath);
  const manifestVersion = String(manifest.version || '');
  const manifestVersionName = String(manifest.version_name || '');
  if (!packageVersion || packageVersion !== manifestVersion || packageVersion !== manifestVersionName) {
    throw new Error(
      `Release version files are out of sync. package.json=${packageVersion || '(empty)'} `
      + `manifest.version=${manifestVersion || '(empty)'} `
      + `manifest.version_name=${manifestVersionName || '(empty)'}`
    );
  }
  return packageVersion;
}

function assertOfficialBuild(expectedVersion) {
  const manifestPath = path.join(buildDir, 'manifest.json');
  for (const requiredPath of [manifestPath, path.join(buildDir, 'history.html'), path.join(buildDir, 'history.js')]) {
    if (!fs.existsSync(requiredPath)) {
      throw new Error(`Missing Official build output: ${requiredPath}. Run npm run build:official first.`);
    }
  }
  const distributionPath = path.join(buildDir, '.aira-sync-distribution');
  const distribution = fs.existsSync(distributionPath)
    ? fs.readFileSync(distributionPath, 'utf8').trim().toLowerCase()
    : '';
  if (distribution !== 'official') {
    throw new Error(`Expected build/official, but distribution marker is "${distribution || '(missing)'}".`);
  }
  const edition = readReleaseMarkerFromDir(buildDir);
  if (edition !== RELEASE_EDITION) {
    throw new Error(`Expected final Official build, but release edition is "${edition || '(unknown)'}".`);
  }
  const manifest = readJson(manifestPath);
  if (String(manifest.version || '') !== expectedVersion) {
    throw new Error(
      `Official build version mismatch. Expected ${expectedVersion}, got ${manifest.version || '(empty)'}. `
      + 'Run npm run build:official again.'
    );
  }
  if (Object.prototype.hasOwnProperty.call(manifest, 'key')) {
    throw new Error('Official build must omit manifest.key so the Firefox package has no Chromium identity.');
  }
  if (!Object.prototype.hasOwnProperty.call(manifest.background || {}, 'service_worker')) {
    throw new Error('Official build must declare background.service_worker before Firefox packaging.');
  }
}

function collectInjectedHosts() {
  const assetsDir = path.join(buildDir, 'assets');
  if (!fs.existsSync(assetsDir)) return [];
  const hosts = new Set();
  for (const fileName of fs.readdirSync(assetsDir)) {
    if (!fileName.endsWith('.js')) continue;
    const source = fs.readFileSync(path.join(assetsDir, fileName), 'utf8');
    for (const match of source.matchAll(/https:\/\/[a-zA-Z0-9.-]+/g)) {
      hosts.add(match[0]);
    }
  }
  return Array.from(hosts).sort();
}

function warnOnPlaceholderRoutes() {
  const placeholderHosts = collectInjectedHosts().filter((host) => host.includes(PLACEHOLDER_HOST));
  if (placeholderHosts.length === 0) return;
  console.warn(
    '[pack] WARNING: this Official build carries placeholder service routes, so Aira sign-in and Aira cloud sync'
    + ' cannot work:'
  );
  for (const host of placeholderHosts) console.warn(`[pack]   ${host}`);
  console.warn('[pack] Rebuild with AIRA_SYNC_OFFICIAL_API_ROUTES set to the real hosted-service routes.');
}

function copyDir(source, target) {
  if (fs.existsSync(target)) fs.rmSync(target, { recursive: true, force: true });
  fs.cpSync(source, target, { recursive: true });
}

function packZip(cwd, outputPath) {
  if (fs.existsSync(outputPath)) fs.rmSync(outputPath, { force: true });
  execFileSync('zip', ['-qr', outputPath, '.'], { cwd, stdio: 'inherit' });
}

const version = assertReleaseVersionLocked();
assertOfficialBuild(version);
warnOnPlaceholderRoutes();

const { xpiFilename, zipFilename } = getOfficialFirefoxPackageBasenames(version);
const xpiPath = path.join(root, xpiFilename);
const zipPath = path.join(root, zipFilename);

console.log(`[pack] Firefox gecko identity locked: ${FIREFOX_EXTENSION_ID}`);
console.log(`[pack] Creating ${xpiFilename} and ${zipFilename}...`);

try {
  copyDir(buildDir, packWorkDir);
  const stagedManifest = prepareFirefoxStoreManifest(packWorkDir);
  console.log(`[pack] Firefox manifest permissions: ${stagedManifest.permissions.join(', ')}`);
  packZip(packWorkDir, zipPath);
  fs.copyFileSync(zipPath, xpiPath);
} finally {
  fs.rmSync(packWorkDir, { recursive: true, force: true });
}

console.log('[pack] Verifying Firefox Official package...');
execFileSync(process.execPath, [verifyScript, xpiPath, zipPath], { cwd: root, stdio: 'inherit' });
console.log(`[pack] Done: ${xpiFilename} (temporary install), ${zipFilename} (AMO upload)`);
