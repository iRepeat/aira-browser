# 重元素网页的加载与交互卡顿：调研与优化方案

更新日期：2026-09-15
状态：调研结论；**第一批低风险削减已实施并装机**。未做帧率验证（用户决定不测）。

本文聚焦一条新的用户反馈线索：**DOM 元素多、子资源多的网页，加载和滚动时明显卡顿**。
它与既有的 [`web-scroll-smoothness.md`](./web-scroll-smoothness.md) 是互补关系：既有文档从「用户脚本注入尾部窗口、广告拦截 cosmetic、favicon 发现」入手，本文补充两个它未覆盖的维度——**ArkWeb 渲染进程/surface 层配置**，以及**「元素数量」如何成倍放大 Aira 自有注入脚本的成本**。既有文档的滚动安静窗口结论在本文继续成立，不推翻。

## 实施记录

| 项 | 状态 | 位置 |
|---|---|---|
| P0-3 媒体 Observer 快筛 | 已实施 | `core/web/HostedWebNode.ets` 新增 `canContainMediaNode`，在 `enqueueAddedMediaElements` 中跳过不可能含 media 的节点（文本节点、无元素子节点的元素） |
| P0-4 `hasEditedContent()` 结果缓存 | 已实施 | 新增 `editedContentCache*` 与 `invalidateEditedContentCache()`；由用户编辑事件（input/focusin/focusout/reset）与 pagehide 精确失效，1.5s TTL 兜底程序化编辑。**childList 变更故意不失效**——重元素页面持续插入节点，在那上面失效等于抵消缓存 |
| P0-4b `clearEditingIfEmpty()` 提前退出 | 已实施 | `userEdited` 已为 false 时跳过全文档查询（其结果不可能改变状态） |
| P0-5 去掉 LoadFinished 的重复大脚本注入 | 已实施 | 新增 `PAGE_BEHAVIOR_RESAMPLE_SCRIPT`；`onLoadFinished` 改为只请求重采样，`onPageEnd` 保留完整注入作为安装兜底 |
| P0-6 file-picker 定时器降频 | 已实施 | `WEB_FILE_SAVE_PICKER_COMPAT_SCRIPT` 改为探测后再补写，不再每次 tick 重复 `Object.defineProperty` |
| P0-7 滚动链路定时器抖动 | **部分实施** | 仅跳过「待提交值未变化」时的 `clearTimeout`+`setTimeout` 重排 |
| P0-7b 视频几何 scroll 监听器提前退出 | 已实施 | 每个文档（含 iframe）的捕获 `scroll` 监听器先查有无播放中的 video，再决定是否重排 80 ms 定时器 |
| P0-8 拦截前廉价短路 | 已实施 | `core/browser/BrowserAdBlockCoordinator.ets` 在分类与原生匹配前短路，并新增 `isNativeAuthorityRequestUrl`。**覆盖范围有限**：仅命中「该请求未启用过滤」（全局关闭或站点未启用）与「非 http(s) URL」（`data:`/`blob:`/`file:` 等）两种情况；对已启用过滤的 http(s) 子资源仍会走完整分类与原生匹配 |
| P0-1 重页面测量 | **部分实施** | 做了页内 rAF 探针与 `hitrace` 系统追踪；未做前后台对照矩阵 |
| P1-3b 胶囊卡顿修复（fix#1） | **已实施后回退** | 曾把滚动驱动的 presentation 变化改走 panel channel 以避免整壳 rebuild；真机复测无改善（336→380 ms），前提被证伪，**代码已回滚**。见第八节 |
| P0-2 `scriptRules: ['.*']` 语义确认 | **未实施** | 需要真机对照实验，未确认前不改写法 |

**已排除的一项。** 既有调研曾怀疑 `AdBlockInteractionGuardRuntimeScriptService` 的触摸监听器应为 passive。复核该文件后确认**已经是正确的**：`listenerTypes.forEach` 里写的是 `passive: type !== 'click'`，只有 `click` 分支需要 `preventDefault()`。无需改动。

**P0-7 证据修正。** 本文初稿建议「同手势内 `|delta| < 1px` 直接 return」。复核 `BrowserWebScrollInteractionCoordinator` 与两个决策协调器后确认这样**不安全**：滚动事件在 Aira 里同时充当「绘制/交互就绪」信号，且当累积位移已达阈值但处于冷却期时，正是随后那些 delta=0 的事件负责触发最终切换。按初稿做法会把底栏/状态栏切换推迟到下一次真实位移，改变既有手感。因此只保留了可解释为中性的定时器改动。

### 唯一一项确定性实测结果

在 `www.qq.com` 上用同一探针注入「优化前 / 优化后」两个构建测量（计数与设备性能无关）：

| 指标 | 优化前 | 优化后 |
|---|---|---|
| 媒体 Observer 候选根数 | 238 | 242（同一量级，属正常浮动） |
| 实际入队并逐个建 TreeWalker | **238** | **62** |

即**冗余入队减少约 74%**。

**该结果只证明「冗余工作被消除」，不证明帧率改善。** 帧瓶颈若在页面自身脚本或 GPU 合成上，这点 CPU 侧节省可能看不出来。用户已决定不做 Profiler 对比，因此**帧率是否有改善在本仓库仍是未验证项**。

### 功能回归审查（复查后修复两处）

优化只允许减少冗余工作，不允许改变或丢失既有功能。逐条对照原逻辑复查后，**发现并修复了两处由本次优化引入的回归**：

| 回归 | 原逻辑 | 缺陷 | 修复 |
|---|---|---|---|
| P0-5 重采样替代完整注入 | `onLoadFinished` 无条件重跑 `PAGE_BEHAVIOR_SIGNAL_SCRIPT`；未安装时它会安装 | 若 `onPageEnd` 未触发（错误页、同文档导航等），重采样脚本只是空跑，**页面行为信号会永久不被安装** | 重采样脚本改为返回安装状态（`aira-page-behavior-installed` / `aira-page-behavior-missing`）；`runJavaScript` 返回 `Promise<string>`，据此在未安装时回退到完整注入 |
| P0-6 file-picker 探测后补写 | 每 250 ms 无条件重新 `defineProperty` | 若页面执行 `delete window.showSaveFilePicker`，`typeof undefined !== 'function'` 会被误判为「已就位」，**兼容从此不再恢复**；而原逻辑会在 250 ms 内恢复 | `isCompatHolding()` 同时要求 `getOwnPropertyDescriptor !== undefined` 且当前值不是函数；属性被删除或被重定义为函数都算「已失效」并补写 |

**P0-5 等价性的直接证据。** `PAGE_BEHAVIOR_SIGNAL_SCRIPT` 自身的重入守卫是：

```js
if (window.__airaPageBehaviorSignalInstalled === true) {
  try { window.__airaPageBehaviorSignalForceSample('reinjected'); } catch (_error) {}
  return;
}
```

也就是说**已安装时原逻辑本来也只做一次 `forceSample`**。重采样脚本做的正是同一件事，因此正常路径下两者行为等价，差别只是省去 39.7 KB 的跨进程传输与解析；未安装时才走回退。

**P0-4 的残余行为差异（已知且保守）。** 若页面**程序化地清空**输入框且未派发 `input`/`change`（框架通常都会派发），`hasEditedContent()` 的缓存最长会滞后 1.5 秒才反映「已不再编辑」。影响是 `isUserEditing` 这一优先级信号可能多保持最多 1.5 秒。方向是**保守的**（后台标签更晚被回收，而非更早），不涉及数据丢失。真实用户编辑路径每次事件都会失效缓存，与原来逐次扫描一致。

**唯一一处刻意的行为删减。** `clearEditingIfEmpty()` 在 `userEdited` 已为 false 时不再执行全文档查询——该查询结果在那种状态下不可能改变任何变量（它只用把 `userEdited` 置 false，而它已经是 false），因此是纯无效工作，不构成功能删减。

## 结论摘要

用户感知的「元素多就卡」在 Aira 里至少有五条成本链路会随 DOM 规模或子资源数量线性/超线性放大，其中三条属于 Aira 自有、可以低风险削减：

1. **两个全文档 `MutationObserver(subtree)` + 每次通知的全 DOM `querySelectorAll`**。元素越多、框架 DOM churn 越频繁，回调次数越多；`hasEditedContent()` 一旦用户编辑过就变成每次 `notify()` 都做一次全 DOM 扫描。（Aira 自有，可削减）
2. **页面结束时的全文档 `querySelectorAll('[class],[id]')` cosmetic 候选扫描**。成本直接是元素数量的函数。（Aira 自有，但改动有兼容性风险，需先测量）
3. **`onInterceptRequest` 内同步执行原生广告规则匹配**。子资源越多，主线程同步调用次数越多；重元素页面通常子资源也更多。（Aira 自有，可加廉价快筛）
4. **滚动期间修改 Web 视口几何**（沉浸式顶栏隐藏会改 `contentTopPx`/`contentHeightPx`）。DOM 越重，整页 relayout 越贵。（Aira 自有，收益预期明确但需验证首帧不跳）
5. **渲染进程拓扑未做任何按页/按设备策略**。手机端 ArkWeb 默认单渲染子进程，而 Aira 同时挂载多个真实 Web surface（活动 + 最多 3 个 background-hot + 1 个 parked），隐藏标签的 JS 与前台标签共享同一个渲染器主线程。（平台能力已存在但完全未使用）

最合理的路径**不是**立刻改这些点，而是先补齐测量（本仓库 `compatibleSdkVersion = 6.1.0(23)`，正好可用华为 API 23 起的 `SCROLL_ARKWEB_FLING_JANK` 抛滑丢帧事件），再用「元素规模分桶」的方式判断哪条链路在重页面里占比显著，然后按 P0 → P1 → P2 顺序动。

## 证据边界

沿用既有调研的三分法，避免把平台资料当成已确诊根因：

- **华为确认事实**：来自华为官方文档，并在本机 DevEco SDK 声明文件
  `/Applications/DevEco-Studio-26.0.0.621.app/Contents/sdk/default/openharmony/ets/` 下逐条核对过签名与版本号。
- **Aira 代码事实**：可复现的 `file:line` 证据。
- **Aira 工程推论**：把上述事实映射到 Aira 实现，**必须经真机轨迹验证**，本文不声称已确诊。

本文没有做代码修改、构建、安装、设备操作或截图，也没有新一轮真机帧轨迹。

## 一、为什么「元素多」会特别放大 Aira 的成本

### 1. 全文档 MutationObserver 的触发频率与 DOM 规模正相关

`PAGE_BEHAVIOR_SIGNAL_SCRIPT`（`core/web/HostedWebNode.ets:731-1896`，约 39.7 KB）为每个文档和每个 depth ≤ 2 的 iframe 注册 `MutationObserver`：

```ts
// core/web/HostedWebNode.ets:1671-1677
var observer = new MutationObserver(function (mutations) {
  enqueueAddedMediaElements(mutations, depth, doc);
});
observer.observe(doc.documentElement || doc, { childList: true, subtree: true });
```

`enqueueAddedMediaElements`（`:1638`）会遍历本次通知的所有 `addedNodes`。这个脚本本来只关心 `audio`/`video`，但回调无条件在每个 subtree 变更上执行。重元素页面（内容社区、电商、后台型 Web 应用）的 DOM 增删频率远高于静态页面，因此**同一份脚本在重页面上的实际执行次数显著更多**。

`PAGE_CHROME_THEME_SIGNAL_SCRIPT`（`:356-730`，约 11.3 KB）另有 head 的 `MutationObserver({childList, subtree, attributes})` 和 body/root 属性观察者，以及 `:656`、`:672` 两处 observer。

### 2. `hasEditedContent()` 是 O(元素数) 且被反复调用

```ts
// core/web/HostedWebNode.ets:873-886
function hasEditedContent() {
  var nodes = document.querySelectorAll(
    'input, textarea, [contenteditable="true"], [contenteditable=""], [role="textbox"], [role="searchbox"], [aria-multiline="true"]');
  var limit = Math.min(nodes.length, 80);
  ...
}
```

单次有 80 节点上限，但它是**全文档选择器查询**——选择器匹配本身要遍历整棵 DOM 树，与元素数量成正比。既有调研已指出：一旦用户编辑过任何内容，每次 `notify()`（install / DOMContentLoaded / load / pageshow / visibilitychange / 各媒体事件）都会重跑一次。

### 3. page-end 的全文档 cosmetic 候选扫描

`services/adblock/AdBlockCosmeticRuntimeScriptService.ets:37` 在页面结束时执行 `document.querySelectorAll('[class],[id]')`，随后最多三次 `runJavaScript` 往返（`services/adblock/AdBlockCosmeticInjectionService.ets:24-101`），单次预算 `MAX_COSMETIC_NODES_PER_PASS = 600`。这只是把**返回结果**截断到 600，扫描本身要先遍历全文档。元素越多越贵。

### 4. `onInterceptRequest` 内的同步原生匹配

```ts
// core/browser/BrowserAdBlockCoordinator.ets:536 起（handleInterceptRequest）
const classification = this.requestClassifier.classify({...});   // 构造 evidence 数组
const evaluation = this.runtimeGeneration.evaluateNetworkRequest(evaluationInput);
```

`evaluateNetworkRequest` 最终同步调用原生模块 `checkRequest`（`services/adblock/AdBlockNativeAuthorityEngineService.ets:69-92`）。华为官方 FAQ 明确「Web 组件不支持异步判断是否拦截网络请求」——所以这条路**不能**简单挪到 TaskPool。子资源数量越多，主线程同步次数越多。

### 5. 滚动期间修改 Web 视口几何

沉浸式顶栏隐藏/显示会写入 `webViewportVisualTopInset` 并刷新 `webViewportPresentation`：

```ts
// app/pages/BrowserShellPage.ets:3360-3369
resolveVisibleTopInsetPx: (): number => this.getWebTopChromeStableInsetPx(),
applyPresentation: (visible, targetTopInsetPx, _source): void => {
  this.webStatusBarVisible = visible;
  this.webViewportVisualTopInset = targetTopInsetPx;
  this.refreshWebViewportPresentation(targetTopInsetPx);
},
```

它直接驱动 Web 宿主的 `position({y: contentTopPx})` 与 `height(contentHeightPx)`（`app/components/browser/BrowserWebViewportSurfaceHost.ets:42-50`），由 `core/browser/BrowserWebViewportCoordinator.ets:89-101` 计算。**改变 ArkWeb 视口高度会让页面重新布局**，而重 DOM 页面的 relayout 成本正是元素数量的函数。代码注释也确认了这是有意为之的立即套用：

```
// BrowserWebViewportSurfaceHost.ets:47-49
// Web content geometry must settle in the same layout pass as history
// navigation. Animating height/top changes moves the scroll viewport
// while ArkWeb is restoring the target document.
```

阈值与冷却（24/32 px、360 ms）限制了触发频次（`core/browser/BrowserTopImmersionScrollCoordinator.ets`），但**没有限制单次成本**。

### 6. 多个真实 Web surface 共享一个渲染器主线程

- 挂载策略：`app/components/browser/BrowserHostedWebSurfaceSlots.ets:26-27`（活动 + background-hot 可见性切换）、`:73-79`（parked 槽位 1x1、opacity 0.01）。
- background-hot 上限：`app/components/browser/BrowserShellPresentationTokens.ets:26` `MAX_BACKGROUND_HOT_TAB_COUNT = 3`。
- 运行期保留预算：`data/preferences/PreferencesRepository.ets:150-165`（balanced 档 mounted 15 / hot 5 / warm 10）。
- 手机端 ArkWeb 默认 `RenderProcessMode.SINGLE`（多 Web 共享一个渲染子进程）——仓库当前**完全没有调用** `setRenderProcessMode`。

隐藏 surface 并非 frozen，只是 `Visibility.Hidden`；其页面 JS 仍在该共享渲染进程的主线程上跑。重页面在后台标签里持续做 DOM 工作时，会直接竞争前台标签的渲染帧预算。这是「元素多」反馈中最符合官方列出的「页面加载后立即创建隐藏或离线 Web 组件会阻塞应用主线程」一类原因，但**需要轨迹确认后台标签确实在跑重任务**。

## 二、本轮核对的华为确认事实（含 SDK 签名）

以下均在 `@ohos.web.webview.d.ts` / `component/web.d.ts` 中直接读到声明。

| 能力 | 签名 / 枚举 | 版本 | 本仓库状态 |
|---|---|---|---|
| 渲染进程模式 | `static setRenderProcessMode(mode: RenderProcessMode)` / `getRenderProcessMode()`；`enum RenderProcessMode`（`SINGLE=0` 多 Web 复用、`MULTIPLE=1` 每 Web 一个） | 12+ | **未使用** |
| 引擎预加载 | `static initializeWebEngine(): void`（必须在 Web 组件初始化前、非异步线程调用） | 10+ | 已用（`app/abilities/EntryAbility.ets:222`） |
| 预连接 | `static prepareForPageLoad(url, preconnectable, numSockets)`（仅 DNS + socket，最多 6 连接） | 10+ | **未使用** |
| POST 预取 | `static prefetchResource(request: RequestInfo, additionalHeaders?, cacheKey?, cacheValidTime?)`（仅 POST + `x-www-form-urlencoded`，最多 6 条） | 12+ | **未使用** |
| JS 字节码缓存 | `precompileJavaScript(url, script: string \| Uint8Array, cacheOptions: CacheOptions): Promise<number>` | 12+ | **未使用** |
| BFCache | `static enableBackForwardCache(features)`（**必须在 initializeWebEngine 前**）+ `setBackForwardCacheOptions({size, timeToLive})` | 12+ | 已用（`core/web/WebBackForwardCacheCoordinator.ets:22-25` size=8 / TTL=600s，`:113`/`:151`；`EntryAbility.ets:218` 在 engine init 之前调用，顺序正确） |
| 渲染模式 | `renderMode?: RenderMode`（`ASYNC_RENDER=0` 默认，surface 节点，最高 7680 px；`SYNC_RENDER=1` canvas 节点，支持超长内容但成本更高） | 12+ | **未设置**（等于默认 ASYNC） |
| 共享渲染进程 token | `sharedRenderProcessToken?: string`（多渲染进程模式下相同 token 优先复用同一渲染进程） | 12+ | **未使用** |
| 全量绘制 | `static enableWholeWebPageDrawing()`（全量网页绘制，供 `webPageSnapshot` 长截图） | 12+ | 已用（`EntryAbility.ets:233`，全局开启） |
| 注入脚本 | `runJavaScriptOnDocumentStart(scripts: Array<ScriptItem>)`（**按数组顺序执行**，相同内容静默去重且沿用首次 `scriptRules`） | 15+ | 已用 |
| 注入脚本（另一套） | `javaScriptOnDocumentStart(scripts)`（**按字典序**而非数组顺序，官方不建议与上者混用） | 11+ | 未用 |
| 滚动回调 | `onScroll(callback)` 仅页面全局滚动；`onOverScroll` | 9+/10+ | 已用 `onScroll` |
| 段落式解析 | `optimizeParserBudget(boolean)`（在 FCP 前降低分段阈值，提前进入渲染；仅对每个 Web 首次加载生效） | 15+ | **未使用** |
| 同层渲染 | `enableNativeEmbedMode(boolean)` + `registerNativeEmbedRule(tag, type)` | 11+/12+ | **未使用** |
| 拦截 | `onInterceptRequest` — 官方 FAQ：**不支持异步判断是否拦截**，但可在决定拦截后异步生成响应体 | 9+ | 已用 |

**关于 `scriptRules` 的一个重要发现。** SDK 声明（`component/web.d.ts:3559-3574`）规定的合法形式只有三种：

1. `*` 表示所有来源；
2. 精确 URL，如 `https://www.example.com`；
3. 带通配符的模糊匹配，如 `https://*.example.com`（并明确禁止 `x,*.y.com`、`* foobar.com` 这类写法）。

且第 6 条写明：**「若 `scriptRules` 中有一条不满足上述规则，则该 `scriptRules` 不生效」**。

而 Aira 目前有四处用了 `scriptRules: ['.*']`：

- `core/web/WebAppearancePolicy.ets:84`
- `core/web/BrowserHistoryApiBridge.ets:99`
- `core/web/HostedWebNode.ets:167`、`:1899`、`:1902`、`:1905`
- `core/web/HostedWebNode.ets:2072`（`PAGE_CHROME_THEME_SIGNAL_SCRIPT`）

同一文件的 `HostedWebNode.ets:2068`（`PAGE_BEHAVIOR_SIGNAL_SCRIPT`）用的却是合法形式 `'*'`，说明两种写法混用。`'.*'` 不是文档认可的形式，「不生效」到底是**回退成对所有页面生效**还是**该条被丢弃**，声明文件没有写清。这是一个必须先用真机实验确认语义的点：如果回退为「对所有页面生效」，这些脚本（含 11.3 KB 的 theme probe）的成本就落在了所有页面上，无法按站点收敛；如果被丢弃，则相关功能可能一直没生效。**在确认前不要改这两处写法**——两个方向的改动都会改变行为。

## 三、可优化点与风险分级

### P0：低风险，语义清晰，可独立验证

| # | 动作 | 位置 | 期望 | 风险 |
|---|---|---|---|---|
| P0-1 | **补齐重页面测量**（见第五节）：线上聚合 `SCROLL_ARKWEB_FLING_JANK` + Profiler ArkWeb 模板；Aira 侧把已有 adblock metrics 扩到「按页聚合 + 按元素规模分桶」 | `core/adblock/AdBlockRuntimeGenerationCoordinator.ets:399-432` 已有 p50/p95/p99 | 得到「哪条链路在重页面占比显著」的证据 | 无功能风险 |
| P0-2 | **确认 `scriptRules: ['.*']` 的真实语义**（真机对照 `'*'`），再决定是否统一 | 上述 7 处 | 让注入脚本可按站点收敛，避免在无关页面上跑 theme probe | 改动会变行为，必须先实验 |
| P0-3 | **媒体 MutationObserver 合并 + 快筛**：把 `enqueueAddedMediaElements` 改为 rAF/debounce 合并；对 `addedNodes` 先做零成本快筛（`nodeName` 判断 + 仅在可能含 media 时才 `querySelector`），而不是每个 subtree 变更都进循环 | `core/web/HostedWebNode.ets:1638-1678` | 重页面 DOM churn 期间页面主线程占用下降 | 低：语义仍是「发现新增 media」 |
| P0-4 | **`hasEditedContent()` 结果缓存**：从「每次 notify 全 DOM 扫描」改为按需触发（focusin / 编辑事件后）并缓存结论，页面内失效条件显式化 | `core/web/HostedWebNode.ets:873-886`，调用点在 `buildSnapshot` 路径 | 消除重页面上的重复全 DOM 查询 | 低-中：需确认编辑态判定没有回归 |
| P0-5 | **去掉重复注入**：`onPageEnd` 与 `onLoadFinished` 都会 `runJavaScript` 重注 `PAGE_BEHAVIOR_SIGNAL_SCRIPT`（39.7 KB）与 file-picker 脚本，二者常常连发 | `core/web/HostedWebNode.ets:2242-2257` | 每次加载少一次 39.7 KB 字符串跨进程传输与解析 | 低：脚本内有 installed guard，但 guard 之前要付出传输/解析成本 |
| P0-6 | **file-picker 兼容脚本降频**：`setInterval(..., 250)` 跑 80 次（20 秒）反复 `Object.defineProperty` | `core/web/HostedWebNode.ets:318-355` | 每页少 80 次属性重定义 | 低：改为探测后补写，语义不变（descriptor 的 setter 本就吞掉赋值，只有页面自行 `defineProperty` 覆盖才会被探测到） |
| P0-7 | **滚动链路定时器抖动**：`scheduleContinuationScrollCheckpoint` 每个滚动事件都 `clearTimeout + setTimeout` | `core/browser/BrowserWebScrollInteractionCoordinator.ets:372-382` | 减少每帧定时器 churn | 低。**注**：初稿的「位置未变就早退」经复核不安全，已放弃（见「实施记录」） |
| P0-8 | **`onInterceptRequest` 廉价短路**：过滤对该请求未启用、或 URL 不是原生引擎接受的 http(s) 时，分类与原生 `checkRequest` 都不可能改变结果，直接短路 | `core/browser/BrowserAdBlockCoordinator.ets:536-643` | 命中该路径的子资源主线程同步调用归零；**对已启用过滤的 http(s) 子资源无效**，那部分仍需完整分类（分类结果决定 `resourceType`，是规则匹配的输入） | 低：短路分支与原生 `isEligible` 的 scheme 判断一致，且原路径在该情况下本就不会记录 eligible query 指标 |

P0-3 到 P0-8 都是「削减 Aira 自有成本」，不改变第三方页面语义。P0-1 和 P0-2 应该最先做。

### P1：需要真机数据支持，收益大但影响面广

| # | 动作 | 依据 | 关键约束 |
|---|---|---|---|
| P1-1 | **评估 `RenderProcessMode.MULTIPLE`**：让前台标签的渲染进程与后台隐藏 surface 隔离 | SDK 12+，手机默认 SINGLE；官方列出「达到进程数量上限会回收旧渲染进程」 | 全局静态、必须在 `initializeWebEngine` 前调用 → 只能是**启动期设备分档决策**（按内存档位），不能按标签动态切换；内存成本显著；与 `injectOfflineResources` 冲突（本仓库未用该 API） |
| P1-2 | 若启用 MULTIPLE，用 `sharedRenderProcessToken` 给同 profile/同来源的 Web 共享进程，控制进程数 | SDK 12+ | 绑定发生在渲染进程初始化阶段 |
| P1-3 | **滚动期间把视口几何变化推迟到手势结束**：滚动中只走视觉层（overlay transform），`contentTopPx`/`contentHeightPx` 的变更在 fling 结束/settle 后一次性套用 | `BrowserWebViewportSurfaceHost.ets:42-50`、`BrowserShellPage.ets:3360-3369` | 与历史导航恢复共用同一条「同布局帧settle」约束（见 `:47-49` 注释），需验证首帧不跳、返回时不错位 |
| P1-4 | **验证降低 background-hot 上限**（3 → 更小）或让隐藏标签更早冷却，对前台流畅度的影响 | `BrowserShellPresentationTokens.ets:26` | 影响切标签时的预览/秒开体验，属于体验权衡；且需先证明后台 surface 真在跑重任务 |
| P1-5 | **`enableWholeWebPageDrawing` 的 AB 验证**：它是全局开启且只在 Web 初始化时设置，若对普通滚动帧无成本则保持，若有成本则需权衡标签长截图能力 | `app/abilities/EntryAbility.ets:233`；SDK 说明这是「全量绘制」，为 `webPageSnapshot` 服务 | 官方未给出它对普通滚动的性能说明 → **标注为待验证**，不要凭猜测关闭 |
| P1-6 | **`optimizeParserBudget(true)` 试评估**：在 FCP 前提前进入渲染，改善首屏 | SDK 15+，本仓库 compatibleSdk 23 可用；仅对每个 Web 首次加载生效 | 官方描述是提前解析，需要真机看是否有副作用 |

### P2：高收益但需要兼容性矩阵

| # | 动作 | 风险 |
|---|---|---|
| P2-1 | 按功能开关裁剪 document-start bundle（当前约 57 KB；`PAGE_BEHAVIOR_SIGNAL_SCRIPT` 1166 行里包含 audio context、screen capture、编辑态、媒体几何等大量探测，其中不少功能本身默认关闭却仍注入并运行） | 需逐功能回归；`buildHostedWebDocumentScriptSignature`（`HostedWebNode.ets:2081-2098`）和缓存键（`BrowserHostedWebDocumentStartScriptCoordinator.ets:83-103`）要同步调整 |
| P2-2 | `precompileJavaScript` 字节码缓存 | 官方文档说明它针对 **URL 资源 + `CacheOptions`(ETag/Last-Modified)**；它对 `runJavaScriptOnDocumentStart` 的内联字符串是否适用，**官方未明确** → 标注待验证，需实测 |
| P2-3 | cosmetic 全文档扫描改为分批 + 让出（已有 `MAX_COSMETIC_NODES_PER_PASS = 600` 与 mutation 根上限） | 延迟可能造成广告闪现或改变站点行为 |
| P2-4 | `prepareForPageLoad` / `prefetchPage` 预取 | 官方明确「若用户实际未打开预处理的 Web 页面，将造成额外资源消耗」；且这优化的是**加载时延**，对「元素多导致交互卡」帮助有限，优先级低 |

## 四、明确不建议做

- **滚动时全局暂停页面计时器 / 停止 ArkWeb 加载 / 禁止页面动画**：既有实验开关默认关闭是正确取舍；`BrowserArkWebProcessLifecycleCoordinator.ets:18,33` 的 `pauseAllTimers`/`resumeAllTimers` 只用于进程前后台，不应下放到滚动。
- **在 `onInterceptRequest` 内做异步拦截判断**：官方明确不支持。
- **让隐藏 surface 在页面加载后立即创建来做「预热」**：官方资料明确这类工作本身会阻塞第一次滑动。
- **改写第三方页面的触摸/滚轮监听器为 passive**：既有调研已列为高风险。
- **为省成本直接延迟或禁用 cosmetic filtering**：会广告闪现。
- **在 `onScroll` 里新增任何跨进程 `runJavaScript`**：官方帧率分析把 `onScroll` 中的同步重活与高频 JSB 回调列为典型掉帧原因，优化建议原文是「优化耗时逻辑或对调用进行节流，降低调用频率」「如果回调里涉及复杂计算、文件 IO 或数据库等操作，将任务抛到任务池（`taskpool.execute`）去执行，并迅速返回」。

## 五、验证方法

### 指标

- **主指标**：导航→首滑时间；首滑前后 2 秒的总帧数、慢帧/丢帧数、最大帧耗时。
- **平台事件**：`SCROLL_ARKWEB_FLING_JANK`（API 23+，本仓库 compatibleSdk 23 可用）聚合上报，用 `web_id` 关联页面运行实例。低频聚合，**不要在滚动热路径里写日志或同步落盘**。
- **Aira owner 耗时**：用户脚本计划/执行/报告、cosmetic 注入、favicon/manifest 发现、`onInterceptRequest` 分类与原生匹配、滚动协调器、媒体探测。

### 元素规模分桶（本文新增，针对「元素多」）

按页面 DOM 规模分「轻 / 中 / 重」三桶（页面侧用 `document.getElementsByTagName('*').length` 在 page-end 采样一次，或按 URL 归类），**只有重桶出现稳定恶化才动手改重页面策略**。这样可以避免为少数重页面引入全局性改动。

### 对照矩阵

固定同一设备、同一网页、相近网络与缓存，每组至少重复 3 次：

| 变量 | A 组 | B 组 | 回答的问题 |
|---|---|---|---|
| 页面元素规模 | 轻 DOM 页 | 重 DOM 页 | 恶化是否与元素数相关 |
| 滑动时机 | 可见后立即滑 | 等 2-3 秒 | 是否首轮加载尾部竞争 |
| Aira 脚本 | 全开 | 全关 | 注入脚本总贡献 |
| 后台标签 | 3 个 background-hot | 0 个 | 共享渲染进程竞争是否显著 |
| 服务模式 | 完整模式 | 基础模式 | cosmetic/媒体探测贡献 |

### 判定标准

- **值得优化**：同一 owner 在重桶多次复现稳定与慢帧重叠；关闭后帧指标明显改善；工作属于 Aira 且非页面正确性必需。
- **证据不足**：只有单条 50-100 ms 日志但未与慢帧重叠，或页面自身 LoAF/GPU 工作占主导。
- **停止**：候选占比很小、对照无稳定改善，或必须改变第三方页面语义才能取得小收益。

## 六、建议执行顺序

1. **P0-1**：先上重页面测量与元素规模分桶，拿到重桶基线。
2. **P0-2**：用真机实验确认 `scriptRules: ['.*']` 语义——这是后续所有按站点裁剪的前提。
3. **P0-3 ~ P0-8**：语义最清楚的几条自有成本削减（Observer 合并与快筛、编辑态缓存、去重注入、file-picker 降频、滚动链路早退、拦截快筛）。逐条独立验证、可单独回滚。
4. 用重桶数据决定 **P1**：渲染进程拓扑（P1-1/P1-2）与视口几何延迟（P1-3）预期收益最大，但需要设备分档和首帧一致性验证；P1-4/P1-5/P1-6 属于先验证再决定。
5. **P2** 在具备按功能/按站点兼容性矩阵后再做。
6. 若第 3 步之后重桶体感无稳定改善，**停止继续做壳层干预**，不要用猜测驱动高风险改动。

## 七、待确认清单

1. `scriptRules: ['.*']` 在真机上的实际语义（回退全匹配 vs 被丢弃）。
2. 后台 background-hot surface 的页面是否真的在跑重 DOM 任务（决定 P1-1/P1-4 是否值得做）。
3. `enableWholeWebPageDrawing` 全局开启是否对普通滚动帧有成本。
4. `precompileJavaScript` 是否适用于内联注入字符串（官方未说明）。
5. 手机端是否已有用户开启了滚动安静窗口相关实验开关（`pause_web_animations_during_scroll` 等默认 `false`，`data/preferences/PreferencesRepository.ets:253-255`）。
6. 第 1 号修复（状态收敛到子组件）需要先盘清所有读取 `rootBottomPanelPresentationSnapshot` 的调用点。

## 八、启动后周期性卡顿：真机诊断（根因已确认并修复）

用户实机反馈并精确定位：**底部浮层收起成小胶囊、以及胶囊展开回正常的那两下，网页会卡**；后续补充“大约 25 秒左右有个明显的卡顿点”。

**根因已确认**：启动后约 20-31 秒，Aira 的**自动同步突发**（个性化 / 书签 / 历史）在前台执行，
与用户滑动争抢 ArkTS 主线程。它**不受“广告拦截”“用户脚本”开关影响**，这解释了为什么关掉那些之后仍然卡。
本节同时保留三个被证伪的早期假设，避免重复走这些路。

### 确认根因的证据

同一份 `[DEBUG-sync-jank-9f3c]` 探针日志，修复前后对比（时间相对应用启动）：

| 阶段 | 修复前 | 修复后 |
|---|---|---|
| 首个同步域启动 | **+21.94 s**（个性化）、+30.06 s（书签）、+30.61 s（历史） | **+45.93 s**（书签）、+47.78 s（个性化）、+48.78 s（历史） |

修复前的关键事实：书签与历史在 **30.06 s / 30.61 s** 几乎同时启动（间隔 0.55 s），连续执行；单次耗时
`bookmark_merge_decide 98 ms`、`bookmark_remote_commit 682 ms`（payloadBytes=102858）、
`history_local_apply_exchange 390 ms`。修复后整体推迟约 24 秒，且三个域不再挤在一起。

用户关闭广告拦截与全部用户脚本后仍复现，是排除 Aira 注入路径、指向同步子系统的关键观察。

### 确认的三条缺陷

1. **periodic 绕过变更判定。**
   `SyncExperienceAutomaticRuntime.ets` 的
   `if (automatic && reason !== 'periodic' && !await this.hasBookmarkPendingChanges())` 中，
   `reason !== 'periodic'` 让周期同步跳过“有无变更”检查。启动后 30 秒那次因此**无条件执行**完整的
   远端读取 + 对比 + 回写（实测在无本地变化时仍提交 102858 字节）。
2. **历史没有变更门且周期过短。** `HISTORY_PERIODIC_INTERVAL_MS = 3 分钟`，每 3 分钟无条件同步。
3. **同步在执行中不让出。** 协作节流 `AiraSyncWorkThrottleService` 只有固定 16 ms 让出
   （`AIRA_SYNC_UI_YIELD_MS`），**不感知用户是否在滑动**；历史应用循环
   （`BrowserDatabase.applyHistorySyncChangesInStore`）在一整个 RDB 事务里逐条同步写入，中途不让出。

### 已实施的修复

| 修复 | 位置 | 做法 |
|---|---|---|
| 跨层浏览活动信号 | `common/activity/BrowsingActivitySignal.ets`（新增） | 滚动/触摸时写入一次时间戳，各层可读；放在 `common/` 因为 app/core/services/data 都要用 |
| 自动同步推迟到不滑动时 | `core/sync/SyncExperienceAutomaticRuntime.ets` | 用户在浏览时推迟自动 burst，每 1.2 s 重试，**30 s 上限**兜底；手动同步不受影响 |
| 周期同步分层间隔 | 同上 | 无本地变化时用 15 分钟空闲间隔（书签 + 历史）；**仍然执行**，因为周期同步正是发现远端变更的途径 |
| 执行中让出 | `services/sync/AiraSyncWorkThrottleService.ets` | 滑动期间把 16 ms 让出替换为“等手势结束”，100 ms 轮询，**4 s 上限** |
| 历史写入循环让出 | `data/database/BrowserDatabase.ets` | 每 16 条变更检查一次浏览活动，**4 s 上限** |

**这几条不影响同步正确性**：待执行工作仍排在队列里；空闲间隔只改变频率，不改变是否执行；所有等待都有上限，长滑动不会饿死同步。

### 被证伪的假设

| # | 假设 | 验证方式 | 结果 |
|---|---|---|---|
| 1 | 滚动驱动的 presentation 变化写根 `@State`，导致整个 `BrowserShellPage` 重跑 build | 实施“隔离到 panel channel”的修复后复测 | **无改善**：主线程最大停滞 336→380 ms，>100 ms 卡顿 8→5 次。修复前提不成立，已回退 |
| 2 | 滚动沉浸式顶栏收起改变 Web 视口高度，使页面重布局 | 在 `refreshWebViewportPresentation` 记录 `contentTopPx`/`contentHeightPx` 变化 | **0 次变化**。`webHostHeight` 只由视口尺寸与地址栏焦点决定，胶囊切换不改它 |
| 3 | 30 秒 `RUNTIME_COOLING_TICK_MS` 定时器里同步 `serializeWebState()` 阻塞主线程 | 给冷却路径四个环节计时 | **完全无辜**：`applySessionSyncResult cooled=0 ms=0-4`，`sync(cooling_tick) ms=19`。没有标签被冷却，序列化从未发生 |

### 系统追踪（hitrace）证据

抓取 15 秒系统追踪（`sched` 等 category）后按 `sched_switch` 统计 Aira 主线程连续运行时长：

| 指标 | 数值 |
|---|---|
| 主线程连续运行片段 | 1296 段，合计 **758 ms / 15 s = 5.1% CPU** |
| 最长单段 | **38.2 ms** |
| 超过 50 / 100 / 200 ms 的段 | **0 / 0 / 0** |

**ArkTS 主线程在这段窗口内没有任何一次超过 50 ms 的阻塞。** 同时各埋点在“停滞”窗口里记录的 Aira 自身耗时也很小（例如某窗口 `stallMax=334 ms` 时 `scroll=9 ms`、`intercept=0 ms`）。

### 这段诊断本身的两个限制（重要）

1. **`setInterval` 间隔不能证明主线程被阻塞。** 早期探针用 16 ms 心跳的间隔衡量“主线程停滞”，但定时器回调被延迟也可能来自节流、GC 或其它定时器排队，而非主线程被占用。在系统追踪已经证明主线程未长时间占用的前提下，该指标不可信。
2. **抓追踪时设备已空闲。** 该窗口只有 33 次 `ReceiveVsync`（约 2/s）、10 次 `Repaint`、20 次 `CommitAndGetReleaseFence`，主线程 5.1% CPU —— 这不是一个正在渲染的前台页面。因此**这段追踪既不能证明卡顿存在，也不能证伪卡顿**；它只能证明“在那个空闲窗口里 ArkTS 侧没有阻塞”。

### 早期推断（已被上面的确认结论取代，保留以免误读）

标注：下面这段是**根因确认之前**的推断，方向是错的——它把注意力引向 Web 渲染进程。保留是因为其中的
`bilibili 页面自身丢帧` 测量本身仍然有效，但不要把它的“指向”当作结论。

### 当时指向哪里

同一批测量中，**页面侧 rAF 探针**（`[AIRA-JANK-PAGE]`）在 bilibili 上记录到 `gapMax=652 ms`、`gapsOver50=36`（元素数 1152→2550），而同期 Aira 的 ArkTS 侧工作极小。两者结合指向：**丢帧发生在 Web 渲染进程（页面自身 JS/布局/合成），而不是 Aira 的 ArkTS 壳层**。

Aira 唯一运行在渲染进程里的代码是**注入的 document-start 脚本**（页面行为信号、主题信号、广告拦截 cosmetic、用户脚本、媒体探针），它们本来就随 DOM 规模放大——这与用户最初的“元素多就卡”描述一致。但这仍是**待验证推论**，不是结论。

### 尚未实施、且仍值得做的决定性实验

在**前台、由脚本化手势驱动**的条件下，测量页面侧帧间隔：Aira 注入脚本**全开 vs 全关**（设置里有现成开关）。这能一次性回答“jank 是 Aira 注入造成的，还是 bilibili 自身造成的”。

注意：本仓库 `AGENTS.md` 禁止在未获用户明确授权时进行设备/屏幕捕获，因此该实验需要用户先授权。


## 九、第二次真机诊断：删历史→返回→前几秒卡（另有结论）

用户场景原话：「我删除一条历史记录，返回网页后，滑动就变卡了，前几秒就会卡」。

### 确认根因：history 同步在单事务内独占主线程

新增临时探针 `[DEBUG-scroll-osc-2a71]`（`common/debug/AiraScrollOscProbe.ets`）记录每个滚动样本的源、yOffset、增量与决策原因；与既有 `[DEBUG-sync-jank-9f3c]` 对齐后，一次抓取得到：

| 时刻 | 滚动事件吞吐 | 同期同步阶段 |
| --- | --- | --- |
| 17:51:26 | 17 次/秒 | bookmark 远端读取 |
| 17:51:27 | **1 次/秒** | bookmark 阶段 |
| 17:51:28–31 | 无事件（用户在设置页删历史） | — |
| 17:51:32 | **4 次/秒**（反转 2、翻转 2） | `history_local_apply_exchange_start` |
| 17:51:33 | **5 次/秒**（反转 1、翻转 2） | history 交换中 |
| 17:51:34 | 11 次/秒 | 交换结束 |
| 17:51:35 | 19 次/秒（恢复） | — |

正常满速为 19–20 次/秒（探针心跳 50ms）；该窗口跌到 4–5 次/秒，即主线程约 75–80% 被占用。

### 逐条计时定位到确切元凶：`retention_prune` 为取一行读一万行

第二次抓取加入 `history_change` 逐条计时后，单条成本一目了然：

| 时刻 | kind | 耗时 |
| --- | --- | --- |
| 18:40:01.088 | `upsert_visit` | 56ms |
| **18:40:01.430** | **`retention_prune`** | **332ms** |
| 18:40:01.474 | `delete_visit` | 32ms |
| 18:40:01.493 | `upsert_visit` | 10ms |
| 18:40:02.286 | `retention_prune` | 284ms |

**`retention_prune` 单条 284–332ms，是其余每条的 6–30 倍**，且用户「删一条历史记录」触发的正是它。定位到 `advanceHistorySyncRetentionFromRemotePrune`（`data/database/BrowserDatabase.ets`）：为求保留窗口边界那**一行**，它按 `visited_at DESC` 排序后取 `HISTORY_SYNC_MAX_VISITS`（= 10000）行，再用 `mapHistoryVisitEventRows` 把 10000 行**全部映射成对象**，最后只用第 10000 个。

这不是"让出"能解决的：让出只发生在两条变更之间，单条内部的 300ms 仍是一次完整冻结。已改为 `SELECT visited_at, sync_id … ORDER BY … LIMIT 1 OFFSET 9999` 只读那一行（同文件 `hasHistorySyncProjectionVictims:5080` 已有同样的先例写法）。修复后 `retention_prune` 应降到与其余条目同量级，这正是下一次抓取要验证的。

`HistorySyncMergeService.ets:199,403` 也有 `HISTORY_SYNC_MAX_VISITS - 1` 取边界，但那里数组已在内存中，取第 N 个是 O(1)，**不是**同类问题，已确认无需改动。

### 真机验证结果（已闭环）

真机复测：边界读取由修复前的 **24/28/31/24ms** 降到 **2ms**（探针直接对真实边界读取计时）。四条事实同一次抓取确认：`schemaVersion=7`（迁移已执行）、索引存在、`syncedRows=9999`、`boundaryReadMs=2`。

**但 24ms 不是查询本身的开销，而是缺索引。** 该读要按 `visited_at DESC, sync_id DESC` 排序、在 `sync_account_uid` + `data_scope` 下 offset 走到边界，没有任何索引提供这个组合与顺序，SQLite 只能把该账号全部同步行拷进临时 B 树排序，只为取一行。同一形状还支撑溢出探测与 prune 扫描。

因此新增 `idx_history_visits_sync_scope_time(sync_account_uid, data_scope, visited_at DESC, sync_id DESC)`（schema 6→7；独立迁移步骤，已到 6 的库无需重跑列迁移）。设备同规模（1 万条同步行）实测：300 次边界读取 4.18s → 0.18s，计划变为 `USING COVERING INDEX`。写入代价可忽略（5000 条插入 0.051s → 0.055s）。

### 随后的两处清理（同一路径）

**prune 受害者选择改为 SQL。** `pruneHistorySyncProjection` 原本读该账号整个同步窗口（最多 10000 行）、把每行映射成对象，再在内存里筛出受害者（早于 cutoff 的，加上超出上限的全部）。新索引同时服务这个选择：溢出尾部用 `LIMIT -1 OFFSET 9999` 取，过期行用 `visited_at < ?` 取；尾部首行即边界本身，前沿由同一结果持久化。等价性用 20000 例随机窗口验证（窗口大小低于/等于/高于上限，边界过期与未过期），受害者集合与边界完全一致；顺序有差异但两处消费方均为集合语义。300 次读：4.18s → 0.18s。

`LIMIT -1` 在本客户端无先例，而它若失效会使保留策略静默停止推进，故已在真机确认：10000 条同步行下该查询返回 10000 行，边界与受害者计数均符合旧定义。

**少量记录时的逐条查询改为批量。** `hydrateHistoryVisits` 在少于 80 条时对每个访问单独发一次 URL 查询，范围删除几十条即几十次数据库往返，现合并为一次 `IN` 查询。

### 仍未解决：同场景下"按时间让出"未被真机触发

`AiraSyncWorkThrottleService.afterBatchItem` 已叠加 24ms 时间预算（保留 250 条上界），但三次真机抓取都未出现 `throttle_yield trigger=time`：实际批次只有 1～2 条变更，既不到条数上界，也未跑满时间预算，按设计不应让出。该行为目前由单元测试与同算法仿真覆盖（5 个场景全过），尚缺一次大批量同步的真机证据。

### 上一轮的修复对本场景无效（已纠正）

上一轮加的 yield 门槛是**每 16 条变更一次**。这次只有 5 条，**一次都没触发**。已改为**按时间预算**（连续执行满 24ms 即让出 8ms），并在**开事务之前**等待手势结束（上限 1500ms）；bootstrap 路径原本完全无 yield，一并补上。

### 与同步无关的第二个问题：底部面板与页面互相触发

同一次抓取中底部面板 mode 翻转 **76 次**、滚动方向反转 **53 次**。yOffset 并非单向滑动，而是以约 230ms 交替振荡，且夹带 `−1308px`、`+4482px` 这类整段跳变。

已证实的三点：

- **顶部安全区会真实改变 Web 内容区高度**（这是修正后的结论，推翻了本节初稿的判断）。`BrowserWebViewportSurfaceHost.ets:42` 直接用 `presentation.contentHeightPx` 设定 Web 内容区高度，而 `BrowserWebViewportCoordinator.resolveLayerLayout`（`core/browser/BrowserWebViewportCoordinator.ets:90-92`）里 `contentHeightPx = hostHeight − topInsetPx`，且 `topInsetPx` 由 `resolveTargetWebViewportVisualTopInsetPx`（`BrowserShellPage.ets`）按 `webStatusBarVisible` 决定：隐藏时 0、显示时为安全区高度。**顶部栏一收一展，Web 内容区确实变高变矮**；`contentTopPx` 同时作为内容 `y` 偏移变化。
  注意区分：底部面板 detent **不影响** `webHostHeight`（只依赖窗口尺寸与地址栏聚焦，`BrowserRootBottomPanelLayoutModel.ets:79-83`），但**顶部**沉浸（`BrowserWebTopImmersionSessionCoordinator.applyDesiredVisibility` → `host.applyPresentation`）会经 `webViewportVisualTopInset` 进入上述公式。初稿把「底部面板不改视口」误推广为「视口不变」，是错的。
- **页面自身的位移会被当成用户滑动**。`BrowserWebScrollInteractionCoordinator.resolveScrollInteractionFromDelta` 在无触摸信号时，只要 `delta >= 2px` 就走 `scroll_delta_fallback` 判定为 `user`（`fallbackUserDeltaPx: 2`）。视口高度变化引起的滚动位置补偿因此也会驱动工具栏收起展开。
- **冷却计时被每次基线重置清零**。`BrowserBottomChromeScrollCoordinator.rememberBaseline` 把 `lastTransitionAt` 置 0，而程序化滚动样本会频繁重置基线，使 `transitionCooldownMs: 180` 形同虚设；同级实现 `BrowserTopImmersionScrollCoordinator.ets:130` 是**保留**该时间戳的。已改为保留。

**待验证（已埋点，等待抓取）**：视口高度变化与面板翻转是否在同一时间轴上互为因果。新增 `viewport` 埋点记录 `statusBar/inset/contentHeight/contentTop/host`，与 `transition`/`reversal` 对齐即可判定。顶部沉浸的冷却为 `visibilitySwitchCooldownMs: 360ms`，与实测约 230ms 交替、约 450ms 完整周期同量级，是目前的头号候选。

**尚未定论**：振荡的驱动方是用户手指还是页面/视口自身。探针抓取的地面触摸数据显示用户在 17:52 期间以 300–500ms 间隔连续短触，与 230ms 交替同量级，因此不能排除人为连续上下滑。需要下一次抓取中把 `markSignal` 的判定与真实触摸序列逐条对齐（本次缓冲区已滚动，17:51:37 段的触摸记录不可得）。

### 被证伪的假设（本轮）

早先怀疑「一次手势中有两个滚动信号源交替上报」——即原生 `onScroll`（`global:<tabId>`）与页面注入脚本的嵌套滚动容器（`local:<tabId>:<id>`）基准值不同导致振荡。实测抓取中**没有任何 `local:` 事件**，全部样本都来自 `global:window-main-tab-…`。该假设不成立。

### 本轮测量方法的限制（重要）

`ticks` 统计的是 `onScroll` 事件数，**不是主线程存活度**。页面不滚动时（用户未触摸）自然为 0，因此「某秒 tick 少」本身不构成主线程停顿的证据。仅当**页面确实在移动**时低吞吐才有意义：本节 17:51:32–34 的窗口内同时有翻转与反转事件，说明页面在动，故该低吞吐可作占用证据。后续判断停顿应改用「有滚动请求但帧/事件被合并」的口径。


## 来源

### 本机官方 SDK 声明（逐条核对签名与版本）

- `@ohos.web.webview.d.ts`：`initializeWebEngine:2732`、`prepareForPageLoad:3810`、`prefetchResource:4291`、`setRenderProcessMode:4321`、`getRenderProcessMode:4334`、`precompileJavaScript:4372`、`enableBackForwardCache:4608`、`setBackForwardCacheOptions:4618`、`enableWholeWebPageDrawing:4240`、`RenderProcessMode:2143`
- `component/web.d.ts`：`ScriptItem:3550`（`scriptRules:3574`）、`RenderMode:2340`、`renderMode:3479`、`sharedRenderProcessToken:3504`、`javaScriptOnDocumentStart:7308`、`optimizeParserBudget:7738`、`runJavaScriptOnDocumentStart:7760`

### 华为官方文档

- [Web 加载性能优化](https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-web-develop-optimization)（预启动渲染进程 / 预解析 / 预连接 / 预下载 / 预渲染 / 预取 POST / 预编译 JS 字节码缓存；含成本与场景对照表）
- [Web 帧率问题分析](https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-web-frame-rate-performance-analysis)（`onScroll` 中同步重活、高频 JSB 回调、`JSView:ExecuteRerender`、离线 Web 组件创建阻塞主线程）
- [订阅 ArkWeb 抛滑丢帧事件](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hiappevent-watcher-scroll-arkweb-fling-jank)
- [Web 组件网络拦截能力](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-component-intercept-capab-usage)（`onInterceptRequest` 同步判定约束、与 `WebSchemeHandler` 的分工）
- [Web 组件渲染模式](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-render-mode)（ASYNC / SYNC 取舍）

### Aira 内部

- [`docs/research/web-scroll-smoothness.md`](./web-scroll-smoothness.md)（用户脚本尾部窗口、cosmetic、favicon 发现；本文与之互补不覆盖）
- [`docs/aira-tab-background-management.md`](../aira-tab-background-management.md)

## 调研限制

- 本文没有新的真机帧轨迹，所有 Aira 映射仍是待验证工程推论。
- 华为文档站内容依赖动态加载，本文以本机 DevEco Studio 官方 SDK 声明文件为一手事实来源；文档页仅作交叉参考。
- 未进行构建、安装、设备操作或截图。
