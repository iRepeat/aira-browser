#!/usr/bin/env node
'use strict';

// Download export ghost guard. When a custom download folder's grant is dead
// (app update or reboot clears folder authorization), the old export sequence
// left 0-byte shells in the user's folder while the real file fell back to the
// system download location: path-channel opens "succeed" by creating a
// file-manager-visible shell, the conflict rename retried under a second name,
// and cleanup skipped entries whose size could not be read at all.
//
// The fix has four invariants this scan locks in:
//   1. persistToDirectory probes verifyDirectoryWritable before it creates any
//      download file name in the folder.
//   2. verifyDirectoryWritable probes through the URI channel only, with real
//      bytes and a size check — never through a FileUri(...).path open.
//   3. openExportDestination refuses the path fallback for permission errors.
//   4. copyLocalPathWithoutOverwrite does not retry under a conflict name for
//      permission errors, and deleteZeroByteExport deletes unreadable-size
//      entries too (guard is `> 0`, not `!== 0`).
const fs = require('node:fs');
const path = require('node:path');

const SERVICE = path.resolve(
  __dirname, '../AiraBrowser/entry/src/main/ets/services/download/DownloadFileResolutionService.ets'
);
const DIRECTORY_SERVICE = path.resolve(
  __dirname, '../AiraBrowser/entry/src/main/ets/services/download/DownloadLocationDirectoryService.ets'
);
const DOWNLOAD_V2_SERVICE = path.resolve(
  __dirname, '../AiraBrowser/entry/src/main/ets/services/downloadv2/DownloadV2Service.ets'
);
const MODULE_CONFIG = path.resolve(
  __dirname, '../AiraBrowser/entry/src/main/module.json5'
);
const STRING_RESOURCE_ROOT = path.resolve(
  __dirname, '../AiraBrowser/entry/src/main/resources'
);

const failures = [];

function check(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

function extractMethod(source, name) {
  // Finds the method DEFINITION (a body in braces), skipping interface
  // declarations and call sites that share the name but end with `;` or are
  // plain invocations.
  let searchFrom = 0;
  while (searchFrom <= source.length) {
    const start = source.indexOf(`${name}(`, searchFrom);
    if (start < 0) {
      return undefined;
    }
    if (start > 0 && /[.\w]/.test(source[start - 1])) {
      // A call site such as `this.isPermissionError(` or an identifier that
      // merely ends with the name; keep looking for the definition.
      searchFrom = start + name.length;
      continue;
    }
    let depth = 0;
    let parenEnd = -1;
    for (let index = start + name.length; index < source.length; index += 1) {
      const char = source[index];
      if (char === '(') {
        depth += 1;
      } else if (char === ')') {
        depth -= 1;
        if (depth === 0) {
          parenEnd = index;
          break;
        }
      }
    }
    if (parenEnd < 0) {
      return undefined;
    }
    let cursor = parenEnd + 1;
    let bodyStart = -1;
    while (cursor < source.length) {
      const char = source[cursor];
      // A `;` before any `{` marks an interface or abstract declaration.
      if (char === ';') {
        break;
      }
      if (char === '{') {
        bodyStart = cursor;
        break;
      }
      cursor += 1;
    }
    if (bodyStart < 0) {
      searchFrom = start + name.length;
      continue;
    }
    let braceDepth = 0;
    for (let index = bodyStart; index < source.length; index += 1) {
      const char = source[index];
      if (char === '{') {
        braceDepth += 1;
      } else if (char === '}') {
        braceDepth -= 1;
        if (braceDepth === 0) {
          return source.slice(start, index + 1);
        }
      }
    }
    return undefined;
  }
  return undefined;
}

const service = fs.readFileSync(SERVICE, 'utf8');
const directoryService = fs.readFileSync(DIRECTORY_SERVICE, 'utf8');

const persistToDirectory = extractMethod(service, 'persistToDirectory');
check(persistToDirectory !== undefined, 'persistToDirectory not found in DownloadFileResolutionService.ets');
if (persistToDirectory !== undefined) {
  const probeIndex = persistToDirectory.indexOf('verifyDirectoryWritable');
  const copyIndex = persistToDirectory.indexOf('copyLocalPathWithoutOverwrite');
  check(
    probeIndex >= 0 && copyIndex > probeIndex,
    'persistToDirectory must probe verifyDirectoryWritable before any copyLocalPathWithoutOverwrite call'
  );
  check(
    /directory probe not writable/.test(persistToDirectory),
    'persistToDirectory must log a "directory probe not writable" fallback line'
  );
}

const openExport = extractMethod(service, 'openExportDestination');
check(openExport !== undefined, 'openExportDestination not found in DownloadFileResolutionService.ets');
if (openExport !== undefined) {
  const permissionIndex = openExport.indexOf('isPermissionError');
  const pathFallbackIndex = openExport.indexOf('resolvePathFromUri(targetUri)');
  check(
    permissionIndex >= 0 && pathFallbackIndex > permissionIndex,
    'openExportDestination must check isPermissionError before the resolvePathFromUri fallback'
  );
  const throwMatch = /throw\s+error\s+instanceof\s+Error/.test(openExport);
  check(throwMatch, 'openExportDestination must rethrow permission errors instead of opening by path');
}

const deleteZeroByte = extractMethod(service, 'deleteZeroByteExport');
check(deleteZeroByte !== undefined, 'deleteZeroByteExport not found in DownloadFileResolutionService.ets');
if (deleteZeroByte !== undefined) {
  check(
    /visibleSize > 0/.test(deleteZeroByte),
    'deleteZeroByteExport must keep guarding with `visibleSize > 0` so unreadable-size shells are unlinked'
  );
}

const copyWithoutOverwrite = extractMethod(service, 'copyLocalPathWithoutOverwrite');
check(copyWithoutOverwrite !== undefined, 'copyLocalPathWithoutOverwrite not found in DownloadFileResolutionService.ets');
if (copyWithoutOverwrite !== undefined) {
  const permissionIndex = copyWithoutOverwrite.indexOf('isPermissionError');
  const fallbackIndex = copyWithoutOverwrite.indexOf('resolveAvailableConflictTarget');
  check(
    permissionIndex >= 0 && fallbackIndex > permissionIndex,
    'copyLocalPathWithoutOverwrite must rethrow permission errors before any conflict-name retry'
  );
}

const isPermissionError = extractMethod(service, 'isPermissionError');
check(isPermissionError !== undefined, 'isPermissionError helper not found in DownloadFileResolutionService.ets');
if (isPermissionError !== undefined) {
  check(
    /13900001/.test(isPermissionError) && /13900012/.test(isPermissionError),
    'isPermissionError must classify 13900001 (EPERM) and 13900012 (EACCES)'
  );
}

const verifyWritable = extractMethod(directoryService, 'verifyDirectoryWritable');
check(verifyWritable !== undefined, 'verifyDirectoryWritable not found in DownloadLocationDirectoryService.ets');
if (verifyWritable !== undefined) {
  const openMatch = /await fileIo\.open\(\s*probeUri,/.test(verifyWritable);
  check(
    openMatch,
    'verifyDirectoryWritable must open the probe through the URI channel (fileIo.open(probeUri, ...)), not via FileUri(...).path'
  );
  check(
    /fileIo\.write\(file\.fd, DOWNLOAD_DIRECTORY_PROBE_PAYLOAD\)/.test(verifyWritable),
    'verifyDirectoryWritable must write probe bytes, not just create the file'
  );
  check(
    /stat\.size !== DOWNLOAD_DIRECTORY_PROBE_PAYLOAD\.length/.test(verifyWritable),
    'verifyDirectoryWritable must verify the written size before reporting the folder writable'
  );
}

// When the custom folder is bypassed the user must hear about it, and the
// manifest must keep persisted folder grants across reinstall where the
// system supports it (API 24+).
const downloadV2Service = fs.readFileSync(DOWNLOAD_V2_SERVICE, 'utf8');
check(
  /customDirectoryBypassed = true/.test(downloadV2Service),
  'persistFinishedDownload must mark the fallback result with customDirectoryBypassed = true'
);
check(
  /download_completed_custom_folder_unavailable/.test(downloadV2Service),
  'buildSavedLocationMessage must use download_completed_custom_folder_unavailable when the custom folder was bypassed'
);

const moduleConfig = fs.readFileSync(MODULE_CONFIG, 'utf8');
check(
  moduleConfig.includes('ohos.fileshare.supportPreservePersistentPermission'),
  'module.json5 must declare ohos.fileshare.supportPreservePersistentPermission so reinstall keeps folder grants'
);

for (const locale of ['base', 'zh_CN', 'zh_Hant', 'en_US']) {
  const resourcePath = path.join(STRING_RESOURCE_ROOT, locale, 'element', 'string.json');
  const resource = fs.readFileSync(resourcePath, 'utf8');
  check(
    resource.includes('"download_completed_custom_folder_unavailable"'),
    `string.json for ${locale} must carry download_completed_custom_folder_unavailable`
  );
}

if (failures.length > 0) {
  console.error('Download export ghost guard failed:');
  for (const failure of failures) {
    console.error(`  - ${failure}`);
  }
  process.exit(1);
}

console.log('Download export ghost guard passed.');
