# AGENTS.md — 接手这个项目前先读这页

内江师范学院课程表（Android / Flutter）。当前版本 **1.3.0+18**（`pubspec.yaml`），
**310 个单元测试全绿**（22 个 `test/*_test.dart` + 7 个 `integration_test/*_e2e_test.dart`）。

这一页只写「接手必须知道的约定与红线」，是 [`BUILD_NOTES.md`](BUILD_NOTES.md) 里 §9.x 各轮
踩坑记录的浓缩版。**改代码前先扫一遍 §9.16 ~ §9.28**（显示开关、节假日联网更新、发布流程、
改日历漏推小组件那个回归、全览页 + 多格式导入 + 离线 OCR、节假日合并显示与时长调整、
仓库截图/固件一律用模拟器与合成数据、重写历史也删不掉远端悬空对象、全仓库真实数据清洗、
删库重建与「整批推 tag 不触发 CI」），那里有每条约定是怎么被踩出来的。

## 改完必须跑的验证

```powershell
$flutter = 'D:\DSH\.tools\flutter\bin\flutter.bat'   # 本机路径；CI 固定 flutter 3.47.6
& $flutter analyze            # 必须 0 issue
& $flutter test               # 必须 310 passed
```

* 动了**提醒排程 / 桌面小组件 / 网页导入 / OCR** 这几块（Dart 与 Kotlin 都要改的那种），还要跑对应的
  原生 E2E：`& $flutter test integration_test/reminder_e2e_test.dart -d <设备>` 等。
  **这些用例会把 App 卸载重装，别拿装了真实课表的真机跑，用模拟器。**
* **OCR 的 E2E 要先有语言模型**：`tool/fetch_tessdata.ps1` 拉 `chi_sim` + `eng` 到
  `android/app/src/main/assets/tessdata/`（不进仓库），没有的话
  `integration_test/ocr_e2e_test.dart` 第一条就红。图片那条自带输入（现场画 PNG），
  PDF 那条的夹具是打进包的 asset（原因见 §9.22.5）。
* **改了出厂作息（红线 8）同样要跑原生 E2E**：`flutter test` 不覆盖 `integration_test/`。
  v1.1.13 就是把第 1 节从 08:00 改到 08:20 却没跑 E2E，`reminder_e2e_test.dart` 里写死的
  `07:30` 那一串断言红了整版都没人发现，一直到 v1.1.14 才修（§9.21.4）。
  **测试里别写时刻字面量**，从 `periodOfSection(...)` 推导。
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
10. **凡是改了课表 / 节次 / 节假日日历，都必须走 `AppState._pushWidget()` 把数据推给原生小组件**
   （它故意不 `await`，见方法上的注释）。v1.1.13 就是漏了 `updateHolidays()` /
   `resetHolidays()` / `syncHolidaysFromNetwork()` 三条路径，导致**改完日历桌面小组件还在按旧日历画**，
   直到 v1.1.14 才修（`test/holiday_sync_test.dart` 里那三条回归用例盯着这件事）。
    改动后顺手看一眼：新增的 setter 里有没有忘了推。
11. **`nextClassOccurrence` 的扫描窗口是 21 天**（`scanDays`，含今天）：法定假期可以连放 9 天以上，
    窗口短了首页整个假期都会空白。找不到下一节课时若今天正在放假，要显示「今天放假」而不是留白。
12. **OCR 的语言模型不进仓库，但必须 `noCompress`**：`.gitignore` 忽略
    `android/app/src/main/assets/tessdata/`（单个 13MB），CI 在 `flutter analyze` 之前下载。
    `android/app/build.gradle.kts` 里的 `androidResources { noCompress += "traineddata" }`
    **不能删**：AGP 默认压 assets，`assets.openFd()` 读压缩条目会抛异常，
    表现出来却是 Dart 侧的 `MissingPluginException`（§9.22.4）。
13. **OCR 的 MethodChannel handler 必须整体 try/catch 回 `result.error(...)`**：
    原生异常直接从 handler 里抛出去，Dart 侧看到的是「桥没注册」这种假象，极难查。
    改 `android/.../ocr/OcrBridge.kt` 时保持这个结构。
14. **OCR 语言模型/引擎相关的东西一律在 `OcrService` + `OcrBridge` 里**，别把
    `PdfRenderer`、`TextPainter` 这类平台细节漏到页面层；识别结果先给用户过一眼再解析导入
    （OCR 出来的括号数字是会认花的，§9.22.5 有原文）。
15. **节假日仍然是「逐天」存储的**：`HolidayCalendar.holidays` 一天一条（`yyyy-MM-dd|name`），
    页面上的「一行」只是 `HolidayRange` 这个**显示层视图**（`holidayRanges` 按
    `festivalKeyOf(name)` + epochDay 连续切段）。下发给 Kotlin 的契约因此没变，
    **别顺手把存储改成区间**，否则老存档、原生 `holidays: Set<Long>` 全要跟着动。
    改这段代码时记住四件事：写回只走 `withHolidayRange()`（它负责接管重叠段、删掉被压到的补班日、
    按 `maxHolidayRangeDays = 120` 截断）；返回前一定 `.sorted()`（同一天只留先来的那条）；
    保存路径必须经 `AppState.updateHolidays()`（红线 10 的小组件推送在里面）；
    **一天被别人接管时要记原主**——`HolidayDay.originName` 会以行首 `^原主|日期|名字` 的
    形式进存档，缩短 / 删除那一段时把它还给原来的节日（忘了归还就是「那天悄悄不是假期了」，
    提醒会在放假日响）。**动这个存档格式一定要回头跑老格式的用例**：别用三段竖线编码，
    老数据里名字本身可能带 `|`。
16. **仓库里不许出现真机截图 / 真实课表数据**（2026-10-07 用户明确要求，详见 `BUILD_NOTES.md` §9.24）：
    `screenshots/` 里的图**一律来自模拟器**，且必须是 `lib/dev/demo_seed.dart` 灌进去的
    **全虚构**演示数据（课名通用、教师「示例老师A~J」、教室 `明德楼A101` 这类）。
    真机上装的是作者本人的真实课表（真实课程名 / 教师 / 教室），拍下来就是个人信息。
    要出新截图：`flutter run -t lib/dev/demo_seed.dart -d <模拟器>` →（可选）`adb install -r` 装
    x86_64 release 包 → `screencap` + `pull`；OCR 那张的输入用
    `tool/make_demo_timetable_photo.py` 生成。**别把任何真机截图提交上去**，
    桌面小组件那张也只放应用内的启用说明页（真机桌面会带壁纸与桌面图标）。
    ⚠️ 测试固件同理：`test/fixtures/sample_timetable.xls` **必须是合成的**
    （结构与真实教务导出对齐、内容全虚构，由 `tool/make_xls_fixture.py` 生成，
    改字段就改脚本重新生成 + 同步 `test/xls_reader_test.dart`、`test/app_flow_test.dart`
    里的期望值）。**别再往仓库里放真实教务导出的 .xls**，那里面有真实课程 / 教师 / 教室。
    ⚠️ **不止截图和固件**：2026-10-07 按用户要求把全仓库的真实课表数据都洗了一遍（§9.27）——
    代码注释、测试夹具、文档示例、`preview.html`、桌面小组件预览图里的真实课名 / 教师 / 班级
    一律改成 `示例课程甲~癸` / `示例老师A~J` / `演示26.8`；**教学楼名（明德楼 / 格致楼）故意保留**
    （公开信息，且与已发布的模拟器截图一致）。写新代码举例时直接用这套示例名，别再抄真课表；
    清洗后必须全量 `flutter test`：**按课名找东西的断言是盲区**（§9.27 踩过，一次挂了 4 条）。
    ⚠️ 而且**删提交治不了本**：2026-10-07 用 `git filter-branch` + force push 重写过一次历史
    （§9.26），但 GitHub 仍能按完整 SHA 取到悬空的旧对象（旧提交里的真机截图、真实 .xls 都还
    取得到）。真要彻底消失得联系 GitHub Support 清 GC 或删库重建 —— 所以第一条永远是
    **别把真实数据提交上去**。
    ⚠️ 最终是**删库重建**解决的（§9.28，代价：star / watch / issue / 旧 Release / CI 历史全丢）：
    重写后的历史推到一个同名新空仓库，旧悬空对象才真的变 404 / 422。**别再重复踩这一串坑**。

## 发布

* 推一个 `v*` 标签 → `.github/workflows/release.yml` 会自动
  `analyze → test → build apk --release [--split-per-abi]` 并把四个包传成 Release 资产。
  **注意标签触发的工作流必须已经存在于被标签的那个提交里**（先提交工作流，再打标签）。
* **给新仓库（或刚删库重建的仓库）补历史时，别指望 `git push --tags` 一次点火**：
  2026-10-07 整批推 5 个 tag，远端 tag 都在、workflow 也是 `active`，但 `actions/runs` 是 0。
  解法是**把 tag 删掉再单独推一次**：`git push origin :refs/tags/v1.3.0` +
  `git push origin refs/tags/v1.3.0`（详见 §9.28）。**CI 没跑先数 run 数，再删 tag 重推**。
* Release 资产名**必须 ASCII**（`njtc-schedule-<ver>-<abi>.apk`）：Windows PowerShell 会把
  URL `?name=` 里的中文整段丢掉（详见 §9.18）。本地 `D:\DSH\dist\内师课程表-*.apk` 保持中文名。
* 手动重传 Release 用 `D:\DSH\github_release.ps1`（幂等；令牌放 `$env:GH_PAT`）。

## 文档地图

| 文件 | 内容 |
| --- | --- |
| `README.md` | 功能、截图、使用指南、项目结构、已验证内容 |
| `BUILD_NOTES.md` | **§9.1 ~ §9.28 每轮开发的踩坑与决策**，最值钱的一份 |
| `VIVO_ATOMIC_NOTIFICATION.md` | vivo 原子通知（COURSE 场景）接入细节 |
| `AGENTS.md` | 就是本页：接手约定与红线 |

仓库目录之外的东西（打包发给别人时不会带上）：`D:\DSH\dist\`（APK）、`D:\DSH\build_v130.ps1`
（v1.3.0 那轮用的 analyze + test + 四包构建 + aapt2 校验脚本；`build_*.ps1` 是过往各轮的同款脚本，
**执行策略禁止直接运行未签名脚本**，用 `Invoke-Expression (Get-Content -Raw -Encoding UTF8 '<路径>')`）、
`D:\DSH\github_release.ps1`（发 Release）、`D:\DSH\vivo_cloud_test_checklist.md`（vivo 商店上线自测清单）、
`D:\DSH\release_notes_*.md`。仓库里跟 OCR 有关的两个工具：`tool/fetch_tessdata.ps1`
（下载语言模型到 `assets/tessdata/`）、`tool/make_ocr_fixture.py`（生成 E2E 夹具 PNG/PDF）。

## 待办

* vivo 应用商店上架材料与 COURSE 场景分类审核（`VIVO_ATOMIC_NOTIFICATION.md` + 商店自测清单）。
* 正式签名（换掉 debug key）后才能上架；换签名要注意升级覆盖安装会失败。
