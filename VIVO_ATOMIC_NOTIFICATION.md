# vivo 原子通知（原子岛）接入说明

> 本文是**内师课程表**接入 vivo 原子通知的完整落地说明，包含**可直接发送的申请邮件模板**。
> 代码侧已经全部写完并可用；剩下的只有 vivo 官方的**准入权限**——那是一道流程，不是技术问题。

---

## 一、一句话结论

| 环节 | 状态 |
| --- | --- |
| 客户端代码（构造 `notification.superx.*` / `island.superx.*` 字段、挂到通知上） | ✅ 已完成 |
| 闹钟调度（`AlarmManager` 精确闹钟 + 开机重建 + 每日巡检自持续） | ✅ 已完成 |
| 优雅降级（非 vivo 机型 / 未开通权限 → 普通通知，不丢提醒） | ✅ 已完成 |
| **vivo 官方准入权限** | ⛔ **需要你发一封邮件申请**（见第四节） |
| **应用在 vivo 应用商店上架** | ⛔ 官方硬性前置条件 |

> vivo 官方原文：**「接入前请确保您的应用已经在 vivo 应用商店上架。」**

---

## 二、为什么要申请

vivo 对原子通知（原子岛）实行**准入制**：只有当 vivo 侧为你的包名开通权限后，系统才会解析
通知里的 `notification.superx.*` 字段并渲染成原子通知 / 原子岛胶囊。未开通时：

- 系统**直接忽略**这些字段；
- 通知按普通通知正常展示（因为本应用显式设置了 `notification.superx.showNotify = true`，这也是官方默认值）。

**所以这是一个纯增益功能**：申请下来就多一个炫酷的原子岛，申请不下来也不影响任何提醒。这也是为什么应用里可以放心地默认开启它。

官方文档索引（导航路径：`vivo系统适配指南 → 原子通知`）：

| 文档 | 地址 | 作用 |
| --- | --- | --- |
| 原子通知接入指导 | https://dev.vivo.com.cn/documentCenter/doc/894 | **准入申请流程**（本文的主要依据） |
| 原子通知规范 | https://dev.vivo.com.cn/documentCenter/doc/895 | 各触点样式、动效、消失机制 |
| 原子通知技术规范 | https://dev.vivo.com.cn/documentCenter/doc/896 | **字段表**（代码依据） |
| VPush 客户端 SDK 集成指南 | https://dev.vivo.com.cn/documentCenter/doc/365 | 服务端更新/结束通知时需要 |

---

## 三、官方准入流程（doc/894 原文要点）

1. **接入前请确保您的应用已经在 vivo 应用商店上架。**
2. 第一步：准备接入资料，发送邮件至 **`oosyztz@vivo.com`** 申请接入权限，等待 vivo 原子通知团队审核准入（**7–10 个工作日**）；
3. 第二步：获得准入申请后，完成需求定义及 UI 设计；
4. 第三步：双方评审需求定义及 UI 设计内容，并定稿通过；
5. 第四步：vivo 给开发者开通相关权限，开发者完成开发，双方进行联调与测试；
6. 第五步：应用与 vivo 原子通知完成上线（**vivo 功能上线为机型逐步放量**）；
7. 第六步：进行定期的体验巡检，重大更新进行相互公告。

---

## 四、申请邮件模板（可直接复制）

> **收件人**：`oosyztz@vivo.com`
> **主题**：`【原子通知接入申请】内师课程表（cn.edu.njtc.njtc_schedule）`

```
尊敬的 vivo 原子通知团队：

我方已阅读原子通知产品设计规范与技术规范，准备按照要求适配原子通知，
希望进一步沟通后续流程和相关规范。

以下为接入申请信息：

1. 应用名称：内师课程表
2. 应用包名：cn.edu.njtc.njtc_schedule
3. 开发者联系电话/微信：<请填写真实联系方式>
4. 接入原子通知具体的服务场景：
   高校课程表的上课 / 下节课预告（对应官方场景 "会议日程 METTING"）。
   学生的每节课都有明确的开始与结束时间，属于典型的"事件有明确开始和结束时间"。
   具体触点：下节课预告 —— 下课前 5 分钟在通知中心展示本节下课时间与
   下一节课的课程名 / 上课时间 / 地点，并在支持原子岛的机型上以胶囊形式呈现。
5. 接入需求定义文档：见附件《原子通知接入需求定义文档》（按官方模板
   "原子通知接入需求定义文档示例.xlsx" 填写）
6. 服务示意图：见附件（共 3 张）
   - 01-课程表主界面.png
   - 02-下节课预告-通知中心.png
   - 03-下节课预告-原子岛.png
```

### 附件一：《原子通知接入需求定义文档》填写要点

官方模板：`原子通知接入需求定义文档示例.xlsx`（下载入口在 doc/894 正文内）。
按下表填写即可，字段含义与项目里的实现一一对应：

| 模板字段 | 本应用填写内容 |
| --- | --- |
| 业务场景 | 会议日程（METTING） |
| 原子通知类型 | 强调信息模版（template = 1） |
| 触发时机 | 每节课**下课时刻**（如 10:45）自动触发 |
| 触发方式 | 客户端本地定时触发（AlarmManager 精确闹钟），不依赖服务端推送 |
| 触发频次 | 每周约 20 节课 → 每周约 20 条；单条不刷新（一次性通知） |
| 展示时长 | `keepDuration = 1800` 秒（30 分钟，官方上限 3600 秒） |
| 展示触点 | 通知中心 + 锁屏 + 状态栏（含原子岛胶囊） |
| 点击行为 | `islandClick = 1` → 跳转 App 课程表页 |
| 是否可刷新 | 否。若有课程调整，重新下发一条新通知（`operation = 0`） |
| 结束方式 | 不主动结束，靠 `keepDuration` 到期自动清除 |

### 附件二：服务示意图怎么出

本机没有 vivo 设备，示意图用「真实运行截图 + 官方规范样式」合成即可，
需要三张：
1. **课程表主界面** —— 直接取自 `screenshots/01-timetable-grid.png`（真实截图）；
2. **通知中心大卡** —— 按 doc/895 的强调信息模版样式绘制；
3. **原子岛胶囊** —— 按 doc/895 的「左：图片+文本 / 右：胶囊文本」布局绘制。

> 申请材料里**不需要**提交签名后的 APK；联调阶段 vivo 会提供测试包名白名单。

---

## 五、代码侧实现（已完成，此处供联调对照）

### 5.1 文件清单

| 文件 | 职责 |
| --- | --- |
| `android/app/src/main/kotlin/cn/edu/njtc/njtc_schedule/reminder/Models.kt` | 计划数据结构、周次判定、日期换算（不依赖 `java.time`，兼容 minSdk 24） |
| `.../reminder/PlanStore.kt` | 计划与已排布闹钟的持久化（开机重建要用） |
| `.../reminder/ReminderScheduler.kt` | 滑动窗口推导 + `AlarmManager` 排布 + 每日巡检自持续 |
| `.../reminder/NotificationFactory.kt` | 两条通知通道、文案与课程配色、发送 |
| `.../reminder/VivoHelper.kt` | **vivo 识别 + `superx` 字段挂载 + 系统设置跳转** |
| `.../reminder/ReminderReceiver.kt` | 闹钟落地点，直接发通知 |
| `.../reminder/BootReceiver.kt` | 开机 / 升级后重建全部闹钟 |
| `.../reminder/ReminderBridge.kt` | MethodChannel `cn.edu.njtc.njtc_schedule/reminder` |
| `test/...` + `integration_test/reminder_e2e_test.dart` | 单元测试与**真机端到端验证**（排闹钟 → 发通知 → 校验 superx 字段） |

### 5.2 「下节课预告」→ superx 字段映射

以「示例课程戊第 3-4 节 10:45 下课，下一节是示例课程庚10:55 / 明德楼 B105」为例：

```kotlin
// notification.superx.*
operation      = 0                                   // 创建
showNotify     = true                                // 失败降级为普通通知
template       = 1                                   // 强调信息
scene          = "METTING"                           // 会议日程
keepDuration   = 1800                                // 存留 30 分钟
sound          = true
dismissWhenKill= false                               // 系统默认：不清除
clickResp      = PendingIntent → MainActivity

// notification.superx.baseInfos.*
icon           = R.mipmap.ic_launcher
title          = "「示例课程戊」10:45 下课"
content        = "下节课：示例课程庚 · 10:55 · 格致楼105"
subInfo        = 1                                   // 文本
subText        = "下节课预告 · 第5-6节"
subTextColor   = 课程配色（如 0xFF6366F1）

// notification.superx.infos.*（强调信息模版）
describe       = "下节课预告 · 第5-6节"
coreInfo       = "下节课：示例课程庚 · 10:55 · 格致楼105"
image          = R.mipmap.ic_launcher
imageClickResp = 同 clickResp

// notification.superx.shortInfos.*（小卡 / OriginB 锁屏）
icon / title / content / subText 同 baseInfos

// notification.superx.capsule.*（不支持原子岛的机型：状态栏胶囊）
state          = 1
icon           = R.mipmap.ic_launcher
content        = "大学物理… 10:55"                     // 下一节课短名 + 上课时间
bgColor        = 课程配色
contentColor   = 白色
clickResp      = 同 clickResp

// notification.superx.island.*（OriginOS 5.0+ 原子岛）
leftTemplate   = 1                                   // 图片+文本
leftInfo       = { icon, content = "示例课程庚" }  // 下一节课名
rightTemplate  = 6                                   // 胶囊文本
rightInfo      = { capsuleContent = "10:55 上课", capsuleBgColor = 课程配色 }
islandClick    = 1                                   // 跳落地页
showTime       = 1800
template       = 1                                   // 大卡：强调信息
baseInfos/infos= 复用上面的 Bundle
```

> 官方约束复核：原子岛**摄像头左右两侧都必须有内容**。本实现左侧用 `leftTemplate=1`（图片+文本），
> 右侧用 `rightTemplate=6`（胶囊文本），符合要求。
> 同时，官方要求「同一信息若以原子通知发送，不要再以普通通知发送」——
> 因此**下节课预告**在 vivo 设备上**只发原子通知这一条**（不发普通通知），
> 非 vivo 设备或关闭开关时才发普通通知。

### 5.3 验证字段是否真的挂上去了

不需要 vivo 设备也能验证字段构造正确 —— 用 `dumpsys` 看系统里那条通知的 extras：

```bash
# 触发一条测试提醒（App 内「发送测试提醒」按钮，或直接用 adb 打开 App）
adb shell dumpsys notification --noredact | grep -A 40 "notification.superx"
```

应当能看到 `notification.superx.operation=0`、`notification.superx.scene=METTING`、
`notification.superx.island` 等键。在非 vivo 设备上系统不会渲染它们，但字段本身是实打实挂上去了。

#### 5.3.1 本机实测记录（Android 17 / API 37 模拟器，非 vivo 设备）

在 Google 官方模拟器（`sdk_gphone64_x86_64`、Android 17）上跑完
`integration_test/reminder_e2e_test.dart` 后，趁 App 尚未被卸载，
用 `adb shell dumpsys notification --noredact` 抓到的真实记录
（**需先** `adb shell pm grant cn.edu.njtc.njtc_schedule android.permission.POST_NOTIFICATIONS`，
否则 Android 13+ 上通知根本不会被系统记录）：

```
NotificationRecord(... id=6603 ... : Notification(channel=njtc_course_end ...))
  effectiveNotificationChannel=NotificationChannel{mId='njtc_course_end', mName=下节课预告, mImportance=3, ...}
  ...
  extras={
    android.title=String (「端到端测试课程A」08:45 下课)
    android.text=String (下节课：端到端测试课程A · 08:55 · 格致楼216)
    android.bigText=String (下节课：端到端测试课程A · 08:55 · 格致楼216)
    notification.superx.operation=Integer (0)
    notification.superx.showNotify=Boolean (true)
    notification.superx.template=Integer (1)
    notification.superx.scene=String (METTING)
    notification.superx.keepDuration=Integer (1800)
    notification.superx.sound=Boolean (true)
    notification.superx.dismissWhenKill=Boolean (false)
    notification.superx.changedRecord=Integer (0)
    notification.superx.clickResp=PendingIntent (... cn.edu.njtc.njtc_schedule startActivity ...)
    notification.superx.baseInfos=Bundle (dataSize=920)
    notification.superx.infos=Bundle (dataSize=664)
    notification.superx.shortInfos=Bundle (dataSize=1204)
    notification.superx.capsule=Bundle (dataSize=604)
    notification.superx.island=Bundle (dataSize=3124)
  }
```

**结论**：14 个顶层 `notification.superx.*` 键全部按官方技术规范挂载成功，
类型与取值正确（`scene` 为官方拼写的 `METTING`，`island` 子 Bundle 3124 字节
说明左右岛信息与原子岛大卡数据都已写入）。系统在非 vivo 设备上忽略这些键，
通知按 `showNotify=true` 降级为普通通知 —— 这正是设计预期。

同一轮还抓到了另外两条通知记录，证明两个通道都通：

| 通知 id | 通道 | 通道名 / 重要级 | 来源 |
| --- | --- | --- | --- |
| 6600 / 6604 | `njtc_course_reminder` | 上课提醒 / `mImportance=4` | 「时段预告」「上课提醒」测试 |
| 6603 | `njtc_course_end` | 下节课预告 / `mImportance=3` | 「下节课预告」测试（**这条才带 superx 字段**） |

（id 生成公式：`1000 + (courseName.hashCode and 0x3FF) * 8 + type`，
`type=0` 为第一个提前点、`type=3` 为下节课预告；同一门课的同类提醒互相覆盖，
避免通知栏堆叠。）

闹钟侧同样有据可查（`adb shell dumpsys alarm`）：

```
RTC_WAKEUP #12: Alarm{... type 0 origWhen 1791072300000 cn.edu.njtc.njtc_schedule}
  tag=*walarm*:cn.edu.njtc.njtc_schedule.action.DAILY_DRIVER
RTC_WAKEUP #23..28: Alarm{... origWhen 1791099000000 / 1791099900000 / 1791100500000 /
                                   1791103800000 / 1791106500000 / 1791107700000 ...}
  tag=*walarm*:cn.edu.njtc.njtc_schedule.action.COURSE_REMINDER
RTC_WAKEUP ...: 同上再加 604800000 ms（7 天后同一天）
  tag=*walarm*:cn.edu.njtc.njtc_schedule.action.COURSE_REMINDER
```

* `DAILY_DRIVER` 的时间正好是当日 **00:05**；
* **12 条 `COURSE_REMINDER`** 分成两组、相隔 **恰好 7 天**（604800000 ms），
  单日 6 条落在 **07:30 / 07:45 / 07:55 / 08:50 / 09:35 / 09:55**：
  ① 07:30 = 上午首课提前 30 分钟的**时段预告**；
  ② 07:45 = 上午首课提前 15 分钟；
  ③ 07:55 / 08:50 = 第 1、2 节提前 5 分钟（**每节课都有**）；
  ④ 09:35 = 第 2 节下课前的**下节课预告**（下一节是第 3 节）；
  ⑤ 09:55 = 第 3 节提前 5 分钟。
  注意 **08:40 不存在** —— 第 1→2 节是同一门课、同地点、节次连号的**连堂**，
  按规则不发下节课预告；第 2 节也不发 30/15 分钟提醒（只有时段首课才有）。
* 全部是 `RTC_WAKEUP` 且无窗口期（精确闹钟），与 App 内 `exact=true` 的回显吻合。
  更进一步：**12 个课程闹钟的 dump 里都带
  `showIntent=PendingIntent{… startActivity}`，而 00:05 的巡检闹钟没有** ——
  这正是提醒走 `setAlarmClock`（系统按「用户闹钟」对待，Doze / 厂商省电都不推迟）、
  巡检走 `setExactAndAllowWhileIdle` 的证据。若某些机型/商店不接受闹钟语义，
  把 `ReminderScheduler.kt` 的 `USE_ALARM_CLOCK` 改成 `false` 即可回到纯
  `setExactAndAllowWhileIdle`。

#### 5.3.2 真机实测记录（vivo 云真机，真实 OriginOS）

设备序列号 `10AE1C1NP80011G`，用户导出的 logcat
`logs_10AE1C1NP80011G_1791088183247_export.log`（2026-10-04
`12:25:47`~`12:29:30`）。**结论：`isIslandCapable()` 在真实 ROM 上判为「支持」。**

```
[12:26:10.082] [16277] [16277] [3] [VivoConfigStore] : key:vivo.software.disable_island isCached is true and value is false
[12:26:50.453] [16277] [16277] [3] [VivoConfigStore] : key:vivo.software.disable_island isCached is true and value is false
[12:26:51.234] [16277] [16277] [3] [VivoConfigStore] : key:vivo.software.disable_island isCached is true and value is false
```

* `pid 16277` **就是我们 App 的进程**，`vivo.software.disable_island` 正是
  `VivoHelper.disableIslandFeature()` 传给 `FtFeature.isFeatureSupport()` 的那个
  字符串；`VivoConfigStore` 是 vivo ROM 侧读配置时自己打的日志。
  ⇒ 反射**确实命中**了 ROM 里的 `FtFeature`，且 ROM 回执
  **value = false ⇒ 原子岛未被禁用**；配合 `romVersion() >= 5.0`（取不到时按支持处理）
  即 `isIslandCapable() == true`，卡片上会显示 **`支持原子岛`**。
* 同一次导入还验证了「真实教务系统 → 课表 → 提醒」全链路（见
  `BUILD_NOTES.md` §9.6），因此**原子通知链路的输入端也是真的**。

仍未验证（需要在真机上看一眼，只差最后一步）：
**点「立即验证 → 下节课预告（vivo 走原子岛）」**，看状态栏出现的是原子岛形态还是
普通通知。本轮日志里没有 `NjtcVivo`（挂 superx）与 `NjtcNotify`（发通知）两行，
说明用户当时只做了导入与排布、没有触发这条通知。
⇒ **下一轮已补上（见 §5.3.3）：App 侧确认发出了原子通知，仍缺系统侧截图。**

> 为了让**下一份日志自己就能回答**「支不支持原子岛 / 场景开关开没开」，
> `VivoHelper.deviceSummary()` 已改为额外打一条
> `I/NjtcVivo: 设备摘要 {isVivo=…, isIslandCapable=…, romVersion=…, sceneEnabled=…, …}`。
> 之前这个方法只返回 Map 不打日志，导致真机排障时 `romVersion` 与 `sceneEnabled`
> 完全取不到（只能靠上面那条 `VivoConfigStore` 反推）。

#### 5.3.3 真机实测记录之二 —— 原子通知**确实发出去了**（2026-10-04 13:04）

同一台设备（`10AE1C1NP80011G`）导出的第二份 logcat
`logs_10AE1C1NP80011G_1791090365708_export.log`（窗口 `13:02:42`~`13:05:59`，
App pid **16278**）里，用户这次点了「立即验证」的三个按钮，**App 侧全链路留下证据**：

```
[13:04:48.574] [16278] I NjtcNotify: 已发送[普通通知] id=9902 第3-4节 · 示例课程戊 | 10:00 上课 · 明德楼A103 · 示例老师B
[13:04:53.255] [16278] I NjtcVivo  : 已挂载 superx 字段：scene=METTING template=1 rightTemplate=6 keepDuration=1800s islandShowTime=180s
[13:04:53.262] [16278] I NjtcNotify: 已发送[vivo 原子通知 + 原子岛] id=9901 「示例课程戊」10:45 下课 | 下节课：示例课程庚 · 10:55 · 格致楼105
[13:05:13.196] [16278] I NjtcNotify: 已发送[普通通知] id=9903 还有 30 分钟上课 · 上午共 3 门课 | 08:00 示例课程甲 @格致楼216
```

* `[vivo 原子通知 + 原子岛]` 这个前缀**只有走原子通知分支才会打**
  （`ReminderBridge`/`ReminderScheduler` 里依据 `isIslandCapable()` 选模板），
  普通通道打的是 `[普通通知]`；同批三条里两条走普通、一条走原子 ⇒
  **分支选择在真实 ROM 上工作正常**（我们的预期本来就是「只有下课预告上岛」）。
* `已挂载 superx 字段：scene=METTING template=1 rightTemplate=6 …` 说明
  `Notification.extras` 上的 `notification.superx.*` / `island.superx.*` 全前缀键
  在真机上真的写进去了（模拟器只能证明代码路径，这条证明真机路径）。
* `scene=METTING` 是**未准入时的默认场景值**（vivo 白名单里没有课程类目）——
  准入后由 vivo 下发的正式场景值替换（见 §5.4）。
* 顺带拿到一条与原子通知无关但有用的结论：通知文案里的 `明德楼A103 · 示例老师B`
  表明 App 里那门课的**地点与教师都在**（对比 §5.3.2 同一设备早一轮的排布日志
  里地点字段为空，说明中途的解析修复生效了）。

> **仍缺的最后一块**：系统那一侧长什么样（原子岛/胶囊形态 vs 普通横幅）。
> `NjtcNotify` 只能证明我们按原子通知通道发出，**不能证明 vivo 认了这个字段**——
> 后者要么等准入通过，要么靠一张触发瞬间的状态栏截图。已写入
> `D:\DSH\vivo_cloud_test_checklist.md` 第四轮（v1.1.3）作为唯一待办。

### 5.4 权限开通后需要做的三件事

1. 确认 `isIslandCapable()` 在目标机型上返回 `true`（OriginOS 5.0 / Android 15+）；
2. 用 vivo 提供的测试白名单包名安装，观察状态栏是否出现胶囊；
3. 若 vivo 联调反馈字段名或层级有出入，**只需要改 `VivoHelper.attachSuperx()` 这一个函数**，其余代码无需改动。

---

## 六、注意事项（摘自 doc/895，影响实现取舍）

| 官方约束 | 本应用的处理 |
| --- | --- |
| 单个活动最多支持 10s/次的刷新频次 | 本应用不做刷新，每节课只发一次 |
| 单个活动超过 2 小时不更新则被系统清除 | 下节课预告本就是一次性通知，`keepDuration=1800` 内展示即可 |
| 单个活动最长显示时长 8 小时 | 远小于该上限 |
| 用户手动删除通知中心/锁屏的原子通知后，本次活动不再显示 | 符合预期：删掉就是「已读」 |
| 应用进程被杀时系统默认不清除 | 保持默认（`dismissWhenKill=false`） |
| 应用前台不显示状态栏原子通知 | 系统行为，无需处理 |
| 禁止准入内容：广告营销、违法违规、隐私信息 | 本应用只展示课程名 / 时间 / 地点，无隐私字段 |

---

## 七、vivo 机型上的其他保活优化（代码里也已实现）

原子通知要按时送达，前提是**闹钟没被系统的省电策略压掉**。所以 App 的「提醒设置」页在
vivo 设备上会额外显示一个**vivo 专项优化**卡片，一键跳转：

| 优化项 | 跳转目标 |
| --- | --- |
| 通知权限 | `ACTION_APP_NOTIFICATION_SETTINGS` |
| 精确闹钟 | `ACTION_REQUEST_SCHEDULE_EXACT_ALARM`（Android 12+） |
| 电池优化白名单 | `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` |
| **自启动 / 后台高耗电** | `com.vivo.permissionmanager/.activity.BgStartUpManagerActivity`（按 OriginOS 版本依次尝试多个组件名，全部落空则退到应用详情页） |

> 提醒的健壮性设计（已实现，与 vivo 无关的部分）：
> 采用**滑动窗口 + 每日巡检闹钟**——每次只排布未来 14 天的闹钟（约 160–240 条），
> 另外在每天 00:05 挂一个巡检闹钟把窗口往后推，因此**即使用户一个月不打开 App，提醒也不会断**。
> 开机 / 应用升级后由 `BootReceiver` 从本地计划重建全部闹钟。
