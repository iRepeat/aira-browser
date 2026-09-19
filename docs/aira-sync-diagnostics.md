# 同步卡顿复现日志

2026-09-19。用于定位华为云空间自动/手动同步时的网页滑动卡顿；不是新的同步算法。

## 调用链与测量

自动与手动同步进入 `SyncExperienceAutomaticRuntime.executeRequest`，共用书签、个性化和历史服务。自动入口还有启动延迟、变更检查、域拆分及重试；不能把两种入口的总耗时当成完全相同的工作量。

诊断包从内容就绪/回到前台开始采样，手动或自动同步也可以开始新窗口。每个窗口最多 180 秒；进入后台立即取消采样，避免把挂起时间当成主线程卡顿。结束同步后继续记录尾部和未同步时的基线。

- `capture_start/end`：采样边界；`run_start/end`：轮次、automatic/manual、Provider、操作模式。
- `main_thread_lag`：50 ms 主线程计时器迟到至少 32 ms；`durationMs` 是迟到量，不是帧耗时或准确的单次阻塞长度。定位区间保留额外 50 ms 采样不确定性。
- `heartbeat`：每秒一次，含最大迟到、采样数、活跃阶段和被限频的事件数。即使没有发现迟到也能确认采样是否运行。
- 阶段：书签读取/快照/合并/写入/确认，个性化读取/快照/合并/写入/应用/持久化/书架/备份，华为历史 runner 与 store 的已有细分阶段，华为 `cloudSync`，历史同步后的 UI 刷新。
- 历史收尾拆为 `history_finalize_outbox/cache/head`。`history_replica_lite_compute` / `history_replica_full_compute` 的 detail 返回工作线程内各阶段耗时；由调用线程打印以保留轮次关联。这些也是墙钟耗时，不能等同 CPU 时间；与 TaskPool 总耗时的差额可能包含排队和传输。
- 每条记录包含采样内时间、墙钟时间、轮次、阶段耗时和最近滑动状态；常规详细事件每秒最多 48 条，丢弃数量会报告。历史逐条应用只记录至少 8 ms 的慢项。

新增诊断输出仅使用 `SyncJankProbe` tag 和 `[DEBUG-sync-perf-a31f]` 前缀。detail 只接受枚举、计数与耗时；不保留页面 URL/标题、账号、令牌、快照或原始错误字符串。采样期间不写应用数据库或文件，也不逐帧打印日志。

## 构建和复现

源码的 `AIRA_ENABLE_SYNC_DIAGNOSTICS` 保持 false。使用 `AIRA_SYNC_DIAGNOSTICS=1` 由构建脚本临时启用，成功或失败都恢复源码；release 构建不允许打开。

华为云空间需要本机配置完整的 Official 包：

```sh
AIRA_DISTRIBUTION=official AIRA_SYNC_DIAGNOSTICS=1 ./scripts/build-aira-browser.sh
python3 scripts/capture-aira-sync-diagnostics.py --seconds 240
```

多个设备时指定 `HDC_TARGET`。采集器打印 READY 后，在手机上：

1. 冷启动 Aira，按平时方式打开网页、滑动，等待自动同步；记下明显卡顿的大致时刻。
2. 点击一次“立即同步”，返回同一网页滑动，再记下是否卡顿。
3. 保留一段同步结束后的滑动作为对照。若超过 3 分钟或需要重新测，回到前台会开始新的窗口。

采集默认保存到系统临时目录，文件权限 0600，拒绝将输出保存进仓库。只读取该 tag；不截图、不清理系统日志、不修改设备日志策略。日志可能含当前进程先前窗口，以 `capture` 和 `run` 区分，不要混为一轮。

```sh
node scripts/analyze-aira-sync-diagnostics.cjs /tmp/aira-sync-diagnostics-时间戳.log
node scripts/analyze-aira-sync-diagnostics.cjs /tmp/aira-sync-diagnostics-时间戳.log --assert-responsive
```

解析结果列出每次迟到及时间重叠的候选阶段，也能关联“阶段结束→同步结束→迟到计时器才执行”的情况。断言模式检测到迟到返回 1，无有效采样返回 2，存在有效采样且没发现迟到返回 0。无日志不算通过。

异步阶段耗时包含网络和主动让步，不能按最长阶段直接判定根因。主线程计时器正常但网页仍卡时，应继续用 ArkWeb/Frame/ArkUI/Time 轨迹检查渲染、合成或系统资源竞争；本日志无法单独证明 GPU/ArkWeb 卡顿。

## 验证和平台依据

`node scripts/check-aira-sync-diagnostics.cjs` 直接执行生产探针，覆盖关闭时零定时器、180 ms 阻塞、5 秒异步等待、同步结束后的关联、墙钟校时、后台取消、有界窗口、异常清理、限频和隐私字段过滤。构建脚本自动执行。

首轮验证：6 项探针回归、9 项同步响应性回归、8 项 Provider 迁移回归与构建契约检查通过；Community 免签名诊断构建通过，Official 诊断包 3.2.2（1000446）构建并覆盖安装成功。

## 2026-09-19 手动复现与后续自动轮次

仅记录聚合量，不保存原始日志、页面内容或设备标识到仓库。

| 轮次 | 实测工作 | 耗时与事件循环迟到 |
| --- | --- | --- |
| 手动前自动书签 | 云同步、快照和合并 | 1.83 s，未检测到 ≥32 ms 迟到 |
| 手动前自动个性化 | 读取、合并、写入、确认 | 3.66 s，未检测到 ≥32 ms 迟到 |
| 手动历史 | 新登记 1 条；2960 物理行，27,721,091 字节；上传 34 个物理行 | 总计 62.53 s；全量工作线程任务 52.04 s；收尾附近迟到 357 ms |
| 后续自动历史 | 登记 0、应用 0、上传 0；重复合并已确认缓存 | 总计 11.63 s；合并任务 9.85 s；收尾迟到 335 ms |

27.7 MB 是本机读取并打包的物理副本，包含多设备和分块/槽位数据，**不是本次网络上传量**。52 秒是工作线程任务的墙钟耗时，不能称为主线程阻塞 52 秒。未同步时同样有滑动相关迟到，因此这份日志不证明所有网页卡顿都由同步造成。

对应代码和可重复回归：

1. lite 增量任务被 24 MiB 启发式门槛跳过，随后全量任务却成功传递同等大小的 buffer。移除 lite 的大小拒绝，保留实际任务失败/副本校验失败后的回退；不提高其他路径的预算，也不跳过每个桶的内容校验。
2. 三条成功路径同步调用全量 `normalize` 来保存缓存；改用已有的协作式规范化，复制/去重/排序结果不变，并拆开收尾计时。357/335 ms 目前只能定位到收尾区间，不能仅凭旧日志唯一归因到某一行。
3. 有缓存且无本机改动时，旧路径直接重新读取并合并整份历史。现在先读取云端 Head：相同则跳过；不同则失效缓存并走远端读取，不能因为本机无改动漏掉其他设备的更新。保留期裁剪属于本机改动，即使它移除了最后一个待上传访问，也必须继续规划。

`node scripts/check-aira-history-replica-responsiveness.cjs` 使用生产 runner、executor、传输和规范化代码，数据库/云/任务边界受控。修改前可复现大副本错误回退、收尾 500.5 ms 模拟连续工作以及空跑重复合并；修复后 7 项回归通过，覆盖真实任务失败后的 buffer 重建、三条成功路径的响应性与缓存独立性、迁移时保留 outbox、无变化跳过、远端变化失效和保留期裁剪。模拟工作成本不是真机时间。

保留诊断包用于下一轮真机对比；实际改善幅度尚待相同场景复测。

第二轮验证：7 项副本响应性、9 项公共响应性、6 项探针、8 项 Provider 迁移回归及构建契约通过。Community 免签名编译通过；最终 Official 诊断包已覆盖安装到连接设备，下一次打开应用加载更新。源码恢复 Community 分发和关闭诊断开关。

## 第二次真机反馈：吞吐改善，滑动仍卡

- 手动轮次总计 13.68 s，其中历史 12.25 s。物理副本 27.93 MB、本机状态合计传输 33.25 MB，lite 任务成功执行；任务 5.87 s，内部解包 325 ms、构建/检查投影 5.54 s。新增登记 1 条，写入 23 个物理行。收尾缓存规范化分片耗时 537 ms，期间未检测到 ≥32 ms 计时器迟到。用户明确表示这次没有同时滑动，因此不能拿它证明滑动已经流畅。
- 随后的自动历史轮次耗时 16.20 s；lite 任务 7.30 s。检测到 12 次 ≥32 ms 迟到，最大 106 ms；滑动状态下最高 93 ms，发生于工作线程任务/物理行读取期间；云端等待期间也有迟到。用户确认明显卡顿，原始症状尚未通过验收。
- 紧随其后的无变化自动历史轮次仅 515 ms，已走 `source=cached-head-unchanged`，没有再次合并整个历史。后续一次无变化手动历史也只用 582 ms。

针对 Aira 主进程做了低频 Hiperf 调用栈采样，无截图。第一段采样因 32 MiB 原始数据上限在约 51.8 s 提前结束；用独立短采样的单调时钟和墙钟桥接后，确认它覆盖轻量同步与其前后的网页操作，**没有覆盖后面的重历史任务**。不能用这段样本的线程占比排除历史工作线程竞争。

该样本中主线程约占进程采样 CPU 周期的 42.6%，栈中反复出现 `BrowserShellPage.rerender → updateDirtyElements → buildBottomPanelHostState → BrowserTabHomeCoordinator.buildHomeSystemChromePolicyState → shell.readState`，以及下拉刷新、未展开页面层和子组件参数更新。它是页面渲染成本的具体证据，不是某一帧卡顿或同步因果的完整证明。

在这一展示路径中，`buildHomeSystemChromePolicyState` 原先两次读取完整 Tab Home shell 状态；每次都访问 tabs、瞬时消息、搜索、首页快捷方式、视口等无关页面字段。新增窄的 `readSurfaceProfileInput`，让外观/场景计算只读取所需的 5 个输入，并在一轮策略计算中复用同一份输入。策略仍在原有 coordinator 内，不在页面增加编排；shell 事实回调上限从 9 调整为 10。

`check-aira-home-chrome-scroll-contract.cjs` 新增真实 coordinator 行为回归。修改前，调用两个展示入口触发 3 次完整页面状态读取，断言失败；修改后只分别读取一次展示输入，覆盖系统首页、自定义首页、隐私边界、普通网页、显示覆盖和禁用搜索栏的 8 种场景。此回归只证明依赖收窄和结果保持，实际滑动改善需要完整复测。

该修改已通过 Community 免签名编译及构建契约；Official 诊断包 3.2.2（1000451）已覆盖安装。源码恢复 Community 和关闭诊断开关。复测改为 49 Hz、240 秒、128 MiB 原始数据上限的 Hiperf 采样，并使用 `--clockid realtime`；已用短采样确认设备输出纳秒墙钟时间，可直接与探针的 `wall` 毫秒字段对齐。不要用生成文件名或报告中的 `hiperf_record_time` 猜测采样起点，也不要仅因命令请求了 240 秒就假定实际覆盖了完整窗口。

## 第三轮：设置页也卡，同步计算的明确热点

用户确认自动同步时在原生同步设置页上下滑动也明显卡顿；复现条件不再局限于网页。第三轮采样实际记录 113.9 秒，因 128 MiB 原始数据上限结束；22,703 个样本，未丢样。纳秒墙钟范围覆盖第一轮重历史任务全部及第二轮 lite 计算绝大部分（末尾约 285 ms 不在该段采样内）。后续另开 19 Hz / 4 KiB 栈 / 256 MiB 上限的采样，应用进程退出后结束；不把退出后时间当作有效采样。

- 首轮自动历史 13.15 s，lite 计算 6.00 s，其中投影 5.71 s。同期进程采样 CPU 周期中工作线程约 49.8%、主线程约 25.7%，还有多条 GC 线程。
- 后一轮自动历史 11.42 s，lite 计算 6.12 s、投影 5.84 s；出现 154/126/85 ms 计时器迟到。覆盖到的计算区间里工作线程占进程采样周期约 43.3%。这些是周期样本占比，不是设备 CPU 利用率或主线程阻塞时长。
- 工作线程明确出现 `buildProjectionReusingHead → materializeOwnBucketRecords → parseChunk → parseSnapshotRecord → parseVisit → normalize → normalizeVisit → normalizeUrl`。`normalizeUrl` 是最深应用栈的主要热点（两段重任务分别约占进程样本周期的 19.3% / 14.2%）。

代码中两条冗余路径可直接验证：读取快照记录时 `parseVisit` 已完整校验，随后 `buildVisitRecord` 又序列化并校验同一记录；写入桶时，刚完成整个 state 规范化的记录又重新解析 URL。单条访问校验还调用整份 state 的 normalize，创建去重 Map、数组、排序和空保留期对象。

改为复用 `HistorySyncMergeService.normalizeVisit` 的同一规范化规则；读取记录只做一次完整校验；构建已规范化的访问记录时保留字段、transition 和安全整数时间戳校验，不再次解析 URL。每个远端桶仍完整验证内容、hash 和目标记录一致性，不信任 dirty hint。没有增加跨轮次缓存或跳过损坏检查。

`node scripts/check-aira-history-record-validation.cjs` 用真实 codec/merge 及合成数据复现：1000 条旧记录加 1 条新记录，原先 4002 次 URL 解析，现在 2001 次；整个 state 的 normalize 调用从 3002 次降到 1 次（不计后续确认阶段）。4 项回归覆盖完整读回、空 dirty hint、修改前快照字节摘要、非规范/损坏记录拒绝、本地严格字段校验及同步/协作式输出一致。平台 URL/加密边界由标准实现替代，解析次数的下降可复现，但真机时间和滚动验收仍需复测。

该计算优化已通过 Community 免签名编译及全部构建契约；Official 诊断包 3.2.2（1000453）已覆盖安装并启动设置页复测。源码恢复 Community，诊断开关 false。

安装后两轮自动历史任务的投影分别为 3067 / 3070 ms（9980 / 9984 条访问，3071 个物理行），相比修改前两轮的 5708 / 5839 ms 有明确下降；lite 总计算为 3370 / 3385 ms。第一轮在远端写入附近应用进程退出，不能将未完成轮次当作同步成功；采集器捕获了重启后的下一轮。其他书签/个性化阶段仍有 ≥100 ms 的主线程计时器迟到，因此这两次计算耗时改善还不是整体滑动验收通过。

## 上传失败误触发全量重算

重启后的轮次继续记录到了另一处放大开销的问题：lite 投影成功（3.385 s），云端 `mode=4` 提交在 6.608 s 后以 `code=1` 失败，随后同一轮立即开始全量工作线程任务 49.659 s，其中解码 36.966 s、合并 6.680 s、比较 2.637 s。整轮最后成功但持续 76.184 s。这里只知道平台报告提交失败，不能从数值码单独断言是断网或某种云端故障。

`tryLiteReplicaWrite` 原先用一个 catch 包住计算、上传、确认及收尾，任何异常都返回 undefined 并走全量计算。现在只有计算/副本验证阶段可以返回 undefined；上传和确认失败上抛给现有 `HistorySyncService` 失败结果及自动同步重试策略，未确认的数据不清 outbox、不保存确认 Head。这不改变真实计算失败的 buffer 重建和全量回退，也不承诺后续遇到远端变化时永远不需要全量解码。

副本响应性回归增至 8 项：新用例在初次/缓存两条真实 runner 路径注入一次云端提交失败。修改前错误被吞掉并立即全量重算，用例失败；修改后只执行 lite 计算、保留待同步数据、透传失败，下一次重试可正常确认。

同一段全量任务的 CPU 样本又定位到 `HistorySyncMergeService.isDeleted` 的重复遍历。工作线程的同步 merge 为每条访问调用 `tombstones.some` 和全量 `ranges.some`；已有协作式 merge 则用 Set 和按 URL 分组的 Map。同步 merge 现在采用相同索引，保留精确删除、范围两端包含、clearBefore 和保留期边界规则。记录校验回归增至 5 项；1000 条访问、801 个墓碑和 201 个删除范围的场景，修改前约 98.7 万次删除键读取，超过线性工作量预算，修改后预算内通过，输出与协作式 merge 完全一致。

最终合并上述修改后，5 项记录校验/合并性能回归、8 项副本响应性回归及其余构建契约通过；Community 免签名构建和 Official 构建均成功。Official 诊断包 3.2.2（1000455）已覆盖安装，重新开始有界日志采集；最终设置页滚动体验仍待用户复测。源码保持 Community、关闭诊断；原始设备日志和 CPU 数据只保存在仓库外。

## 第四轮：原生设置页复现与写入读取预算

用户在 1000455 再次确认：打开几个网页产生历史，回同步设置页，在自动同步期间连续上下滑动仍有几个明显卡点。此前自动轮次记录到 76 / 63 / 34 ms 计时器迟到，发生于 worker 开始前；该区间包含主动等待滑动结束，不能仅按时间重叠归因到状态编码。

新一段 49 Hz 调用栈采样实际覆盖 239.9 秒，没有丢样，包含一次完整的 14.08 秒自动历史同步。该轮有 3118 个物理行、9991 条访问；传输物理副本 29.29 MB，worker 解包 277 ms、投影 3348 ms。同步开始后记录到 102 / 32 ms 迟到。102 ms 区间的主线程栈含设置导航/组件初次构建和底部栏参数更新，不能声称这 102 ms 都由同步编码造成；计时器也不是逐帧采样，不能用后续没有 ≥32 ms 迟到反驳用户看到的卡点。

该轮 worker 执行期间及写后仍有主线程工作；代码与采样共同确认两个可单独回归的负担：

- `stageProjection` 仅比较本次 upsert 的几十行，却先读取整张 block 表；`writePreparedProjection` 在云端确认后又读整张表，随后已有的 Head 相同快捷路径并不使用这些 block。真机写入前后两次分别读取 3111 个 block，耗时 166 / 152 ms（包含让步，不是连续阻塞时长）。现在写入比较按表/本次 rowId 分批查询，最多 200 个 ID 一批，并保留账号谓词；写后先读新 Head，匹配仍使用原有确认规则，不匹配才读取所有 block 交给 worker 校验。迁移清理后仍完整读取以检查残留。
- `SettingsScrollBody` / `SettingsPresentationScrollBody` 没有向公共活动信号报告滚动。该轮在用户上下滑动设置页时一直记录 `browsing=false`；现有自动调度与协作节流因此没有识别这一操作。两种容器现在在 `onDidScroll` 非零位移时标记活动，覆盖触屏、惯性和鼠标滚动；零位移回调不延长等待，不修改 ArkUI 状态。已有等待上限保持不变。

`node scripts/check-aira-history-remote-read-budget.cjs` 经过真实 remote-store 公共写入入口，用受控 RDB/云/worker 边界与 3000 行合成副本验证。修改前，小写入物化了 59,990,116 字节；修改后低于 20 KB。5 项用例覆盖无变化/空投影、Head 不匹配的全量校验、确认失败不清理、云失败不确认、大批次参数上限、账号隔离和删除计数。这里测量的是读取负担，不是真机 FPS。

`check-aira-sync-responsiveness.cjs` 增至 10 项，新增用例执行两个真实 Scroll 的回调，再调用生产节流器；修改前缺少回调失败，修改后验证上下滑动能触发等待、停止后能继续同步。`history_state_pack` 新增独立阶段与 `yields` / `sleptMs`，以区分主动等待和实际编码耗时。

平台依据：Huawei DevEco SDK `component/scroll.d.ts` 的 `onDidScroll`（API 12）说明回调包含滚动、控制器、其他输入及回弹；`@ohos.data.relationalStore.d.ts` 的 `RdbPredicates.in` 明确空数组使条件无效，因此读取函数显式处理空 ID 集合，禁止它退化为全表查询。

这些修改减少了可验证的主线程工作并补齐设置页的交互感知。原始滚动卡顿仍以更新后的真机复测为准，尚未宣称解决。

本轮 Community 免签名编译、全部构建契约及 Official 构建成功；1000456 已覆盖安装并启动，开始新的有界日志/CPU 采样。源码已恢复 Community 分发、关闭诊断，`git diff --check` 通过。Huawei RDB 空 `in` 集合的注意事项已记入 HarmonyOS 技能的原生存储排错记录。

1000456 启动后的首轮自动历史同步已确认定向读取落地：初始规划仍读取 3118 个物理行（29.29 MB），但写入前只读取 10 个 block 和 1 个 Head，写后只读取 7 个 Head；worker 解包 305 ms、投影 3377 ms，缓存收尾 531 ms。该轮没有 ≥32 ms 计时器迟到，活动信号均为 false，尚没有用户同步滑动反馈，因此只能确认读取量下降，不能作为滚动通过的证据。

这一段 49 Hz 采样再次触及 256 MiB 原始数据上限，实际约 106.5 秒即结束；已导出并另开 19 Hz / 4 KiB 栈的有界采样。采样覆盖范围始终以记录时间为准。

## 同日下午：`Huawei History visits is invalid` 与失败重试循环

用户报告历史同步失败，重新连接后在 HistorySyncService 日志确认准确错误为 `visits`（数量），不是 `visit payload`（单条记录）。唯一对应抛出路径是 Head 的 `counts.visits` 校验。设备当时运行 1000464；每轮读取 7 个 Head、3217 个 block，然后失败，约每 7～8 秒重复，自动调度日志的 reason 为 `membership`。

10001 条合成访问通过旧 lite writer 可以成功发布，但下一次 decodeRows 立即出现同样错误：writer 的 normalize 只去重/排序，不执行一万条保留策略，而 reader 把计数硬限制为一万。保留期裁剪在登记新访问之前，跨越边界时不能靠它保证写入上限。

修复给三个 publication 入口加同一上限守卫，lite runner 的超限本地状态直接交给完整 merge/apply 路径，保证保留边界也持久化到本机。读取历史超限快照允许有界恢复（最多十万），但仍逐条校验、验证桶/块 hash、原始数量及整个原始 stateChecksum，之后才由既有 merge 应用最近一万条策略。新 writer 仍只能发布最多一万条；不是提升产品保留数量或跳过损坏验证。

记录校验回归从 5 增至 7 项。修改前 publication 上限断言失败，完整旧格式的 10001 条 fixture 报 `Huawei History visits is invalid`；修改后同步/协作读取均可验证并恢复，重新发布一万条的 Head，损坏数据、非法计数和超出恢复上限仍拒绝。

失败调度存在独立放大：executeHistoryDomain 清空了 historyAutomaticNotBefore；后续 membership 刷新取消原定退避 timer，改为五秒后重跑。`check-aira-history-retry-backoff.cjs` 直接执行生产失败处理和调度，修改前报 `membership bypassed failure backoff`。修复将失败截止时间保存在调度器中，让会员/前台/网络/本地变化通知都尊重失败退避；健康状态的本地变化仍按原延迟处理，手动同步不经过此自动等待。

Huawei DevEco SDK 的 `@ohos.systemDateTime.d.ts` 确认 `getUptime(TimeType.ACTIVE)` 是不含深度休眠的毫秒计时。新探针优先使用这个时钟，平台不可用时才回退并标记。HiLog 的 `-T`/`-v` 参数已通过连接设备上的 `hilog -h` 核对。采样周期和阈值是 Aira 工程选择，不是华为掉帧事件的判定标准。

官方帧率分析参考：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-frame-rate-analysis 。本次复用既有原生能力，不需要更新 HarmonyOS 技能。


## 删除三条历史后的手动同步（1000465）

计数边界/退避修复的 Community 与 Official 构建均通过；1000465 已安装。首次自动恢复成功，记录 `ok=1 applied=0 uploaded=232`，完整校验计算 30.15 s，云端写入/确认 22.32 s，整轮 54.82 s。用户随后确认报错消失。

用户删除三条历史后手动同步，run 26 的历史阶段 16.63 s（整个手动请求 20.95 s）。读取 3306 个物理行并打包 31,149,255 字节；状态打包 250 ms；lite worker 解包 279 ms、投影 3410 ms；云端写入/确认 11.17 s；主线程收尾重新规范化 438 ms。上传 67 个物理行，不等同于修改了 67 条历史。

覆盖这次手动同步的 19 Hz / 4 KiB 栈采样记录 90 s，无丢样。主线程窗口的应用叶子栈包含 normalizeUrl、协作排序、packCooperatively、appendString 和 readRawRows。样本占比是该窗口的 CPU 周期加权分布，不是绝对 CPU 使用率或逐帧耗时。

本轮减少实际工作量：

- 移除 runner 的全量确认态内存缓存及收尾 normalize。账号范围内的持久化 Head 与新读取的远端 Head 仍决定无变化跳过、读取副本或拉取云端；保留期裁剪计入本地工作。确认后仍按原规则清 outbox/保存 Head，Provider 切换仍保留 outbox。
- 只有 Head 未变的 lite 准备阶段按账号及本设备 logicalId 前缀查询 block，保留所有小 Head。完整合并回退显式补读其他设备副本，不能把局部副本当作完整远端状态。
- lite 桶复用改为用已严格校验的目标记录重建原时间戳的规范 chunk，比较完整字节、chunk hash 和 bucket hash。省去再次 JSON 解码/网址解析存量记录；不依赖 dirty hint，不改变快照格式。内容、元数据或 hash 不匹配时重建该桶。

回归先红后绿：收尾测试原本重复解析 1000 条 URL；lite 读取预算原本读取其他设备约 30 MB；规范字节复用原本需要 2001 次 URL 解析，新实现只需目标数据的 1001 次。新增损坏 payload/时间/hash 不可复用及三条精确删除 roundtrip；完整旧格式黄金摘要未变。一万条上限恢复测试继续通过。

平台查询依据为 Huawei DevEco SDK `@ohos.data.relationalStore.d.ts` 的 `RdbPredicates.beginsWith`（API 9）。本轮未改变 cloud/RDB 线程归属，原始日志/调用栈位于仓库外。真机改善尚待新包验证。

本轮 Community 免签名构建、Official 构建及全部构建契约通过；1000466 已覆盖安装。首轮启动自动同步成功：1339 个物理行、13,139,578 字节；worker 解包 187 ms、投影 1646 ms、总计 1833 ms；收尾只剩 outbox 2 ms 和 Head 1 ms，全量缓存整理阶段已消失。整轮 7.24 s，上传 11 行。这轮是新增一条访问，不是之前删除三条的同负载对照，不能直接用总耗时断言加速比例；同样删除及滑动仍待用户复测。源码恢复 Community，诊断关闭，diff 检查通过。


1000466 的手动删除复测已成功：9998 → 9988 条访问，1339 行副本 / 13,140,599 字节，打包 117 ms；worker 解包 218 ms、投影 1709 ms、总计算 1927 ms；outbox 与 Head 收尾各 2 ms。上传 183 行，云端写入/确认 24.64 s，历史总计 27.77 s，完整手动请求 31.33 s。相比上一轮删除三条（67 行上传），本轮删除更多，云端等待更长；不能把总耗时增加解释成计算回退。副本字节下降约 58%，投影计算约减半，收尾重算消失；尚不证明滚动帧率达标。

用户说明手动同步有阻塞模态进度框，无法同步滑动，所以之前要求手动同步时滑动的验收步骤不成立。`SyncExperienceHost.syncNow` 对普通同步移除模态进度，沿用现有按钮“正在同步”状态。配置操作仍互斥；返回不取消共享同步任务；离开页面后不弹出完成/失败对话框。在页面内失败仍显示恢复入口。新回归执行真实 syncNow/onBackPress，覆盖不可打开模态、重复点击只有一个请求、允许返回以及离开后的结果不打扰。

普通手动同步取消阻塞进度框的 11 项响应性回归、其余构建契约、Community 免签名与 Official 构建均通过。1000467 已覆盖安装并启动；源码恢复 Community、诊断 false。未授权截图，未进行屏幕捕获；界面实际交互仍需后续使用验证，不能用没有计时器迟到替代逐帧验收。


## 1000467：解除手动遮罩后的连续滚动暴露累计等待

新日志的 manual run 1 有持续 `browsing=true`，总计 68.391 s。书签 29.379 s，其中本地快照 8.156 s、合并 8.136 s，多处阶段之间相隔约 4 s；对应 throttle 的 4 s 轮询等待在每个阶段重复触发。常用设置 CLOUD_FIRST 30.126 s 后平台回调 `outcome=failed code=1`，未能从数值码进一步区分网络或平台原因；第二次手动只重试该域，2.979 s 成功。历史阶段 8.870 s 成功，副本 13.36 MB、lite compute 1.812 s、上传 13 行，未回退全量计算。

本轮滚动中的计时器迟到为书签阶段 42 ms，以及常用设置远端读取阶段 66 / 67 / 42 ms。阶段包含异步等待，只有重叠关系，没有新 CPU 调用栈证明这些迟到均由同步计算导致。历史阶段时用户已停止滚动，不能据此判定历史同步时滚动无卡点。

移除 throttle 的等待手势结束/4 s 轮询；保留 8 ms 计算预算，交互时每次让出一个 16 ms 定时器片段，并保证中间能处理一段计算。非交互时继续零延迟事件循环让步。行为回归原本两项失败；新逻辑连续滚动和多阶段处理仍推进，每次让步不超过 16 ms，不累计数十秒等待，11 项通过。此修复消除等待放大，不替代之前减少全量读取/解析的性能修复。

取消手势结束等待的 Community 免签名构建与 Official 构建及全部契约均通过，1000468 已覆盖安装并启动，新一轮有界日志/调用栈采样已启动。源码恢复 Community、诊断关闭，diff 检查通过。尚未取得该包持续滚动时的真机对照，不宣称所有卡点消失。


## 1000468 后续：打包等待与删除写入放大

第一轮手动总计 70.551 s，历史计算 2.011 s、535 个物理变更，云端提交 60.566 s 后成功。一次 66 ms 主线程迟到发生于写入/提交边界；180 s CPU 样本实际从该迟到之后约 5 s 才开始，不能拿它证明该卡点由 commit 引起。无变化的后续手动在持续滑动中 2.253 s 完成，书签 762 ms、历史 Head 探测 522 ms，无全量任务。

另一轮持续滑动中书签 1.476 s、常用设置 783 ms，历史行打包 1.174 s，状态打包 3.409 s（其中 180 次让步共睡眠 3000 ms）、worker 3.246 s。主线程窗口采样确有 packCooperatively/appendString、状态编码及 RDB 读取，但调用栈占比不是逐帧卡顿归因。该次诊断窗口在云提交结束前达到 180 s 上限，不能宣称整轮已完成。

细化短批次策略：计数到批次边界但没有用满 8 ms 计算时间片时只做零延迟事件循环让步，不固定休眠一帧；达到计算预算或新交互信号时才让出一帧。模拟持续滚动、180 个 1 ms 短批次的测试在修改前超出休眠预算，修改后通过；12 项响应性回归通过。

用户指出少量删除产生数百行属于算法放大。复现确认固定“尽量装满”的分块会让删除后的后续记录移动，整桶新时间戳又令未变数据块字节改变。lite 投影现在先尝试按目标（非当前发布）槽已有 chunk 的结尾记录键保持分界，所有输出仍来自已验证的 desired records。与旧 chunk 规范字节相同则保留时间戳/哈希并省略该行上传；空 chunk、容量不足、损坏分界提示或新槽回退原 compact 算法。Head/bucket/chunk 格式与 12 KiB 上限不变，始终只改 inactive slot。

真实 codec 回归：一万条访问，连续两轮各删 40 条，第二轮 upsert 从全桶方案 288 行降至 172 行（约 40%）。应用新 chunks/buckets 但不发布 Head 时，旧快照仍可完整读取；发布后完整 roundtrip 保留全部删除；无变化下一轮只生成 Head。共 9 项 codec 回归通过，旧格式黄金摘要、一万条边界恢复、严格损坏校验继续通过。此结果是合成同负载对照，不等同于真机上传耗时必然按同比例下降。

分块复用与短批次让步优化已通过全部构建契约、Community 免签名与 Official 构建；1000470 已覆盖安装并启动，新日志采集已开启。源码恢复 Community、诊断 false。上传行数下降有真实 codec 同负载回归证据，真机云端耗时与滑动改善仍待对照；主线程全量读库/打包尚未迁移到 worker。


1000470 装机后有一轮手动成功：书签 1.123 s、常用设置 3.478 s、历史 6.245 s，总计 10.848 s。历史 enrolled=1、dirty=1、upsert/uploaded=5；副本 14,358,943 字节，行打包 156 ms，本地读取 111 ms，状态打包 294 ms（182 次让步共睡眠 20 ms），worker 解包 213 ms / 投影 1639 ms / 合计 1852 ms，云端写入与确认 3.133 s，收尾 outbox/Head 各 2 ms。该轮是新登记一条访问而非先前几十条删除，不能把 535→5 声称为同负载优化比例。历史阶段仍有 33 ms 计时器迟到，browsing=false，不构成滑动验收通过。

随后 18:12:33 的服务日志显示 Head 未变、无待同步变化，历史用时 592 ms、applied=0 uploaded=0 skipped=1；确认无变化路径没有重新执行全量读取/计算。主线程读取/打包与接近整份状态的 worker 计算仍是后续需要减少的工作。

## 1000470 之后：数据库 worker 路径从不可用到达成

在 1000470 的诊断构建上用 Official 包复现「删几条历史 → 立即同步」，Provider 为华为云空间。带本地变更的轮次（自动或手动，reason=local_change）连续暴露这条新路径的三个问题，逐个定位后落地：

1. `history_replica_database_fallback :: reason=worker-unavailable`，整份日志没有 `history_replica_database_taskpool`。分步诊断后确认 `step=dispatch`，`hilog.error` 打出 `Error: Can't return Promise in pending state`：`@Concurrent` 入口被写成 `async`，该 TaskPool 运行时拒绝返回 pending Promise（仓库其余 `@Concurrent` 都是同步的）。改为同步入口 + 平台建议在 taskpool 线程执行的 `getRdbStoreSync` / `queryWithoutRowCountSync` 同步 RDB API。
2. 之后任务能执行但仍失败，错误为 `read-replica-heads: SQLite: Generic error`。确认华为云空间的 Head/Block 是 `DISTRIBUTED_CLOUD` 表，worker 连接无法查询它们；改用显式 SQL（`querySqlWithoutRowCountSync`）仍是同一错误，证明与谓词封装无关，而是平台限制。
3. 据此定稿：worker 只读**本地（非分布式）库**的状态与 outbox，复制行仍由主线程按现有方式打包后以 ArrayBuffer 传入，worker 解码并生成差异。

修复内容：`@Concurrent` 入口同步化；`HuaweiHistoryReplicaReader.plan` 用 `getRdbStoreSync`/`queryWithoutRowCountSync`/`querySync` 同步读取，worker 内 `application.getApplicationContext()` 自取 Context；`HistorySyncSnapshotReader` 新增 `*Sync` 读取并与主线程异步+yield 版本共用 `parseVisit` 校验；`HuaweiSpaceHistoryRemoteStore` 增加 `supportsWorkerReplicaPlan()` 能力开关；回退诊断保留 `step=`/`code=` 与阶段标签。

回归：`check-aira-history-record-validation.cjs` 的同步 RDB 桩与运行入口改为「本地库 + 打包复制行」，`check-aira-history-replica-responsiveness.cjs` 断言 worker 只收到 scalar 与一个 ArrayBuffer（不含 state 对象）。11 项记录校验、10 项副本响应性、12 项同步响应性、历史同步契约及其余构建契约、Community 免签名编译通过。

最终真机复测（Official 诊断包，删若干历史后手动同步）：`history_replica_database_taskpool error=0`（2212 ms），`history_replica_database_compute decodeMs=72 projectionMs=1819 rows=1456 visits=9456 upsert=165 totalMs=2205`，`plan-merge database=1 upsert=165`，`write-remote database=1 changed=167`，`run-total uploaded=167 database=1`。整份日志里 `read-local` 与 `history_state_pack` 出现 0 次——主线程不再读取本地整份状态、也不再打包那约 5 MB 状态；该轮没有 `history_replica_database_fallback`。

仍在主线程的是复制行的读取与打包（`read-rows AiraH2HistoryBlocks rows=1449` ≈ 100 ms、`history_row_pack` ≈ 149 ms、约 14 MB），因为平台不允许 worker 读取 `DISTRIBUTED_CLOUD` 表。该轮主线程迟到只有 45～50 ms（bookmark/history scope），无回退。
