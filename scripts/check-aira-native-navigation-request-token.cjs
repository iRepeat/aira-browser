const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

// Opening a URL from a bookmark / history / offline / userscript surface goes through
// `requestOpenBrowserUrlWithRouteParams`: it stages the request in an in-memory queue AND returns route params
// for `router.back`. The shell consumes the in-memory copy first, and `router.getParams()` keeps returning the
// route copy for the whole page lifetime — so unless the in-memory copy carries the same token, the route copy
// is consumed again on every later page-show. That re-opened the bookmarked URL and replaced whatever page the
// tab had since navigated to, which users saw as "the page jumps back after a background/foreground round
// trip". Typing an address does not use this path, which is why that never reproduced.
const repoRoot = path.resolve(__dirname, '..');
const centerPath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/core/navigation/BrowserNativeNavigationRequestCenter.ets');
const consumePath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/core/navigation/BrowserNativeNavigationConsumeCoordinator.ets');
const center = fs.readFileSync(centerPath, 'utf8');
const consume = fs.readFileSync(consumePath, 'utf8');

function fnBody(source, signature) {
  const start = source.indexOf(signature);
  assert.ok(start >= 0, `Missing function: ${signature}`);
  // Default parameter values contain `{}`, so the body starts at the first `{` after the parameter list closes.
  const paramsEnd = source.indexOf('):', start);
  assert.ok(paramsEnd > start, `Missing parameter list end: ${signature}`);
  const openBrace = source.indexOf('{', paramsEnd);
  assert.ok(openBrace > paramsEnd, `Missing body: ${signature}`);
  let depth = 0;
  for (let index = openBrace; index < source.length; index += 1) {
    const character = source[index];
    if (character === '{') {
      depth += 1;
    } else if (character === '}') {
      depth -= 1;
      if (depth === 0) {
        return source.slice(start, index + 1);
      }
    }
  }
  assert.fail(`Unbalanced body: ${signature}`);
}

const withRouteParams = fnBody(center, 'export function requestOpenBrowserUrlWithRouteParams(');
const consumeWithFallback = fnBody(center, 'export function consumePendingBrowserNavigationRequestWithRouteFallback(');

test('the in-memory and route copies of one request share a token', () => {
  assert.ok(
    center.includes('routeToken?: string;'),
    'a pending navigation request must be able to carry the route token it was staged with'
  );
  assert.ok(
    withRouteParams.includes('const routeParams = buildBrowserNavigationRouteParams(') &&
      withRouteParams.includes('requestOpenBrowserUrl(url, intent, title, source, boundary, routeParams.openToken)'),
    'staging the request and building the route params must use one shared token'
  );
});

test('consuming the in-memory copy retires the route copy too', () => {
  assert.ok(
    consumeWithFallback.includes('routeToken: memoryRequest.routeToken ??') ,
    'the memory consume path must report the shared token so the route copy is recorded as consumed'
  );
  assert.ok(
    consume.includes('if (request.url.trim().length > 0 && consumeResult.routeToken.length > 0) {') &&
      consume.includes('this.host.setConsumedRouteToken(consumeResult.routeToken);'),
    'the consume coordinator must retire any token it was handed'
  );
});

console.log('Native navigation request token contract passed.');
