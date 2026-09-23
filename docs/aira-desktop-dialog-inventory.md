# Aira 居中弹窗全量清单（只读盘点）

状态：**盘点结果，未做任何代码改动。** 盘点范围 `AiraBrowser/entry/src/main/ets/**/*.ets`，已排除 `*/build/*`、`*/.test/*`、`oh_modules`、`node_modules`。视觉草稿见 `docs/reference/aira-desktop-dialog-catalog.html`，规范见 `docs/aira-desktop-dialog-design-spec.md`。

## 0. 总览

| 机制 | 数量 | 说明 |
| --- | --- | --- |
| `@CustomDialog` struct | **39** | 由 **54** 个 `CustomDialogController` 实例化；40 个 controller 显式设 `DialogAlignment.Center`，14 个未设置（用平台默认） |
| `showCenteredAlertDialog(...)` 调用点 | **93** | 分布 42 个文件；另有 1 处定义（`CenteredDialogSurface.ets:110`） |
| 裸 `AlertDialog.show(...)` | **3** | `CenteredDialogSurface.ets:111`（定义内）、`BrowserNativeAlertDialogPresenter.ets:24`、`:38` |
| `BrowserAdaptiveModalOverlay` 宿主 | **10** | 大屏专用居中卡片壳 |
| `bindSheet` + `preferType: SheetType.CENTER` | **11** | 全部为条件式（`shellFamily` / `desktopPresentation` / `useCenteredSheet` / `presentationMode`） |
| 自绘居中模态 | **1** | `UserScriptManagementHost.buildNativeModalSurface()` |
| `bindContentCover` | **2** | 其中 1 处就是 `BrowserAdaptiveModalOverlay` 内部 |
| **PC 上仍是底部弹窗**（`SheetType.BOTTOM` 字面量、无大屏分支） | **17 处 + 10 种 systemSheet 类型** | 见第 6 节，这是最需要优先处理的 |
| `bindSheet` 总数 | 25 | 其中 24 处写了 `preferType` |
| 手写 `Stack({ alignContent: Alignment.Center })` | 134 处 / 78 文件 | 绝大多数是图标、封面等局部布局容器；真正构成全屏覆盖层的只有 5 处，其中居中的 1 处 |

**不存在的机制**（已确认）：`promptAction.openCustomDialog`、`getPromptAction().openCustomDialog`、`UIContext.*CustomDialog*`、`UIContext.showAlertDialog`、`CustomDialog.show`、`showActionSheet`、`CustomDialogController` 之外的 `DialogAlignment.Center`、无条件的 `SheetType.CENTER`。

> **形状归并**：93 个 `showCenteredAlertDialog` 调用点只有 **4 种按钮形状**（见第 2 节），所以视觉上只需 4 张草稿即可覆盖全部 93 处。39 个 `@CustomDialog` 与 10 个 overlay 宿主各有独立布局，需逐个画。

---

## 1. `@CustomDialog` 全量（39 个 struct）

`C` = controller 设置。所有 controller 的公共项：`customStyle: false`（除 `AiraProComplimentaryClaimDialog` 为 `true`）、`cornerRadius: CENTERED_DIALOG_CORNER_RADIUS_VP`(28)、`backgroundColor: resolveCenteredDialogSurfaceColor()`、`backgroundBlurStyle: BlurStyle.NONE`。**没有任何 controller 设置 `gridCount` / `isModal` / `showInSubWindow` / `maskColor`；唯一设置 `width` 的是 `SyncExperienceScreen.ets:168`。**

| # | struct | 定义 | controller（file:line） | 可见标题 | 形状 | 按钮（顺序） | 布局 | surface | 打开者 / 大屏门控 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `AdBlockGithubRuleDialog` | `adblock/AdBlockCustomRulesScreen.ets:43` | `adblock/AdBlockCustomRulesHost.ets:94` | URL 订阅导入 | 表单（1 输入） | 确定 / 取消 | 竖向 | SYSTEM_SURFACE | `AdBlockCustomRulesHost.ets:244`；宿主兼大屏 `SettingsLargeScreenShell.ets:826` |
| 2 | `AdBlockRuleImportProgressDialog` | `adblock/AdBlockCustomRulesHost.ets:41` | `:109` | 正在处理（动态） | 进度 | 无 | — | SYSTEM_SURFACE | `:457` |
| 3 | `LocalBackupImportProgressDialog` | `backup/LocalBackupImportDialog.ets:43` | `backup/LocalBackupScreen.ets:149` | 正在导入备份 | 进度 | 无 | — | SYSTEM_SURFACE | `LocalBackupScreen.ets:514` |
| 4 | `LocalBackupImportDialog` | `backup/LocalBackupImportDialog.ets:258` | `backup/LocalBackupScreen.ets:111` | 选择导入内容 | 多选（5 开关） | 导入（单） | — | SYSTEM_SCROLL | `LocalBackupScreen.ets:470`，门控 `useCenteredImportDialog` |
| 5 | `BookmarkImportResultDialog` | `bookmarks/BookmarkImportResultDialog.ets:10` | `pages/BookmarkManagerPage.ets:261` | 导入成功 | 结果行 | 知道了 | 竖向 | SYSTEM_SURFACE | `BookmarkManagerPage.ets:1356` |
| 6 | `BookmarkManagerCreateFolderDialog` | `bookmarks/BookmarkManagerDialogs.ets:23` | `BookmarkLargeScreenWorkspace.ets:118`、`BookmarkManagerPage.ets:216`（**均未设 alignment**） | 新建文件夹 | 表单（1 输入） | 确定 / 取消 | 竖向 | SYSTEM_SURFACE | `BookmarkLargeScreenWorkspace.ets:272`（大屏）/ `BookmarkManagerPage.ets:842` |
| 7 | `BookmarkManagerEditNodeDialog` | `bookmarks/BookmarkManagerDialogs.ets:84` | `BookmarkLargeScreenWorkspace.ets:131`、`BookmarkManagerPage.ets:227`（**均未设 alignment**） | 编辑文件夹 / 编辑书签 | 表单（2 输入 + 图标） | 保存 / 取消 | 竖向 | SYSTEM_SURFACE | `BookmarkLargeScreenWorkspace.ets:804`（大屏）/ `BookmarkManagerPage.ets:1583` |
| 8 | `BrowserDownloadConfirmDialog` | `browser/BrowserDownloadConfirmSheet.ets:23` | `:300` | 无标题（文件类型图标） | 自定义 | 动态确认 / 动态取消 | 竖向 | SYSTEM_SURFACE | `:368` |
| 9 | `BrowserDownloadSettingsDialog` | `browser/BrowserDownloadSettingsDialog.ets:18` | `browser/BrowserDownloadManagementScreen.ets:141` | 下载设置 / HLS 分片并发数 / 自动清理 / 私密下载文件 / 私密下载记录 | 滚动列表 | 无（header 返回/关闭） | — | SYSTEM_TALL | `BrowserDownloadManagementScreen.ets:404`，仅大屏 `native_tab` |
| 10 | `BrowserLargeScreenWebZoomDialog` | `browser/BrowserLargeScreenWebZoomDialog.ets:18` | `pages/BrowserShellPage.ets:5457` | 网页缩放 | 自定义 | 默认 / 完成 | 默认 header 内 + 完成单按钮 | SYSTEM_SURFACE | `BrowserShellPage.ets:5034`（大屏 shell intent） |
| 11 | `BrowserPrivateModeConfirmationDialog` | `browser/BrowserPrivateModeConfirmationDialog.ets:13` | `pages/BrowserShellPage.ets:5482` | 动态 | 确认 + 条件 Checkbox | 动态确认 / 动态取消 | 竖向 | SYSTEM_SURFACE | `BrowserShellPage.ets:9899` |
| 12 | `DocumentViewerFileInfoDialog` | `browser/BrowserShellDialogs.ets:31` | `pages/BrowserShellPage.ets:5584` | 文件信息 | 键值行 | 知道了 | 竖向 | SYSTEM_SURFACE | `BrowserShellPage.ets:9893` |
| 13 | `HomeShortcutEditDialog` | `browser/BrowserShellDialogs.ets:96` | `pages/BrowserShellPage.ets:5504`（**未设 alignment**） | 编辑快捷方式 | 表单（2 输入 + 图标） | 保存 / 取消 | 竖向 | SYSTEM_SURFACE | `BrowserShellPage.ets:4556` |
| 14 | `SiteReportDialog` | `browser/BrowserShellDialogs.ets:208` | `pages/BrowserShellPage.ets:5569`（**未设 alignment**） | 举报网站 | 单选 + 备注 TextArea | 确定 / 取消 | 竖向 | SYSTEM_SURFACE | `BrowserShellPage.ets:10092` |
| 15 | `DesktopShortcutNameDialog` | `browser/BrowserShellDialogs.ets:330` | `pages/BrowserShellPage.ets:5520`（**未设 alignment**） | 安装网页 | 表单 + 图标选择 | 恢复网站图标（条件）/ 安装 / 取消 | 竖向 | SYSTEM_SURFACE | `BrowserShellPage.ets:3697` |
| 16 | `BrowserShellWebPromptDialog` | `browser/BrowserShellDialogs.ets:473` | `pages/BrowserShellPage.ets:5537`（**未设 alignment**） | 动态，回退「网页提示」 | 表单（1 输入） | 确定 / 取消 | 竖向 | SYSTEM_SURFACE | `BrowserShellPage.ets:4168` |
| 17 | `BrowserShellHttpAuthDialog` | `browser/BrowserShellDialogs.ets:551` | `pages/BrowserShellPage.ets:5553`（**未设 alignment**） | 动态 host，回退「网页身份验证」 | 表单（2 输入，其一带密码） | 登录 / 取消 | 竖向 | SYSTEM_SURFACE | `BrowserShellPage.ets:4178` |
| 18 | `BrowserSitePermissionPromptDialog` | `browser/BrowserSitePermissionPromptHost.ets:16` | `:75`（**未设 alignment**） | 动态，回退「站点权限请求」 | 确认 | 仅使用期间允许 / 本次使用允许 / 不允许 | 竖向 3 按钮 | SYSTEM_COMPACT | `BrowserSitePermissionPromptHost.ets:119` |
| 19 | `BrowserWebTextZoomSheet` | `browser/BrowserWebTextZoomSheet.ets:16` | `pages/BrowserShellPage.ets:5443` | 网页文字大小 | 自定义（缩放控件） | 默认（header）/ 完成 | 横向 Row | SYSTEM_SURFACE | `BrowserShellPage.ets:10284` |
| 20 | `HomePageSettingsDialog` | `browser/HomePageSettingsSheet.ets:46` | `browser/BrowserSystemSurfaceHost.ets:92` | 主页设置 / 壁纸设置 | 滚动列表 | 无（header 返回/关闭） | — | 无 modifier（用 `CenteredDialogSurface(fillHeight)`） | `BrowserSystemSurfaceHost.ets:269`，**大屏门控** |
| 21 | `HomeShortcutSelectionDialog` | `browser/HomeShortcutSelectionDialog.ets:9` | `browser/BrowserSystemSurfaceHost.ets:69` | 添加至首页 | 滚动列表（List×2） | 内容行内按钮 | — | SYSTEM_TALL | `BrowserSystemSurfaceHost.ets:252`，**大屏门控** |
| 22 | `ReaderSpeechVoiceDialog` | `browser/ReaderSpeechVoiceDialog.ets:23` | `offline/OfflinePageViewerScreen.ets:138`、`pages/BrowserShellPage.ets:5595` | 选择音色 | 单选（maxHeight 320） | 取消 | 横向 Row | SYSTEM_TALL_PADDED | `OfflinePageViewerScreen.ets:1405` / `BrowserShellPage.ets:9584` |
| 23 | `CustomHomepageRemoteUrlDialog` | `customhome/CustomHomepageRemoteUrlDialog.ets:5` | `customhome/CustomHomepageSettingsScreen.ets:194`（**未设 alignment**） | 添加网址主页 | 表单（1 输入 + helper/error） | 添加 / 取消 | 竖向 | SYSTEM_SURFACE | `CustomHomepageSettingsScreen.ets:993` |
| 24 | `AiraProComplimentaryClaimDialog` | `membership/AiraProComplimentaryClaimDialog.ets:20` | `membership/AiraProScreen.ets:109`（`customStyle: true`） | 免费领取 Aira Pro | 图片 + 天数 | 动态 / 取消 | 竖向 | 无（内联 width/constraintSize/radius） | `AiraProScreen.ets:320` |
| 25 | `AlwaysPrivateModeConfirmationDialog` | `settings/AlwaysPrivateModeConfirmationDialog.ets:9` | `SettingsInlineDetailPanel.ets:240`、`GeneralPrivateTabsSettingsPage.ets:56`、`SettingsDetailPage.ets:232` | 始终保持隐私模式 | 确认 + Checkbox | 确认开启 / 取消 | 竖向 | SYSTEM_SURFACE | 三处，均无壳层门控 |
| 26 | `ClearBrowsingDataDialog` | `settings/ClearBrowsingDataDialog.ets:328` | `settings/SettingsInlineDetailPanel.ets:210` | 清除浏览数据 | 多选（4 单选 + 6 复选） | 清除 / 取消 | 竖向 | SYSTEM_TALL_PADDED | `SettingsInlineDetailPanel.ets:932`，**大屏门控** |
| 27 | `DesktopInterfaceModeConfirmationDialog` | `settings/DesktopInterfaceModeConfirmationDialog.ets:9` | `settings/BrowserTabletInterfaceModeSettingsContent.ets:38` | 在手机上使用桌面界面？ | 确认 + Checkbox | 继续切换 / 取消 | 竖向 | SYSTEM_SURFACE | `BrowserTabletInterfaceModeSettingsContent.ets:115` |
| 28 | `SecureDnsProfileEditDialog` | `settings/SecureDnsProfileEditHost.ets:37` | `settings/SettingsLargeScreenShell.ets:207` | 添加自定义 DNS | 表单（2 输入） | 保存并使用 / 取消 | 竖向 | 无 modifier（用 `CenteredDialogSurface`） | `SettingsLargeScreenShell.ets:583`，**大屏门控** |
| 29 | `SupportQqGroupDialog` | `settings/SupportQqGroupDialog.ets:14` | `SettingsInlineDetailPanel.ets:226`、`SettingsDetailPage.ets:218` | 交流QQ群 | 二维码 + 群号 | 复制群号码 | 竖向 | SYSTEM_SURFACE | `SettingsInlineDetailPanel.ets:479` / `SettingsDetailPage.ets:574` |
| 30 | `SiteControlsManualOriginDialog` | `sitecontrols/SiteControlsManualOriginDialog.ets:11` | `SiteControlsCapabilityScreen.ets:94`、`SiteControlsManagementScreen.ets:102`（**均未设 alignment**） | 添加站点 | 表单（1 输入 URL） | 继续 / 取消 | 竖向 | SYSTEM_SURFACE | `SiteControlsCapabilityScreen.ets:299` / `SiteControlsManagementScreen.ets:157` |
| 31 | `SyncExperienceSelectionDialog` | `sync/SyncExperienceSelectionDialog.ets:17` | `sync/SyncExperienceScreen.ets:129`（唯一设置了 `width: resolveWideCenteredDialogWidth()`） | 选择同步内容 / 同步方式 | 步骤流（Navigation） | 下一步 | — | SYSTEM_TALL_DEFINITE | `SyncExperienceScreen.ets:764`，门控 `useLargeScreenSelectionDialog` |
| 32 | `SyncFailureDialog` | `sync/SyncFailureDialog.ets:10` | `SyncAdvancedSettingsPage.ets:131`、`SyncWebdavConfigPage.ets:146` | 同步失败（动态） | 详情行 | 知道了 / 复制详情 | 竖向 | SYSTEM_SURFACE | `SyncAdvancedSettingsPage.ets:812` / `SyncWebdavConfigPage.ets:991` |
| 33 | `SyncOperationProgressDialog` | `sync/SyncOperationProgressDialog.ets:10` | **7 个**：`SyncAdditionalBackupHost.ets:127`、`SyncExperienceHost.ets:85`、`SyncMasterControlSection.ets:68`、`BookmarkManagerPage.ets:242`、`CustomHomepageSettingsScreen.ets:212`、`SyncAdvancedSettingsPage.ets:169`、`SyncWebdavConfigPage.ets:183` | 正在处理 N%（动态） | 进度（72vp） | 无 | — | SYSTEM_SURFACE | 7 个打开点，均无壳层门控 |
| 34 | `SyncResultDialog` | `sync/SyncResultDialog.ets:22` | `SyncAdvancedSettingsPage.ets:147`、`SyncWebdavConfigPage.ets:162` | 操作结果（动态） | 滚动列表（maxHeight 340） | 知道了 | 竖向 | SYSTEM_SURFACE | `SyncAdvancedSettingsPage.ets:799` / `SyncWebdavConfigPage.ets:978` |
| 35 | `TranslationProviderWorkspaceValidationDialog` | `translation/TranslationProviderWorkspaceHost.ets:41` | `:80` | 正在测试翻译服务 | 进度（34vp） | 无 | — | SYSTEM_SURFACE | `:273` |
| 36 | `ClientUpdateRequiredDialog` | `update/ClientUpdateRequiredSheet.ets:18` | `:110` | 需要升级 Aira | 确认 + 版本 | 前往升级 / 继续使用本地功能 | 竖向 | SYSTEM_SURFACE | `:153` |
| 37 | `UserScriptInstallDialog` | `userscripts/UserScriptInstallDialog.ets:8` | `browser/BrowserSystemSurfaceHost.ets:112` | 准备安装用户脚本（动态） | 滚动列表 | 安装/更新 + 关闭 | — | SYSTEM_TALL | `BrowserSystemSurfaceHost.ets:290`，**大屏门控** |
| 38 | `UserScriptManualUrlDialog` | `userscripts/UserScriptManualUrlDialog.ets:10` | `userscripts/UserScriptManagementHost.ets:113`（**未设 alignment**） | 从 URL 添加 | 表单（1 输入 URL） | 读取 / 取消 | 竖向 | SYSTEM_SURFACE | `UserScriptManagementHost.ets:548` |
| 39 | `TranslationProviderValidationDialog` | `pages/TranslationProviderConfigPage.ets:38` | `:80` | 正在测试翻译服务 | 进度（34vp） | 无 | — | SYSTEM_SURFACE | `:203` |

**未设置 `alignment` 的 11 个 struct（14 个 controller）**：`BookmarkManagerCreateFolderDialog`、`BookmarkManagerEditNodeDialog`、`BrowserSitePermissionPromptDialog`、`CustomHomepageRemoteUrlDialog`、`SiteControlsManualOriginDialog`、`UserScriptManualUrlDialog`、`HomeShortcutEditDialog`、`DesktopShortcutNameDialog`、`BrowserShellWebPromptDialog`、`BrowserShellHttpAuthDialog`、`SiteReportDialog`。平台默认值为 `DialogAlignment.Default`，其运行时是否居中**不在仓库源码内，未确认** —— 这本身就是一个应当消除的不确定项（统一显式声明）。

---

## 2. `showCenteredAlertDialog` 全量（93 处 → 4 种形状）

所有调用点都经 `configureCenteredAlertDialog` 强制注入 `width`（宽窗钉 420）、`cornerRadius: 28`、`backgroundColor`、`backgroundBlurStyle: NONE`。

### 2.1 形状分类

| 形状 | 按钮 | 处数 | 说明 |
| --- | --- | --- | --- |
| **S1 两按钮** | 左「取消」+ 右「动作」 | 多数 | 默认 `HORIZONTAL`；右按钮按语义着色（破坏性用 `permission_blocked`） |
| **S2 单按钮** | 「知道了」 | 约 25 | 纯提示 |
| **S3 多按钮竖向** | 3 个 | **7 处** | 见 2.3，需改为横排 |
| **S4 仅 `secondaryButton`** | 单个「完成」/「知道了」 | 4 处 | `SyncPersonalServerConfigPage.ets:247,255,293` |

### 2.2 全部调用点（按文件）

| 文件 | 行号 |
| --- | --- |
| `components/adblock/AdBlockCustomRulesHost.ets` | 312、365、420 |
| `components/adblock/ManualElementHideSiteRulesHost.ets` | 144、184 |
| `components/backup/LocalBackupScreen.ets` | 540 |
| `components/bookmarks/BookmarkLargeScreenWorkspace.ets` | 816、895、1036 |
| `components/browser/BrowserDownloadManagementScreen.ets` | 908、958、**1538（S3）** |
| `components/browser/BrowserLargeScreenAccountPopover.ets` | 294 |
| `components/browser/BrowserNativeAlertDialogPresenter.ets` | 24、38（裸 `AlertDialog.show`） |
| `components/browser/BrowserWebCapabilityAlertDialogPresenter.ets` | 28、48、80、**107（S3）** |
| `components/browser/ExternalAppSearchDisclosurePresenter.ets` | 7 |
| `components/customhome/CustomHomepageSettingsScreen.ets` | 826、876、1088、1140 |
| `components/history/HistoryLargeScreenWorkspace.ets` | 463、486、505、524、548 |
| `components/history/HistoryManagerScreen.ets` | 1277、1315、1592、2497 |
| `components/novel/NovelBookshelfScreen.ets` | 418 |
| `components/offline/OfflinePageViewerScreen.ets` | 1614 |
| `components/offline/OfflinePagesScreen.ets` | 308 |
| `components/search/SearchEngineEditHost.ets` | 209 |
| `components/search/SearchSettingsHost.ets` | 333 |
| `components/settings/AppProxyProfileEditHost.ets` | 439 |
| `components/settings/BrowserToolbarCustomizationScreen.ets` | 696 |
| `components/settings/BrowserTrackingProtectionSettingsContent.ets` | 193 |
| `components/settings/BrowserUserAgentSettingsScreen.ets` | 720、815 |
| `components/settings/BrowserWebSecuritySettingsContent.ets` | 193 |
| `components/settings/SecureDnsProfileEditHost.ets` | 330 |
| `components/settings/SettingsEmbeddedDetailPanel.ets` | 942、1116 |
| `components/settings/SettingsInlineDetailPanel.ets` | 963、996、1034、1055 |
| `components/settings/SettingsWebAppsDetailPanel.ets` | 492 |
| `components/sync/HuaweiSpaceBookmarkUpgradePromptPresenter.ets` | 24 |
| `components/sync/SyncAdditionalBackupHost.ets` | 550、588 |
| `components/sync/SyncExperienceHost.ets` | 510、557、**581（S3）**、**625（S3）**、**653（S3）**、**674（S3）**、**720（S3）**、746、761 |
| `components/sync/SyncMasterControlSection.ets` | 159、218 |
| `components/translation/TranslationProviderWorkspaceHost.ets` | 253、330 |
| `components/userscripts/UserScriptManagementHost.ets` | 774 |
| `pages/AdBlockSettingsPage.ets` | 270 |
| `pages/BookmarkManagerPage.ets` | 1044、1342、1636 |
| `pages/HuaweiAccountInfoPage.ets` | 158 |
| `pages/SettingsDetailPage.ets` | 868、900、947、968 |
| `pages/SiteCustomizationDetailPage.ets` | 220 |
| `pages/SyncAdvancedSettingsPage.ets` | 412、434、553、648、697、720 |
| `pages/SyncPersonalServerConfigPage.ets` | 247、255、273、293 |
| `pages/SyncWebdavConfigPage.ets` | 591、647、764 |
| `pages/TranslationProviderConfigPage.ets` | 175、235 |
| `pages/UserScriptDetailPage.ets` | 132 |

### 2.3 强制竖向按钮（7 处，全部需改为横排）

1. `components/browser/BrowserWebCapabilityAlertDialogPresenter.ets:107` —— SSL / HTTPS-First 证书告警
2. `components/browser/BrowserDownloadManagementScreen.ets:1538` —— 删除下载（大屏 `native_tab` 界面）
3. `components/sync/SyncExperienceHost.ets:581` —— 需要升级后才能同步
4. `components/sync/SyncExperienceHost.ets:625` —— 同步失败（含更换同步方式）
5. `components/sync/SyncExperienceHost.ets:653` —— 同步失败（两按钮）
6. `components/sync/SyncExperienceHost.ets:674` —— 同步失败（无重试）
7. `components/sync/SyncExperienceHost.ets:720` —— Aira 云书签同步需要 Pro

### 2.4 复用形状的高频标题（40 个纯字面量）

`删除历史记录`(4)、`删除用户脚本`(3)、`刷新网站图标？`(2)、`清空拦截统计`(2)、`启用翻译服务？`(2)、`退出华为账号吗`(2)、`删除离线页面`(2)，其余 33 个各 1 次：`开启增强反跟踪？`、`恢复默认工具栏`、`删除代理`、`重置站点设置`、`删除自定义 DNS`、`删除自定义 UA`、`关闭 JavaScript？`、`删除自定义规则`、`删除这条清理规则`、`清除这个网站的规则`、`无法导入主页`、`使用该主页`、`恢复系统主页`、`删除自定义主页`、`清除搜索历史`、`删除搜索引擎`、`取消下载？`、`删除下载`、`移出书架`、`清除历史记录`、`删除站点历史记录`、`打开多个标签页`、`删除站点历史`、`关闭同步？`、`重新开启华为云空间书签同步`、`需要升级后才能同步`、`Aira 云书签同步需要 Pro`、`私有化部署已连接`、`连接失败`、`断开本机连接？`、`未能断开`、`删除书签`、`重置当前站点`。

---

## 3. `BrowserAdaptiveModalOverlay` 全量（10 处）

| # | 位置 | 标题 | desktopWidth / Height | minW–maxW / minH–maxH | showDesktopHeader | dismissOnOutsideTap | 内容形状 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A1 | `membership/AiraProScreen.ets:217` | 动态：登录华为账号 / 同步指南 / 法务标题 / 进入 Aira Pro | `'76%'` / 动态（`'82%'` 或 500） | 520–720 / 420–720 | 条件 | 默认 true | 法务网页文档 / 同步指南 / 华为登录 |
| A2 | `onboarding/BottomToolbarGuideOverlay.ets:28` | 底部工具条提示 | `'70%'` / 480 | 480–560 / 420–560 | 默认 true | **false** | 视频 + 文案 + 2 按钮 |
| A3 | `bookmarks/BookmarkMoveFolderSelectionSheet.ets:241` | 无（默认空） | `'64%'` / `'78%'` | 460–640 / 440–680 | **false** | 默认 true | 文件夹滚动列表（LazyForEach） |
| A4 | `browser/NewUserGiftOverlay.ets:24` | 新用户礼包 | `'70%'` / 460 | 480–560 / 420–520 | 默认 true | **false** | 礼包图 + 文案 + 单按钮 |
| A5 | `browser/BrowserSystemSurfaceHost.ets:159` | 目录 / 亮度与主题 / 阅读设置 / 文字 | 680/520/520/600 | 560–760、460–560、460–560、500–640 / 500–720、240–310、260–340、420–600 | 默认 true | 默认 true | 小说目录 / 设置表单 |
| A6 | `browser/BrowserWebPageToolsOverlayHost.ets:147` | 网站版本 / 网页标识 / 屏幕方向 / 站点信息 | `'76%'` / 动态 | 520–680 / 360–620 | 默认 true | 默认 true | 单选列表 / 站点信息 |
| A7 | `browser/FeatureGateOverlay.ets:23` | 动态 | `'70%'` / 520 | 480–560 / 460–600 | 默认 true | 默认 true | 套餐单选 |
| A8 | `browser/BrowserWifiQrResultOverlay.ets:64` | Wi-Fi 信息 | `'70%'` / 390 | 500–620 / 360–430 | 默认 true | 默认 true | 名称 / 密码 / 二维码 |
| A9 | `translation/WebpageTranslationTargetLanguageSheet.ets:234` | 目标语言 | `'68%'` / `'68%'` | 500–620 / 400–560 | 默认 true | 默认 true | 语言单选列表 |
| A10 | `update/CommunityUpdateOverlay.ets:28` | 软件更新 | `'70%'` / 520 | 480–560 / 460–620 | 默认 true | 默认 true | 更新说明滚动列表 |

`phoneSheetAlignment: Alignment.Center` 只有 3 处（A2 / A4 / A10），也就是说**这三个弹窗在手机形态下也是居中浮层**——在手机上是偏离既有规范的。`showDesktopRefreshButton` 无任何调用点。

---

## 4. `bindSheet` + `SheetType.CENTER` 全量（11 处）

| # | 站点 | CENTER 条件 | height | dragBar | showClose | 内容标题 | 形状 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| B1 | `sync/SyncAdditionalBackupHost.ets:219` | `desktopPresentation` | LARGE | `!desktopPresentation` | true | 备份频率 | 单选列表 |
| B2 | `membership/AiraProScreen.ets:189` | `pageLayoutMode === 'large_screen'` | FIT_CONTENT | `!==` | 条件 | 登录华为账号 / 法务 / 同步指南 | 自定义 |
| B3 | `sync/CrossDeviceLinkHost.ets:234` | `desktopPresentation` | FIT_CONTENT | `!` | false | 确认登录Aira-sync 扩展 | 纯确认 |
| B4 | `sync/CrossDeviceLinkHost.ets:247` | `desktopPresentation` | FIT_CONTENT | `!` | false | Aira / 使用华为账号登录，安全同步你的书签 | 登录表单 |
| B5 | `sync/CrossDeviceLinkHost.ets:260` | `desktopPresentation` | LARGE | `!` | true | 跨设备标签页（sheet title） | 滚动列表 |
| B6 | `settings/SettingsDetailContent.ets:146` | `isLargeScreen` | `'68%'` | `!` | false | 标签页样式 | 单选列表 |
| B7 | `settings/SettingsEmbeddedDetailPanel.ets:235` | `shellFamily === 'large_screen'` | FIT_CONTENT / LARGE | `!==` | false | 使用用户脚本前，请先了解风险 / 脚本更新检查 / 开启网页内容过滤？/ 启用第三方过滤规则？ | 风险同意 / 自定义 |
| B8 | `settings/BrowserToolbarCustomizationScreen.ets:190` | `desktopPresentation` | LARGE | `!` | true | 中间区域上滑 / 选择要自定义的操作 | 单选列表 |
| B9 | `customhome/CustomHomepageSettingsScreen.ets:356` | `presentationMode === 'embedded'` | FIT_CONTENT | `!==` | true | 开发者说明 | 自定义 + 按钮 |
| B10 | `settings/SettingsCenterScreen.ets:323` | `presentationMode === 'native_tab'` | LARGE / FIT_CONTENT | 条件 | 条件 | 确认登录Aira-sync 扩展 / 应用内代理 / 华为登录 | 纯确认 / 自定义 |
| B11 | `settings/BrowserUserAgentSettingsScreen.ets:201` | `useCenteredSheet` | LARGE | `!` | true | 自定义 UA | 表单 |

上述 11 处全部为**条件式** CENTER，条件来自 4 种不同的 prop 命名：`shellFamily`（1）、`desktopPresentation`（5）、`pageLayoutMode`（1）、`presentationMode`（2）、`isLargeScreen`（1）、`useCenteredSheet`（1）。**这本身就是需要收敛的点**——同一个决策用了 6 种不同的开关名。

---

## 5. 自绘居中模态（1 处）

| 位置 | 尺寸/层级 | 遮罩 | 标题 | 内容 |
| --- | --- | --- | --- | --- |
| `userscripts/UserScriptManagementHost.ets:390`（`buildNativeModalSurface`） | 全屏 Stack，`zIndex(40)`，尺寸由 `resolveNativeModalLayout()` 决定，圆角 `BROWSER_LARGE_SCREEN_MODAL_CORNER_RADIUS_VP` | 全屏 Button，`opacity(0.18)`，点击关闭 | 无 | 用户脚本安装 / 风险提示 |

另有 4 处全屏 Stack 覆盖层（`AiraProScreen.ets:203`、`BrowserPrivateModeLockOverlay.ets:35`、`UserScriptManagementHost.ets:232`、`ReaderModeOverlay.ets:425` 图片预览），其中只有 `AiraProScreen.ets:203` 是居中容器，且它的遮罩由内层 overlay 提供。图片预览（`BrowserMediaResourcesSheet.ets:1248` 的 `bindContentCover`）是**全屏非居中**，不在本清单的居中范围内，但需要一并确认是否纳入规范。

---

## 5b. 组件级表面（既不是 `@CustomDialog`、也不是 `AlertDialog`）

这一类是**直接被 `bindSheet` / `CenteredDialogSurface` / `BrowserAdaptiveModalOverlay` 当作内容消费的组件**。它们没有自己的 controller，所以上一版清单漏掉了它们——包括全部「说明 / 同意 / 引导」类弹窗。

| # | 组件 | 定义位置 | 可见标题 | 形状 | 宿主（file:line） |
| --- | --- | --- | --- | --- | --- |
| 1 | `AdBlockRiskConsentSheet` | `adblock/AdBlockRiskConsentSheet.ets:22` | `开启网页内容过滤？` / `启用第三方过滤规则？`（2 个状态） | 说明 + 同意 | `SettingsEmbeddedDetailPanel.ets:315`（大屏 CENTER sheet） |
| 2 | `AdBlockRuleNoticeCard` | `adblock/AdBlockRuleNoticeCard.ets` | 规则说明 | **页面内提示卡，非弹窗** | 规则列表内 |
| 3 | `UserScriptRiskConsentSheet` | `userscripts/UserScriptRiskConsentSheet.ets` | `使用用户脚本前，请先了解风险` | 说明 + 同意 | `SettingsEmbeddedDetailPanel.ets:329`（大屏 CENTER sheet） |
| 4 | `UserScriptUpdateSheet` | `userscripts/UserScriptUpdateSheet.ets:112` | `脚本更新检查` | 列表 + 动作 | `SettingsEmbeddedDetailPanel.ets:343` |
| 5 | `UserScriptPageActionsSheet` | `userscripts/UserScriptPageActionsSheet.ets` | 页面脚本（空态 `暂无可用功能`） | 列表 + 动作 | `BrowserToolbarSystemSheetContent.ets`、`BrowserLargeScreenNavigationToolbarSurface.ets:607` |
| 6 | `UserScriptInstallSheetContent` | `userscripts/UserScriptInstallSheetContent.ets` | 由脚本名提供 | 滚动内容 | `UserScriptInstallDialog` 内部复用 |
| 7 | `ReleaseNoticeSheet` | `update/ReleaseNoticeSheet.ets:40` | 动态标题 + `更新日志` | 说明 + 滚动 | `BrowserShellPage.ets:6650` 的 `releaseNotice` 分支（**PC 上仍是底部弹窗**） |
| 8 | `CustomHomepageInfoSheet` | `customhome/CustomHomepageInfoSheet.ets:31` | `开发者说明` | 说明 + 滚动 | `CustomHomepageSettingsScreen.ets:356`（`presentation: 'centered'`） |
| 9 | `SyncDesktopBookmarkGuideContent` | `sync/SyncDesktopBookmarkGuideContent.ets` | 同步指南 | 说明 + 步骤 | `AiraProScreen.ets:217` 的 C1 内容 |
| 10 | `SyncFirstActivationFlowSheet` / `SyncFirstActivationItemsSheet` / `SyncGoalSelectionSheet` | `sync/SyncGoalSelectionSheet.ets:47` | `选择同步内容` / `同步方式` | 步骤流（Navigation） | `SyncExperienceSelectionDialog` 与手机 sheet 共用 |
| 11 | `BrowserSiteInfoSheet` | `browser/BrowserSiteInfoSheet.ets:349` | `站点信息` / `拦截日志`（分段） | 滚动列表 | `BrowserWebPageToolsOverlayHost.ets:147`（C6 的 `siteInfo` 变体） |
| 12 | `BrowserScreenOrientationSheet` | `browser/BrowserScreenOrientationSheet.ets:77` | `屏幕方向` | 单选 | `BrowserWebPageToolsOverlayHost.ets:147`（C6） |
| 13 | `BrowserUserAgentPresetSheet` | `browser/BrowserUserAgentPresetSheet.ets:86` | `网页标识` | 分段单选 | `BrowserWebPageToolsOverlayHost.ets:147`（C6） |
| 14 | `BrowserDesktopSiteModeSheet` | `browser/BrowserDesktopSiteModeSheet.ets` | `网站版本` | 单选 | `BrowserWebPageToolsOverlayHost.ets:147`（C6） |
| 15 | `BrowserMediaResourcesSheet` | `browser/BrowserMediaResourcesSheet.ets:377` | `页面资源` + 图片预览（`bindContentCover`） | 列表 / 图片预览 | `BrowserToolbarSystemSheetContent.ets`（`resourceCandidates`） |
| 16 | `BrowserHlsTakeoverSheet` | `browser/BrowserHlsTakeoverSheet.ets:93` | `HLS 接管准备` | 详情 + 动作 | `BrowserModalBottomOverlay`（底部，非居中） |
| 17 | `BrowserToolbarSystemSheetContent` | `browser/BrowserToolbarSystemSheetContent.ets` | `更多工具` | 宫格 | `BrowserShellPage.ets:6650`（**PC 上仍是底部弹窗**） |
| 18 | `HistoryVisitDetailsSheet` | `history/HistoryVisitDetailsSheet.ets:75` | `历史详情` | 键值行 | `HistoryManagerScreen.ets:352`（**PC 上仍是底部弹窗**） |
| 19 | `TabOverviewLayoutChoiceSheet` | `settings/TabOverviewLayoutChoiceSheet.ets:86` | `标签页样式` | 单选 + 开关 | `SettingsDetailContent.ets:146`（大屏 CENTER sheet） |
| 20 | `AppProxyQuickSheetContent` | `settings/AppProxyQuickSheetContent.ets:94` | `应用内代理` | 开关 + 单选 | `SettingsCenterScreen.ets:323`、`BrowserToolbarSystemSheetContent.ets` |
| 21 | `BrowserToolbarCustomizationScreen` 的 sheet 内容 | `settings/BrowserToolbarCustomizationScreen.ets:407` | `中间区域上滑` / `选择要自定义的操作` | 单选 | `BrowserToolbarCustomizationScreen.ets:190`（大屏 CENTER sheet） |
| 22 | `BrowserUserAgentSettingsScreen` 的居中表单 | `settings/BrowserUserAgentSettingsScreen.ets:409` | `自定义 UA` | 表单（2 输入） | `BrowserUserAgentSettingsScreen.ets:201`（大屏 CENTER sheet） |
| 23 | `BrowserCrossDeviceTabsSheet` | `browser/BrowserCrossDeviceTabsOverlay.ets` | `跨设备标签页` | 滚动列表 | `CrossDeviceLinkHost.ets:260`、`BrowserLargeScreenNavigationToolbarSurface.ets:524` |
| 24 | `HuaweiLoginSheetContent` | `sync/HuaweiLoginSheetContent.ets:41` | `Aira` / `使用华为账号登录，安全同步你的书签` | 登录表单 | 4 处：`CrossDeviceLinkHost.ets:247`、`SettingsCenterScreen.ets:323`、`AiraProScreen.ets:189`、`SyncWebdavConfigPage.ets:265` |
| 25 | `DesktopLoginConfirmSheetContent` | `sync/DesktopLoginConfirmSheetContent.ets:35` | `确认登录Aira-sync 扩展` | 纯确认 | `CrossDeviceLinkHost.ets:234`、`SettingsCenterScreen.ets:323` |
| 26 | `AiraLegalWebDocumentContent` | 法务组件 | 法务文档标题 | 长文档滚动 | `AiraProScreen.ets:217` 的 C1 内容 |
| 27 | `ReadingExperienceSystemSheet` | `browser/ReadingExperienceSystemSheet.ets:42-58` | `目录` / `亮度与主题` / `阅读设置` / `文字` | 列表 / 设置 | `BrowserShellPage.ets:6650`（**PC 上仍是底部弹窗**） |
| 28 | `OfflinePageViewerScreen.buildDetailsSheet` | `offline/OfflinePageViewerScreen.ets:472` | `离线网页详情` | 键值行 | `OfflinePageViewerScreen.ets:301`（**PC 上仍是底部弹窗**） |
| 29 | `ReaderModeOverlay.buildImagePreview` | `browser/ReaderModeOverlay.ets:425` | 无 | **全屏非居中**（`reader_image_preview_scrim`） | `BrowserShellPage.ets:9475`、`OfflinePageViewerScreen.ets:553` |

> 第 1、3、4、7、8、19 项就是上一版草稿遗漏的「说明 / 同意 / 引导」类弹窗。它们现在在原型目录的第 7、8 节有逐张草图。

### 5c. 第三版补扫出的内容组件

用户反馈「开启同步那个开关弹窗漏了」后，按「名字像弹窗/sheet 内容、但从未在草稿里出现」做的全仓扫查结果（351 个 `export struct` 过滤后）：

| # | 组件 | 定义位置 | 可见标题 | 形状 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 1 | `SyncFirstActivationItemsSheet` | `sync/SyncFirstActivationItemsSheet.ets:33` | `选择同步内容` | **开关列表**（`Toggle({ type: ToggleType.Switch })` :98） | 摘要：`先选择要在设备之间保持一致的内容，下一步再选择同步方式。`（`core/sync/SyncFirstActivationItemsCoordinator.ets:61-62`）；行内带色块图标底座 |
| 2 | `SyncFirstActivationFlowSheet` | `sync/SyncFirstActivationFlowSheet.ets` | 由 `Navigation` 子页提供 | 步骤流 | 包住上项的壳 |
| 3 | `SyncGoalSelectionSheet` | `sync/SyncGoalSelectionSheet.ets:47` | `同步方式` | 单选列表 | 步骤流第 2 步 |
| 4 | `SyncContentSwitchCard` | `sync/SyncContentSwitchCard.ets` | `同步内容` | **开关卡（设置页内，非弹窗）** | 与弹窗共用同一套开关语言 |
| 5 | `HistoryBookmarkFolderSelectionOverlay` | `history/HistoryBookmarkFolderSelectionOverlay.ets` | 保存到书签 | 文件夹列表 | 历史页浮层 |
| 6 | `UserScriptInstallSheetContent` | `userscripts/UserScriptInstallSheetContent.ets` | 脚本详情 + 权限清单 | 列表 | `UserScriptInstallDialog` 的内容层 |
| 7 | `ReadingExperienceSystemSheet` | `reading/ReadingExperienceSystemSheet.ets:36-58` | `目录` / `亮度与主题` / `阅读设置` / `文字` | 列表 / 设置 | PC 上仍是底部弹窗 |
| 8 | `ReaderSpeechPlayerOverlay` / `ReaderSpeechPlayerSheet` | `browser/ReaderSpeechPlayerScreen.ets` | `朗读` | 播放器 | 与 B22 音色选择是两个不同表面 |
| 9 | `NovelReaderOverlay` | `browser/NovelReaderOverlay.ets:234/805` | 书名 + 进度 | 阅读浮层 | |
| 10 | `CookieManagementContent` | `settings/CookieManagementContent.ets:108-110` | `Cookie` | 单选（不阻止 / 仅阻止第三方 / 阻止全部） | |
| 11 | `ManualElementHideSelectionOverlay` | `browser/ManualElementHideSelectionOverlay.ets:162` | `已选择 N 个元素` | 页内选择态浮层 | 非居中弹窗 |
| 12 | `HomeNativeSettingsContent` / `WallpaperSettingsContent` | `settings/HomeNativeSettingsContent.ets:107` / `wallpaper/WallpaperSettingsScreen.ets:71` | `主页外观` / `壁纸设置` / `壁纸来源` | 开关 + 列表 | B20 的内容层 |

**已判定为页面内联面板而非弹窗（不单列草图）**：`AdBlockSettingsContent`、`AppIconSettingsContent`、`BrowserTrackingProtectionSettingsContent`、`BrowserWebSecuritySettingsContent`、`KeyboardShortcutsContent`、`PasswordSettingsContent`、`SecureDnsSettingsContent`、`SettingsAboutOverviewContent`、`ThemePaletteSettingsContent`、`WebpageTranslationSettingsContent`、`SiteControlsExternalNavigationDefaultContent`、`BrowserDownloadSettingsContent`、`BrowserToolbarPreview`。

**已判定为全屏/页内浮层而非居中弹窗**：`BrowserTabsFloatingOverlay`、`BrowserTabsSharedSnapshotOverlay`、`BrowserPrivateModeLockOverlay`、`BrowserWebTopChromeOverlay`、`BrowserVideoAssistantPlayerOverlay`、`ElementInspectionOverlay`、`FloatingSelectionToolbar`、`WebContextMenuOverlay`（后者已由桌面菜单规范覆盖）、`ReaderModeOverlay` 的图片预览。

---

## 6. PC 上仍是底部弹窗（完整审计：26 处，三种机制）

> **结论（用户已确认）：PC 壳层下不允许任何底部弹窗，本表全部改为居中对话框。** 内容组件一行不改，只换宿主并删掉 `dragBar: true` / `BrowserImmersiveSheetLayout` / `BrowserModalBottomOverlay`。改后效果见 `docs/reference/aira-desktop-dialog-catalog.html` 第 6 节（机制 A/B/C 审计表 + F0 前后对比 + F13d 华为登录 + F7d–F10d 阅读四件套 + B3d 元素检查）。判定条件从 6 种 prop 名收敛为 `shellFamily === 'large_screen'`。

> **审计修正记录**：本文档的早期版本只扫了 `bindSheet`，得出 16 处。重新审计后实际是 **26 处**——多出的 10 处中，**5 处来自一个完全未审计过的机制（直接使用 `BrowserModalBottomOverlay`）**。教训：数“底部弹窗”不能只 grep `bindSheet`。

### 6.1 机制 A · `bindSheet` + `SheetType.BOTTOM`（25 处调用点）

| 分类 | 数量 | 说明 |
| --- | --- | --- |
| 字面量 `SheetType.BOTTOM` | **14** | 无条件。其中 **12 处是问题**；`BrowserBottomAddressPanel:776`（宿主大屏不挂载）与 `UserScriptManagementHost:214`（仅 page 模式）无需处理 |
| 条件式三元 CENTER/BOTTOM | **11** | 其中 **9 处有隐蔽问题**：同一组件也被 `@Entry` 路由页复用，而那些页面**不传那个 prop**，于是 PC 上仍退化为底部弹窗。只有 `SettingsEmbeddedDetailPanel:235` 与 `SyncAdditionalBackupHost:219` 的宿主只在大屏壳里，真正安全 |

**机制 A 问题站点（21 处调用点）**

| # | 站点 | 内容 |
| --- | --- | --- |
| A1 | `BrowserShellPage.ets:6650` | 10 种 systemSheet：发布公告 / 登录确认 / 用户脚本页面操作 / 应用内代理 / 资源候选 / 阅读文字 / 阅读外观 / 阅读设置 / 目录 / 跨设备标签页 |
| A2 | `SettingsDetailPage.ets:342` · `SettingsInlineDetailPanel.ets:308` | 清除浏览数据 |
| A3 | `AdBlockSettingsPage.ets:119` | 开启网页内容过滤？ |
| A4 | `SyncWebdavConfigPage.ets:265` · `BrowserCrossDeviceTabsOverlay.ets:157` | 华为登录面板 |
| A5 | `BookmarkManagerPage.ets:374` | 移动书签 |
| A6 | `WebpageTranslationSettingsScreen.ets:198` | 目标语言 |
| A7 | `SyncExperienceScreen.ets:233` | 选择同步内容 / 同步方式 |
| A8 | `LocalBackupScreen.ets:208` | 选择导入内容 |
| A9 | `HistoryManagerScreen.ets:352` | 历史详情 |
| A10 | `OfflinePageViewerScreen.ets:301` | 离线网页详情 |
| A11 | 条件式 CENTER 隐藏问题共 9 处：`BrowserToolbarCustomizationScreen:190` · `BrowserUserAgentSettingsScreen:201` · `SettingsCenterScreen:323` · `SettingsDetailContent:146` · `CustomHomepageSettingsScreen:356` · `CrossDeviceLinkHost:234/247/260` · `AiraProScreen:189` | 工具栏自定义 / 自定义 UA / 登录确认 / 标签页样式 / 开发者说明 / 登录确认×2 + 跨设备标签页 / Aira Pro 面板 |

### 6.2 机制 B · 直接使用 `BrowserModalBottomOverlay`（5 处）

不经 `bindSheet`、也不经 `BrowserAdaptiveModalOverlay`，自己直接调底部覆盖层。**全部没有任何大屏分支。**

| # | 定义位置 | 高度 | 挂载点 | 大屏门控 | 内容 |
| --- | --- | --- | --- | --- | --- |
| B1 | `browser/BrowserHlsTakeoverSheet.ets:518` | `'78%'` | `BrowserShellPage.ets:6525` | **无** | HLS 接管准备 |
| B2 | `browser/ReaderSpeechPlayerScreen.ets:502` | 常量 | `BrowserShellPage.ets:8569` | **无（且未传 layoutMode）** | 朗读播放器 |
| B3 | `browser/ElementInspectionOverlay.ets:258` | 常量 | `BrowserShellPage.ets:8478` | **无** | 元素检查 |
| B4 | `offline/OfflinePageViewerScreen.ets:657` | 常量 | 离线页内 | **无** | 朗读播放器（第二挂载点） |
| B5 | `history/HistoryBookmarkFolderSelectionOverlay.ets:29` | 常量 | `HistoryManagerScreen.ets:795` | **无** | 选择书签文件夹 |

### 6.3 机制 C · 手机形态也居中的异常（3 处）

`update/CommunityUpdateOverlay.ets:33` · `browser/NewUserGiftOverlay.ets:32` · `onboarding/BottomToolbarGuideOverlay.ets:36` 传了 `phoneSheetAlignment: Alignment.Center`，意味着它们在**手机上也是居中浮层**，偏离手机壳的底部规范。其余 7 个 `BrowserAdaptiveModalOverlay` 宿主走的是 `Alignment.Bottom`。不影响 PC，但需登记。

### 6.4 无需处理（已排除）

| 站点 | 排除理由 |
| --- | --- |
| `browser/BrowserBottomAddressPanel.ets:776` | 其宿主 `BrowserBottomAddressPanel` 在大屏不挂载（`BrowserRootBottomPanelSessionCoordinator.ets:1491-1498` 以 `largeScreenShellActive` 为排除项） |
| `userscripts/UserScriptManagementHost.ets:214` | bindSheet 只在 `buildPageSurface()` 内；大屏两个宿主都传 `presentationMode: 'native_tab'`，走自绘 `buildNativeModalSurface()` |
| `browser/BrowserAdaptiveModalOverlay.ets:78` | 基础设施本体，手机路径；大屏走 `bindContentCover` |

| # | 站点 | 大屏仍为底部弹窗的原因 |
| --- | --- | --- |
| 1 | `pages/BrowserShellPage.ets:6650` | options 恒为 `BOTTOM` + `dragBar: true`。`BrowserSystemSurfacePresentationViewModel.resolve()` 只把 4 类改派到居中对话框，其余 10 种类型在大屏仍走这里：`releaseNotice`、`desktopLoginConfirm`、`webPageTools`、`userScriptPageActions`、`appProxyQuick`、`resourceCandidates`、`readerText`、`readerAppearance`、`readerSettings`、`crossDeviceTabs` |
| 2 | `pages/SettingsDetailPage.ets:342` | 页面不读任何壳层标志；`SettingsNavigationCoordinator.ets:290`、`BrowserShellRouteCoordinator.ets:352` 均无大屏改派 |
| 3 | `pages/AdBlockSettingsPage.ets:119` | 同上；push 点无大屏改派 |
| 4 | `pages/SyncWebdavConfigPage.ets:265` | push 点 `SettingsNavigationCoordinator.ets:613-625` 无大屏改派 |
| 5 | `pages/BookmarkManagerPage.ets:374` | 该 `@Entry` 页本身无大屏分支 |
| 6 | `pages/SettingsCenterPage.ets:21` → `SettingsCenterScreen.ets:323` | 传 `presentationMode: 'page'`，故取 BOTTOM |
| 7 | `customhome/CustomHomepageSettingsScreen.ets:356` | `CustomHomepageSettingsPage.ets:16` 传 `'standalone'` |
| 8 | `settings/BrowserToolbarCustomizationScreen.ets:190` | `BrowserToolbarCustomizationPage.ets:19` 未传 `desktopPresentation` |
| 9 | `settings/BrowserUserAgentSettingsScreen.ets:201` | `BrowserUserAgentSettingsPage.ets:38` 未传 `useCenteredSheet` |
| 10 | `pages/WebpageTranslationSettingsPage.ets:57` → `WebpageTranslationSettingsScreen.ets:198` | 页面无大屏分支 |
| 11 | `pages/SyncSettingsPage.ets:8` → `SyncExperienceScreen.ets:233` | 该页用默认 `SyncExperienceHost()`，两个开关都是 false |
| 12 | `sync/CrossDeviceLinkHost.ets:234/247/260` | `CrossDeviceLinkPage.ets:24` 未传 `desktopPresentation` |
| 13 | `offline/OfflinePageViewerScreen.ets:301` | 页面无大屏分支；大屏 `OfflinePagesScreen` 也会 push 该页 |
| 14 | `history/HistoryManagerScreen.ets:352` | `@Entry` 页本身无大屏分支 |
| 15 | `browser/BrowserCrossDeviceTabsOverlay.ets:157` | 组件在大屏（`BrowserTabsFloatingOverlay.ets:622`）也渲染，bindSheet 无分支 |
| 16 | `settings/SettingsInlineDetailPanel.ets:308` | `preferType` 为字面量 BOTTOM（清浏览数据 sheet）；大屏另有 `ClearBrowsingDataDialog` 分支，但该 sheet 本身没有分支 |
| 17 | `browser/BrowserBottomAddressPanel.ets:776` | `preferType` 无分支，但宿主在大屏不挂载（`BrowserRootBottomPanelSessionCoordinator.ets:1491-1498` 以 `largeScreenShellActive` 为排除项）→ 实际不受影响 |

---

## 7. 与 `docs/aira-desktop-dialog-design-spec.md` 的差异（需修正）

原规范第 1.1 节的 E 类写「26 处 `bindSheet` 中的多数」。实测：`bindSheet` 共 **25** 处真实调用，`preferType` 写了 24 处；PC 上仍是底部弹窗的是上表 **17 处（其中 1 处在大屏不挂载，实际 16 处）**。规范中的数字应按本文件更新。

另：原规范漏记了 `bindContentCover` 的图片预览（`BrowserMediaResourcesSheet.ets:1248`）与 4 处全屏 Stack 覆盖层，本文件补全。
