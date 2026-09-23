# Aira 桌面居中弹窗设计规范

状态：**已落地**。大屏居中对话框的档位、外壳和 PC 底部弹窗宿主已按本规范实现。手机底部半模态保持原样。

**风格基线：参考图语言（v3）。** 见 2.1。

## Scope

本规范适用于 `shellFamily === 'large_screen'`（PC / 2in1 / 平板键盘鼠标 / 展开态折叠屏）下所有**居中的模态表面**：确认框、短表单、单选列表、权限与认证提示、以及带内嵌面板的居中工作区。

不在本范围内：

- 手机触屏壳层的底部半模态（`SheetType.BOTTOM`）保持现状。
- 指针触发的右键菜单已由 [`aira-desktop-context-menu-design-spec.md`](./aira-desktop-context-menu-design-spec.md) 约束，本规范只要求两者共用同一套遮罩浓度、圆角阶梯与 hover 语言。
- 非模态的 Toast / InfoBar 不在范围内。

实现：`DesktopDialogShell.ets`、`BrowserDialogPresentationTokens.ets`、`DesktopDialogWidthViewModel.ets`、`DesktopDialogSheetChrome.ets`。

视觉草稿：`docs/reference/aira-desktop-dialog-prototype.html`（现状 / 建议并排，含「清除浏览数据」应用示例）。

---

## 1. 落地前基线

### 1.1 PC 上的居中弹窗目前有 5 套并行机制

| # | 机制 | 规模 | 宽度来源 | 是否为大屏设计 |
| --- | --- | --- | --- | --- |
| A | `BrowserAdaptiveModalOverlay` + `BrowserLargeScreenModalHeader` | 10 个宿主 | `desktopWidth` 百分比 → `AppWindowModalLayoutService.resolveModal()`，再被 `desktopMinWidth` / `desktopMaxWidth` 夹取 | 是，唯一一套 |
| B | `@CustomDialog` + `DialogAlignment.Center` + `CENTERED_DIALOG_*_SURFACE_MODIFIER` | 39 个 struct / 54 个 controller（40 个设了 `Center`） | 内容 `calc(100% - 24vp)`，`maxWidth` 420（"宽变体" 560） | 否，直接复用手机 modifier |
| C | `AlertDialog.show` / `showCenteredAlertDialog` | **93 个调用点 / 42 个文件**（另有 1 处定义 + 2 处裸 `AlertDialog.show`） | `CenteredDialogWidthViewModel`：窗口宽 > 467vp 时钉死 420 | 否，系统 chrome |
| D | `bindSheet` + `SheetType.CENTER` | 11 处，全部为条件式 | 平台决定（居中半模态默认高 560vp） | 半 |
| E | `bindSheet` 默认 / `SheetType.BOTTOM` | `bindSheet` 共 **25** 处；其中 **17 处**  在 PC 上仍是底部弹窗（1 处宿主在大屏不挂载，实际 16 处） | 平台决定 | 否，**PC 上仍是底部弹窗** |

E 的关键证据：`app/pages/BrowserShellPage.ets:6650` 固定 `preferType: SheetType.BOTTOM` 且 `dragBar: true`，没有任何大屏分支。`BrowserSystemSurfacePresentationViewModel.resolve()` 只把 `homeShortcutSelection`、`homeSettings`、`userScriptInstall` 与 4 种小说阅读器类型改派到居中对话框，其余 10 种类型在 PC 窗口上依然是带拖拽条的底部弹窗。

> 全量逐条清单（含每处 file:line）见 `docs/aira-desktop-dialog-inventory.md`，逐个视觉草稿见 `docs/reference/aira-desktop-dialog-catalog.html`。
>
> 另：D 类 11 处虽然都是条件式 CENTER，但判断条件用了 **6 种不同命名的 prop**（`shellFamily`、`desktopPresentation`、`pageLayoutMode`、`presentationMode`、`isLargeScreen`、`useCenteredSheet`）——同一个决策用了六种开关名，这是宽度与内边距不统一的直接原因。

### 1.2 不一致清单

**宽度。** 居中对话框家族里同时存在 400 / 420 / 460 / 480 / 500 / 520 / 560 / 600 / 620 / 640 / 680 / 720 共 12 个 `maxWidth` 数值，外加 64% / 68% / 70% / 76% / 82% 共 5 个百分比宽度。`BrowserAdaptiveModalOverlay` 单文件默认值即为 `'82%'` / min 520 / max 720。

**平台容器上限。** 官方文档（`ts-methods-custom-dialog-box`，`width` 属性）写明"弹窗宽度默认最大值：400vp"；`CenteredDialogSurface.ets` 的注释也记录了 "CustomDialogController caps its own box at 400 vp by default"。但全仓**没有任何 controller 设置 `width` 或 `gridCount`**（已 grep 确认为 0），而 `CENTERED_DIALOG_SYSTEM_TALL_DEFINITE_SURFACE_MODIFIER` 却把内容宽度设到 `resolveCenteredWideDialogWidth()`（可达 560）。

**圆角。** 对话框外壳有三处各自定义的同值常量 28vp（`BROWSER_LARGE_SCREEN_MODAL_CORNER_RADIUS_VP` / `CENTERED_DIALOG_CORNER_RADIUS_VP` / `BROWSER_MODAL_BOTTOM_SHEET_CORNER_RADIUS`），覆盖了平台默认的 32vp。对话框**内部**卡片圆角另有 24 / 22 / 18 / 16 / 14 / 10，`SettingsGroupCard` 在手机态 22、`desktopPresentation` 时 8 —— 同一屏出现三层不同圆角。

**内边距。** 居中对话框 20/20/22/18；底部 sheet 16/26/24；AdaptiveOverlay 里的 `flat_content` 由每个调用点自己写 16/16~26/20~24；header 左 20 / 右 16。

**标题。** `BrowserLargeScreenModalHeader` 17fp Medium 左对齐，但同一个组件在 `dialogMode` 为 true 时切到 20fp Bold 居中；`@CustomDialog` 正文标题统一 20fp Bold 居中（`SyncResultDialog` 例外，19fp）；`BrowserFeatureSheetHeader` 24fp Bold 左对齐。同一套 chrome 组件里靠布尔值切换两套标题规范。

**按钮。** `BrowserSheetActionButton({ stacked: true })` + `Column` 产生竖向堆叠、全宽、44vp 胶囊、15fp 的按钮，是绝大多数居中对话框的默认写法（例：`DesktopInterfaceModeConfirmationDialog.ets:48-70`）。连原生 AlertDialog 也有 7 处强制竖向：`BrowserWebCapabilityAlertDialogPresenter.ets:111`、`BrowserDownloadManagementScreen.ets:1542`、`SyncExperienceHost.ets:585/629/657/678/724` —— 后两者本身就是大屏专用界面。

**遮罩。** 系统 `maskColor` 默认 `0x33000000`（20%）用于 B / C / D 路径；自绘 `$r('app.color.browser_overlay_scrim')` = `#66000000`（40%）用于 A 路径。

**阴影。** `BrowserAdaptiveModalOverlay` 的卡片完全没有 `.shadow()`，只有 border 与 clip；`@CustomDialog` 路径在 2in1 上由平台给 `OUTER_FLOATING_MD`（获焦）/ `OUTER_FLOATING_SM`（失焦）。

**动效与关闭。** A 路径 220ms `EaseOut` + `scale 0.97` + 自绘 scrim 淡入，已接 ESC；B / C 路径走平台默认动画，代码里没有时长常量。关闭方式：A 有 header ✕；多数 `@CustomDialog` 没有关闭按钮，只依赖点遮罩或 ESC；`NewUserGiftOverlay` 与 `BottomToolbarGuideOverlay` 设了 `dismissOnOutsideTap: false`。

**输入框。** `BrowserShellDialogs.ets` 中 7 处采用下划线式输入框（透明背景 + 仅底边 1vp 边框 + `borderRadius(0)` + 44vp），是移动端表单习惯。

**hover / focus。** `app/components` 下只有 19 个文件含 `onHover` 或 `hoverEffect`，集中在 settings rows 与菜单；居中对话框内容区基本没有鼠标态反馈。

**测试覆盖。** `test/CenteredDialogWidthViewModel.test.ets` 是唯一的居中弹窗相关契约测试。没有任何测试引用 `BrowserModalPresentationTokens`、`BrowserAdaptiveModalOverlay`、`BrowserSystemSurfacePresentationViewModel` 或 `BrowserBottomSheetSurfacePresentation`。

**已确认的确定性缺陷。**

- `ClearBrowsingDataDialog.ets` 的 `dialogState.message` 在两个布局（`buildDialogLayout` 与 `buildSheetLayout`）里都没有被渲染，PC 弹窗与手机 sheet 都丢失了「时间范围适用于历史记录和最近关闭；Cookie、缓存、站点存储按系统 Web 能力清除全部。」这句必要说明。
- 分组卡使用与弹窗相同的 surface 色，分组边界只剩 0.5vp 分割线。

### 1.3 官方平台事实（HarmonyOS 文档，作为平台侧唯一依据）

`CustomDialog`（`customStyle: false`）：

- 默认圆角 32vp；未设置宽高时容器宽度按栅格系统自适应。
- `width` 属性：默认最大值 400vp；百分比相对**所在窗口**宽度。
- 高度默认最大 `0.9 × (窗口高 - 安全区域)`。
- "受安全区域的影响，弹窗显示区域将排除安全区域。例如在 PC/2in1 设备上避让屏幕边缘以及窗口标题栏。"
- `shadow`：**当设备为 2in1 时，默认场景下获焦阴影值为 `OUTER_FLOATING_MD`，失焦为 `OUTER_FLOATING_SM`；其他设备默认无阴影。**

`bindSheet` 的 `preferType`（`ts-universal-attributes-sheet-transition`）：

- 宽度 `< 600vp`：底部、全屏，默认底部。
- `600vp ≤ 宽度 < 840vp`：底部、居中、跟手、侧边、全屏，默认居中。
- 宽度 `≥ 840vp`：同上，默认跟手。
- 居中 / 跟手弹窗：`SheetSize.LARGE` 与 `MEDIUM` 无效，默认高度 560vp；最小 320vp，最大窗口短边 90%。

半模态设计指南（`design-guides/bindsheet`）：

- 最小高度 320vp，最大高度"屏幕短边的 90%"。
- "半模态内容在更大屏幕上可以选择使用 Popup 容器承载，容器宽度保持默认 400vp。"
- "电脑设备中半模态的最大高度规则始终保持为窗口高度的 90%，跟随窗口高度拉伸。"

官方多设备最佳实践（平板 / 折叠屏 / Pura X 三处重复同一结论）：

> 构建 UI 布局时，可通过条件表达式判断：当横向断点为 sm 时，使用普通居中弹框；否则，使用跟手弹框 PopoverDialog，提升大屏设备的操作效率。

并给出 `preferType: SheetType.POPUP`：宽度 < 600vp 的设备默认显示底部弹窗，其他设备自动适配为跟手弹窗。

通用应用 UX 体验标准：

- 点击热区不得小于 40vp×40vp（推荐 48vp×48vp）。
- 电脑设备键鼠交互热区不小于 5mm；触屏不小于 7mm。
- 断点 API：`getWindowWidthBreakpoint()` → XSmall / Small / Medium / Large / XLarge。
- 警告弹窗 `title` 与 `subtitle` 的字体最大放大倍数为 2。

### 1.4 主流桌面规范对比

| 规范 | 最小宽 | 最大宽 | 圆角 | 内边距 | 按钮 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| Material 3 basic dialog | 280dp | **560dp** | 28dp | 24dp | 右对齐，8dp 间距，确认最右 | scrim 32%、elevation 6dp、标题 24sp、正文 14sp。超出 560 应改用 side sheet 或整页，不拉伸对话框 |
| Fluent 2 Dialog | 320px | **600px** | 8px | 24px | 右对齐 | 超出则改用 Drawer / Page |
| Apple HIG（macOS） | — | alert 标准 **420pt**（260–540pt）；sheet 不宽于父窗口；设置类窗口约 400–600pt | — | 边缘 20pt | 右对齐，默认按钮最右，取消在其左 | 控件间距 8pt、按钮间距 12pt |

三边共识：纯对话框（确认 / 表单）的合理上限是 **560–600**；内容更宽时规范一致要求**换形态**（side sheet / 跟手 popover / 整页）；按钮横向右对齐；标题习惯左对齐。

补充：以上三家的具体数字差异很大（Material 半径 28 / Fluent 半径 8 / macOS 半径 10–12），所以"对齐 Material"和"对齐 macOS"会产出**完全不同的观感**。本规范的风格基线选择见 2.1。

---

## 2. 设计结论

### 2.1 风格基线：参考图语言（v3）

**决策：以三张参考图（`Alert.png` / `Alert2.png` / `Small.png`）建立的视觉语言为唯一基线。** 它取代了之前的 macOS / AppKit 取向草案。

参考图确立的语言：

| 特征 | 参考图 |
| --- | --- |
| 大圆角、**无描边**、靠阴影分层 | 三张图一致（圆角约为宽度的 6%），删掉上一版的 `0.5vp` 描边 |
| 按钮是 **40vp 胶囊**（半径 = 高度 / 2），纯色填充，无描边无渐变无阴影 | `Alert.png` / `Alert2.png` |
| 次要按钮 = **浅灰填充**（非描边、非透明） | 三张图的 `Label` / `Cancel` / `**` |
| 危险按钮 = **浅红填充 + 红字**（**不是**实心红，也不是只有红字） | `Alert2.png` 的 `Don't Save`、`Small.png` 的 `Delete` |
| 标题 **19fp Bold 左对齐、可换行**（不做单行省略） | `Alert.png`「Save this message as a draft?」 |
| 正文 13.5fp、行高 1.5、与背景拉开层级 | 三张图 |
| 1–2 个动作 → **并排等宽**；≥3 个动作 → **竖向堆叠全宽** | `Alert.png` / `Alert2.png` |
| 表单：标签右对齐 + 控件左对齐；输入框白底 + 1vp 描边 + **聚焦蓝色外发光**；选择器 / 下拉用**灰色填充无描边** + 尾部 chevron | `Small.png` |

**无渐变原则（硬规定）：** 任何控件（按钮、复选框、单选框、开关、选中态、窗口标题栏、工具条、菜单选中行）都不得使用渐变、内部高光或光泽效果。控件只用 `纯色填充 + 圆角 + 阴影` 三个手段表达层次。

**PC 密度决策（已定）：一个数都不缩。**

参考图是移动/平板尺度（40vp 胶囊按钮、19fp 标题、24vp 圆角），看着像“在 PC 上会太大”，但结论是**保持原值**：

| 项 | 结论 | 依据 |
| --- | --- | --- |
| 按钮高 `40vp` | **不动** | 这就是 HarmonyOS 平台自己在 PC/2in1 上的对话框尺寸。官方热区标准本身分设备：电脑键鼠 ≥ 5mm，触屏 ≥ 7mm；系统推荐触屏点击热区 `40vp×40vp`。跟着平台走，在系统对话框旁边才不突兀；PC/2in1 本身也可能两用触屏 |
| 标题 `19fp` | **不动** | 它不是“大”：Windows 11 对话框标题约 20px，HarmonyOS 对话框标题默认 20fp Bold。缩小反而发虚 |
| 圆角 `24vp` | **不动** | 这套参考图语言的签名特征，缩了就不像了 |
| 内边距 `24vp` | **不动** | Material 与 Fluent 的对话框也正好都是 24 |
| 动作排布 | **只改这里** | “仅使用期间允许”折行的根因是 **3 个按钮并排**，不是字号大。已由“≥ 3 个竖排”修好，再加一条防折行规则（见 2.5） |

**不引入按设备切换密度的机制。** 虽然官方热区标准分设备，但双档密度会新增一个不一致轴。保持单一值，用排布规则解决拥挤。

**保留的上一版结论：** 关闭路径不默认提供右上 ✕（由「取消」+ Esc 承担）；强调色只用在主按钮与选中态上。

视觉草稿：`docs/reference/aira-desktop-dialog-catalog.html`（全量 83 张逐个）与 `docs/reference/aira-desktop-dialog-prototype.html`（三风格对比 + 解剖 + 实例）。

### 2.2 形态收敛

`large_screen` 下只允许两种模态形态：

1. **居中对话框**：局部确认、权限、认证、短表单、单选列表。对应官方"sm 断点用普通居中弹框"。
2. **跟手弹窗（popover）**：由触发控件锚定弹出，用于选项列表与高频工具。对应官方"大屏用跟手弹框提升效率"，实现走 `SheetType.POPUP` 或自绘锚定壳。

明确禁止：

- **`large_screen` 下出现底部弹窗，零容忍。当前共 26 处，三种机制，全部需要改。**
  - 机制 A：`bindSheet` + `SheetType.BOTTOM` + `dragBar: true`（**21 处**调用点）
  - 机制 B：**直接使用 `BrowserModalBottomOverlay`**（**5 处**：HLS 接管 / 朗读播放器×2 / 元素检查 / 选择书签文件夹）。这 5 处不经 `bindSheet`，所以早期审计漏掉了；审计时不能只 grep `bindSheet`。
  - 完整清单：`docs/aira-desktop-dialog-inventory.md` 第 6 节；改后效果：`docs/reference/aira-desktop-dialog-catalog.html` 第 6 节。
- **同一份内容在 PC 上仍然靠 `layoutMode === 'phone'` 分支走手机布局。** `BrowserBottomSheetSurface({ presentation: 'flat_content' })` 这种"透明壳套在别人 chrome 里"的写法（14 个文件）必须收敛。
- **使用 `BrowserImmersiveSheetLayout`。** 它的模糊标题栏 + 内容顶部 76vp 内缩是为底部弹窗设计的，居中对话框不用。
- **只给部分入口加壳层判断。** 同一个组件被多个宿主复用时，条件式 `preferType` 会在没传 prop 的路由页上静默退化成底部弹窗——当前有 **9 处** 属于这种情况。要么在所有入口都传，要么根本不提供手机分支。
- 每个调用点自己写宽度、圆角、内边距、遮罩或动画时长。
- 3 个及以上动作并排。

> 注：上一版草案曾禁止"竖向堆叠全宽按钮"；参考图 `Alert2.png` 对 ≥3 个动作明确使用竖向堆叠，所以该条已改为"1–2 个动作并排，≥3 个动作堆叠"。竖向堆叠不再是"手机感"的问题，按钮的**尺寸与填充语言**才是。

> 注：上一版草案曾禁止"竖向堆叠全宽按钮"；参考图 `Alert2.png` 对 ≥3 个动作明确使用竖向堆叠，所以该条已改为"1–2 个动作并排，≥3 个动作堆叠"。竖向堆叠不再是"手机感"的问题，按钮的**尺寸与填充语言**才是。

### 2.3 宽度算法

#### 2.3.1 现在的乱源

宽度同时有三个互不相干的来源：

1. **平台默认**：`@CustomDialog` 在 `customStyle: false` 下容器最大 **400vp**（官方文档 `ts-methods-custom-dialog-box`），且全仓 **没有任何 controller 设置 `width`**。所以这一族弹窗物理上上不了 420，而内容却声明 `maxWidth: 420`。
2. **百分比宽度**：`BrowserAdaptiveModalOverlay` 的 10 个宿主手写了 7 个百分比（`'82%'` / `'76%'` / `'70%'` / `'68%'` / `'64%'`）—— 同一弹窗在 900vp 窗口和 1440vp 窗口下**占据的比例不一样**，视觉上就是“一会儿宽一会儿窄”。
3. **逐处手写 maxWidth**：全仓有 12 个不同的 `maxWidth` 数值（400/420/460/480/500/520/560/600/620/640/680/720）加 5 个百分比。它们没有任何推导关系。

#### 2.3.2 两条硬禁止

- **禁止百分比宽度**。弹窗宽度只能是绝对值或“全宽降级”两种，不允许跟随窗口比例缩放。
- **禁止调用点写宽度数字**。调用方只声明**档位**，数值由 `core` 侧的 width view model 解析。

#### 2.3.3 唯一公式

```
入参：  tier    // 调用方按内容形状声明的档位
        W       // 当前窗口宽（vp）
        H       // 当前窗口高（vp）

edge       = 24                              // 距窗口边缘的最小留白
usableW    = W - edge * 2
usableH    = H - edge * 2

// 1. 先取档位标准宽
w = tier.width

// 2. 窄窗降级（见 2.3.5）
if W < 600:  w = usableW                      // 全宽对话框

// 3. 夹取：不低于档位最小宽，不高于可用宽
w = clamp(w, tier.minWidth, usableW)

// 4. 高度不设档位，由内容决定，只封顶
h = min(contentHeight, tier.maxHeight, usableH)
```

调用方不传 `W` / `H`（由壳注入），也不传任何像素值。

#### 2.3.4 档位与判据（决策表）

**档位由内容形状决定，不由宽度反推。** 下面是一张开发者直接查的表：

| 档位 | 标准宽 | 最小宽 | 上限 | 判据（满足任一） |
| --- | --- | --- | --- | --- |
| **XS** | `360vp` | `320vp` | 560 | 只有标题 + ≤ 1 行正文 + ≤ 2 个动作；或只有一个控件；或是进度指示 |
| **S** | `420vp` | `320vp` | 560 | 有输入控件但无列表；或只有图片/二维码；或 3 个动作的纯确认 |
| **M** | `520vp` | `360vp` | 640 | 有列表（可选项 / 键值行 / 开关行 / 双行说明） |
| **L** | `640vp` | `420vp` | 720 | 有 ≥ 2 个分段标题；或内嵌导航；或需要滚动阅读的长文档 |
| **XL** | `720vp` | `480vp` | 720 | 全文阅读类（法务全文、变更日志全文、小说目录全长）。**当前 94 个表面中无一项使用**，保留备用 |

补充判据（避免歧义）：

- 3 行以内的“说明分行”不算列表，仍算 XS / S。
- **列表判据 = ≥ 2 行**键值行 / 可选项 / 开关行。“键值行”（标签 值）算列表，所以文件信息 / 历史详情 / 操作结果这类都上 M；**但只有 1 行键值行不算列表**（如「需要升级 Aira」的可用版本行），归 S。
- 只有 1 个输入框的极简表单（新建文件夹）也走 S，不要因为“就一个框”降到 XS——XS 的语义是“没有可操作控件”。
- 宽度档位与形态无关：居中对话框和跟手弹窗用同一张表。

#### 2.3.5 降级规则

| 条件 | 行为 |
| --- | --- |
| `W < 600vp` | 宽度改为 `W - 24vp`（全宽对话框）；圆角 24 → 20；左右内边距 24 → 20 |
| `W < 480vp` | 无论几个动作，**全部竖向堆叠**（并排会挤换行） |
| `W < 1000vp` 且档位为 L / XL | 逐级降档：`XL → L → M`，不改变内容与分组 |
| `usableW < tier.minWidth` | 取 `usableW`（宁可窄也不溢出窗口） |

#### 2.3.6 高度规则

- 高度**不设档位**，由内容决定。
- 封顶：`min(720vp, H - 48vp)`。
- 超过封顶时：标题区与动作区固定，**只有正文区滚动**。
- 标题最多 2 行折行（不做单行省略）。

#### 2.3.7 平台陷阱（必须写进实现）

`@CustomDialog` + `customStyle: false` 时容器默认上限 400vp。当前全仓 **0 个 controller 设置 `width`**，所以：

- 任何 S 档及以上的 `@CustomDialog` 都会被卡到 400vp，且 `CENTERED_DIALOG_SYSTEM_TALL_DEFINITE_SURFACE_MODIFIER` 声明的 560vp 内容会被裁切。
- 实现时必须**同时在 controller 上写 `width: tier.width`**（controller 级 `width` 才能突破容器默认上限），而不是只给内容挂 `maxWidth`。
- `AlertDialog` 路径不受 400vp 限制，直接给 `width = tier.width` 即可。

#### 2.3.8 逐表面分档表（已定档，直接实现）

按内容形状逐项定档的结果（与 `docs/reference/aira-desktop-dialog-catalog.html` 的 94 张草图一一对应）：

| 档位 | 数量 | 表面 |
| --- | --- | --- |
| **XS 360** | 11 | A1 两按钮确认 · A2 单按钮提示 · A3 破坏性确认 · B02 规则导入进度 · B03 备份导入进度 · B10 网页缩放 · B19 网页文字大小 · B33 同步进度 · B35 翻译校验（工作区） · B39 翻译校验（页面） · S2 同步尚未开启 |
| **S 420** | 31 | A4/A4b/A4c 多按钮确认 · B01 URL 订阅导入 · B06 新建文件夹 · B07 编辑书签 · B11 隐私模式切换 · B13 编辑快捷方式 · B15 安装网页 · B16 网页提示 · B17 HTTP Auth · B18 站点权限请求 · B23 添加网址主页 · B24 免费领取 Pro · B25 始终保持隐私模式 · B27 手机上的桌面界面 · B28 添加自定义 DNS · B29 交流QQ群 · B30 添加站点 · B36 需要升级 Aira · B38 从 URL 添加 · C2 底部工具条 · C4 新用户礼包 · D-b 登录确认 · D-c 风险同意 · E1 脚本安装（自绘） · G1 内容过滤同意 · G2 第三方规则 · G3 脚本风险 · H4 自定义 UA · T4 朗读播放器 |
| **M 520** | 40 | B04 选择导入内容 · B05 导入成功 · B08 下载确认 · B09 下载设置 · B12 文件信息 · B14 举报网站 · B20 主页设置 · B21 添加至首页 · B22 选择音色 · B31 选择同步内容（开关） · B32 同步失败 · B34 操作结果 · B37 安装用户脚本 · C3 移动书签 · C5 小说目录 · C6 网页工具 · C7 FeatureGate · C8 Wi-Fi 信息 · C9 目标语言 · C10 软件更新 · D-a 备份频率 · G4 脚本更新检查 · G6 开发者说明 · H2 屏幕方向 · H5 更多工具 · H6 工具栏自定义 · H7 页面脚本 · H10 HLS 接管 · H11 历史详情 · H12 标签页样式 · H13 应用内代理 · H14 同步方式 · H15 跨设备标签页 · H16 离线网页详情 · S1 额外备份内容 · S3 同步内容开关卡 · T1 选择书签文件夹 · T2 脚本安装详情 · T6 Cookie 管理 · T8 主页外观 |
| **L 640** | 10 | B26 清除浏览数据（两段 10 行） · C1 Aira Pro 桌面弹窗 · G5 发布公告 · G7 同步指南 · G8 法务文档 · H1 站点信息（分段） · H3 网页标识（三段） · H8 页面资源候选 · T3 阅读体验面板 · T5 小说阅读器浮层 |
| **XL 720** | 0 | （保留） |

不在表内的两个（H9 图片预览、T7 隐藏元素选择）是**全屏浮层**，不走弹窗宽度规范。

> **量化对比**：实现本算法后，居中对话框家族从“3 套宽度来源 + 12 个裸数值 + 5 个百分比”收敛为“**4 个在用档位 + 1 个保留档位 + 1 个公式**”。

### 2.4 Token 表（目标值，参考图语言取向）

| 项 | 目标值 | 说明 |
| --- | --- | --- |
| 外壳圆角 | `24vp` | 参考图圆角约为宽度的 6%；已废弃 28vp / 12vp / 平台 32vp |
| 外壳描边 | **无** | 只靠阴影分层；已删除上一版的 `0.5vp` 描边 |
| 阴影 | 双层柔和 | `0 8px 28px rgba(16,20,32,.13)` + `0 2px 6px rgba(16,20,32,.07)` |
| 内边距 | `24 / 24 / 22 / 24` | 左右 24、上 24、下 24 |
| 标题 | `19fp` Bold 左对齐，**可换行** | 不做单行省略；废弃 13fp Semibold 与 `dialogMode` 居中变体 |
| 说明 / 正文 | `13.5fp`，行高 `1.5`，`rgba(10,10,12,.72)` | 标题与正文间距 `10vp` |
| 关闭入口 | 「取消」按钮 + Esc / ⌘. | 不默认提供右上✕ |
| 按钮尺寸 | 高 `40vp`，圆角 `20vp`（胶囊） | 触屏与桌面同一尺寸；小尺寸变体 `30vp` / `36vp` |
| 按钮样式 | **纯色填充，无描边、无渐变、无阴影** | 废弃上一版的描边 + 内高光 |
| 主按钮 | 强调色填充 + 白字 | |
| 次按钮 | `#ECEDEF` 填充 + 主文字色 | 不再用描边或透明底 |
| 危险按钮 | `#FFD8D5` 填充 + `#E03127` 字 | **不是实心红，也不是只有红字** |
| 按钮排布 | 1–2 个 → 并排等宽（`flex:1`），间距 `12vp`；≥3 个 → 竖向堆叠全宽 | 废止"竖向=手机感"的旧结论 |
| 文本框 | 高 `36vp`、圆角 `12vp`、白底 + `1vp #D9D9DE` 描边 | 聚焦：`2vp` 强调色描边 + `0 0 0 4vp` 外发光；多行高 `72vp` |
| 选择器 / 下拉 | 高 `36vp`、圆角 `12vp`、`#ECEDEF` 填充、**无描边** | 尾部 chevron |
| 选择控件 | `17vp`；复选框圆角 `4vp`，单选框实心圆 + 白点 | 选中填充强调色；前置标签在后 |
| 开关（Switch） | 轨道 `44 × 26vp`、圆角 `13vp`；滑块 `20vp` 白色圆 | 开启态轨道填强调色；**开关与复选框不可混用**：需逐项立即生效用开关，表单多选用复选框 |
| 列表行高 | `34vp` 单行 / 自适应双行 | 相邻行 `1vp rgba(0,0,0,.055)` 分隔 |
| 分组盒 | `#F2F3F5` 填充 + 圆角 `16vp`、**无描边** | |
| 悬停 | `rgba(0,0,0,.04)` | |
| 动效 | `120ms` 淡入，不做缩放 | 统一时长常量 |

### 2.5 交互规则

- 标题 19fp Bold 左对齐，下方接 13.5fp 正文；不再用布尔值在居中 / 左对齐之间切换。
- 按钮一律胶囊填充：主按钮强调色、次按钮浅灰、危险按钮浅红 + 红字；**不得使用描边式、透明底或渐变按钮**。
- 动作数量决定排布：**1–2 个并排等宽；≥ 3 个必须竖向堆叠全宽**（参考图 `Alert2.png`）。不允许 3 个及以上并排。
- **防折行**：任一标签按 `14fp` 估算后超过「内容宽 / 按钮数」时，也改为竖排。按钮标签永不折行（`maxLines: 1`），宁可竖排也不缩字号。
- 关闭路径统一为「取消」+ Esc / ⌘.；不默认提供右上角 ✕。
- 输入框为白底 + 描边的圆角样式，聚焦必须给出蓝色外发光；废弃下划线式。
- 选择器 / 下拉用灰色填充无描边，不要做成描边输入框。
- 所有可点击元素必须有悬停反馈；悬停只用极轻填充，不做整块变灰。
- 焦点顺序与 ESC 行为由壳统一接管；`dismissOnOutsideTap: false` 仅用于必须读完的公告，并在规范中逐条登记。
- 手机样式的圆形 hero 图标（56vp 底座 + 18vp 圆角）在桌面收敛为 48vp 底座 + 14vp 圆角。
- 强调色只允许出现在主按钮与选中状态的控件上。
- 危险语义必须用「浅红填充 + 红字」，不得用实心红块（太宣誓）、也不得只用红字（看不出可点）。
- 弹窗正文必须渲染状态里的说明字段；不允许出现「定义了 message 但没显示」的情况。

### 2.6 组件与所有权

沿用右键菜单已跑通的范式：

- `core/browser/BrowserDialogPresentationTokens.ets` —— 唯一的数值 owner。
- `core/browser/DesktopDialogWidthViewModel.ets` —— 宽度阶梯与降级策略（扩展现有 `CenteredDialogWidthViewModel`，遵守"policy 放 core"的贡献规则）。
- `app/components/common/DesktopDialogShell.ets` —— 唯一的 ArkUI 容器 owner，负责 header、✕、宽度、圆角、阴影、遮罩、hover、ESC 与焦点。
- `docs/aira-desktop-dialog-design-spec.md` —— 本文件，唯一的规范 owner。
- 业务组件只声明标题、档位语义、按钮与动作，不得出现宽度、圆角、内边距、遮罩、动画时长的裸数字。

**待决策的工程取舍：**

- 方案 A：保留原生 `@CustomDialog`，但在 controller 上显式设置 `width` 与 `cornerRadius`（否则宽度永远卡在 400vp）。
- 方案 B：把 B / C / D 路径全部收敛到 `DesktopDialogShell`（`BrowserAdaptiveModalOverlay` 的泛化版），原生 `CustomDialog` 只保留给最简单的 1–2 按钮确认。

建议 **方案 B**：只有自绘壳能同时解决宽度阶梯、阴影、遮罩浓度、hover、标题对齐与关闭入口这 6 个问题，且项目已有 80% 成品的 `BrowserAdaptiveModalOverlay` 可复用。

---

## 3. 迁移顺序

1. **E 类优先**：把 PC 上仍是底部弹窗的 **26 处**（机制 A 21 处 + 机制 B 5 处）全部改为居中对话框。内容组件**一行不用改**，只换宿主并删 `dragBar` / `BrowserImmersiveSheetLayout` / `BrowserModalBottomOverlay`。同时把 9 处"只给部分入口加壳层判断"的组件改成全入口一致。观感收益最大。（用户已确认：本次一起做）
2. 修掉已确认的缺陷：`CENTERED_DIALOG_SYSTEM_TALL_DEFINITE_SURFACE_MODIFIER` 的 560 内容宽在 400vp 容器内的裁剪问题（见第 4 节），以及 `ClearBrowsingDataDialog` 丢失 `message` 与分组卡不可见的问题。
3. 建立 tokens 与 `DesktopDialogShell`，先迁 3–5 个代表性对话框（确认类、表单类、列表类各一）作为样板。
4. 批量迁移 B 类 39 个 `@CustomDialog`，删除各调用点的裸数值与 `presentation: 'flat_content'` 分支。
5. 收敛 A 类 10 个 `BrowserAdaptiveModalOverlay` 宿主：默认值进 tokens，删除每处手写的 `desktopWidth / Min / Max`。
6. 补契约测试：扩展现有 `test/CenteredDialogWidthViewModel.test.ets`，断言阶梯值、夹取规则、档位降级、遮罩与圆角 token。

---

## 4. 待确认事项

以下均需真机 / 模拟器验证，本规范暂不下结论：

1. `CENTERED_DIALOG_SYSTEM_TALL_DEFINITE_SURFACE_MODIFIER` 设到 560vp 的内容宽，在 2in1 上是否真的被 400vp 容器裁掉。
2. `customStyle: false` 配合显式 `width` 是否能突破 400vp 上限（若不能，方案 A 不成立）。
3. `BrowserAdaptiveModalOverlay` 的 `bindContentCover` + 0×0 `Row` 方案在键盘焦点、输入法避让、多窗口切换下的行为是否满足方案 B 的要求。
4. `SheetType.POPUP` 在本项目当前 API 版本上的跟手行为与锚定目标能力。
5. 桌面鼠标热区按 5mm 折算后，24vp 按钮高度与 26vp 列表行高是否需要在低 DPI 设备上回退到 28vp / 32vp。
6. 居中对话框收敛到半径 12vp / 24vp 按钮之后，已冻结的桌面菜单标准（容器半径 18vp、行高 44vp）是否也需要同步降档，否则两套桌面语言会并存。
7. HarmonyOS 平台自身在 2in1 上的对话框观感（默认阴影 `OUTER_FLOATING_MD`）与 macOS 取向的自绘三层阴影叠加时，是否需要把原生阴影显式关掉。
