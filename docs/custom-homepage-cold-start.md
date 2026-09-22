# 第三方主页冷启动：实测时间线与优化结论

更新日期：2026-09-22
状态：**已实测**（HarmonyOS 6.1.0 / API 23 真机，`com.aira.browser`，本地导入 ZIP 主页）

本文记录第三方（本地导入）主页冷启动的真实耗时构成，以及由此确定的两条优化边界。
目的是让后续优化**先读这份数据**，不要再对已经证伪的方向投入。

## 一、实测时间线

同一台设备连续 4 次「杀进程 → 启动」，各段误差 < 30ms，取代表值（设备时间，同一次启动内相对 ms）：

| 相对时刻 | 事件 | 来源 |
| --- | --- | --- |
| 0 | 点击图标 / `aa start` | 系统 |
| +99 | `appspawn` 收到请求 | `C02C11/appspawn` |
| +125 | 进程创建成功 | `APPSPAWN: Child process ... success` |
| +299 | `UIAbility onCreate`（JS 开始） | `AiraBrowser: Ability onCreate` |
| +406 | `onCreate` 结束 | `JSIAbility end, name: onCreate, time: 108` |
| +509 | ArkUI `LoadContent` | `JsWindowStage` |
| +726 | ArkUI 请求首帧 | `Root node request first frame` |
| **+789** | **应用首帧上屏（Aira 界面可见）** | `NotifyCompleteFirstFrameDrawing` |
| +747 | 主页 `loadUrl` 开始 | `web_load_start` |
| +1013 | 主页 `page_end` | `web_ready reason=page_end` |
| **+1226** | **封面抬起，真主页可见** | `web_settled` |
| +4160 | 平台首屏信号送达 | `web_first_screen_paint` |

**冷启动总计约 1.23 秒。**

## 二、三个已确认的结论

### 1. 主页包本身不是瓶颈

`loadUrl` → `page_end` 仅 **~250ms**（主页包含 140 KB HTML，其中 60 KB 内联脚本，
外加 435 KB 的 `assets/lunar.js`）。

**因此以下方向已证伪，不要投入：**

- 拆分/压缩主页的 HTML 与那条 435 KB 的农历库
- 对本地包做脚本字节码预编译（且 `precompileJavaScript` 文档明确只接受 HTTP/HTTPS URL，对本地包无效）
- 为了"解析更快"而改写主页自身结构

### 2. 大头是 App 冷启动本身，占 789ms（约 64%）

这段是系统 `appspawn` + 进程创建 + ArkUI 框架装载，Aira 可控的只有 `onCreate` 的 108ms。
`first_paint_readiness_total` 88ms、`launch_readiness_total` 104ms 都远小于此。

任何"让第三方主页快很多"的期望都必须先扣除这 789ms 的固定成本。

### 3. 用户感知的"慢"，来自页面就绪后那段被门闩拖住的白等

```
+789ms   Aira 界面出现
+1013ms  主页文档加载完成        ← 本可立即显示
+1226ms  实际才显示（封面机制下）
```

**主页在 +1013ms 就已经能显示了，却被压到 +1226ms。** 这一段与主页包无关，
纯粹是"等待确认已绘制"的门闩在拖延。封面移除后不再等待此判定（见 §3）。

## 三、冷启动封面已整体移除

原先第三方主页冷启动会用一张**持久化的上次截图**盖住加载过程（缩放淡入，等文档
settle 后交叉淡出）。**该机制已全部删除**，原因：

1. **它掩盖的等待只有几百毫秒。** 实测文档加载本身仅约 250ms（见 §2），而封面机制
   为此付出了持续截图（冷却 1.6s / 周期 4s）、JPEG 编码、落盘、以及一个按渲染身份
   索引的持久化仓库。
2. **每一个环节都是失效点。** 渲染身份（含主题）一变封面立刻作废；宽高比校验用的是
   壳视口、截图用的是文档视口，两者不一致时封面被跳过；存储读取是同步文件 IO 且在
   UI 线程。用户反馈的"闪一下"正是这些路径。
3. **`documentSettled` 的意义已经消失。** 它原本只服务于封面淡出时序。

随之删除的内容（共约 1460 行）：

| 删除对象 | 说明 |
| --- | --- |
| `CustomHomepageLaunchSnapshotCoordinator` | 截图调度（周期、内容变更、页面隐藏三条触发） |
| `CustomHomepageLaunchSnapshotViewModel` | 封面元数据、渲染身份校验、TTL、宽高比校验 |
| `CustomHomepageLaunchSnapshotCaptureService` | 基于 `webPageSnapshot` 的抓帧 |
| `CustomHomepageLaunchSnapshotStore` | 持久化、JPEG 打包、过期清理 |
| `CustomHomepageSurface` 的封面层 | 图像、缩放/淡入淡出、staging/hold/reveal 计时器 |
| 运行时 `documentSettled` 状态 | 含 `settledGeneration`、settle 兜底与探针 |
| `notifyContentChanged` 主机回调 | 主页改自身布局后刷新封面用 |
| 三个仅服务截图的 getter | committed controller / 组件 id / 文档视口测量 |

**新行为**：文档在 `page_end` 直接提交并显示，不再等待任何绘制判定。加载期间由
staging 节点的主题底色（`WebAppearancePolicy.backgroundColor`）承担空窗，
该底色由 document-start 脚本强制写入，与主题一致。

## 四、附录：揭示门闩的调参过程（已随封面一并删除）

以下数据在移除前测得，保留作为参照：

### 优化前

`onLoadFinished` → `beginDocumentSettleProbe`：跨进程 `runJavaScript` 轮询，每 100ms 一次，
要求**连续 2 次**读到相同且可信的结果才揭示，最多 18 次，另有 3000ms 兜底。

其中「连续 2 次」是主要成本：实测每次跨进程往返约 100ms，所以两次读把揭示推迟了约 200ms。

### 当时的优化后

- `CUSTOM_HOMEPAGE_SETTLE_PROBE_STABLE_READS`：`2` → `1`
- 新增 `CUSTOM_HOMEPAGE_SETTLE_PROBE_MIN_DWELL_MS = 100`（**从 probe 开始计时**的静置）
- 揭示时刻 = max(静置 100ms, 首次可信读到达) ，**不再是两者相加**

静置从 probe 开始计时而非从可信读计时，是为了保证「JS 里已换主题但尚未合成上屏」的
合成器延迟仍被覆盖：读得越快，静置越长。同时保留对 `pending`（文档或可见图片未就绪）
仍走完整 18 次上限的逻辑，`pending` 永远不会被当作"已完成"。

### 实测结果

| 指标 | 优化前 | 优化后 |
| --- | --- | --- |
| `readyToSettledMs` | 317 / 321 / 326 / 329 | **213 / 215 / 215 / 215** |
| `totalMs`（loadUrl → 可显示） | 670 ~ 710 | **568 ~ 596** |

稳定节省约 **100 ~ 110ms**（多次复现，不是单次偶然）。

## 五、深色模式冷启动闪浅色：真根因与修复

删除封面后暴露出的问题：**系统深色下冷启动，主页先渲染浅色再翻成深色**。
排查过程记录如下，因为前两次修复方向都是错的，值得留档。

### 探针实测数据（关键）

在 `page_end` 用 `runJavaScript` 读取页面真实状态：

```
resolvedThemeMode=dark
colorScheme=normal      ← 既不是 light 也不是 dark
media=light             ← 设备是深色，但 Web 告诉页面"你是浅色"
dataTheme=light
bodyBg=rgb(255,255,255)
bgVar=#ffffff
bootstrapIn=missing     ← document-start 注入的 style 根本不存在
```

### 根因一：`scriptRules` 对 `file://` 不生效

华为文档明确规定（`web.d.ts` 的 `ScriptItem.scriptRules`）：

> 对于 **HTTP/HTTPS 以外的协议**，精确匹配和模糊匹配不支持，**协议必须以 `://` 结尾**，
> 例如 `resource://`；若不满足上述规则，**`scriptRules` 不生效**。

导入主页走 `file://`，而注入规则写的是通配 `'./*'` 形式的 `.*` —— 规则被整体丢弃，
两处 document-start 脚本（外观 bootstrap 与桥接 bootstrap）**从未执行**。
`bootstrapIn=missing` 即直接证据。

修复：新增 `resolveDocumentStartScriptRule`，对非 HTTP 协议返回 `scheme://` 形式；
HTTP(S)/`data:` 保持 `.*`。两条注入路径（`WebAppearancePolicy`、`CustomHomepageBridgeService`）
都改为按文档 URL 解析规则。

> 影响面提示：`HostedWebNode` 与 `OfflinePageViewerScreen` 也用同样的 `'.*'`。
> 它们走 HTTP(S) 与 `loadData`，通配在那里是合法的，因此未改动。

### 根因二（真正导致闪的那一条）：`WebDarkMode.Off` 不等于"不干预"

| `WebDarkMode` | 文档语义 |
| --- | --- |
| `Off` | web dark mode is **disabled** |
| `On` | enabled |
| `Auto` | **follows the system setting** |

本地导入主页的 `shouldForceDarkWebContent` 恒为 false（该功能只对 `url` 型主页开放），
于是拿到 `darkMode: Off`。**`Off` 会覆盖系统设置**，使文档报告
`prefers-color-scheme: light`（`media=light` 即此证据）。

而导入主页的深色主题通常写在 `@media (prefers-color-scheme: dark)` 里，media 不命中
→ 首帧用浅色默认值 → 主页自己的脚本跑完才切换 → **闪**。

修复：非强制反色时改用 `WebDarkMode.Auto`（不反色，但让 media query 反映系统）。
仅改 `CustomHomepagePresentationViewModel`；普通网页的
`resolveWebAppearancePolicyForTheme` 未改动。

### 前两次修复为何无效

两次都改的是 `prefersDarkColorScheme`（document-start 脚本写入的 `color-scheme`）。
方向不算错，但**引擎层的 `darkMode` 优先级更高**，把那个值压过去了；
更何况根因一使脚本从未执行，改的值根本没机会生效。

## 六、已尝试但实测无效：`onFirstScreenPaint`

API 23 的 `WebAttribute.onFirstScreenPaint` 会给出文档自身的首屏时间（实测约 400ms），
曾计划用它替代 probe 作为揭示门闩，并已在 `CustomHomepageHostedWebNode.ets` 中接入
（带 API 版本门控，经 `AttributeModifier` 承载）。

**但实测它到达应用的时间是 +4160ms，比页面可见（+1013ms）晚了约 3.1 秒。**

因此在本设备上它**不能作为呈现门控**。当前保留它**仅作诊断**输出
（`web_first_screen_paint` 日志行），不得将其改为门控条件——那样只会推迟显示。

（另一条已验证的路径：试图用 `onAreaChange` 的布局回调作为兜底首屏信号是**错误的**，
因为节点首次布局早于 `page_end`，会恒早触发并伪装成"已首屏"，从而破坏 probe 的语义。
该尝试已回退。）

## 七、尚未实施、预期仍有效的方向

这些**未做验证**，属推测，按需再评估：

1. **`injectOfflineResources`**（API 12+）：把包内资源注入内存缓存以加速首屏。
   本地包资源很少（琉璃包解压后 4 个），收益上限受 §2 的 250ms 约束。
2. **`file://` 改 Aira 私有 standard scheme + `setWebSchemeHandler`**：异步读、
   正确 `Content-Type`、可加进程内缓存。同样受 §2 约束。
3. **减少重复的 document-start 注入**：`sync_bridge` 目前会重发完整 bootstrap 脚本。
4. **冷启动固定成本（789ms）**：属平台层，Aira 可控空间仅 `onCreate`。

（原先第 4 条"减少重复 document-start 注入"仍然成立；`sync_bridge` 会重发完整
bootstrap 脚本，仅是未测收益。）

同时已实施但**未测收益**的一项：分级刷新（`buildSourceKey` / `buildAppearanceKey` /
`buildRenderPipelineKey`）。它针对的是**主题切换与实验开关变化**，能避免重建整个
ArkWeb 运行时；对冷启动无影响（冷启动走 `start(true)` 强制重载）。
注意：强制深色（`darkMode` / `forceDarkAccess`）无法通过 JS 在线应用，因此它仍在
`buildRenderPipelineKey` 内，变化时依旧重建——这是为 URL 型主页保留的正确性。

## 八、复现方法

```bash
T=<device-serial>
hdc -t $T shell aa force-stop com.aira.browser; sleep 3
hdc -t $T shell hilog -r
hdc -t $T shell aa start -b com.aira.browser -a EntryAbility
sleep 9
hdc -t $T shell hilog -T CustomHomeRuntime -x
```

关注 `[DEBUG-FAVICON-COLDSTART]` 前缀的分段输出：

- `web_load_start`：开始加载
- `web_ready reason=page_end`：文档就绪
- `web_first_screen_paint documentPaintMs=`：平台首屏（诊断）

封面移除后不再有 `web_settled` 行；页面在 `page_end` 即提交显示。
排查深色闪白时曾临时加入 `web_theme_probe` 探针，定位后已移除（它在每次加载都产生一次
跨进程 `runJavaScript`，不应留在正式路径）。

加上 `BrowserAppRuntime` tag 的 `Startup step` 行，即可得到 §1 的完整时间线。
