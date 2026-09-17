// Contract check for the personal-server History field limits.
//
// WHY THIS EXISTS
// The History route in `src/routes/history-routes.js` caps the per-visit fields it accepts and
// rejects the *whole* exchange batch when one record exceeds a limit. Aira Browser's outbox drains
// oldest-first and only removes a row on acknowledgement, so a single record the route refuses is
// retried on every later sync and never leaves the queue: one page whose title exceeded the limit
// stopped History sync from ever completing. The client now caps each outbox payload to these limits
// before submitting (`normalizeHistorySyncMutationForTransport` in
// `AiraBrowser/entry/src/main/ets/common/models/HistorySyncModels.ets`).
//
// This check pins the server side of that contract: it proves the un-normalized payload is refused
// and the normalized one is accepted, so the two sides cannot silently drift apart.
//
// The normalizer below is a deliberate mirror of the client implementation. If the client limits
// change, change them here too.
//
// RUN
//   node scripts/check-history-field-limits.js
// Requires the same Node runtime as the server itself (the installed better-sqlite3 binary is built
// for one Node ABI; a mismatched runtime fails with ERR_DLOPEN_FAILED before this check can run).

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_ROOT = path.resolve(__dirname, '..');
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'aira-history-limits-'));
const port = 19000 + crypto.randomInt(4000);

const child = spawn(process.execPath, ['src/server.js'], {
  cwd: SERVER_ROOT,
  env: { ...process.env, AIRA_DATA_DIR: dataDir, AIRA_PORT: String(port), AIRA_HOST: '127.0.0.1' },
  stdio: ['ignore', 'pipe', 'inherit'],
});

let serverOutput = '';
child.stdout.on('data', (chunk) => { serverOutput += chunk; });

const baseUrl = `http://127.0.0.1:${port}`;

let passed = 0;
let failed = 0;

function check(name, condition, detail = '') {
  if (condition) {
    passed += 1;
    console.log(`  ok   ${name}`);
    return;
  }
  failed += 1;
  console.log(`  FAIL ${name}${detail ? ` (${detail})` : ''}`);
}

async function request(method, route, body, token) {
  const response = await fetch(baseUrl + route, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let parsed = null;
  try { parsed = await response.json(); } catch (_error) { parsed = null; }
  return { status: response.status, body: parsed };
}

async function waitForHealth() {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try {
      const response = await fetch(`${baseUrl}/health`);
      if (response.ok) return;
    } catch (_error) { /* not up yet */ }
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
  throw new Error(`server did not become healthy:\n${serverOutput}`);
}

// --- mirror of the client normalizer (HistorySyncModels.ets) --------------------------------
const TITLE_MAX = 2048;
const DEVICE_NAME_MAX = 128;
const REFERRER_MAX = 8192;
const SOURCE_MAX = 64;
const URL_MAX = 8192;
const VISIT_ID_MAX = 512;
const MUTATION_ID_MAX = 256;
const VISIT_ID_PATTERN = /^h1:[A-Za-z0-9._-]{1,160}:.+$/;

const capText = (value, max) => (value.length > max ? value.slice(0, max) : value);

function normalizeVisit(visit) {
  const visitId = visit.visitId.trim();
  if (visitId.length <= 0 || visitId.length > VISIT_ID_MAX || !VISIT_ID_PATTERN.test(visitId)) {
    return undefined;
  }
  const url = visit.url.trim();
  if (url.length <= 0 || url.length > URL_MAX) return undefined;
  return {
    ...visit,
    visitId,
    url,
    title: capText(visit.title, TITLE_MAX),
    referrer: capText(visit.referrer, REFERRER_MAX),
    deviceName: capText(visit.deviceName, DEVICE_NAME_MAX),
    source: capText(visit.source, SOURCE_MAX),
  };
}

function normalizeMutation(mutation) {
  const { mutationId } = mutation;
  if (mutationId.trim().length <= 0 || mutationId.length > MUTATION_ID_MAX) return undefined;
  if (mutation.kind === 'upsert_visit') {
    if (mutation.visit === undefined) return undefined;
    const visit = normalizeVisit(mutation.visit);
    return visit === undefined ? undefined : { mutationId, kind: mutation.kind, visit };
  }
  if (mutation.kind === 'delete_visit') {
    const visitId = (mutation.visitId ?? '').trim();
    const ok = visitId.length > 0 && visitId.length <= VISIT_ID_MAX && VISIT_ID_PATTERN.test(visitId);
    return ok ? { mutationId, kind: mutation.kind, visitId } : undefined;
  }
  if (mutation.kind === 'delete_range') {
    const url = (mutation.url ?? '').trim();
    return url.length > 0 && url.length <= URL_MAX
      ? { mutationId, kind: mutation.kind, url, startedAt: mutation.startedAt, endedAt: mutation.endedAt }
      : undefined;
  }
  if (mutation.kind === 'clear_before') {
    return { mutationId, kind: mutation.kind, clearBefore: mutation.clearBefore };
  }
  return undefined;
}

// --- the check -------------------------------------------------------------------------------
async function run() {
  try {
    await waitForHealth();

    const setupCode = fs.readFileSync(path.join(dataDir, 'setup-code'), 'utf8').trim();
    const pairing = await request('POST', '/v1/pairing/exchange', {
      code: setupCode, deviceId: 'limits-device-1', deviceName: 'Limits Check', deviceKind: 'phone',
    });
    const token = pairing.body.token;
    const clientId = 'limits-device-1';

    // The server advances its head and expires an old cursor, so track nextCursor like a real client.
    let cursor = 0;
    const exchange = async (mutations) => {
      const result = await request('POST', '/v1/sync/history/exchange', {
        clientId, cursor, pullLimit: 200, mutations,
      }, token);
      if (result.status === 200 && typeof result.body?.nextCursor === 'number') {
        cursor = result.body.nextCursor;
      }
      return result;
    };

    const visit = (overrides) => ({
      visitId: 'h1:limits-device-1:visit-1',
      clientId,
      nativeVisitId: 'visit-1',
      url: 'https://example.com/',
      title: 'short',
      visitedAt: Date.now(),
      transition: 'link',
      referrer: '',
      deviceName: 'Aira HarmonyOS',
      source: 'app',
      ...overrides,
    });

    console.log('\nover-long title (the reported failure)');
    const hugeTitle = 'a'.repeat(6000);
    const rawTitle = await exchange([
      { mutationId: 'raw-title', kind: 'upsert_visit', visit: visit({ title: hugeTitle }) },
    ]);
    check('un-normalized title is refused with history_field_too_long',
      rawTitle.status === 400 && rawTitle.body?.code === 'history_field_too_long',
      `status=${rawTitle.status} code=${rawTitle.body?.code}`);
    check('the refusal reads as the message the user saw',
      rawTitle.body?.message === '历史记录字段过长。', rawTitle.body?.message);

    const fixedTitle = await exchange([
      normalizeMutation({ mutationId: 'fixed-title', kind: 'upsert_visit', visit: visit({ title: hugeTitle }) }),
    ]);
    check('normalized title is accepted', fixedTitle.status === 200 &&
      fixedTitle.body?.acknowledgements?.length === 1, `status=${fixedTitle.status}`);

    console.log('\nan over-long record no longer blocks the records behind it');
    const batch = await exchange([
      normalizeMutation({
        mutationId: 'batch-1', kind: 'upsert_visit',
        visit: visit({ visitId: 'h1:limits-device-1:visit-2', nativeVisitId: 'visit-2', title: hugeTitle }),
      }),
      normalizeMutation({
        mutationId: 'batch-2', kind: 'upsert_visit',
        visit: visit({ visitId: 'h1:limits-device-1:visit-3', nativeVisitId: 'visit-3', title: '正常标题' }),
      }),
    ]);
    check('both records are acknowledged', batch.body?.acknowledgements?.length === 2,
      `acknowledged=${batch.body?.acknowledgements?.length}`);

    console.log('\nthe other field limits on the same route');
    for (const [label, patch] of [
      ['deviceName', { deviceName: 'd'.repeat(300) }],
      ['referrer', { referrer: 'https://example.com/' + 'r'.repeat(9000) }],
      ['source', { source: 's'.repeat(200) }],
    ]) {
      const raw = await exchange([{ mutationId: `raw-${label}`, kind: 'upsert_visit', visit: visit(patch) }]);
      const fixed = await exchange([normalizeMutation({ mutationId: `fixed-${label}`, kind: 'upsert_visit', visit: visit(patch) })]);
      check(`${label} refused raw, accepted normalized`,
        raw.status === 400 && fixed.status === 200, `raw=${raw.status}/${raw.body?.code} fixed=${fixed.status}`);
    }

    console.log('\na URL is withheld rather than truncated (a truncated URL names another page)');
    const longUrl = 'https://example.com/' + 'a'.repeat(9000);
    check('over-long URL is withheld by the normalizer',
      normalizeMutation({ mutationId: 'url', kind: 'upsert_visit', visit: visit({ url: longUrl }) }) === undefined);
    const rawUrl = await exchange([{ mutationId: 'raw-url', kind: 'upsert_visit', visit: visit({ url: longUrl }) }]);
    check('the server agrees the raw URL is invalid',
      rawUrl.status === 400 && rawUrl.body?.code === 'invalid_history_url',
      `status=${rawUrl.status} code=${rawUrl.body?.code}`);

    console.log('\nordinary in-limit history is unaffected');
    const normal = await exchange([
      normalizeMutation({
        mutationId: 'normal', kind: 'upsert_visit',
        visit: visit({ visitId: 'h1:limits-device-1:visit-9', nativeVisitId: 'visit-9', title: '示例标题' }),
      }),
    ]);
    check('in-limit record is accepted', normal.status === 200 &&
      normal.body?.acknowledgements?.length === 1, `status=${normal.status}`);
    const bootstrap = await request('POST', '/v1/sync/history/bootstrap', { clientId, pageLimit: 200 }, token);
    check('the stored title came back capped at the limit',
      (bootstrap.body?.visits ?? []).some((stored) => stored.title.length === TITLE_MAX));
  } finally {
    child.kill();
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

run()
  .then(() => {
    console.log(`\n${passed} passed, ${failed} failed`);
    process.exit(failed === 0 ? 0 : 1);
  })
  .catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
