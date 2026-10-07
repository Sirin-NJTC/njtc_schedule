# AGENTS.md — 接手这个项目前先读这页

内江师范学院课程表（Android / Flutter）。当前版本 **1.1.12+14**（`pubspec.yaml`），
**210 个单元测试全绿**（17 个 `test/*_test.dart` + 6 个 `integration_test/*_e2e_test.dart`）。

这一页只写「接手必须知道的约定与红线」，是 [`BUILD_NOTES.md`](BUILD_NOTES.md) 里 §9.x 各轮
踩坑记录的浓缩版。**改代码前先扫一遍 §9.16 ~ §9.18**（显示开关、节假日联网更新、发布流程），
那里有每条约定是怎么被踩出来的。

## 改完必须跑的验证

```powershell
$flutter = 'D:\DSH\.tools\flutter\bin\flutter.bat'   # 本机路径；CI 固定 flutter 3.47.6
& $flutter analyze            # 必须 0 issue
& $flutter test               # 必须 210 passed
```

* 动了**提醒排程 / 桌面小组件 / 网页导入**这三块（Dart 与 Kotlin 都要改的那种），还要跑对应的
  原生 E2E：`& $flutter test integration_test/reminder_e2e_test.dart -d <设备>` 等。
  **这些用例会把 App 卸载重装，别拿装了真实课表的真机跑，用模拟器。**
* 网页导入的两个 E2E 需要先起固件服务 `tool/jwglxt_fixture_server.py`（用法见 README「测试」）。
* `flutter test` 之后 `GeneratedPluginRegistrant.java` 里可能残留 `integration_test` 插件，
  紧接着 `flutter build apk` 会报「程序包 dev.flutter.plugins.integration_test 不存在」——
  **重跑一次 build 即自愈**，不是代码问题。

## 红线（破坏了不容易发现）

1. **「天」一律用 epochDay（UTC 天数）**：Dart 侧 `epochDayOf()`（`lib/models/holiday_calendar.dart`）
   必须和 Kotlin 侧 `DayMath` 算出同一个数。别用本地时区/`DateTime.day` 去跨语言对天数，
   节假日和调休补班全靠这个对齐。
2. **`HolidaySyncService.update()` 永不抛异常**：网络失败只能变成 `note`，日历保持原样。
   `AppState._shouldAutoSyncHolidays()` 的**第一条判断必须是 `source == manual → false`**
   （用户手改过的日历绝不能被联网结果覆盖）；启动静默同步无论成功失败都要 `syncReminders()`。
3. **哪些设置要重排提醒、哪些不用**：显示类开关（`showWeekend`、`showInactiveCourses`）只影响渲染，
   **不重排**；节假日/调休、提醒时间、开关提醒这类会影响闹钟的必须重排。
   新加设置时先问自己属于哪一类。
4. **提醒载荷是 Dart → Kotlin 的 JSON 契约**：`lib/services/reminder_service.dart` 的
   `buildPlanPayload()` ↔ `android/.../reminder/Models.kt` 的 `ReminderPlan`（含 `fromJson`）
   必须同步改，Kotlin 侧新字段要给默认值，否则老数据反序列化会炸。
   真机取证线索：`adb logcat -s flutter` 里的 `HolidaySync: ok=… 放假=N 补班=M`。
5. **`lib/widgets/timetable_grid.dart` 的内部列索引永远是 7 天**，只有「渲染几列」随
   `_visibleDays`（`showWeekend ? 7 : 5`）变；`_todayColumn` 落在隐藏列时要返回 null。
   改这里务必跑 `test/timetable_grid_test.dart`。
6. **仓库是公开的，别提交敏感文件**：`android/local.properties`、keystore / `.jks`、`.env`
   都已在 `.gitignore` 里，加新密钥前先确认不会被 `git status` 带进去。
7. **当前 APK 是 debug 签名**，只能自测/内测分发，**不能上架应用商店**。
8. **改出厂作息要同时动四个地方**：`lib/models/period.dart` 的 `defaultPeriods`、
   `android/.../widget/WidgetData.kt` 的 `DEFAULT_PERIODS`（Kotlin 侧兜底）、
   `preview.html` 的 `PERIODS`，**外加把 `PeriodStore.currentVersion` +1**。
   最后一步最容易漏：老用户只要打开过「节次时间」页并点过保存，本地就躺着一份
   旧存档，不给版本号的话它会一直挡着新默认值，**课程提醒也就一直按已作废的时间响**。
   `legacyDefaultPeriods` 是判断「那份存档只是原样保存、还是用户真调过」的基准，别删。
9. **周次换算只有 `lib/models/semester.dart` 一份**（`weekOfSemester`）。
   首页、网格、`AppState` 都调它，别再手写 `difference().inDays ~/ 7 + 1` ——
   那玩意儿会把时分秒算进去，`startDate` 一有时间分量就和别的页面算出不同的周。

## 发布

* 推一个 `v*` 标签 → `.github/workflows/release.yml` 会自动
  `analyze → test → build apk --release [--split-per-abi]` 并把四个包传成 Release 资产。
  **注意标签触发的工作流必须已经存在于被标签的那个提交里**（先提交工作流，再打标签）。
* Release 资产名**必须 ASCII**（`njtc-schedule-<ver>-<abi>.apk`）：Windows PowerShell 会把
  URL `?name=` 里的中文整段丢掉（详见 §9.18）。本地 `D:\DSH\dist\内师课程表-*.apk` 保持中文名。
* 手动重传 Release 用 `D:\DSH\github_release.ps1`（幂等；令牌放 `$env:GH_PAT`）。

## 文档地图

| 文件 | 内容 |
| --- | --- |
| `README.md` | 功能、截图、使用指南、项目结构、已验证内容 |
| `BUILD_NOTES.md` | **§9.1 ~ §9.18 每轮开发的踩坑与决策**，最值钱的一份 |
| `VIVO_ATOMIC_NOTIFICATION.md` | vivo 原子通知（COURSE 场景）接入细节 |
| `AGENTS.md` | 就是本页：接手约定与红线 |

仓库目录之外的东西（打包发给别人时不会带上）：`D:\DSH\dist\`（APK）、`D:\DSH\build_112.ps1`
（analyze + test + 四包构建 + aapt2 校验）、`D:\DSH\github_release.ps1`（发 Release）、
`D:\DSH\vivo_cloud_test_checklist.md`（vivo 商店上线自测清单）、`D:\DSH\release_notes_*.md`。

## 待办

* vivo 应用商店上架材料与 COURSE 场景分类审核（`VIVO_ATOMIC_NOTIFICATION.md` + 商店自测清单）。
* 正式签名（换掉 debug key）后才能上架；换签名要注意升级覆盖安装会失败。
