// ==UserScript==
// @name         Aira 覆盖更新测试
// @namespace    aira.overwrite.test
// @version      1.0.0
// @description  本地覆盖更新测试用脚本。旧版：先安装这一个，再用新版文件覆盖导入。
// @match        *://*/*
// @grant        GM_getValue
// @grant        GM_setValue
// @updateURL    https://community.invalid/aira-overwrite-test.meta.js
// @downloadURL  https://community.invalid/aira-overwrite-test.user.js
// ==/UserScript==

// 这是覆盖更新测试的「旧版」，与新版共用同一 @name + @namespace，因此会被识别为
// 同一个脚本、走覆盖替换而不是新增。它带 @updateURL/@downloadURL，新版故意不带，
// 用来确认覆盖后更新地址仍被保留。
(function () {
  'use strict';

  if (window.__airaOverwriteTestMounted === true) {
    return;
  }
  window.__airaOverwriteTestMounted = true;

  var VERSION = '1.0.0';
  var STORAGE_KEY = 'aira-overwrite-test-installed-at';
  var BADGE_ID = 'aira-overwrite-test-badge';

  function readInstalledAt() {
    try {
      if (typeof GM_getValue === 'function') {
        return String(GM_getValue(STORAGE_KEY, ''));
      }
    } catch (_error) {
    }
    return '';
  }

  // 只在首次运行时写入，之后覆盖安装不应改动这个时间，用来确认脚本保存的数据没被清掉。
  function rememberInstalledAt() {
    try {
      if (typeof GM_setValue === 'function' && readInstalledAt().length === 0) {
        GM_setValue(STORAGE_KEY, new Date().toISOString());
      }
    } catch (_error) {
    }
  }

  function mountBadge() {
    if (document.getElementById(BADGE_ID) !== null) {
      return;
    }
    var badge = document.createElement('div');
    var installedAt = readInstalledAt();
    badge.id = BADGE_ID;
    badge.textContent = '覆盖更新测试 · 旧版 v' + VERSION +
      (installedAt.length > 0 ? ' · 首次安装 ' + installedAt : '') + ' · 点此隐藏';
    badge.title = 'Aira 本地覆盖更新测试脚本（旧版）';
    badge.style.cssText = [
      'position:fixed',
      'right:12px',
      'bottom:12px',
      'z-index:2147483647',
      'max-width:80vw',
      'padding:8px 12px',
      'border-radius:8px',
      'background:#b3261e',
      'color:#ffffff',
      'font:12px/1.5 -apple-system,BlinkMacSystemFont,"HarmonyOS Sans",sans-serif',
      'box-shadow:0 2px 8px rgba(0,0,0,0.3)',
      'cursor:pointer',
      'user-select:none'
    ].join(';');
    badge.addEventListener('click', function () {
      badge.remove();
    }, true);
    (document.body || document.documentElement).appendChild(badge);
  }

  rememberInstalledAt();
  mountBadge();
  console.log('[Aira 覆盖更新测试] 旧版 v' + VERSION + ' 已运行');
})();
