// ==UserScript==
// @name         Aira 覆盖更新测试
// @namespace    aira.overwrite.test
// @version      2.0.0
// @description  本地覆盖更新测试用脚本。新版：用这个文件覆盖导入旧版，应替换而不是新增。
// @match        *://*/*
// @grant        GM_getValue
// @grant        GM_setValue
// ==/UserScript==

// 这是覆盖更新测试的「新版」，与旧版共用同一 @name + @namespace，所以导入时应被识别为
// 同一个脚本并走覆盖替换。它故意不带 @updateURL/@downloadURL，用来确认覆盖后旧版留下的
// 更新地址仍然保留。
(function () {
  'use strict';

  if (window.__airaOverwriteTestMounted === true) {
    return;
  }
  window.__airaOverwriteTestMounted = true;

  var VERSION = '2.0.0';
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

  // 新版只读不写：首次安装时间应保持旧版写入的值不变。
  function mountBadge() {
    if (document.getElementById(BADGE_ID) !== null) {
      return;
    }
    var badge = document.createElement('div');
    var installedAt = readInstalledAt();
    badge.id = BADGE_ID;
    badge.textContent = '覆盖更新测试 · 新版 v' + VERSION +
      (installedAt.length > 0 ? ' · 首次安装 ' + installedAt : '') + ' · 点此隐藏';
    badge.title = 'Aira 本地覆盖更新测试脚本（新版）';
    badge.style.cssText = [
      'position:fixed',
      'right:12px',
      'bottom:12px',
      'z-index:2147483647',
      'max-width:80vw',
      'padding:8px 12px',
      'border-radius:8px',
      'background:#0a59f7',
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

  mountBadge();
  console.log('[Aira 覆盖更新测试] 新版 v' + VERSION + ' 已运行');
})();
