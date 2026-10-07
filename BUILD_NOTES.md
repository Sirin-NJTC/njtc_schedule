# 构建说明（BUILD_NOTES）

本项目**只面向 Android**（Windows 桌面平台已移除），并在
**Flutter 3.47.6 stable（Dart 3.13.5）** 上完整验证通过：

`flutter pub get` / `flutter analyze` / `flutter test` /
`flutter build apk --debug` / `flutter build apk --release` /
**Android 模拟器（API 37）实测安装运行**。

## 1. 环境要求

| 项目 | 必需工具 |
| --- | --- |
| 通用 | **Flutter SDK ≥ 3.27**（更低版本会因 `CardThemeData`、`Color.withValues` 等 API 报错） |
| Android | Android SDK（`platforms;android-36` 与 `build-tools;36.0.0`）+ **JDK 17~21** |

检查环境是否就绪：

```bash
flutter doctor -v
```

> `flutter doctor` 可能报 `Android license status unknown`，原因是缺少
> `cmdline-tools` 组件。Gradle 只读 `licenses/` 目录下的许可文件，
> **不影响构建**；若要消除该提示，装一次 `cmdline-tools` 并执行
> `flutter doctor --android-licenses` 即可。

## 2. 首次构建

```bash
cd njtc_schedule
flutter pub get
```

### 重新生成平台工程（仅在缺少 `android/` 时才需要）

仓库已包含完整的 `android/` 平台工程（Flutter 3.47.6 的官方脚手架，
使用 **Kotlin DSL**：`android/app/build.gradle.kts`、`settings.gradle.kts`）。
若你要用自己版本的 Flutter 重新生成：

```bash
flutter create --platforms=android --org cn.edu.njtc .
```

> 注意：该命令会额外生成 `test/widget_test.dart`（模板计数器测试），
> 它与本项目无关，**请删除后再跑 `flutter test`**，否则会因找不到 `MyApp` 而失败。
> 另外它会覆盖 `MainActivity.kt`，**务必先备份**
> `android/app/src/main/kotlin/cn/edu/njtc/njtc_schedule/` 整个目录
> （提醒功能的原生实现全在里面）。

## 3. 常见构建故障（务必先读）

### 3.1 `Could not close incremental caches`（项目与 pub 缓存跨盘符）

若项目在 D 盘而 pub 缓存默认在 C 盘（`C:\Users\<你>\AppData\Local\Pub\Cache`），
Kotlin 增量编译对插件源码做 `relativeTo()` 时会抛
`IllegalArgumentException: this and base files have different roots`，
表现为插件编译任务失败：

```
Execution failed for task ':shared_preferences_android:compileDebugKotlin'.
> java.lang.Exception: Could not close incremental caches in ...\caches-jvm\jvm\kotlin:
  class-fq-name-to-source.tab, source-to-classes.tab, internal-name-to-source.tab
```

真正的原因藏在 `Suppressed` 里，**不要被 `Could not close incremental caches`
这句表象误导**（换 JDK、杀 Java 进程、清 `build/` 都无效）。

**解法**：在 `android/gradle.properties` 里关闭增量编译（本项目已加）：

```properties
# 项目在 D: 盘而 pub 缓存在 C: 盘时，Kotlin 增量缓存无法跨盘符计算相对路径，
# 会导致 compileDebugKotlin 报 "Could not close incremental caches"。
kotlin.incremental=false
```

### 3.2 `file_picker` 与 `flutter_plugin_android_lifecycle` 的 compileSdk 冲突

`file_picker` 8.x / 9.x 的 `android/build.gradle` 硬编码 `compileSdk 34`，
而 `flutter_plugin_android_lifecycle` 要求 36，会报：

```
Dependency ':flutter_plugin_android_lifecycle' requires libraries and applications
that depend on it to compile against version 36 or later of the Android APIs.
:file_picker is currently compiled against android-34.
```

**解法**：`file_picker` **必须 ≥ 10.3.10**（该版本起改为
`compileSdk flutter.compileSdkVersion`）。**请勿降级。**

### 3.3 JDK 版本：用 17~21，不要用 22+

Java 25 会打印 `A restricted method in java.lang.System has been called`
一类告警，且 AGP / Kotlin 官方支持上限是 21。可用下面的命令指定 JDK：

```bash
flutter config --jdk-dir "C:\Program Files\Android\openjdk\jdk-21.0.8"
```

### 3.4 其他注意

* 删除 `build/` 时用 `cmd /c rd /s /q build`；
  PowerShell 的 `Remove-Item -Recurse -Force` 在深层路径上可能静默失败。
* 多个 `flutter` 命令**不要并发**执行，会争抢启动锁。
  卡在 `Storage ... is already registered` 时，先
  `Get-Process java | Stop-Process -Force`。
* 构建日志里 `SDK processing. This version only understands SDK XML versions
  up to 3 but an SDK XML file of version 4 was encountered.` 是无害告警。

### 3.5 （已不适用）桌面端的 symlink 报错

本项目已删除 `windows/` 平台，**不会再遇到** `Building with plugins requires
symlink support.`。若你自行加回桌面平台，Windows 上创建符号链接需要管理员
权限或开发者模式；免管理员的绕过办法是预先手工建立目录联接（junction），
原理是 Flutter 源码 `flutter_plugins.dart` 的 `_createPlatformPluginSymlinks`
里有 `if (link.existsSync()) { continue; }` —— 链接已存在就会被跳过。

## 4. 运行

```bash
# 列出可用设备（模拟器需先启动）
flutter devices

# 在真机 / 模拟器上运行
flutter run -d <device-id>

# 启动一个已创建的 AVD
flutter emulators
flutter emulators --launch <emulator-id>
```

## 5. 测试与静态检查

```bash
flutter analyze   # 期望：No issues found!
flutter test      # 期望：All tests passed!（87 个用例）
```

测试包含：

* `test/timetable_parser_test.dart` —— 解析器单元测试（含一格多课、单双周、
  页脚学期起始日期与总周数、以及「周次不得退化」「时间字段不在第 0 段」两条回归用例）
* `test/xls_reader_test.dart` —— 用 `test/fixtures/njtc_sample.xls`
  （真实教务系统导出文件）验证 `.xls` 读取链路
* `test/zf_html_parser_test.dart` —— 用 `test/fixtures/zf_xskb_list.html`
  （正方教务课表页固件）验证 HTML 解析器：rowspan/colspan 不重复计课、
  `<hr>` 与 `-----` 两种分格多课写法、`title` 字段（教师 / 周次(节次) / 地点 / 教学班）、
  元信息（学期 / 专业 / 起始日期 / 总周数）、非课表页面识别
* `test/web_import_test.dart` —— 网页导入解析链路四级兜底
  （正方 jwglxt JSON 接口 → 正方结构 → 任意 HTML 表格 → 纯文本），
  以及非 Android 平台直接返回失败、不触碰原生通道
* `test/timetable_grid_test.dart` —— 网格渲染：同格冲突课并排不互相覆盖、
  第 11 节（旧版写死 10 节）能显示、单双周角标、非本周课不出现、
  「今天」高亮只在当前周出现
* `test/home_page_test.dart` —— 首页周次交互：周次选择弹窗（选周即切）、
  「回到本周」按钮的显示与消失、首周 / 末周箭头禁用、
  未设起始日期时的提示、空课表空状态
* `test/app_flow_test.dart` —— 端到端：真实 `.xls` 字节 → `XlsReader` →
  `TimetableParser` → `Timetable` → 真实 `pumpWidget` 渲染 `TimetableGrid`，
  断言 20 门课程被正确解析、7 个星期表头与真实课程名出现在渲染树中、
  该周激活课程数 == `CourseCard` 个数（第 9 周为 15 个），
  并验证切换周次后单周 / 双周课程真的在界面上互换

### 5.1 真机 / 模拟器上的端到端验证

`integration_test/` 下的用例会真的调用原生通道、排布真实闹钟并发送真实通知：

```bash
flutter test integration_test/reminder_e2e_test.dart -d <device-id>
```

网页登录导入的端到端验证（用本地固件页代替真实教务系统，**不需要登录**）：

```bash
# 1) 宿主机起一个固件 HTTP 服务（端口随意，别用 8080 —— 常被其它软件占用）
python -m http.server 8137 --bind 0.0.0.0 --directory D:\DSH\njtc_schedule\test\fixtures
# 2) 跑用例（用例内用 10.0.2.2 指向宿主机；真机请直接换成真实网址）
flutter test integration_test/web_import_e2e_test.dart -d <device-id>
```

上面这条走的是**渲染后的 DOM**（`#kbtable` / `.kbcontent` 抠字段）。
App 还有一条优先级更高的路径：在课表页里顺手 POST 一发
`xskbcx_cxXskbcxIndex.html?doType=query&gnmkdm=N2151`，直接吃 `kbList`
原始 JSON（整学期数据，比 DOM 稳）。这条路径用另一个固件服务验证：

```bash
# 1) 能应答 POST 的固件服务（GET 给课表页，POST 给 kbList JSON）
python tool/jwglxt_fixture_server.py 8138
# 2) 跑用例
flutter test integration_test/jwglxt_json_e2e_test.dart -d <device-id>
```

> `WebImportActivity` 支持一个**仅供自动化测试**的 `autoRead` 参数：页面加载后
> 自动等课表标记出现再读取，等价于用户点一次「读取课表」。真实使用时不会走到
> 这条路径（默认 `autoRead=false`）。
>
> ⚠️ 调试 WebView 时，`adb logcat -d`（事后取）通常已经拿不到日志（缓冲区滚动），
> 必须**在测试运行期间**抓：`adb logcat -c` + `adb logcat -v time > 文件`。
> 原生侧日志统一带 `NjtcWebImport` 标签，可用 `-s NjtcWebImport` 过滤。

跑完后可在宿主机上复核原生侧的真实状态：

```bash
adb shell dumpsys alarm | grep -i -A 3 njtc
adb shell dumpsys notification --noredact | grep -A 30 "notification.superx"
```

该用例会**故意保留**已排布的计划与已发出的通知，方便上面两条命令复核。

> ⚠️ `flutter test integration_test` 在测试结束后会**自动卸载 App**，
> 卸载后它的闹钟与通知都会消失。如果要用 `dumpsys` 取证，必须在测试
> **运行期间**执行（本用例末尾刻意停留 75 秒，就是为这个窗口留的时间）。

若设备是 Android 13+，先授予通知权限才能看到通知：

```bash
adb shell pm grant cn.edu.njtc.njtc_schedule android.permission.POST_NOTIFICATIONS
adb shell appops set cn.edu.njtc.njtc_schedule SCHEDULE_EXACT_ALARM allow
```

## 6. 打包

```bash
# 通用 APK（产物在 build/app/outputs/flutter-apk/app-release.apk）
flutter build apk --release

# 按 ABI 拆分（体积更小，推荐分发用）
flutter build apk --release --split-per-abi

# 上架用 AAB
flutter build appbundle --release
```

Android 发布签名（可选）——当前 `--release` 用的是 Flutter 模板默认的
**debug 签名**（`CN=Android Debug`），可直接安装但**不能上架**：

```bash
keytool -genkey -v -keystore njtc-release.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias njtc
```

然后把 `njtc-release.jks` 放到 `android/app/`，在 `android/key.properties` 中配置：

```properties
storePassword=<密码>
keyPassword=<密码>
keyAlias=njtc
storeFile=njtc-release.jks
```

最后在 `android/app/build.gradle.kts` 的 `signingConfigs` 中引用，并把
`buildTypes.release` 的 `signingConfig` 从 `signingConfigs.getByName("debug")`
改为你的配置。

### 6.1 上架应用商店时关于精确闹钟权限的说明

最终 APK 里会同时出现两个权限（`aapt2 dump badging` 可见）：

```
uses-permission: name='android.permission.SCHEDULE_EXACT_ALARM'
uses-permission: name='android.permission.USE_EXACT_ALARM'
```

- `SCHEDULE_EXACT_ALARM` 是**用户可授予/可撤销**的权限，应用需要引导用户在系统
  设置里打开「闹钟和提醒」。本项目已在提醒页内做了这项引导。
- `USE_EXACT_ALARM` 是**系统自动授予、无法撤销**的权限，但 Google Play 对它做了
  使用场景限制（官方只接受闹钟、日历/日程这类核心功能）。课程表属于日程类，
  通常可以通过审核，但**提交审核时需在「权限声明」里说明用途**。
- 如果不打算上架 Google Play（例如只在国内渠道或直接分发 APK），保留现状即可。
  若审核被拒或不想承担该风险，从  `android/app/src/main/AndroidManifest.xml` 中删掉
  `<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>` 一行即可——
  代码里 `ReminderScheduler` 对「无法使用精确闹钟」有完整降级路径
  （返回 `exact=false` 并改用非精确的 `setAndAllowWhileIdle`），功能不受影响，
  只是提醒时间可能有几分钟浮动。

> 关于 `setAlarmClock`：提醒默认用 `setAlarmClock` 排布（系统按「用户闹钟」
> 对待，Doze 与厂商省电都不会推迟），它同样受 `SCHEDULE_EXACT_ALARM`
> 约束、同样需要「闹钟和提醒」权限；被拒绝时会自动退回
> `setExactAndAllowWhileIdle` → `setAndAllowWhileIdle`。
> 代价是状态栏可能出现一个闹钟小图标（依赖系统版本），
> 若不想接受，把 `ReminderScheduler.kt` 里的 `USE_ALARM_CLOCK` 改为 `false` 即可。

## 7. 关于课表文件格式（重要）

内江师范学院教务系统（正方）导出的课程表是**老式 `.xls`（OLE2 / BIFF8）**，
不是 `.xlsx`。Dart 生态里的 `excel` 包只支持 `.xlsx`（zip + XML 容器），
直接喂 `.xls` 会解析失败。

因此本项目自带一个纯 Dart 的极简 `.xls` 读取器：
`lib/services/xls_reader.dart`。导入逻辑会先看文件头：

* `D0 CF 11 E0 A1 B1 1A E1`（OLE2）→ 走 `XlsReader`
* `50 4B 03 04`（zip）→ 走 `excel` 包按 `.xlsx` 解析

两条路径都会交给 `TimetableParser.parseGrid` 变成课程。解析器还会从表格
页脚（以「注」开头的那一行）提取**学期起始日期**与**总周数**，这两个值决定
「当前第几周」以及课程提醒按哪一周生效，因此不可缺失。

**退路**：万一遇到 `XlsReader` 也读不了的怪文件，可以在 Excel/WPS 里
「另存为 `.xlsx`」后重新导入，或直接使用「粘贴课程表文本」方式。

## 8. 课程提醒与 vivo 原子通知

提醒功能的原生实现位于
`android/app/src/main/kotlin/cn/edu/njtc/njtc_schedule/reminder/`，
Dart 侧为 `lib/services/reminder_service.dart` 与
`lib/pages/reminder_settings_page.dart`，两侧通过 MethodChannel
`cn.edu.njtc.njtc_schedule/reminder` 通信。

设计要点：

* 一次性排布**未来 14 天**的精确闹钟（上限 240 个），并用一个
  **每日 00:05 的巡检闹钟**滚动后移窗口 ⇒ 用户长期不打开 App 提醒也不会断。
* 设备重启 / 应用更新后由 `BootReceiver` 从本地计划重建，不依赖 Flutter 层。
* Android 12+ 若未授予精确闹钟权限，自动降级为 `setAndAllowWhileIdle`
  （可能被系统延迟几分钟），不会崩溃。
* 课程提醒投递到 vivo 原子通知需要向 vivo 申请准入，
  详见 **[VIVO_ATOMIC_NOTIFICATION.md](VIVO_ATOMIC_NOTIFICATION.md)**。
  未获准入时系统会忽略 superx 字段并按普通通知展示（纯增益，不会丢提醒）。

## 9. 已在本机验证过的内容

验证环境：Flutter 3.47.6 stable / Dart 3.13.5，Windows 11（10.0.29680.1000），
JDK 21.0.8，Android SDK 36（build-tools 36.0.0）。
测试设备：Android 模拟器 **API 37（Android 17）x86_64**。

| 命令 | 结果 |
| --- | --- |
| `flutter pub get` | 通过 |
| `flutter analyze` | `No issues found!` |
| `flutter test` | `+78: All tests passed!` |
| `flutter build apk --debug` | `app-debug.apk` — 152.06 MB |
| `flutter build apk --release` | `app-release.apk` — 50.62 MB |
| `flutter build apk --release --split-per-abi` | `app-armeabi-v7a-release.apk` 15.58 MB、`app-arm64-v8a-release.apk` 17.97 MB、`app-x86_64-release.apk` 19.4 MB |
| 在 Android 模拟器（API 37，x86_64）安装并启动 | **成功** —— 界面正常渲染、日志无崩溃，实测截图见 `D:\DSH\dist\screenshot-release-*.png` |
| `flutter test integration_test/reminder_e2e_test.dart -d emulator-5554` | **`01:16 +1: All tests passed!`**，详见下方「提醒链路实测」 |
| `flutter test integration_test/web_import_e2e_test.dart -d emulator-5554` | **`00:03 +1: All tests passed!`**（连跑两次均通过），详见下方「网页导入实测」 |
| `flutter test integration_test/jwglxt_json_e2e_test.dart -d emulator-5554` | **`00:03 +1: All tests passed!`**，详见下方「正方 JSON 接口实测」 |

### 9.1 提醒链路实测（Android 17 / API 37 模拟器）

集成测试在真实设备上跑通了「课表 → MethodChannel → 原生排闹钟 → 发通知」全链路：

```
[E2E] 课程排到 周1 第1/2/3节；今天第 2 周
[E2E] syncPlan → ok=true scheduled=12 horizon=14 exact=true next=2026-10-05(周一) 07:30
[E2E] status  → platform=true vivo=false island=false brand=google sdk=37 notif=true exact=true
                battery=false hasPlan=true count=12
[E2E] preview(8) →
        2026-10-05(周一) 07:30  [sessionPreview]  上午课程预告（提前 30 分钟）  端到端测试课程A @明德楼B216
        2026-10-05(周一) 07:45  [lead]  上课前 15 分钟（仅时段首课）  端到端测试课程A @明德楼B216
        2026-10-05(周一) 07:55  [lead]  上课前 5 分钟（每一节课）  端到端测试课程A @明德楼B216
        2026-10-05(周一) 08:50  [lead]  上课前 5 分钟（每一节课）  端到端测试课程A @明德楼B216
        2026-10-05(周一) 09:35  [endPreview]  下课前 5 分钟预告  下节课：端到端测试课程B @明德楼A101  [下课]
        2026-10-05(周一) 09:55  [lead]  上课前 5 分钟（每一节课）  端到端测试课程B @明德楼A101
        2026-10-12(周一) 07:30  [sessionPreview]  上午课程预告（提前 30 分钟）  …（第二周同 6 条）
[E2E] testNow(下节课预告) → vivo 原子通知（当前非 vivo 设备，字段已挂载但会被系统忽略）
[E2E] testNow(时段预告) → 普通通知
[E2E] testNow(上课提醒) → 普通通知
```

原生侧用 `dumpsys` 取证（**注意：`flutter test integration_test` 跑完会自动卸载
App，卸载后闹钟与通知一并消失，所以必须在运行期间取证**）：

* `adb shell dumpsys alarm` —— 抓到 **1 个 `DAILY_DRIVER`（当日 00:05）
  + 12 个 `COURSE_REMINDER`**，全部 `RTC_WAKEUP` 精确闹钟；12 条分两组、
  相隔恰好 604800000 ms（7 天），单日 6 条落在
  **07:30 / 07:45 / 07:55 / 08:50 / 09:35 / 09:55** —— 正好对应
  上午首课的时段预告 → 时段首课 15 分钟 → 第 1、2 节各 5 分钟 →
  第 2 节下课前的下节课预告 → 第 3 节 5 分钟；
  **08:40 不存在**（第 1→2 节同名、同地点、节次连号 = 连堂，按规则不发预告）。
  另外，12 个课程闹钟的 dump 里都带
  `showIntent=PendingIntent{… startActivity}`，而 00:05 的巡检闹钟没有 ——
  这正好证明提醒走的是 `setAlarmClock`（系统当作用户闹钟，Doze / 省电都不推迟），
  巡检仍走 `setExactAndAllowWhileIdle`。
* `adb shell dumpsys notification --noredact` —— 抓到 3 条通知记录：
  `id=6600` / `id=6604` 走 `njtc_course_reminder`（上课提醒，importance=4）、
  `id=6603` 走 `njtc_course_end`（下节课预告，importance=3，**带全部 14 个
  `notification.superx.*` 键**）。完整的 superx 键值见
  [VIVO_ATOMIC_NOTIFICATION.md](VIVO_ATOMIC_NOTIFICATION.md) 第 5.3.1 节。
  取证前要先 `adb shell pm grant cn.edu.njtc.njtc_schedule
  android.permission.POST_NOTIFICATIONS`，否则 Android 13+ 不会记录通知。

数据链路验证：真实 `.xls` 经 `XlsReader` 读出的 **72 个单元格与 Python `xlrd`
结果逐字一致**，端到端解析出 **20 门课程**（周一~周五），字段
（课程名 / 节次 / 周次 / 单双周 / 地点 / 教师 / 课程代码 / 教学班）全部正确。

APK 元数据（`aapt2 dump badging`）：包名 `cn.edu.njtc.njtc_schedule`、
`versionName=1.1.1`（`pubspec.yaml` 的 `version: 1.1.1+3`）、
`versionCode` = universal `3` / armeabi-v7a `1003` / arm64-v8a `2003` /
x86_64 `4003`（`--split-per-abi` 会自动加 `1000 × ABI 序号`）、
`minSdkVersion=24`、`targetSdkVersion=36`、`compileSdkVersion=36`、
应用名 **内师课程表**、入口 `cn.edu.njtc.njtc_schedule.MainActivity`。

> 版本号有两处，必须同步：`pubspec.yaml` 的 `version:` 决定 APK 文件名与
> `versionCode`，`lib/pages/settings_page.dart` 里「关于」卡片的
> `内江师范学院课程表 v1.1.1` 是给人看的显示串（Flutter 不提供免依赖的
> 运行时读版本号能力，所以这里是硬编码 + 注释提醒同步）。

> ⚠️ 当前 `--release` APK 用的是 Flutter 模板默认的 **debug 签名**
> （`CN=Android Debug`）：可以直接安装到手机使用，但**不能上架应用商店**。
> 正式发布请按第 6 节生成自己的 `njtc-release.jks` 并配置 `signingConfigs`。

### 9.2 网页导入实测（Android 17 / API 37 模拟器）

`integration_test/web_import_e2e_test.dart` 在模拟器里跑通了
「真实 WebView 打开课表页 → 注入 JS 抓取 → 原生写文件回传 → Dart 解析」全链路
（**连跑两次均通过**）：

```
[E2E-WEB] 打开 http://10.0.2.2:8137/zf_xskb_list.html
[E2E-WEB] status=WebImportStatus.ok message=已识别 9 门课
[E2E-WEB] pageUrl=http://10.0.2.2:8137/zf_xskb_list.html title=学生课表
[E2E-WEB] rawText 长度=702
[E2E-WEB] 课表：学期=2026-2027年第1学期 / 专业=机器人工程 / 周数=20 /
          起始=2026-08-31 / 课程数=9
          人工智能导论 | 韩云 | 明德楼B216 | 周1 第1-2节 7-18周
          高等数学Ⅰ（上） | 曾玉祥 | 明德楼A103 | 周1 第3-4节 7-18周
          思想道德与法治 | 代维 | 明德楼B303 | 周1 第9-10节 12-14周
          ……（共 9 门，2026-08-31 起 20 周）
00:02 +1: All tests passed!
```

原生侧日志（`adb logcat -s NjtcWebImport`）显示抓取与回传都正常：

```
onCreate autoRead=true
onPageStarted http://10.0.2.2:8137/zf_xskb_list.html
onPageFinished url=http://10.0.2.2:8137/zf_xskb_list.html title=学生课表
probe raw="true" hit=true … autoRead=true done=false attempts=0
autoRead timer -> extract (finishing=false destroyed=false)
extract start url=… / extract value len=5831
finishWithPayload len=4128
MainActivity.onActivityResult req=20750 res=-1
onActivityResult resultCode=-1 pending=true path=…/cache/webimport_payload.json error=null
```

> ⚠️ 踩坑记录：`WebView.evaluateJavascript` 的回调值是**结果的 JSON 表示** ——
> JS 里 `return 'true'`（字符串）回调拿到的是**带引号**的 `"true"`，
> 直接 `value == "true"` 会恒为 false。表现为「页面明明是课表却探测不到」，
> 测试长时间挂起后收到一个 `RESULT_CANCELED`。必须
> `value.trim('"') == "true"`（见 `WebImportActivity.jsIsTrue`）。

### 9.3 交付版 APK 实机冒烟（release 构建，非 debug 构建）

上述 E2E 跑的是 `flutter test integration_test` 装的 **debug** 构建。为了确认
交付到 `D:\DSH\dist\` 的 **release** 构建本身也能跑，另做了一次冒烟：

```
adb install -r 内师课程表-1.1.1-x86_64.apk        → Success
adb shell am start -n cn.edu.njtc.njtc_schedule/.MainActivity
adb shell pidof  cn.edu.njtc.njtc_schedule        → 5909（进程存活）
adb shell dumpsys activity activities | grep topResumedActivity
    → cn.edu.njtc.njtc_schedule/.MainActivity
adb logcat | grep -E 'FATAL|AndroidRuntime|E/flutter'   → 无输出
```

截图：首页空状态（`dist/screenshot-release-build.png`）→ 点「导入课表」进入导入页
（`dist/screenshot-release-import.png`，三张卡片 + 「网页导入怎么用」齐全）→
点第一张卡打开原生 WebView（`dist/screenshot-release-webimport.png`）：

```
I/NjtcWebImport: onCreate autoRead=false
I/NjtcWebImport: onPageStarted https://tpass.njtc.edu.cn/auth/oauth/login
I/NjtcWebImport: onPageFinished url=… title=统一身份认证中心
I/NjtcWebImport: probe raw="false" hit=false url=… autoRead=false done=false attempts=0
```

这是一次**真实联网**验证：模拟器直连学校统一身份认证中心（页面为内江师范学院
「账号密码 / 手机验证码 / APP扫码」登录页），说明
① release 构建的 WebView 通路可用；② `probe` 在登录页正确判定为「非课表」；
③ 校园网入口无需 VPN 即可访问。

### 9.4 正方 JSON 接口实测（Android 17 / API 37 模拟器）

`integration_test/jwglxt_json_e2e_test.dart` + `tool/jwglxt_fixture_server.py`
验证了「注入脚本在课表页里 POST 数据接口」这条**优先路径**（DOM 抠字仍作为兜底）：

```
[E2E-JSON] 打开 http://10.0.2.2:8138/jwglxt/kbcx/xskbcx_cxXskbcxIndex.html
[E2E-JSON] status=WebImportStatus.ok message=已从教务接口识别 6 门课
[E2E-JSON] 课表：学期=2026-2027年第1学期 / 周数=18 / 课程数=6
           人工智能导论 | 韩云 | 明德楼B216 | 周1 第1-2节 7-18周 单双周=0
           高等数学Ⅰ（上） | 曾玉祥 | 明德楼A103 | 周1 第3-4节 1-16周 单双周=0
           大学物理V（上） | 张熙程 | 明德楼B105 | 周4 第7-8节 1-15周 单双周=1
           思想道德与法治 | 代维 | 明德楼B303 | 周5 第9-10节 1-1周 单双周=0
           思想道德与法治 | 代维 | 明德楼B303 | 周5 第9-10节 3-3周 单双周=0
           思想道德与法治 | 代维 | 明德楼B303 | 周5 第9-10节 5-9周 单双周=0
```

要点：

* 端点是**推出来的**，不是写死的：`location.pathname` 匹配 `/…/(kbcx|xtgl|
  xsxxxggl|xkgl)/` 后拼回 `origin + 前缀 + /kbcx/xskbcx_cxXskbcxIndex.html`。
  不同学校的路径前缀不同（有的 `/jwglxt`，有的直接根目录），写死一定会错。
* 学年 / 学期码从页面控件读（`#xnm` / `#xqm`），`3`=第一学期、`12`=第二学期。
* 页面上没有「共 N 周」时，总周数由 `max(zcd 里的周次)` 反推。
* **离散周次要逐段保留**：`1,3,5-9周` 变成 3 门次（`1-1` / `3-3` / `5-9`），
  不能补空隙 —— 补了会凭空多出没课的周次。
* `kbList` 解析不出课程时会**回落到 DOM 路径**，不会返回一张空课表。

### 9.5 release 构建的功能实测（导入 → 提醒 → 原子通知）

`flutter test integration_test` 装的始终是 **debug** 构建，而交付到
`D:\DSH\dist\` 的是 **release** 构建。两者的 dex 结构并不相同：release 由
R8 处理过（实测 release 只有 1 个 `classes.dex`、类名被重命名；debug 有 11 个
dex、类名原样），所以「debug 通过」**不能**推出「release 通过」。为此在
release APK 上完整走了一遍真机流程：

```
adb uninstall cn.edu.njtc.njtc_schedule          # split 包 versionCode 比旧包大，必须先卸
adb install -r 内师课程表-1.1.1-x86_64.apk        → Success
adb shell pm grant cn.edu.njtc.njtc_schedule android.permission.POST_NOTIFICATIONS
adb shell appops set cn.edu.njtc.njtc_schedule SCHEDULE_EXACT_ALARM allow
```

1. **文件导入**：`adb push test/fixtures/njtc_sample.xls /sdcard/Download/` →
   导入页「导入教务系统导出的文件」→ 系统文件选择器（DocumentsUI）→ 下载 →
   选中文件。结果：课表标题 `njtc_sample`、副标题
   `2026-2027年第1学期 · 机器人工程`，网格正常渲染、`今天` 列高亮、
   底部导航出现 ⇒ release 构建的自研 BIFF8 `.xls` 读取器与解析器可用。
2. **提醒排布**：设置页「课程提醒」显示
   `提前 30 / 15 / 5 分钟 · 下节课预告 · 已排布 55 个` ⇒ release 构建的
   Kotlin 排布链路（MethodChannel → `ReminderScheduler`）可用。
3. **提醒语义**：课程提醒页「最近的提醒（滚动 14 天）」按真实课表列出
   `07:30 上午课程预告（提前 30 分钟）` → `07:45 上课前 15 分钟（仅时段首课）`
   → `07:55 上课前 5 分钟` → `09:35 下课前 5 分钟预告 · 下节课：Python程序设计`
   → `09:55 上课前 5 分钟` → `11:35 下课前 5 分钟预告 · 下节课：大学体育Ⅰ`
   → `14:00 下午课程预告` → `14:15 上课前 15 分钟`，并显示
   `已排布 55 个提醒（未来 14 天）· 使用精确闹钟`。
4. **原子通知**：点「立即验证 → 下节课预告（vivo 走原子岛）」后
   `adb shell dumpsys notification --noredact` 里出现

   ```
   pkg=cn.edu.njtc.njtc_schedule id=3403 channel=njtc_course_end
   android.title=「人工智能导论」09:40 下课
   android.text=下节课：下一节课 ·  · 地点待定
   notification.superx.island=Bundle (dataSize=3032)
   ```

   **14 个 `notification.superx.*` 键全部齐全**（operation / template / scene /
   keepDuration / sound / showNotify / dismissWhenKill / changedRecord /
   clickResp / baseInfos / infos / shortInfos / capsule / island），
   logcat 佐证：

   ```
   I/NjtcVivo: 已挂载 superx 字段：scene=METTING template=1 rightTemplate=6 keepDuration=1800s islandShowTime=180s
   I/NjtcNotify: 已发送[vivo 原子通知（当前非 vivo 设备，字段已挂载但会被系统忽略）] id=3403
   ```

   ⇒ **R8 混淆不会破坏原子通知链路**。这一点是安全的：全工程没有任何
   `addJavascriptInterface`，反射只指向**平台类**
   （`android.os.FtBuild` / `android.util.FtBuild` / `android.os.FtFeature` /
   `android.util.FtFeature` / `android.os.SystemProperties` /
   `NotificationManager.getSceneStatus`），而 manifest 里声明的组件
   （`MainActivity` / `WebImportActivity` / `ReminderReceiver` / `BootReceiver`）
   由 AGP 生成的 aapt keep 规则保住类名，所以 obfuscation 只影响我们自己的
   内部类名，调用方与被调用方一起改名，行为不变。

### 9.6 真机实测（vivo 云真机）

用户通过 vivo 云测平台在自己的真机上跑了一轮（设备序列号
`10AE1C1NP80011G`），导出日志 `logs_10AE1C1NP80011G_1791088183247_export.log`
（1.23 MB / 9026 行，覆盖 `12:25:47`~`12:29:30`）。**这是第一次在真实
OriginOS + 真实教务系统上跑通全链路**，结论如下。

```
[12:26:03.958] NjtcWebImport: onPageFinished url=… title=个人课表查询
[12:26:09.262] NjtcWebImport: extract start
[12:26:09.917] NjtcWebImport: extract value len=77906
[12:26:09.922] NjtcWebImport: finishWithPayload len=58095
[12:26:09.940] NjtcWebImport: onActivityResult resultCode=-1 pending=true path=…/webimport_payload.json error=null
[12:26:10.072] NjtcReminder: 每日巡检闹钟已设在 2026-10-05(周一) 00:05
[12:26:10.072] NjtcReminder: 排布完成：共 45 个提醒闹钟（推导 45 个，上限 240），窗口 14 天，精确闹钟=true，最近一次=2026-10-06(周二) 09:30
[12:26:10.072] NjtcReminder:   #0 2026-10-06(周二) 09:30 上课前 30 分钟（时段首课 · 整段预告） … 明德楼B309
[12:26:10.072] NjtcReminder:   #1 2026-10-06(周二) 09:45 上课前 15 分钟（仅时段首课） … 明德楼B309
[12:26:10.072] NjtcReminder:   #2 2026-10-06(周二) 09:55 上课前 5 分钟（每一节课） … 明德楼B309
[12:26:10.082] VivoConfigStore: key:vivo.software.disable_island isCached is true and value is false
```

1. **网页登录导入在真实教务系统上跑通**：登录后停在真实页面
   `个人课表查询`，点「读取课表」抓回 **77906 字符** HTML（模拟器固件只有
   5831 字符），写出 **58095 字节** payload，`resultCode=-1` 正常回传。
2. **解析 + 排布在真实课表上跑通**：import 回传后 **132 ms** 内完成排布 ——
   `45 个提醒闹钟`、`精确闹钟=true`，课程地点是真实数据（明德楼B309 / B213 /
   A203）。⇒ CAS 登录 → 正方 DOM → 解析 → 课表 → 提醒这一整条链路在真机上成立。
3. **提醒四条语义在真实课表上同样正确**：周二首课 10:00 → 09:30 / 09:45 /
   09:55 三条；周四 16:00 / 16:15 / 16:25、周五 16:00 / 16:15 / 16:25 ——
   即「30/15 只给当天该时段首课、5 分钟每节课都有」。
4. **原子岛能力判定在真实 ROM 上生效**：`12:26:10.082`、`12:26:50.453`、
   `12:26:51.234` 三次出现 **我们进程（pid 16277）** 触发的
   `VivoConfigStore: key:vivo.software.disable_island isCached is true and value is false`
   —— 这是 `VivoHelper.disableIslandFeature()` 反射 `FtFeature` 后 ROM 侧打出的
   回执，**value=false ⇒ 原子岛未被禁用**。反射链路在真机上可用
   （此前只在模拟器上得到 `isVivo=false`）。
5. **导出日志有隐私过滤**：URL 被替换成 `*****`、课程名被替换成 `************`
   （通知文案与页面 URL 都拿不到原文），排障时只能靠 tag 与数字。

**本轮据日志修掉的两个问题：**

* `WebImportActivity.onDestroy()` 在 WebView 仍挂在窗口上时直接
  `destroy()`，真机日志里对应
  `cr_AwContents: WebView.destroy() called while WebView is still attached to window.`
  +
  `chromium: [ERROR:aw_browser_terminator.cc(156)] Renderer process (8785) crash detected (code -1).`
  ⇒ 现在先 `(webView.parent as? ViewGroup)?.removeView(webView)` 再 `destroy()`。
  只崩渲染进程、不影响主进程，但会刷错误日志，部分 ROM 还会连带回收页面。
* `VivoHelper.deviceSummary()` **只返回 Map、不打日志**。真机上只能靠 ROM 自己
  打的那条 `VivoConfigStore` 反推原子岛可用，`romVersion` 与 `sceneEnabled`
  完全取不到 ⇒ 现在 `deviceSummary()` 会额外打一条
  `I/NjtcVivo: 设备摘要 {isVivo=…, isIslandCapable=…, romVersion=…, sceneEnabled=…, …}`，
  以后用户导出的 logcat 就能直接回答「支不支持原子岛 / 场景开关开没开」。

> 本轮日志里**没有** `NjtcVivo`（挂 superx）与 `NjtcNotify`（发通知）两行 ——
> 说明用户在这 4 分钟里只做了导入与排布，**没有点「立即验证 → 下节课预告」**，
> 因此「原子通知在真机上以什么形态弹出」仍是未验证项（见
> `VIVO_ATOMIC_NOTIFICATION.md` §5.3.2 的待办）。

### 9.7 用户反馈四条（v1.1.2）

用户拿到 1.1.1 后在真机上提了四条：

> 为什么进入 APP 是横屏？而且导入课程没有老师和教室，登录时输入密码输入法直接黑屏了，
> 还不能自己自定义添加课程。

**① 横屏。** 真机是折叠屏，且两处 Activity 都没有声明方向 ⇒ 现在
`AndroidManifest.xml` 里的 `.MainActivity` 与 `.webimport.WebImportActivity`
都加了 `android:screenOrientation="portrait"`。课表是竖版长列表，锁竖屏同时
也是下面 ③ 的缓解手段。

**② 导入缺教师与教室 —— 根因是反向代理让 JSON 接口从未被请求。**
内江师范的 jwglxt 挂在代理域名下：

```
https://jxglpt-njtc-edu-cn-s.proxy.njtc.edu.cn/sso/driotlogin?url=kbcx%2Fxskbcx_cxXskbcxIndex.html%3Fgnmkdm%3DN2151
```

`location.pathname` 是 `/sso/driotlogin`，**不含 `/kbcx/` 段**，而旧
`tryJwglxtJson()` 第一行就是
`var m = location.pathname.match(/^(.*?)(?:\/(?:kbcx|xtgl|xsxxxggl|xkgl)\/)/i);
if (!m) { return null; }` ⇒ **直接放弃，那一枪从来没打出去**，只能退化成
「抠 DOM → 通用表格 → 整页文字」，教师与地点就丢了。

现在 `WebImportActivity` 的 `EXTRACT_JS` 多了 `endpointCandidates()`：除了原先
按 pathname 推端点，还会从 `location.search`/`hash` 的 `url=` 参数里**连解两次码**，
用 `/^(.*?)(?:kbcx|xtgl|xsxxxggl|xkgl)\//i` 反推出教务根路径，再拼
`origin + '/' + base + 'kbcx/xskbcx_cxXskbcxIndex.html'`；候选端点按优先级去重后
逐个试，命中第一个返回 `kbList` 的就用它（`xnm`/`xqm` 仍从页面控件读，读不到就
**不发请求、绝不瞎猜**）。`controlValue()` 也改成遍历 document 与同源 iframe。

同时补了**兜底**：真机 payload 里每格只有一行 `课名 地点`（反向代理后 DOM 没有
`title=` 标注），旧 `_parseBlock` 会把整行当课名、`location` 留空。现在
`_reTrailingPlace` 会把尾部 `XX楼A101` 拆出来当地点（拆完名字为空则不拆，避免把
楼名当课程），`_parseFreeLine`（整页文字兜底）同样会摘出地点，并支持
「星期一 / 周一」两种星期写法。

> 佐证：真机日志行 `… ************ 明德楼B309 @`，格式（`ReminderScheduler.kt:118-121`）
> 是 `… ${c.name} @${c.location}` ⇒ 也就是说 `c.location` 是**空串**，楼名被并进了课名。

**③ 输入法导致黑屏。** 真机日志里这段时间**没有** renderer 崩溃、也没有新异常，
时间点又正好落在横屏宽幅（注入触摸坐标 `x≈2250`）⇒ 大概率是「横屏 + 折叠屏 +
`adjustResize` 压缩窗口」下 WebView 的渲染问题，锁定竖屏是主要缓解手段。若真机上
仍然复现，下一轮再对 WebView 单独做处理（`setLayerType` / 延迟 resize）。

**④ 自定义添加课程。** 新增 `lib/pages/course_edit_page.dart`：
`openCourseEditor(BuildContext, {Course? original})` + `CourseEditPage`
（课程名称 / 教师 / 地点 / 星期 / 节次区间 / 周次区间 / 单双周），入口三处 ——
首页标题栏「+」、空状态「手动添加课程」、课程详情弹窗的「编辑 / 删除」。
保存或删除后统一走 `AppState.updateTimetable()`，会自动落盘并**重排提醒闹钟**。
没有任何课表时点「手动添加课程」会先自动建一份「我的课表」（学期起始日期留空，
交给首页既有的告警引导用户去设置）。

**新增诊断日志**（以后只靠用户导出的 logcat 就能定位解析问题）：

```
NjtcImport: 载荷 表格HTML=3577 文本=46 jsonRows=0 页面标题=学生课表 接口端点=
NjtcImport: 解析来源=正方课表页 DOM 课程=9 有教师=9 有地点=9
```

四条解析路径（`教务接口 jsonRows` / `正方课表页 DOM` / `通用网页表格` / `整页文字`）
各打一次「课程 / 有教师 / 有地点」三个数量，一眼就能看出是走了哪条路、教师与地点
各解析出几门。

**本轮验证**：`flutter analyze` → No issues found；`flutter test` →
**87 个用例全绿**（新增 `test/course_edit_test.dart` 5 个 + 解析兜底 4 个）。
`D:\DSH\dist\` 四个 1.1.2 包（universal 51.07 / arm64-v8a 18.10 /
armeabi-v7a 15.72 / x86_64 19.59 MB，versionCode `4/1004/2004/4004`）。

端点推导这段是**新代码、且只在真机页面上才会跑到**，所以另外用 Node 单独验了一遍：
`D:\DSH\verify_endpoint_candidates.mjs` 会**从 `.kt` 里当场抽出
`endpointCandidates()` 的源码**（不复制粘贴，避免测试副本与真身漂移）再执行，
7 条断言全过：内江师范那条真实代理 URL 的**第一候选**就是
`origin + /kbcx/xskbcx_cxXskbcxIndex.html`（老代码正是在这里 `return null`）；
`url=jwglxt/kbcx/…` 这种带 context-path 的能拼对；常规部署 / 根路径部署 /
把 `url=` 放在 hash 里都能认；认不出来时仍有固定两条兜底且顺序不变。

**模拟器复核（1.1.2 x86_64 装到 API 37）**：
* 首页标题栏出现新的「+」按钮，点进去是完整的「添加课程」表单；
* 填 `Physics / Smith / B309`（周一 第 1-2 节）保存后立刻打日志 ——
  `#2 2026-10-05(周一) 07:55 上课前 5 分钟（每一节课） Physics @B309`，
  即**手动新增的课确实进了持久化并重排了提醒闹钟**（`${c.name} @${c.location}` 两个字段都对）；
* 把系统强制转成横屏（`settings put system user_rotation 1`）后
  `dumpsys window` 仍是 `mCurrentRotation=ROTATION_0`、截图仍是 `1080x2400`
  ⇒ **竖屏锁定生效**。

> 构建踩坑（值得记住）：`flutter test` 之后紧接着 `flutter build apk --release`，
> `GeneratedPluginRegistrant.java` 里可能残留 `integration_test` 插件，导致
> `程序包 dev.flutter.plugins.integration_test 不存在` 而构建失败；**重跑一次即自愈**。
> 更阴的是失败后 `build/app/outputs/flutter-apk/app-release.apk` 还是**上一轮的旧文件**，
> 脚本会把它当成新产物复制出去（本轮 universal 那份就一度是 1.1.1 改名）。
> ⇒ 打包脚本现在先删 4 个旧 apk 再构建，并用 `aapt2 dump badging` 逐个核对 `versionName`。

### 9.8 导入入口改融合门户 + 节次时间可自定义（v1.1.3）

用户第二轮反馈（原文）：

> 连接出了问题，使用这个链接让用户自己找到课程表界面再导入
> pass.njtc.edu.cn/frontend/center_portal_njtc/home/index.html，
> 另外课程开始结束时间要求自定义，这次的 log 如下：…

**① 默认入口从「一步到位的 CAS 深链」改成融合门户首页。**

真机日志显示旧入口那条 CAS 深链走不通：

```
13:02:47 onPageFinished … title=统一身份认证中心
13:03:05 onPageFinished … title=We've got some trouble | - Webservice currently unavailable
13:03:16 onReceivedError … net::ERR_FAILED
13:03:29 onPageFinished … title=proxy.njtc.edu.cn/zytec_proxy/cas_login?redirect_uri=…
```

即 `tpass` → `proxy/zytec_proxy/cas_login` 这一跳服务端自己报错了。现在的做法是
**把选择权交回用户**：默认打开融合门户首页，用户自己点进「课表查询」，看到课表后
再点右上角「读取课表」；菜单里同时保留「直达课表查询页」（载 `JWGLXT_URL`）作为备选。

* `PORTAL_URL = https://pass.njtc.edu.cn/frontend/center_portal_njtc/home/index.html`，
  `DEFAULT_URL = PORTAL_URL`；原 CAS 深链改名 `JWGLXT_URL`（旧 `TIMETABLE_URL` 已删）。
* **`KEY_LAST_URL` 的值从 `"last_url"` 改成 `"last_url_portal"`** —— 老用户机器上
  存的是旧 CAS 深链，不换键名会被 resume 回旧地址、根本看不到新入口。
* 菜单顺序：切换手机/电脑版 → 刷新页面 → 回到融合门户首页 → 直达课表查询页 → 清除登录状态。
* Dart 侧 `lib/services/jwxt_service.dart` 的 `portalUrl` 同步改掉，并新增 `casUrl`
  常量；失败文案与 `lib/pages/import_page.dart` 的四步说明都改成
  「先登录融合门户，自己点进课表查询」。

**② 节次（上下课）时间可自定义。**

* `lib/models/period.dart`：`Period` 增加 `encode()` / `decode()` / `withTime()`；
  新增模块级 `activePeriods` 与 `setActivePeriods()` / `resetActivePeriods()` /
  `normalizePeriods()`（按 11 节补齐并 clamp）/ `periodsCustomized()` /
  `firstInvalidSection()`；`periodOfSection()` 改读 `activePeriods`。
  **`defaultPeriods` 的 11 条时间未改**（第 1 节 08:00-08:45 … 第 11 节 20:50-21:35）。
* `lib/storage/period_store.dart`：键 `njtc_periods`，存 `["08:00-08:45", …]`，
  **下标即节次-1**（不存节次号也不会错位）；解析不出东西时返回 null 回落默认。
* `lib/app_state.dart`：`init()` 里**在 `syncReminders()` 之前**读回节次（提醒排布
  用的就是这份时间）；新增 `periods` / `hasCustomPeriods` / `updatePeriods()` /
  `resetPeriods()`，保存后会 `_syncAfterChange()` 重排闹钟。
* 新页面 `lib/pages/period_settings_page.dart` + 设置页「节次时间」入口（`/periods` 路由）：
  11 行，每行「第N节 + 开始 ~ 结束 + 时长」，点时间走 `showTimePicker`（强制 24 小时制），
  顶部「恢复默认」、底部「保存」；保存前用 `firstInvalidSection()` 校验
  「结束必须晚于开始」。页面编辑的是**草稿**，点保存才写回，改到一半返回不会弄乱作息。
* 所有读取点已从 `defaultPeriods` 换成 `activePeriods`：`lib/widgets/timetable_grid.dart`
  （5 处）、`lib/pages/course_edit_page.dart:250,270`、`lib/services/reminder_service.dart:388`。
* 顺带引入 `flutter_localizations`（`MaterialApp` 的
  `localizationsDelegates: GlobalMaterialLocalizations.delegates` +
  `supportedLocales: [zh_CN, en]`），否则 `showTimePicker` / `showDatePicker`
  的按钮是英文的 CANCEL / OK。

**本轮验证**：`flutter analyze` → No issues found；`flutter test` → **106 个用例全绿**
（新增 `test/period_settings_test.dart` 19 个：编解码 / 补齐与夹取 / 存取往返 /
坏数据回落 / `AppState` 读回与重置 / 设置页入口与时间选择器）。

> 真机取证（原子通知侧，本轮意外收获）：用户这次**点了**「立即验证 → 下节课预告」，
> 日志拿到 App 侧最关键的一条证据 ——
>
> ```
> 13:04:53.255 NjtcVivo: 已挂载 superx 字段：scene=METTING template=1 rightTemplate=6
>                        keepDuration=1800s islandShowTime=180s
> 13:04:53.262 NjtcNotify: 已发送[vivo 原子通知 + 原子岛] id=9901 「高等数学Ⅰ（上）」10:45 下课
>                        | 下节课：大学物理V（上） · 10:55 · 明德楼B105
> ```
>
> ⇒ 真机上**确实走的是原子通知分支、superx 挂载成功**（场景值仍是默认 `METTING`，
> 未准入）。同批 `id=9902 … 明德楼A103 · 曾玉祥` 说明**当前课表里地点与教师都在**。

---

## 9.9 借用参考实现的导入系统 + 门户入口改公网地址（v1.1.5）

这一轮是用户直接点名的：「我之前不是发了几个参考吗？你试着借用他们的导入系统」。
参考材料都在本机，先把「哪个能借」判清楚了再动手。

### 9.9.1 三个参考里，只有一个能借

| 目录 | 是什么 | 能不能借 |
| --- | --- | --- |
| `D:\DSH\_research_cs\` | 完整 Kotlin 源码（`com.courseschedule`），导入系统齐全 | **能借**，本轮主要来源 |
| `D:\DSH\_wk_tmp\x\WakeupSchedule_Kotlin-master\` | WakeUp 开放版源码 | 借不了：只有旧版苏大 `xskb_list.do` 一条路子（`ImportViewModel.kt:390` 用 `getElementById("kbtable")` + `getElementsByClass("kbcontent")`），**没有多校适配器系统** |
| `D:\DSH\CourseTable\`（uni-app）、`D:\DSH\cakeni_CourseSchedule_技术情报报告.md` | 情报/前端 | 仅作参考，无 Java/JS 取数实现 |

**另一个关键收获来自 WakeUp 的在线目录快照**
（`D:\DSH\_research_CourseSchedule\analysis\wakeup-schedule-sync-20260928\sync-result.json`，
`source: "WakeUp Schedule online directory v54, local snapshot"`）。里面**内江师范学院**这一条是：

```json
{ "school": "内江师范学院",
  "old_url": "https://tpass.njtc.edu.cn/frontend/center_portal_njtc/home/index.html",
  "new_url": "https://tpass.njtc.edu.cn/frontend/center_portal_njtc/home/index.html#/home/index",
  "source_type": "zf", "adapter_id": "zhengfang_auto", "has_fragment": true }
```

两点结论：**①校内那套门户在公网主机 `tpass.njtc.edu.cn` 上也能开**（`pass.njtc.edu.cn`
才是只在校园网解析的那个，见 9.7）；**②这所学校是正方系，走 `zhengfang_auto` 自动适配**。
第 ① 点直接决定了下面的门户地址改动。

### 9.9.2 从参考实现借了什么（`WebImportActivity.kt`）

参考实现的正方适配器表（`_research_cs\app\src\main\java\com\courseschedule\ui\importdata\AcademicAdapterRegistry.kt:66-84`）：

```
ZHENGFANG_AUTO   selectors = #Table1, #kbgrid_table, #table1, #sycjlrtabGrid
                 globals   = veInitDefaultJson, __INITIAL_STATE__
                 requestPathPrefixes = /kbcx/xskbcx_cxXskbcxIndex.html   captureMode = PAGE_FETCH
ZHENGFANG_LEGACY selectors = #Table1, #table1                            （DOM 方式）
ZHENGFANG_JWGLXT selectors = #kbgrid_table, #sycjlrtabGrid + 同上 globals （PAGE_FETCH）
```

而 `#kbtable` / `.kbcontent`（我们原来认的那两个）其实是**强智**（`QIANGZHI_*`）的 id ——
正方要用上面那四个之一。于是在 `WebImportActivity.kt` 里：

1. **`PROBE_JS` 的识别集合扩大**，并加了「页面上的全局变量也算数」：
   ```js
   var IDS = '#kbtable,.kbcontent,#Table1,#kbgrid_table,#table1,#sycjlrtabGrid';
   // 命中条件之一：veInitDefaultJson / kbxx / __INITIAL_STATE__ / dateList
   // 存在，且其 JSON 里出现 kcmc|kcm|kbList|xqj|skxq
   // 命中条件之二：整页就是 JSON（body 以 [ 或 { 开头且含课表键）
   ```
2. **新增 `DIAG_JS`：抓不到时先回答「这是哪种页面」。** 只读结构、不碰账号与 cookie：
   标题、正文长度、「星期X」出现次数、若干全局变量的名字与长度、页面上所有
   `select` 的 `id=value[label]`、所有 `table` 的 `#id或.class:行数`。
   `probePage()` 里**只在 `hit == false` 时**执行并打一行 `page diag=…`。
   真机上 WebView 截屏全黑（见 9.7 末），这一行日志是唯一能看出页面长什么样的东西。
3. **`EXTRACT_JS` 照搬参考实现的取数顺序**（`AcademicCaptureScript.kt` 的思路）：
   * 取数候选：内联全局（`veInitDefaultJson` / `__INITIAL_STATE__` / `kbxx` /
     `kckbData` / `lessonArray` / `__NEXT_DATA__` / `dateList`）→ 整页 JSON →
     `win.table0` → 最后才是传统 DOM。
   * `deepFindRows(root)`：深度 ≤6、节点 ≤5000、每个数组抽样 ≤300 行取平均分，
     **平均分 ≥7 才算课表数组**，取分数最高的那个。
   * `deepAnyKey(o, ks, depth)`：**深度 2 下钻**对象与数组。正方新版把星期/节次/周次
     塞进 `id.skxq` 这类子对象里，只看顶层键会漏。
   * `slimRows(rows)`：键投影 + **把嵌套对象的原始值抬到顶层**
     （`{id:{skxq:'1',jcs:'1-2'}}` → `skxq='1', jcs='1-2'`），因为 Dart 侧只认平铺键。
   * `termCodes()`：先读 `#xnm` / `#xqm`，读不到就遍历所有 `select` 找
     `id/name` 含 `xnxq|xnm|xqm|term|semester` 的，从 label/value 提 `20\d{2}` 年份，
     尾数按正方惯例 `1→3`、`2→12` 映射。
4. **DOM 打分的兜底也认正方 id**：`/^(Table1|table1|kbgrid_table|sycjlrtabGrid)$/`
   命中加 800000 分（原来的 `#kbtable` / `.kbcontent` 分支保留）。

### 9.9.3 为什么又写了一个 Node 守卫（`D:\DSH\verify_webimport_js.mjs`）

`EXTRACT_JS` 现在是一段近 2 万字符的字符串常量，**`flutter analyze` 与 `flutter test`
都覆盖不到它**，而它只在真机页面上才跑得起来。所以写了个**在项目外**的 Node 脚本
（不进源码 zip、不进 APK）：从 Kotlin 里**当场抽出** `PROBE_JS` / `DIAG_JS` / `EXTRACT_JS`
（按 `private val NAME = """` … `""".trimIndent()` 截取），先 `new Function(js)` 做语法检查，
再把 `var ROW_NAMES` 到 `function borrowedHit` 之间的函数体抽出来，配一套**假的
`window` / `document`**，用真形状的数据喂进去跑。**它当场抓出两个真 bug**：

* `rowScore(嵌套行) = 6` → `deepFindRows` 返回 `null`：分数不够 7，整张课表被丢掉。
  → 加 `deepAnyKey`，并给 `deepFindRows` 补一条 `named > 0`（数组里必须真有课名），
  否则「只有节次+周次」的数组会以 5 分混进来。
* `slimRows` 把嵌套对象拼成字符串挂在父键下（`o.id = 'skxq=1,jcs=1-2'`），
  Dart 侧永远读不到。→ 改成抬到顶层，并额外遍历「这一行自己的键」（不只白名单键）。
  行数上限同时从 2000 收到 **800**（真机整页 JSON 可能就是几万行）。

修完 **pass=24 fail=0**，`EXTRACT_JS` 19834 字符语法 OK。

### 9.9.4 门户入口改公网地址 + 修掉一个子串误判

**背景**：1.1.4 已经把默认入口从校园网域名改回 CAS 深链（9.7），但用户看到的仍是
「先登录、再自己找课表」。既然公网主机上也有门户（9.9.1 第 ① 点），就让默认入口
直接落在门户上。实测三条：

```
https://tpass.njtc.edu.cn/frontend/center_portal_njtc/home/index.html  → 200，正文仅 176 字节
    （内容是 <meta http-equiv="refresh" content="0;url=https://tpass.njtc.edu.cn/app.php/portal_v4">）
https://tpass.njtc.edu.cn/app.php/portal_v4  → 200 → 跳 /auth/oauth/authorize?…
    redirect_uri=…/app.php/portal_v4/ ，标题「统一身份认证中心」（22.8KB）
https://pass.njtc.edu.cn/…  → 解析失败（ENOTFOUND）
```

于是：`PORTAL_URL = "https://tpass.njtc.edu.cn/app.php/portal_v4"`（`DEFAULT_URL` 就是它），
`PORTAL_CAMPUS_URL` 保留作记录，菜单项「融合门户首页（需校园网）」改名「融合门户首页」。

**顺手修掉 1.1.4 的一个真 bug**：回退判定原来写的是
`failed.contains(PORTAL_HOST)`，而 `"tpass.njtc.edu.cn"` **正好以 `"pass.njtc.edu.cn"` 结尾**，
把 CAS 登录页误判成门户 ⇒ CAS 侧每次网络错误（回退时那种 `ERR_CACHE_MISS` 很常见）
都会触发一次原地重载 + 一条误导性 Toast。改成 `isPortalUrl()`：

```kotlin
private fun isPortalUrl(u: String?): Boolean {
    val uri = android.net.Uri.parse(u ?: return false)
    if (!uri.host.equals(PORTAL_HOST, ignoreCase = true)) return false
    val path = uri.path ?: return false
    return path.contains("portal_v4") || path.contains("center_portal_njtc")
}
```

**同一个坑我自己又踩了一次**：`D:\DSH\verify_default_entry.mjs` 第一版用
`!defaultUrl.includes(campusHost)` 断言，直接 FAIL —— 因为
`"https://tpass.njtc.edu.cn/app.php/portal_v4"` 里也含 `"pass.njtc.edu.cn"`。
**教训：主机名要比相等，不能比子串。**（守卫脚本现在先**剥掉注释**再检查
「源码里有没有 `contains(PORTAL_HOST)`」，因为注释里正举着这个反例。）

### 9.9.5 本轮验证

* `D:\DSH\verify_webimport_js.mjs` → **ALL PASS（pass=24 fail=0）**。
* `D:\DSH\verify_default_entry.mjs` → **ALL PASS（11 条断言）**，其中一条会**真发一次 HTTP**：
  `默认入口公网真能打开（HTTP 200）—— title=[统一身份认证中心] len=22382
  final=…/auth/oauth/authorize?…redirect_uri=…%2Fapp.php%2Fportal_v4%2F`；
  另有 DNS 解析、主机名相等、CAS 深链带 `service=` 等。
* `flutter analyze` → No issues found；`flutter test` → **106 个用例全绿**。
* Dart 侧文案同步：`lib/services/jwxt_service.dart`（`portalUrl` / `campusPortalUrl` 注释）、
  `lib/pages/import_page.dart` 四步说明改成「打开内师融合门户（先跳统一身份认证）→
  登录 → 在门户里自己点进课表查询 → 点右上角『读取课表 ✓』」。

### 9.9.6 本轮踩的坑

* **改字符串字面量时把行尾的 `,` 写成了 `;`**：`lib/pages/import_page.dart:208` 的
  `Text(...)` 参数列表被提前终止，报 `Expected to find ')' - import_page.dart:208:56`，
  release 构建直接失败（`flutter analyze` **能**查出来，所以先跑 analyze 就不会浪费一次构建）。
* 文案里的 Markdown 星号（`**自己点进**`）在 `Text` 里会**原样显示**，
  写完顺手去掉 —— 这个项目没有 Markdown 渲染。
* 版本：`pubspec.yaml` `1.1.5+7`，`settings_page.dart` 关于页 `v1.1.5`。

---

## 9.10 v1.1.6 —— 修掉「进得去页面但读取不到」+ 桌面小组件

### 9.10.1 现象与定位：一次同步 XHR 把 WebView 的 JS 线程卡死了

用户原话：**「现在能进页面，但是读取不到」**。真机日志只有三行，然后什么都没有：

```
14:03:46.001 onPageFinished url=…/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151&layout=default title=个人课表查询
14:03:46.014 probe raw="true" hit=true       ← 新写的正方识别已经命中（页面认得出来）
14:03:51.071 extract start url=…             ← 用户点了右上角「读取课表」
（NjtcImport 这个标签整场一行都没打）
```

⇒ `webView.evaluateJavascript(EXTRACT_JS, cb)` 的**回调根本没回来**，不是「抓到了空数据」。

根因在旧的 `tryJwglxtJson()` 里，有一处**同步 XHR**：

```js
xhr.open('POST', endpoint + '?doType=query&gnmkdm=N2151', false)   // ← false = 同步
```

同步 XHR **不能设超时、也不能中断**；只要请求挂住，WebView 的 JS 线程就永久阻塞，
连 `evaluateJavascript` 的结果都送不回来。全文件扫过一遍：**没有 `while` 循环**，
这是唯一的阻塞点。（另有一处隐患一并加固：`WebChromeClient` 只覆写了 `onProgressChanged`，
`onJsAlert/onJsConfirm` 走默认实现会弹系统框并阻塞 JS。）

顺带发现两个逻辑错：①那个 POST 发到了**页面地址** `xskbcx_cxXskbcxIndex.html`，
而正方 jwglxt 的数据接口是 `xskbcx_cxXsKb.html`（返回 `{"kbList":[…]}`）；
②正方课表是 **div 网格 `.kbcontent`**，不是 `<table>`，所以按 `tables.length` 找表永远找不到。

### 9.10.2 改法：三阶段抓取 + 看门狗，且**一处同步请求都不留**

`android/app/src/main/kotlin/cn/edu/njtc/njtc_schedule/webimport/WebImportActivity.kt`：

* **删掉** `tryJwglxtJson()` / `queryJwglxtJson()`（同步 XHR 就在里面）。
* 新增 `jsonEndpoints()`：**只算不发** —— 把 `endpointCandidates()` 的结果里
  `_cxXskbcxIndex.html` 换成 `_cxXsKb.html` 排前面，原页面地址兜底，去重。
* `extract()` 重写成三阶段，每阶段都有 token 作废机制（`extractToken` / `extractPhase`）：
  * **pass 0**：直接抓当前 DOM（借来的 `EXTRACT_JS` 内联数据 → 整页 JSON → 同源 iframe → DOM 打分）；
  * **pass 1**：没课 → 先 `evaluateJavascript(TRIGGER_QUERY_JS)` 点一下页面上的「查询」，
    等 `QUERY_SETTLE_MS = 1800ms` 再抓一遍 DOM；
  * **pass 2**：还没课 → `postForKbList()` 在 **Kotlin 侧**用 `HttpURLConnection`
    POST 真正的数据接口（`NET_TIMEOUT_MS = 8000`，body 带 `xnm/xqm/kzlx/queryModel.*`，
    `Cookie` 从 `CookieManager.getInstance().getCookie(referer)` 取 —— 登录态是 WebView 建立的）。
  * **看门狗** `EXTRACT_TIMEOUT_MS = 20000`：无论如何都会恢复「读取课表」按钮并提示卡在哪一阶段。
* 新增 `hasRows()` 判空（`jsonRows` 非空 / `kbFilled>0` / `tableHtml` 含 `kbcontent` 且够长 / 正文够长），
  payload 增加 `endpoints`、`kbFilled`、`diag`（`tables/frames/bodyLen/bestId/bestScore/xnm/xqm`）。
* 新增 `TRIGGER_QUERY_JS`：先找 `window.query/search/doQuery/loadData/reloadData/refresh`，
  找不到就找文本是「查询/搜索/查课表」的 `button/a/input` 点一下。

**Dart 侧不用改**：`lib/services/jwxt_service.dart:212-220` 早就在读 `payload['jsonRows']`
并走 `ZfHtmlParser.coursesFromJwglxtJson()`。

### 9.10.3 守卫脚本跟着升级（`D:\DSH\verify_webimport_js.mjs`）

除了原有 24 条，新增三组断言，从 **pass=23 fail=1 修到 ALL PASS（pass=44 fail=0）**：

1. **不许再出现会卡死的写法**：`EXTRACT_JS` 里不得有 `xhr.open(…, false)`、不得有 `while (`；
   整个 Kotlin 源码里不得再出现 `tryJwglxtJson` / `queryJwglxtJson`。
2. `TRIGGER_QUERY_JS` 也要过 `new Function` 语法检查，且必须含查询函数名与「查询」字样。
3. Kotlin 侧三阶段骨架必须在：`EXTRACT_TIMEOUT_MS`、`QUERY_SETTLE_MS`、`postForKbList`、
   `CookieManager.getInstance().getCookie`、`doType=query&gnmkdm=N2151`、`NET_TIMEOUT_MS`、`runExtractPass`。

### 9.10.4 桌面小组件「今日课程」

参考 `D:\DSH\_refs\wakeup-schedule` 的 `widget\TodayWidget.kt`（`AppWidgetProvider` +
`RemoteViewsService` + `RemoteViewsFactory`），但**故意不用列表**：一天最多五六门课，
静态 5 行少一层 Service 生命周期，刷新时机完全自己控制，也更省电。

* `android/app/src/main/kotlin/cn/edu/njtc/njtc_schedule/widget/WidgetData.kt`：
  读原生存档 → 算出「今天要画哪几行」。今天星期几用 `((Calendar.DAY_OF_WEEK + 5) % 7) + 1`
  （周一=1…周日=7）；周次算法与 Dart 的 `AppState._autoDetectWeek()` 一致
  （`days/7 + 1` 再夹到 `[1, totalWeeks]`）；单双周、周次区间与 `Course.isActiveOnWeek()` 一致；
  取色与 `AppTheme.colorForCourse()` 一致（码元求和 `% 8`）。**最多 5 行**，多的折成
  「还有 N 门 · 点开看全部」。
* `widget/TodayWidgetProvider.kt`：`onUpdate` + `onReceive` 处理自己发的
  `cn.edu.njtc.njtc_schedule.WIDGET_REFRESH`、`DATE_CHANGED`、`TIME_SET`、`TIMEZONE_CHANGED`、
  `BOOT_COMPLETED`、`MY_PACKAGE_REPLACED`（跨零点要换成新一天的课）。
  用 `RemoteViews` + `setInt(bar, "setBackgroundColor", color)` 画左侧色条。
* `widget/WidgetBridge.kt` + 通道 `cn.edu.njtc.njtc_schedule/widget`（`update` / `refresh`），
  在 `MainActivity.configureFlutterEngine()` 里注册。`widget/NjtcWidgetStore.kt` 存
  `timetable` / `periods` / `has_timetable` 三样。
* 布局 `android/app/src/main/res/layout/widget_today.xml`（5 行写死）、底板
  `res/drawable/widget_bg.xml`、元信息 `res/xml/widget_today_info.xml`
  （`updatePeriodMillis=1800000`，30 分钟是系统最小值，主要靠主动刷新）。
* `AndroidManifest.xml` 注册 `<receiver android:name=".widget.TodayWidgetProvider">` +
  `<meta-data android:name="android.appwidget.provider">`。
* Dart 侧 `lib/services/widget_service.dart`：`sync()` 把 `Timetable.toJsonString()` 与
  节次表（精简成 `[{s,a,b}]`）推给原生；设置页新增「桌面小组件」入口
  （`lib/pages/settings_page.dart` 的 `_WidgetEntry`），里面写清怎么把挂件拖到桌面，
  还带一个「立即同步」按钮。

**为什么让 Dart 主动推、而不是原生自己去读 `FlutterSharedPreferences`**：
①`shared_preferences_android-2.4.28` 把 `setStringList` 存成
`LIST_PREFIX + Base64(Java 序列化 ArrayList)`（`LIST_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu"`），
原生要读得先 Base64 解码再 Java 反序列化，不值当；
②Flutter 侧是**异步落盘**，刚 `setString()` 完就刷新时原生另开一个实例可能读到旧值。
推过去存进原生自己的 `njtc_widget`，顺序就确定了。

### 9.10.5 本轮踩的坑（很重要）

* **别在保存路径上 `await` 一个没有桩的平台通道调用**。最初把
  `await WidgetService.sync(...)` 放进 `AppState._syncAfterChange()`，结果
  `test/course_edit_test.dart` 的第一个用例**卡死 10 分钟**：`pumpAndSettle()`
  一遍遍空转到超时（每轮都要等那个永远不回来的平台消息）。改成
  `unawaited(WidgetService.sync(...))`（`dart:async`）后，全量测试 4 秒跑完 112 个用例。
  `WidgetService.sync()` 自己 try/catch 吞掉所有异常，所以不 await 也不会冒出未处理异常。
* `test/` 里的 `select-Object -Last` 会**缓冲全部输出**，看起来像「没有任何输出」——
  排查挂起要把输出重定向到文件再 tail。
* 一个文件单独跑很快、全量跑挂住 ⇒ 说明挂的是**某个用例**，用
  `Start-Process + 重定向日志 + 看 compact reporter 停在哪个用例名** 最快定位。

### 9.10.6 本轮验证

* `flutter analyze` → No issues found。
* `flutter test` → **112 个用例全绿**（106 + 新增 `test/widget_service_test.dart` 6 个：
  平台开关、推的 JSON 形状、自定义作息、没有课表时的 `hasTimetable=false`、原生抛错被吞、`refresh`）。
* `.\gradlew.bat :app:compileDebugKotlin` → **BUILD SUCCESSFUL**（widget 四个 Kotlin 文件编译通过）。
* 版本：`pubspec.yaml` `1.1.6+8`，`settings_page.dart` 关于页 `v1.1.6`。

## 9.11 v1.1.7 —— `innerText` 兜底 + 把抓取脚本放到真 DOM 上验一遍

### 9.11.1 又一个「读取不到」的嫌疑犯：`innerText` 对隐藏元素返回空串

`innerText` 和 `textContent` 看着像同义词，其实差一条：**`innerText` 只返回「渲染出来」
的文字**，元素被 CSS 隐藏（`display:none` / 折叠的页签）时它返回 `''`；`textContent`
不管可见性，一律返回全部文本。

正方系列页面恰恰**特别爱把课表塞进隐藏容器**：切页签的 tab、`display:none` 的结果区、
折叠面板。这时候 `EXTRACT_JS` 里凡是用 `innerText` 判断「这页有没有课表」「这个格子有没有
内容」的地方，都会得到「什么都没有」，于是安静地走进兜底分支 —— 用户看到的就是
「读取不到」，而页面明明是好的。

1.1.6 全文件排查后，`EXTRACT_JS` 里多数地方本来就写了 `innerText || textContent`，
但有 **4 处漏了**（见下），本轮统一补齐：

| 位置 | 原写法 | 影响 |
| --- | --- | --- |
| `PROBE_JS` 正文判定 | `document.body.innerText \|\| ''` | 隐藏课表页被判成「不是课表页」，直接不进抓取 |
| `PROBE_JS` iframe 判定 | `d.body.innerText \|\| ''` | 同上 |
| `DIAG_JS` 指纹 | `document.body.innerText \|\| ''` | 日志里 `days=0 bodyLen=0`，误导排查 |
| `TRIGGER_QUERY_JS` 按钮文字 | `el.innerText \|\| el.value \|\| el.title` | 「查询」按钮认不出来，点不到查询 |

`TRIGGER_QUERY_JS` 那处的兜底顺序是 `innerText || textContent || value || title`：
`<input type=button value="查询">` 的 `textContent` 是空串，所以顺序不会把 `value` 挡掉
（jsdom 里实测走的就是 `value` → `click:查询`）。

### 9.11.2 更重要的：`EXTRACT_JS` 以前**从没在真 DOM 上跑过**

回头看 1.1.5 → 1.1.6 的排查过程，有个尴尬的事实：抓取脚本只有两种「验证」——

1. `new Function(code)` 语法检查；
2. 把 `EXTRACT_JS` 里的一小段（`var ROW_NAMES` … `function borrowedHit`）抠出来，
   喂给一个**手搓的假 DOM**（`D:\DSH\verify_webimport_js.mjs`）。

也就是说 `collect` / `cells` / `filledCells` / `termCodes` / `jsonEndpoints` /
表格打分这一大坨**从来没被执行过一次**。真机报「读取不到」时，分不清是脚本抠不到、
接口没回、还是解析层吃不下 —— 只能靠猜。

本轮补上：`D:\DSH\_verify\verify_extract_pipeline.mjs` 用 **jsdom 起真 DOM**，
把 `EXTRACT_JS` 原文抽出来 `window.eval` 跑，**29 条断言 / 5 个场景**：

* 场景 1 常规部署 `/jwglxt/kbcx/…`：选中 `#kbtable`（不是那张 `other-table`）、
  `kbFilled=9`、正文有「星期X」和课名、`jsonRows=null`；
  **端点推断**给出 `…/jwglxt/kbcx/xskbcx_cxXsKb.html` 打头（页面 `_cxXskbcxIndex.html`
  → 数据 `_cxXsKb.html`），并额外给 `/kbcx/` 那一层（context-path 猜错时的第二条路）。
* 场景 2 **反向代理**（内江师范真实形态）：`url=` 参数解两遍码后取出
  `…/kbcx/xskbcx_cxXsKb.html` —— 老代码正是在这里 `return null`，
  于是永远拿不到接口数据，教师/教室只能靠抠 DOM。
* 场景 3 正方新版形状：表格外包一层 `<div id="kbtable">`（表格自己没有 id），
  靠 `parentNode.id === 'kbtable'` 的加分仍选中它。
* 场景 4 前面塞 3 张噪声表，课表仍要胜出（`tables=5`，`bestId=kbtable`）。
* 场景 5 `TRIGGER_QUERY_JS`：有 `query()` 时 `call:query`；没有时退回点按钮
  `click:查询`。

脚本最后把场景 1 的载荷落盘成 `test/fixtures/extract_payload_jsdom.json`
（**真 JS 在真 DOM 上的产物**），再由 `test/webimport_jsdom_payload_test.dart`
（8 个用例）喂给 `JwxtService.parsePayload` 跑完下半段。

**最有价值的那条断言**：载荷路径与「整页 HTML 直接解析」**逐门完全一致** ——
9 门课，课名/星期/节次/周次/单双周/教师/教室/课号/教学班全等，
连学期（2026-2027年第1学期）、专业（机器人工程）、总周数（20）都一样。
载荷里的 `tableHtml` 只有 **2921 字节**（整页 4637 字节），
丢掉了 `#head`、`other-table` 和 HTML 外壳；学期/专业能活下来，
靠的是同一份载荷里的 `payload['text']`（整页正文）。
**这两半缺一不可** —— 以后谁要「优化载荷体积」，先把这条测试跑一遍。

### 9.11.3 本轮踩的坑

* **断言不要数字符串出现次数**：夹具里 `kbcontent` 出现 10 次，但 `<div class="kbcontent">`
  只有 **9 个**（第 10 次在文件顶部的注释里）。要断言就 `querySelectorAll('.kbcontent').length`。
* **jsdom 没有实现 `innerText`**（返回 `undefined`）。这反而成了好事：
  它顺带证明了 `innerText || textContent` 这层兜底不是装饰 —— 少了它，
  正文判定、课程格文本、按钮文字全是空串。
* `runScripts: 'outside-only'` 时**页面内联 `<script>` 不执行**，
  所以场景 5 里 `window.query` 不存在，走的正是「退回点按钮」那条路；
  要测函数优先，得从外面 `w.eval('window.query = …')` 注入。
* Dart 里 `'$fixturePath'` 不会插值（单引号里 `$` 后面跟的是未定义的标识符名，
  编译期直接报 `Undefined name`）—— 常量要写 `$_fixturePath`。

### 9.11.4 本轮验证

* `flutter analyze` → No issues found。
* `flutter test` → **120 个用例全绿**（112 + `test/webimport_jsdom_payload_test.dart` 8 个）。
* `node D:\DSH\verify_webimport_js.mjs` → **ALL PASS 44 条**（老的片段级守卫没被打破）。
* `node D:\DSH\_verify\verify_extract_pipeline.mjs` → **ALL PASS 29 条**。
* 版本：`pubspec.yaml` `1.1.7+9`，`settings_page.dart` 关于页 `v1.1.7`。
* 改了 `EXTRACT_JS` 就要重跑一次 jsdom 脚本，否则 fixture 会过期：
  `node D:\DSH\_verify\verify_extract_pipeline.mjs`
  （jsdom 装在 `D:\DSH\_verify`，不进 App 仓库、不进源码 zip）。

## 9.12 v1.1.8 —— 接口路径曾经是死代码（模拟器 E2E 抓出来的真 bug）

### 9.12.1 现象

`integration_test/jwglxt_json_e2e_test.dart` 在 1.1.7 上**失败**：

```
NjtcImport: 载荷 表格HTML=417 文本=87 jsonRows=0 课程格=1 页面标题=学生课表
            接口端点=http://10.0.2.2:8138/jwglxt/kbcx/xskbcx_cxXsKb.html
            诊断={tables: 1, frames: 0, bodyLen: 87, bestId: kbtable, bestScore: 1000034, xnm: 2026, xqm: 3}
NjtcImport: 解析来源=… 课程=0
```

注意三件事：`接口端点` **已经算出来了**、`xnm/xqm` **也有值**（2026 / 3），
可 `jsonRows=0`，而且 logcat 里**只有 `extract pass=0` 一行**，接着就
`finishWithPayload` —— pass 1 / pass 2 根本没跑。

### 9.12.2 根因：`hasRows()` 一真，接口阶段就永远进不去

1.1.6 引入的三阶段 `extract()` 里，pass 0 写的是：

```kotlin
if (hasRows(payload)) { settleOk(payload); return }
```

而 `hasRows()` 的判据是 `kbFilled > 0` —— **DOM 里抠到任意一格就算「读到了」**。
`tool/jwglxt_fixture_server.py` 的页面故意只画**一个** `.kbcontent`（人工智能导论），
接口却返回 4 行 `kbList`（拆成 6 门课）。这正是正方真实页面的形态：
**页面只渲染一屏 / 当前周，接口给的才是整学期**。

于是：DOM 有一格 → pass 0 直接 `settleOk` → pass 2 的 `postForKbList()` 永远不执行。
`jsonEndpoints()` 算出来的接口地址、`xnm/xqm` 全都白算了。
用户看到的是「导入成功，但只有一屏的课」，比彻底失败更难被发现。

### 9.12.3 改法

`android/app/src/main/kotlin/cn/edu/njtc/njtc_schedule/webimport/WebImportActivity.kt`：

* 新增 `private fun canQueryInterface(p: JSONObject): Boolean` ——
  `endpoints` 数组非空 **且** `xnm`/`xqm` 都不为空才认为「这个页面值得再打一次接口」。
* 新增 `private fun startNetPhase(token: Int, payload: JSONObject, fallback: JSONObject?)`
  —— 把「取 endpoints / xnm / xqm → 进 net 阶段 → `postForKbList`」抽出来；
  地址或学年学期不全时，有 `fallback` 就用它 `settleOk`，没有才 `settleFail`。
* pass 0 分支改成：

```kotlin
if (hasRows(payload)) {
    // ⚠️ 别再改回「有 DOM 就直接 settleOk」：那样接口路径变成死代码，
    // 页面只画一屏时用户就只拿到一屏的课（1.1.6 / 1.1.7 的真 bug）。
    if (pass == 0 && canQueryInterface(payload)) {
        startNetPhase(token, payload, fallback = payload)
        return
    }
    settleOk(payload)
    return
}
```

  pass 1 末尾则改成 `startNetPhase(token, payload, fallback = null)`（老链路不变）。
* `postForKbList(token, endpoints, xnm, xqm, base, fallback)` 增加 `fallback` 形参，
  并给候选地址排序 + 限流：

```kotlin
val (dataish, others) = endpoints.partition { DATA_ENDPOINT_RE.containsMatchIn(it) }
val tries = (dataish + others).take(MAX_NET_TRIES)
```

  全部试完还是没 `kbList` 时，`fallback != null && hasRows(fallback)` 就
  `Log.i(TAG, "接口没返回课表（$lastErr），回落到页面 DOM")` + `settleOk(fallback)`。
* companion object 新增两个常量：`MAX_NET_TRIES = 2`（最坏 2 × `NET_TIMEOUT_MS`
  8000ms = 16s，压在 `EXTRACT_TIMEOUT_MS` 20s 看门狗之内 —— `jsonEndpoints()`
  会把页面地址也当候选塞进来，POST 页面地址只会拿回 HTML，所以必须限条数）、
  `DATA_ENDPOINT_RE = Regex("cxXsKb|cxXsgrkb", RegexOption.IGNORE_CASE)`。

**为什么一定要回落 DOM**：接口地址可能是猜的（反向代理的 context-path 不一定对），
用户宁可拿到「只有一屏的课表」也不要拿到「导入失败」。

### 9.12.4 守卫升级

`D:\DSH\verify_webimport_js.mjs` 从 44 条加到 **54 条**，新增：

* 六个 Kotlin 骨架 needle（`canQueryInterface` / `startNetPhase` / `MAX_NET_TRIES` /
  `DATA_ENDPOINT_RE` / `回落到页面 DOM`）；
* **顺序敏感**的一条：`canQueryInterface(payload)` 在源码里的下标必须
  **大于** `if (hasRows(payload)) {` 的下标、且间距 < 1600 字符 ——
  这正是 1.1.6/1.1.7 出 bug 的那个位置，钉住它就不会再被改回去；
* `startNetPhase(token, payload, fallback = payload)` 与 `… fallback = null)`
  两种调用形态都在，防止有人把「有 DOM 课」那条路又接回老的 pass 1/2 链路。

### 9.12.5 验证

* `flutter analyze` → No issues found。
* `flutter test` → **120 个用例全绿**。
* `node D:\DSH\verify_webimport_js.mjs` → **ALL PASS 54 条**。
* `integration_test/jwglxt_json_e2e_test.dart`（模拟器 emulator-5554）→ **通过**：
  `jsonRows=4`、`接口端点=…/jwglxt/kbcx/xskbcx_cxXsKb.html`、
  `解析来源=教务接口 jsonRows 课程=6 有教师=6 有地点=6`、
  `message=已从教务接口识别 6 门课`、学期 2026-2027年第1学期 / 周数 18；
  `大学物理V（上）` 单双周=1；`思想道德与法治` 离散周次拆成 `1-1`/`3-3`/`5-9` 三段。
* `integration_test/web_import_e2e_test.dart`（DOM 路径回归）→ **通过**：
  `已识别 9 门课`、学期 / 专业 / 周数 20 / 起始 2026-08-31 全对
  （该页 `xnm`/`xqm` 为空 ⇒ `canQueryInterface` 为 false ⇒ 仍走 DOM，符合预期）。
* 版本：`pubspec.yaml` `1.1.8+10`，`settings_page.dart` 关于页 `v1.1.8`。

### 9.12.6 教训

* **「测试没改、产品改了」也算回归**：`jwglxt_json_e2e_test.dart` 和夹具一直没动，
  但 1.1.6 的三阶段重构把它的目标路径变成了死代码。有 E2E 才看得见。
* **分支里最有价值的那条路，要单独问一句「它真的会走到吗」**：
  `hasRows()` 提前 `return` 这种写法，静态看是「能跑就不折腾」，实际是让整段代码失效。
* 别只写「XXX 存在」的断言 —— 顺序 / 位置也是逻辑，`indexOf` 的大小比较就能守住它。

---

## 9.13 v1.1.8 补测 —— 反向代理形态（内江师范真实地址）首次在真机上跑通

### 9.13.1 为什么还要加这条

前两条 E2E 覆盖的是「抠渲染后的 DOM」和「常规部署 `/jwglxt/kbcx/xskbcx_cxXskbcxIndex.html`」。
可学校实际给学生的地址是**反向代理**形态：

```
https://jxglpt-xxx.proxy.njtc.edu.cn/sso/driotlogin?url=kbcx%252Fxskbcx_cxXskbcxIndex.html%253Fgnmkdm%253DN2151
```

路径里**根本没有 `/kbcx/` 这一段**，真地址藏在 `url=` 参数里、而且是**双层**百分号编码
（`%252F` 解一遍是 `%2F`，解两遍才是 `/`）。1.1.5 之前的老代码就是在这里直接 `return null`，
于是永远拿不到接口数据、只能退化成抠 DOM —— 教师 / 地点整列都丢。

1.1.7 起 `endpointCandidates()` 会解两遍码把端点拼出来，但**只在 jsdom 里验过**推导逻辑，
真 WebView 上一次都没跑过。这条补的就是这个缺口。

### 9.13.2 固件服务扩了两个「代理落地方式」

`tool/jwglxt_fixture_server.py` 新增：

| 路径 | 形态 |
| --- | --- |
| `GET /sso/driotlogin?url=…` | 登录接口**原地**吐课表页，`url=` 参数还在 → 走「解两遍码」分支 |
| `GET /sso/driotlogin_r` | 302 跳到 `/kbcx/xskbcx_cxXskbcxIndex.html` → 跳完参数没了，只能靠 `location.pathname` 推 |

两种落地方式都必须推出**同一个**数据接口 `/kbcx/xskbcx_cxXsKb.html`。
另外加了两个只给测试用的观察口：`GET /__posts`（按顺序返回服务端收到的 POST 路径）、
`GET /__reset`（清空）。**这是这条测试最硬的一条断言** —— 它证明 App 打的确实是
「推导出来的数据接口」，而不是像老代码那样把 POST 发到页面地址上。

### 9.13.3 新测试 `integration_test/jwglxt_proxy_e2e_test.dart`

两个用例（原地吐页面 / 302 跳转），断言：`message` 含 `教务接口`（没退化成抠 DOM）、
服务端收到的**第一个** POST 就是 `/kbcx/xskbcx_cxXsKb.html`、6 门课、学期
`2026-2027年第1学期`、周数 18、`大学物理V（上）` 单双周=1、`思想道德与法治` 离散周次
逐段保留 `1-1` / `3-3` / `5-9`。

固件地址做成可覆盖的，模拟器和真机同一份测试：

```bash
# 模拟器（默认值，宿主机的 127.0.0.1 就是 10.0.2.2）
flutter test integration_test/jwglxt_proxy_e2e_test.dart -d emulator-5554

# 真机：先把手机的 8138 反投到宿主机，再覆盖固件地址
adb reverse tcp:8138 tcp:8138
flutter test integration_test/jwglxt_proxy_e2e_test.dart -d <serial> \
  --dart-define=FIXTURE_HOST=http://127.0.0.1:8138
```

### 9.13.4 真机（vivo V2520A / Android 17）实测结果

`+2: All tests passed!`（EXIT=0）。两种形态的日志：

```
# 形态一：url= 参数还在
NjtcImport: 载荷 表格HTML=417 文本=87 jsonRows=4 课程格=1 页面标题=学生课表
            接口端点=http://127.0.0.1:8138/kbcx/xskbcx_cxXsKb.html
            诊断={tables: 1, frames: 0, bodyLen: 87, bestId: kbtable, bestScore: 1000034, xnm: 2026, xqm: 3}
NjtcImport: 解析来源=教务接口 jsonRows 课程=6 有教师=6 有地点=6
[E2E-PROXY] pageUrl=http://127.0.0.1:8138/sso/driotlogin?url=kbcx%252F…  title=学生课表
[E2E-PROXY] 固件服务收到的 POST 路径=[/kbcx/xskbcx_cxXsKb.html]

# 形态二：302 之后参数丢了
[E2E-PROXY] pageUrl=http://127.0.0.1:8138/kbcx/xskbcx_cxXskbcxIndex.html
[E2E-PROXY] 固件服务收到的 POST 路径=[/kbcx/xskbcx_cxXsKb.html]
```

顺带把 1.1.8 release 包（`内师课程表-1.1.8-arm64-v8a.apk`）装进真机做了冷启动冒烟：
`versionCode=2010 versionName=1.1.8`、无崩溃、小组件 provider 已注册，设备摘要为
`{isVivo=true, isIslandCapable=true, romVersion=17.0, sceneEnabled=false, brand=vivo,
manufacturer=vivo, model=V2520A, osVersion=17.0, androidSdk=37, androidRelease=17,
notificationsEnabled=true, exactAlarmAllowed=true, ignoringBatteryOptimizations=false}`
—— 真机上原子岛能力确实被判成 `true`（`sceneEnabled=false` 是因为 `COURSE` 场景还没拿到
vivo 准入，仍走 `METTING`）。

### 9.13.5 教训

* **「推导逻辑在 jsdom 里过了」不等于「真 WebView 上能用」**：jsdom 没有真网络栈、没有
  Cookie、没有 WebView 的地址栏行为，302 之后 `location` 变成什么它管不了。
  凡是要跟真实浏览器行为对齐的，最后都得在设备上跑一遍。
* **断言要打在「服务端看到了什么」上**，而不是只看 Dart 侧的结果：`/__posts` 这一条
  才真正区分出「打的是数据接口」和「打的是页面地址」（后者也能返回 200，只是 body 是 HTML）。
* 真机跑 `integration_test` 要 `adb reverse` + `--dart-define`；而且**跑完 App 会被卸载**
  （`flutter test integration_test` 的行为），所以跑完要记得把 release 包装回去。

## 9.14 v1.1.9 —— 桌面小组件白卡的真因：`android.view.View` 不在 RemoteViews 白名单里

### 9.14.1 现象

用户 v1.1.8 把「今日课程」拖到桌面后，看到的是一张**纯白圆角卡片**（截图里连一个字都没有）。
同时 `dumpsys appwidget` 显示小组件**已经正常绑定**、宿主也**拿着我们推的 `RemoteViews`**：

```
provider [930] ProviderId{uid:10515, … cmp:ComponentInfo{cn.edu.njtc.njtc_schedule/cn.edu.njtc.njtc_schedule.widget.TodayWidgetProvider} … initialLayout=#7f0b003b}
Widgets: [0] id=23 … views=android.widget.RemoteViews@83069c6 visible=false
```

App 一启动还会打 `NjtcWidget: 刷新小组件 1 个` —— 也就是说**通道是通的、数据也推到了宿主**，
问题只出在「宿主拿到 RemoteViews 之后画不出来」。

### 9.14.2 定位手法：别截图，直接把「画成什么样」问出来

真机有安全锁屏，`adb shell input` 解不开，桌面截图这条路是堵死的（试了亮屏、MENU、上滑，
`mDreamingLockscreen` 一直是 `true`）。于是给原生加了一个**探针**：

* `TodayWidgetProvider.buildViews(context, widgetId)`：把「画界面」从 `render()` 里抽出来，
  变成可以单独调用的纯函数；
* `TodayWidgetProvider.probeRendered(context)`：`buildViews(...).apply(context, FrameLayout(context))`
  之后用 `findViewById<TextView>(id).text` / `visibility` 把**真正会被宿主渲染出来的文字**
  读出来，返回 `Map`（`date` / `week` / `empty` / `emptyVisible` / `footer` / `rows`）；
* `WidgetBridge` 加 `"probe"` 方法，`WidgetService.probe()` 转发（**这一路不许静默吞异常**，
  否则就又变成「查不出来」）。

在模拟器上一跑，探针没返回 nil，而是把宿主侧的异常原文带回来了：

```
WidgetService.probe 失败：PlatformException(error, Binary XML file line #60 in
cn.edu.njtc.njtc_schedule:layout/widget_today: Error inflating class android.view.View, null,
android.view.InflateException: Binary XML file line #60 in …:layout/widget_today:
Error inflating class android.view.View
Caused by: android.view.InflateException: …: Class not allowed to be inflated android.view.View
```

### 9.14.3 根因

`RemoteViews` 只允许白名单里的控件类（平台里带 `@RemoteView` 注解的那些：`TextView`、
`ImageView`、各种 `Layout`、`ProgressBar`…）。**裸 `android.view.View` 不在白名单里。**
而 `widget_today.xml` 里那 5 条颜色分隔条（`bar_1`…`bar_5`）正是用 `<View>` 写的
（第 56/108/160/212/264 行）⇒ 宿主 inflate 到第一条就抛异常 ⇒ **整个布局画不出来**，
用户在桌面上看到的就只是一张空卡。

同一份错误也发生在 `widget_today_preview.xml`（我为「添加小组件」预览新写的布局，
里面同样用了 `<View>`）—— 所以「添加界面也是白卡」和「桌面也是白卡」是**同一个根因**。

### 9.14.4 改法

* `widget_today.xml`：5 处颜色条 `<View>` → `<ImageView android:contentDescription="@null" />`
  （`ImageView` 在白名单里，`setInt(id, "setBackgroundColor", color)` 一样有效），
  并在第一处写了长长的注释说明为什么不能用 `View`。
* `widget_today_preview.xml`：3 处同样改掉，抬头注释写明这条规则。
* `widget_today.xml` 的 `widget_footer` 补默认文字「打开 App 同步课表」：
  XML 里原本没有默认 text，而文字全靠代码填，万一还没同步过一次，卡片就是空的。
* `res/xml/widget_today_info.xml` 补上 `android:previewLayout="@layout/widget_today_preview"`
  与 `android:previewImage="@drawable/widget_preview"`（老系统只认后者、API 31+ 优先前者；
  两者都没有时，「添加小组件」列表里就只有一张白卡）。
  预览图由 `tool/make_widget_preview.py`（Pillow，500×252）画出来。
* 顺手把 `WidgetData.build` 抛异常的分支从「`return`（什么都不更新）」改成
  **渲染一张兜底卡**（「课表数据读不出来，打开 App 重试」）：原先取数一失败，
  宿主就永远停在占位/上次内容上，用户同样只会看到白板。
* 新增 `override fun onEnabled()`：第一个小组件被添加时立刻刷新，不必等 App 启动一次。

### 9.14.5 守住它

* 新增单测 `test/widget_layout_whitelist_test.dart`（3 条）：
  扫描 `android/app/src/main/res/layout/widget_*.xml`，**任何不在白名单里的控件名都算失败**，
  裸 `<View>` 单独给一条更直白的提示；再单独断言 `bar_1`…`bar_5` 的标签是 `ImageView`。
  这样「下次又写回 `<View>`」会直接红。
* 新增集成测试 `integration_test/widget_render_e2e_test.dart`（2 条）：
  ①只读探针（真机上用来问「你现在会画成什么样」）；②注入今天两门课再探针断言
  （日期含 `M月D日`、`week == 第1周`、两行、页脚含 `2 门`、`emptyVisible == false`）。

### 9.14.6 验证（1.1.9）

* `flutter analyze` → `No issues found!`
* `flutter test` → **`+123: All tests passed!`**（120 + 3 条白名单守卫）
* `gradlew :app:compileDebugKotlin` → `BUILD SUCCESSFUL`
* 模拟器（API 37）：`flutter test integration_test/widget_render_e2e_test.dart -d emulator-5554`
  → **`+2: All tests passed!`**，探针打出真实渲染结果：
  * 空存档：`{"date":"10月4日 周日","week":"","footer":"打开 App 同步一次课表","emptyVisible":true,"rows":[],"empty":"今天没课"}`
  * 注入两门课后：`{"date":"10月4日 周日","week":"第1周","footer":"共 2 门 · 点开看全部","emptyVisible":false,"rows":["08:00-09:40 人工智能导论@明德楼B216","10:00-11:40 高等数学Ⅰ（上）@明德楼A203"],"empty":"今天没课"}`
* 真机（vivo V2520A / Android 17）装 1.1.9 后：**桌面截图确认真机上也画得出来了**，见 §9.14.7。

### 9.14.7 真机实测（vivo V2520A / Android 17，2026-10-04）

**1.1.9 装上去了**：`adb -s 10CG681D4N004KB install -r 内师课程表-1.1.9-arm64-v8a.apk` → `Success`；
`dumpsys package` 读到 `versionName=1.1.9`；`am start -n cn.edu.njtc.njtc_schedule/.MainActivity`
→ `ActivityTaskManager: Displayed … +465ms`。

**原计划的取现路走不通**：这台 vivo 在重装之后**不再输出我们 App 自己的任何日志** ——
`logcat -c` 后冷启动，`logcat -d -s NjtcWidget:* NjtcVivo:*` 是空的，
`logcat -d | Select-String 'Njtc|flutter|AndroidRuntime'` 只剩 `adbd / Finsky / BinderSender /
BatteryStatsService / ActivityTaskManager` 这些系统行，整个 buffer 只有 277 行。
（同一天早些时候同机同标签是能看到 `NjtcWidget: 已同步小组件数据` 的，所以这不是标签写错。）
顺带一个坑：`logcat --pid=` 想拼变量时**不能叫 `$pid`** —— PowerShell 里 `$pid` 是只读自动变量，
赋值直接报 `无法覆盖变量 PID，因为该变量为只读变量或常量`，于是 `--pid=` 拿到空值、命令静默无输出。

**改用「系统侧状态 + 广播 + 截图」三件套取证**（都不依赖 App 日志）：

1. `dumpsys appwidget` 找到我们的 provider 与已放置的实例：
   ```
   [930] provider ProviderId{uid:10515, app:10515, cmp:ComponentInfo{cn.edu.njtc.njtc_schedule/
        cn.edu.njtc.njtc_schedule.widget.TodayWidgetProvider}, profile:UserHandle{0}}
     min=(64001x28161) minResize=(64001x28161) updatePeriodMillis=1800000 resizeMode=3 initialLayout=#7f0b003b
   Widgets:
   [15] id=32
     host=HostId{user:0, app:10108, hostId:1024, pkg:com.bbk.launcher2}
     provider=ProviderId{uid:10515, …}
     views=android.widget.RemoteViews@f8038c6
   ```
   ⇒ 小组件实例是 **`id=32`**（不是 23，23 是「番茄小说」那个 `com.dragon.read` 的，
   早先我看走了眼），宿主是 vivo 桌面 `com.bbk.launcher2`，**一直好好挂在桌面上**。
2. 手工触发一次刷新：
   `adb shell am broadcast -a cn.edu.njtc.njtc_schedule.WIDGET_REFRESH -n cn.edu.njtc.njtc_schedule/.widget.TodayWidgetProvider`
   → `Broadcast completed: result=0`，再 dump 一次，**我们的 `views=` 从 `@f8038c6` 变成 `@ee520b5`**
   （同一个列表里番茄小说的 `@bf2b83` 纹丝不动）⇒ 1.1.9 的 `onReceive → refreshAll → buildViews →
   updateAppWidget` 在真机上带着**真实的 22 门课存档**跑通了，而且宿主收下了新 RemoteViews、没抛 inflate 异常。
3. 亮屏 + `input keyevent 3`（HOME）后 `dumpsys window` 已是
   `mCurrentFocus=Window{… com.bbk.launcher2/com.bbk.launcher2.Launcher type=1}`、`mDreamingLockscreen=false`，
   直接 `screencap` 把桌面拍下来（存 `screenshots/widget_ok_real_device.png`）：

   ```
   10 月 4 日 周日                          第 5 周
   今天没课
   今天没课，好好休息
   内师课程表
   ```

   ⇒ **白卡没了，字全在**。日期/周次/「今天没课」判断/页脚四块都来自真机上那份真实课表
   （今天 10-04 是周日，导入的 22 门课确实没有周日课，所以「今天没课」是**正确**结果而不是失败）。
   想看有课的样子可以改用模拟器上的 `widget_render_e2e_test.dart`（注入两门课那条用例）。

### 9.14.8 教训

* **「日志说推送成功」不等于「界面对」**：`updateAppWidget` 不报错、宿主持有 RemoteViews、
  `dumpsys` 里 id 都绑好了，界面照样可以是白的 —— 因为**画不出来是在宿主进程里失败的**。
  这种「跨进程渲染」的问题，必须在**宿主那一侧**取证（`RemoteViews.apply()` 后读控件），
  光看自己进程的日志永远看不出问题。
* **宿主 inflate 用的白名单是真约束，不是建议**：`RemoteViews` 的注释里写得很清楚，
  但写布局时很容易顺手写个 `<View>` 当分隔条 —— 它在普通 Activity 里完全合法。
  凡是被 RemoteViews 承载的布局，都要按白名单挑控件（并写成测试）。
* **别让「查不到」的路径静默失败**：探针第一版把异常吞了，返回 `null`，于是只知道「没数据」；
  把异常打出来，一次就拿到 `Class not allowed to be inflated`。
  凡是「用来查问题」的代码，永远不要 catch 完就当没事。
* **解锁不了的手机别硬刚**：安全锁屏下 `adb shell input` 是解不开的（试过亮屏/MENU/上滑，
  `mDreamingLockscreen` 一直为 `true`）。**但也别就此认定它一直锁着** —— 后来一查
  `mCurrentFocus` 已经是桌面了（用户自己解锁过），白捡一张真机截图。取现前先问一次设备状态，
  别拿上几轮的结论当现在的事实。
* **设备会「吞日志」，所以证据不能只押在日志上**：这台 vivo 重装 1.1.9 之后不再输出我们的
  `NjtcWidget`/`flutter` 日志（buffer 里 277 行全是系统行）。跨进程渲染这种事，
  更硬的证据是**系统侧状态**（`dumpsys appwidget` 里 `views=` 对象的句柄变没变）与**屏幕截图**：
  广播前后句柄从 `@f8038c6` 变成 `@ee520b5`，比一万行日志都直接。

---

## 9.15 v1.1.10 —— 连堂课在课表上「只占一节」

### 9.15.1 现象与复现

用户 2026-10-04 反馈：**多节连堂的课在课表上只占用一节课的位置**。

先写「量尺寸」的用例把它钉在测试里，别靠眼睛猜（`test/timetable_grid_test.dart`
新增「连堂课块撑满所占节次」组）。改之前实测：

| 课程占用 | 卡片应有的高 | 实际画出来 |
| --- | --- | --- |
| 第 3-6 节（跨 4 小节） | 4 × 74 = 296 | **42 px** |
| 第 1-2 节（跨 2 小节） | 2 × 74 = 148 | **61 px** |

也就是说卡片高度几乎只跟**文字几行**有关，跟它占几节**完全无关** —— 连堂课当然看着「只占一节」。

### 9.15.2 根因

`lib/widgets/timetable_grid.dart` 的 `_buildDayColumn` 里，课程块是这么套的：

```
Positioned(top, left, width, height)   // height = (endSection-startSection+1) * sectionHeight ✅ 算得没错
  └─ Stack(children: [CourseCard, if (单双周) Positioned(角标)])
```

外层 `Positioned` 的高度是对的，坏在里层 `Stack` 用了**默认的 `StackFit.loose`**：
非定位子控件拿到的是「0..宽 × 0..高」的**松约束**；而 `CourseCard` 是
`LayoutBuilder → Container(不带宽高) → Column(mainAxisSize: min)`，于是它**按内容自适应**高度
（两三行字 ≈ 42~61px），把 `Positioned` 留出来的高度白白空着。

顺带说明这不是「本来就这么设计」：`timetable_grid.dart` 文件头第 6 行写着
「课程块按「跨了几节」撑高，不再是「第一节画卡片、后面画色块」」—— 意图如此，只是实现漏了这一层约束。

### 9.15.3 改法

`lib/widgets/timetable_grid.dart`：里层 `Stack` 加 `fit: StackFit.expand`（并留注释说明为什么不能省）。

```dart
child: Stack(
  fit: StackFit.expand,   // 不能省：默认 loose 会让 CourseCard 缩成内容高度
  children: [ CourseCard(...), if (p.course.oddEven != 0) Positioned(...) ],
),
```

`fit` 只作用于**非定位**子控件，右上角的单/双周角标是 `Positioned`，位置不受影响。

### 9.15.4 验证

* `test/timetable_grid_test.dart` 新增 3 条：跨 4 小节 = 296、跨 2 小节 = 148、
  并排冲突课各自撑满（并排时宽度均分）。
* `flutter analyze` → **No issues found**；`flutter test --reporter compact` → **126 用例全绿**（123 + 3）。
* **把真实课表渲染成 PNG 肉眼看一遍**：临时写了个 `test/zz_render_preview_test.dart`
  （用完即删），用 `XlsReader` + `TimetableParser` 读真实 `test/fixtures/njtc_sample.xls`，
  再 `RenderRepaintBoundary.toImage()` 导出 `screenshots/grid_span_fix_110.png`。
  图里每一块课程都**正好铺满它占的两行**（含右上角单双周角标），
  连堂「只占一节」的样子确实没了。
  （注意：widget 测试里的中文会渲染成方块，那是测试字体，不是 bug；这张图是用来看**版式**的。）
* 真机 1.1.10 装机核对：`adb install -r 内师课程表-1.1.10-arm64-v8a.apk` → `Success`，
  `dumpsys package` 显示 `versionCode=2012 versionName=1.1.10`；
  装机那一刻手机正在被用户使用（前台是 QQ），所以**没有强行切前台截图**，
  真机课表的目视确认留给用户（§9.15.5 记账一条教训：自动化验证也要挑不打扰用户的时机）。
* 构建：`D:\DSH\build_110.ps1` 跑完 `ALLDONE`，`D:\DSH\dist` 四个包
  `内师课程表-1.1.10-{universal,armeabi-v7a,arm64-v8a,x86_64}.apk`，
  `aapt2 dump badging` 核对 = **versionCode 12 / 1012 / 2012 / 4012，versionName `1.1.10`**，
  体积 53.64 / 16.72 / 18.95 / 20.39 MB；上一版四个 1.1.9 已移入 `D:\DSH\dist\old\`。

### 9.15.5 教训

* **「算对了」不等于「画对了」**：`_layout()` 的 span 计算没错，外层 `Positioned` 的高度也没错，
  可因为少了一个 `fit`，界面上就是错的。旧用例只断言「这门课出现了没有」，没人**量过尺寸**。
  UI bug 要用 `tester.getSize()` 量出来 —— 这类断言比 `findsOneWidget` 值钱得多。
* **Flutter 的约束默认是松的**：`Stack` / `Row` / `Column` 的非定位子控件都拿松约束，
  子控件自己不定尺寸就会「缩水」。要撑满得显式 `StackFit.expand` / `SizedBox.expand` /
  `CrossAxisAlignment.stretch`。
* **排过序的列表里别按下标认对象**：并排冲突那条断言我第一版用 `.first/.last`，
  而 `_layout` 是按「先 startSection 再 endSection」排过的，顺序和我写的相反；
  改成按课名 `find.ancestor(...)` 定位才稳。
* **自动化验证也要挑时机**：装完 1.1.10 想顺手截一张真机课表，结果 `am start` 之后
  前台还是用户正在用的 QQ —— 手机是用户的，别为了拿一张截图把人家的界面顶掉。
  这类「要占用用户屏幕」的取证，要么换成离线渲染（本轮就是这么做的：导出 PNG），
  要么当面问一句。

---

## 9.16 v1.1.11 —— 三个显示/提醒开关：周六日、非本周课程、法定节假日（含调休）

### 9.16.1 需求（用户 2026-10-04）

> 这个周六周日是否显示建议加一个开关，非本周课程是否显示也加一个开关，再设计一个
> 法定节假日关闭通知的开关（自行调整节假日以及调休时间）

三件事各自独立，但都要能持久化、都要立刻生效：

| 开关 | 默认 | 作用 |
| --- | --- | --- |
| 显示周六 / 周日 | 开 | 关掉后课表只画周一~周五五列 |
| 显示非本周课程 | 关 | 打开后把「本周不上」的课也画出来（半透明），方便看整学期分布 |
| 放假当天不提醒 | 开 | 放假日整天不排课程提醒；配套一份**可自行增删改**的节假日 + 调休补班日日历 |

### 9.16.2 显示开关：为什么画几列和布局分开

`lib/widgets/timetable_grid.dart` 里加了两个 `final bool`（`showWeekend` / `showInactiveCourses`，
都带默认值，老调用点不用改），并引入：

```dart
int get _visibleDays => widget.showWeekend ? days : 5;   // days 仍是 7
```

**只影响「画几列」，不影响 `_layout()` 的索引**（`_buildDayColumn(d)` 里的 `d` 依旧是
`0..6` 的星期下标）。这样避免了「下标要不要 −1」「今天高亮算第几列」这类换算错误 ——
换算只出现在一处：`_todayColumn` 末尾 `return col < _visibleDays ? col : null;`
（周末列被关掉时，今天若是周六/周日就不高亮，而不是高亮到一列看不见的地方）。

非本周课程用**半透明**表达而不是隐藏式灰掉：`_Placed` 增加 `final bool active`，
课程块外面套 `Opacity(opacity: p.active ? 1.0 : 0.35)`。点它仍然能看课程详情
（`onCourseTap` 不变），因为「非本周」不等于「这门课不存在」。

### 9.16.3 节假日日历：只列放假日，补班日留给用户

`lib/models/holiday_calendar.dart`（新）+ `lib/storage/holiday_store.dart`（新）：

* `HolidayCalendar{ holidays: List<HolidayDay>, makeups: List<MakeupDay> }`，
  两者都序列化成「一行一条」的纯文本（`2026-10-01|国庆节`、`2026-10-11|3|补周三的课`），
  存进 SharedPreferences 的两个键（`njtc_holidays` / `njtc_holiday_makeups`）。
* **两个键都不存在**才回落到 `HolidayCalendar.builtin()`（内置 13 天放假日）；
  用户把放假日**全删光**时读回来是**空的**，不会「你又给我恢复了」。
* 内置放假日是**估算值**（2026 中秋 9-25~27、国庆 10-01~07、2027 元旦 1-1~3）：
  这一轮 `web_search` 被限流（`firecrawl returned 429 … retry_after_seconds: 52765`），
  没能核对国务院通知，所以**补班日一条都不猜** —— 各校调休安排差别大，猜错会漏响或多响。
  用户可以在设置里自己加。
* 调休补班日的语义是「这一天按周几上课」：`MakeupDay(date, weekday, note)`，
  `weekday` 1~7（周一~周日）。

### 9.16.4 原生侧：钩子挂在 `computeInstances()` 里

`ReminderPlan` 增加三个带默认值的字段（不破坏老存档的解析）：

```kotlin
val skipHolidays: Boolean = true,
val holidays: Set<Long> = emptySet(),      // epochDay
val makeups: Map<Long, Int> = emptyMap(),  // epochDay -> 按周几上课
```

`ReminderScheduler.computeInstances()` 在算出 `isoDow`（这天本来是周几）与 `epochDay`
之后插入两条：

```kotlin
if (plan.skipHolidays && plan.holidays.contains(epochDay)) continue
val classDow = plan.makeups[epochDay] ?: isoDow
```

`dayCourses` 的过滤条件由 `c.dayOfWeek == isoDow` 改成 `c.dayOfWeek == classDow`。三个要点：

* **放假是整天 `continue`**：一节课都不排，连「下节课预告」也不会漏出去；
* **补班与开关无关**：`makeups` 是「学校安排今天上课」，即使把「放假当天不提醒」关掉，
  补班日也照样按映射的周几排（它本来就不是放假）；
* **两个钩子都在「排闹钟」这一层**，所以改日历之后必须**重新下发计划**才生效 ——
  `AppState.updateHolidays()` / `resetHolidays()` 都会走一遍 `syncReminders()`，
  而纯展示的 `updateDisplayPrefs()` 故意**不重排**（它跟闹钟没关系）。

### 9.16.5 页面

* 设置页（`lib/pages/settings_page.dart`）新增「课表显示」卡片（两个 `SwitchListTile`）
  与「法定节假日」入口（显示 `放假 13 天 · 补班 0 天 · 放假不提醒`）。
* 新页面 `lib/pages/holiday_settings_page.dart`（路由 `/holidays`）四块：
  「节假日关闭通知」开关、「调休补班日」（列表 + 添加）、「放假日」（列表 + 添加 + 恢复内置）、
  底部说明。添加补班日时若同一天已有放假日，会**移除那条放假日**并明确提示 ——
  否则「放假日优先」会让刚加的补班日看起来毫无效果。
* 提醒设置页也加了同一个入口（开关只在节假日页一处，避免两个看起来独立的开关）。

### 9.16.6 验证

* `flutter analyze` → `No issues found!`
* `flutter test --reporter compact` → **`+171: All tests passed!`**（126 → 171，新增 45 条）：
  `test/display_prefs_test.dart` 9 条、`test/holiday_calendar_test.dart` 约 20 条、
  `test/holiday_settings_test.dart` 9 条、`test/timetable_grid_test.dart` 新增 5 条
  （关掉周末只剩五列、非本周课半透明 0.35）。
* `gradlew :app:compileDebugKotlin` → `BUILD SUCCESSFUL`（**JDK 要用
  `C:\Program Files\Android\openjdk\jdk-21.0.8`**；PATH 上那个 JDK 25 会让 Gradle 直接失败）。
* **新增原生 E2E** `integration_test/holiday_reminder_e2e_test.dart`（模拟器 API 37，
  `flutter test integration_test/holiday_reminder_e2e_test.dart -d emulator-5554` → **`+1: All tests passed!`**）。
  课程只排第 2 周（今天那周），避免「一周一次」的重复把结论搅浑，三个场景的实测输出：

  ```
  [E2E] 今天=2026-10-04 明天=2026-10-05(周1) 后天=2026-10-06(周2)
  [E2E] 放假 → ok=true scheduled=0 next=- note=
  [E2E] 放假但开关关掉 → scheduled=3 next=2026-10-05(周一) 07:30
  [E2E] 无补班日 → scheduled=3 next=2026-10-06(周二) 07:30
  [E2E] 带补班日 → scheduled=6 next=2026-10-05(周一) 07:30 note=
  ```

  ⇒ 明天标成放假日时**一个闹钟都没有**（`scheduled=0`、`next=-`）；把开关关掉立刻回来
  （`next` 是明天 07:30）；补班日「明天按周二上课」让明天也多出 3 条提醒（3 → 6），
  且首个提醒从后天提前到明天。最后 `cancelAll()` 收尾，不在设备上留闹钟。

### 9.16.7 教训

* **「一周一次」的课会让放假日断言写歪**：第一版我把「明天放假 ⇒ `scheduled == 0`」当成
  必然，实测是 3 —— 因为课程每周都上，放假只跳过**那一天**，下一周的同一节照排
  （日志里 `next=2026-10-12(周一)` 直接点出来了）。改成「课程只排第 2 周」之后，
  这节课一周只有一次，`scheduled == 0` 才是这句话的正确写法。
  **写断言前先问一句「这个数是怎么来的」**，否则很容易把「正确的行为」判成 bug。
* **要证明「日历起了作用」，就得有对照组**：同一份计划关掉开关 → 3 条、开着 → 0 条，
  这才是因果；只有「放假时是 0」的话，也可能是别的原因导致 0。
  补班日同理：先跑一次**不带**补班日的（首个提醒 10-06），再跑带补班日的（首个提醒 10-05）。
* **平台默认值要写在 Kotlin 的 `data class` 上**：`skipHolidays = true` 这类默认值保证了
  「老存档 / 别的构造点」继续可解析；如果写成必填，旧版本的存档一读就崩。

## 9.17 v1.1.12 —— 法定节假日联网更新（用户 2026-10-04 追加）

### 9.17.1 需求与接口选型

用户的追加要求：「法定节假日要求联网更新」。起因是 9.16.3 里那份内置日历是**估算值**
（当初 `web_search` 被限流，从没核对过官方通知），所以必须有个「一键拉官方的」入口。

`Invoke-WebRequest` 实测三个免费接口：

* `https://timor.tech/api/holiday/year/2026`（**选中**）：无 key、一次拿全年、
  `holiday:true` = 放假 / `holiday:false` = 调休补班，补班还带 `after`（在假期**之后**
  还是之前）与 `target`（补的是哪个节）。实测 200 / 3431 字节。
* `https://timor.tech/api/holiday/info/2026-10-01`：单日查询，要按天循环，放弃。
* `https://api.apihubs.cn/holiday/get?year=2026&size=50`：字段是 `workday` /
  `holiday_legal` 那一套，语义要另外映射，放弃。

### 9.17.2 接口不给「补班那天按周几上课」，只能自己推

接口只说「10-10 是国庆后补班」，**不说那天按周几的课表上课**。而原生提醒的调休语义是
`makeups[epochDay] = 周几`（那天按周几上课）。于是写了
`deriveMakeupWeekday({date, after, holidayEpochDays})`：最多往回（`after:true`）或往前
（`after:false`）探 30 天，找到最近那段**连续假期**、展开整段，取段内工作日
（周一~周五）的**最后一个**（after）或**第一个**（非 after）。

2026 六条实测全对：`01-04→周五`、`02-14→周一`、`02-28→周一`、`05-09→周二`、
`09-20→周五`、`10-10→周三`。推不出来时（找不到假期、整段都在周末）返回 null，
调用方退回「这天真实的周几」，界面上也写明「按惯例推导，请按学校通知核对」——
宁给一个能用的默认值，也不要因为推不出来就干脆不提醒。

### 9.17.3 `merge`：只替换「联网真的覆盖到的年份」

联网有数据的年份**整年替换**，没数据的年份原样保留。实测：内置 13 天 + 2026 联网 33 天
⇒ **36 天**（2026 换成官方的 33 天；内置里 2027 元旦那 3 天留着，因为 2027 返回
`{"code":0,"holiday":{}}`）。这样用户手动加的下一年校历不会被冲掉。

`countDropped(base, fetched)` 顺带算出「会被冲掉几条」，用于覆盖前提醒。

### 9.17.4 启动静默同步 + 30 天节流 + 测试环境不联网

`AppState.init()` 末尾（`unawaited(WidgetService.sync(...))` 之后）：

```dart
if (HolidaySyncService.autoSyncEnabled && _shouldAutoSyncHolidays()) {
  unawaited(syncHolidaysFromNetwork(silent: true));
}
```

* `autoSyncEnabled` = 非 Web 且（`forceAutoSync` 或 `Platform.environment['FLUTTER_TEST'] != 'true'`）
  —— 别让 `flutter test` 打真网络，测试全部走 `getOverride` 打桩；
  `@visibleForTesting static bool forceAutoSync = false;` 是给「启动时到底会不会静默同步」
  这类用例用的（默认 false，测试里显式打开）。
* `_shouldAutoSyncHolidays()` 的判据（**顺序很重要**）：
  1. `source == manual` → **false，绝不自动覆盖**；
  2. `source != net`（也就是内置估算值）→ true；
  3. 没有更新时间 → true；
  4. 距今超过 30 天 → true，否则 false。
* ⚠️ **静默同步也必须 `await syncReminders()`**：新拿到的放假日要真的从闹钟里去掉，
  否则会出现「界面显示放假了、闹钟照响」。
* `debugPrint('HolidaySync: ok=… note=… 放假=N 补班=M silent=…')` 是**真机取证的唯一线索**：
  装完之后 `adb logcat -s flutter` 能看到这次联网到底成不成。

### 9.17.5 失败不是异常，是返回值里的 note

`HolidaySyncService.update()` **从不抛异常**，一律返回
`HolidaySyncOutcome(ok, calendar, note, years)`：超时 / 无网 / HTTP != 200 / 不是 JSON /
`code != 0` → `ok:false` + 中文 note；两年都返回空（还没公布）也是 `ok:false`，
note 是「接口还没公布 2026、2027 年的放假安排」。界面据此显示
「联网更新失败：…（日历保持原样）」。网络是外部依赖，让 UI 去 catch 异常不如让服务
把「为什么没成功」当成返回值。

### 9.17.6 界面

节假日页顶部新增「联网更新」卡片：

* 来源行：`内置估算值，建议联网更新` / `来自联网更新（10月4日 16:20）` /
  `手动调整过，未联网核对`，后面跟 ` · 放假 N 天 · 补班 M 天`。
* 「立即联网更新」按钮，转圈时禁用（`_syncing`）。
* **手动改过之后再联网会先问一句**：「联网更新会按年份整年替换现在的日历，你手动加/改过
  的条目可能被覆盖。继续？」——因为整年替换确实会冲掉用户自己加的日子。

`holiday_store.dart` 因此多了来源信息：`njtc_holiday_source`（`builtin` / `net` / `manual`）
与 `njtc_holiday_updated_at`，`clear()` 连它们一起删。

### 9.17.7 验证

* `test/holiday_sync_test.dart`（**16 用例**，夹具是**真实返回体**
  `test/fixtures/holiday_2026.json` = 33 天放假 / 6 天补班，另有 `holiday_2027.json` 空年份）：
  解析、补班推导、同日既放假又补班只留放假、merge 的年份边界、countDropped、
  update 的「网络失败 / code≠0 / 未公布 / 全拿到」四种结局、`yearsFor` 跨年。
* `test/holiday_settings_test.dart` 新增 **4 个用例**：卡片文案、点按钮后来源变 net 且天数变
  `放假 36 天 · 补班 6 天`、失败时日历不动 + SnackBar、手动改过后二次确认（取消 / 继续两条路）。
* `test/holiday_sync_test.dart` 末尾再补 **5 个 AppState 用例**（`forceAutoSync` + `getOverride`
  打桩，验的就是「启动时到底会不会静默同步」）：从没同步过 → 换成官方 36 天并落盘；
  **手动改过 → 一次接口都不打、用户那份日历原样留着**；30 天内同步过 → 不打；
  40 天前同步过 → 会再打一次；`autoSyncEnabled` 在测试环境为 false。
* **设备级实测（真网络，没有打桩）**：
  * 模拟器（API 37，`内师课程表-1.1.12-x86_64.apk` / code 4014）：卸载重装（全新存档）→
    冷启动 → `HolidaySync: ok=true note=2026 年 放假=36 补班=6 silent=true`。
  * 真机 vivo V2520A（`10CG681D4N004KB`，**升级覆盖安装**，课表与设置保留，
    `versionCode=2014`/`versionName=1.1.12`）→ 启动 → 同一行日志，
    说明这是**真机上真的走通了 HTTPS**，不是打桩。
* `flutter analyze` → **No issues found!**；`flutter test --reporter compact` →
  **`+196: All tests passed!`**（171 → 191 → 196）。

### 9.17.8 教训

* **第一版断言把 36 写成了 33**：merge 是「按年份替换」，内置里 2027 那 3 天不属于被覆盖的
  年份，所以结果是 33 + 3。**算期望值要按「哪些会被替换」，不是按「联网给了多少」**。
* **同一段文案出现两次会让 `findsOneWidget` 失败**：卡片副标题与 SnackBar 都含
  「放假 36 天 · 补班 6 天」，对话框与卡片说明都含「整年替换」。断言「出现过」用
  `findsWidgets`，要精确就断言完整串。
* **`const HolidayDay(DateTime(...))` 编不过**：`DateTime` 不是 const 构造，
  位置参数构造器外面不能加 `const`（编译期直接报 `Cannot invoke a non-'const' constructor`）。
* **纯函数 + 打桩取数是最划算的测法**：解析 / 推导 / 合并全做成纯函数，网络那层只留一个
  `@visibleForTesting static Future<String> Function(Uri)? getOverride`，16 个用例 1 秒跑完，
  一个真网络请求都不打。
* **「启动时静默同步」差点把用户手动改的日历冲掉**：来源字段一开始只用于**显示**，
  而 `_shouldAutoSyncHolidays()` 写的是「来源不是 net 就同步」——`manual` 也不等于 `net`，
  于是用户手动加/删过的日历会在下次启动被悄悄换掉。**记录来源的字段，就要真的拿它做判断**；
  现在的判据第一条就是 `source == manual → false`，想强制更新只能点页面上的按钮
  （那里有二次确认）。这是写设备验证时顺手复查逻辑才发现的，不是测试报出来的。
* **测试环境开关要做成显式的**：`autoSyncEnabled` 在 `flutter test` 下恒为 false 是对的
  （不能打真网络），但那样「启动到底会不会同步」就永远测不到；用一个
  `@visibleForTesting static bool forceAutoSync` 把它分成「环境默认」与「用例强制」两层，
  5 个 AppState 用例才写得出来。

---

## 9.18 v1.1.12 发布：推到 GitHub + Release 挂四个 APK（用户 2026-10-04 追加）

用户追加了两次要求：「推送到我的github仓库」、「apk也挂上去」。仓库是
<https://github.com/Sirin-NJTC/njtc_schedule>（已由用户改成**公开**），默认分支 `main`。

### 9.18.1 结果

* 代码：第一条提交 `21d855f`（v1.1.3 时代）之后，本次提交 **`44b920c`**
  「v1.1.12：网页导入修好、桌面小组件修好、三个显示/提醒开关、法定节假日联网更新」
  （41 个文件：21 改 + 20 新增），再一条 **`aec581f`** 加 CI 工作流；`git push origin main` 成功，
  仓库跟踪文件 95 → **116**。
* Release：<https://github.com/Sirin-NJTC/njtc_schedule/releases/tag/v1.1.12>
  （annotated tag `v1.1.12` → commit `aec581f77bd13daeac7bd4bae44c3390eb22fbac`），
  **release id = 402942296**，说明文字来自 `D:\DSH\release_notes_v1.1.12.md`，**4 个资产**：

  | Release 上的资产名 | 本地 dist 文件 | 字节数 |
  | --- | --- | --- |
  | `njtc-schedule-1.1.12-arm64-v8a.apk` | `内师课程表-1.1.12-arm64-v8a.apk` | 20,334,222 |
  | `njtc-schedule-1.1.12-armeabi-v7a.apk` | `内师课程表-1.1.12-armeabi-v7a.apk` | 18,087,000 |
  | `njtc-schedule-1.1.12-x86_64.apk` | `内师课程表-1.1.12-x86_64.apk` | 21,899,913 |
  | `njtc-schedule-1.1.12-universal.apk` | `内师课程表-1.1.12-universal.apk` | 57,781,343 |

  四个都 `state=uploaded` 且**服务端字节数与本地逐字节一致**；不带令牌的匿名 `HEAD` 请求
  返回 `200 / Content-Length=20334222 / Content-Type=application/vnd.android.package-archive`，
  说明别人（同学）能直接下载。

### 9.18.2 资产名为什么是 ASCII（`njtc-schedule-<ver>-<abi>.apk`）

第一次上传时脚本用的是中文名 `内师课程表-1.1.12-arm64-v8a.apk`，并且做了
`[uri]::EscapeDataString($n)`。结果服务端收到的是 **`-1.1.12-arm64-v8a.apk`** ——
中文**整段消失**（不是乱码、不是报错），四个资产全掉前缀，下载链接变成
`.../download/v1.1.12/-1.1.12-arm64-v8a.apk`。

原因：资产名是通过 URL query（`POST <upload_url>?name=<...>`）传的，Windows PowerShell 5.1 的
`HttpWebRequest` 在拼这种带非 ASCII 的 URL 时把这段丢了。**结论：Release 资产名一律用 ASCII，
在脚本里做「本地中文名 → 上传 ASCII 名」的映射**（`D:\DSH\github_release.ps1` 的 `$assets` 表）。
本地 `D:\DSH\dist\内师课程表-*.apk` 保持中文名不动，只影响上传那一步。

另外一个坑：修名字那一轮脚本先「清掉不在预期名单里的 `.apk`」，日志说清了 4 个，实际只删掉 1 个
（那一行把 4 个名字打印在同一行，说明循环里 `$a` 拿到的是**整份资产数组**而不是单个元素）。
最后是按 asset id 逐个 `DELETE` + 重新 `GET /releases/<id>/assets` 复核，才拿到干净的 4 个。
**教训：批量删除之后必须重新拉一遍清单确认，别信循环里打印的那一行。**

### 9.18.3 fine-grained 令牌踩了三次（重要）

用户先给了一个 fine-grained PAT，三次都没写权限，每次现象不同：

| 情况 | 现象 | 含义 |
| --- | --- | --- |
| 仓库还私有时，令牌用默认的 `Public repositories` 模式 | `GET /repos/Sirin-NJTC/njtc_schedule` = **404** | 404 而不是 403 = 这个令牌**根本看不见**这个仓库 |
| 仓库改公开后 | 读接口全 200，但 `POST /repos/{o}/{r}/git/tags` 与 `POST /repos/{o}/{r}/releases` = **403** `{"message":"Resource not accessible by personal access token"}` | 看得见、但只有只读权限 |
| 用户说「改好权限了」后再探 | 仍 403 | fine-grained 令牌在 `Public repositories` 模式下 GitHub **只给只读**，必须改成 `Only select repositories` + 显式把 `Contents` 设成 `Read and write` |

* **别拿 `GET /repos/...` 返回里的 `permissions.push=true` 判断令牌**：那反映的是**用户**在该仓库的
  角色（owner 当然 true），跟令牌作用域无关。
* **判令牌有没有写权限，干净的探针是 `POST /repos/{o}/{r}/git/tags`**：成功会创建一个游离 tag 对象，
  不改分支、不留可见痕迹；403 就是没写权限。
* 用户最后给了 classic 令牌（勾 `repo`），第一次探针就 `CONTENTS-WRITE: OK`，后面才跑通。
* 令牌是用户贴在聊天里的明文，**用完建议去 GitHub 设置里撤销/轮换**。

### 9.18.4 中途那条 GitHub Actions 路线（留着，以后打 tag 会自动出包）

拿不到写权限时改走 CI，文件在 `.github/workflows/release.yml`（提交 `aec581f`）：
`on: push: tags 'v*'` + `workflow_dispatch`，`permissions: contents: write`，
setup-java temurin 21、`subosito/flutter-action@v2` 固定 `flutter-version: 3.47.6`，
跑 `flutter analyze` → `flutter test --reporter compact` → `flutter build apk --release --split-per-abi`
→ `flutter build apk --release` → `softprops/action-gh-release@v2` 把
`app-{arm64-v8a,armeabi-v7a,x86_64}-release.apk` 与 `app-release.apk` 传成 Release 资产。

* **tag 触发的工作流必须已经存在于被 tag 的那个提交里**，否则推 tag 不会触发任何东西。所以
  push 工作流之后要：`git tag -d v1.1.12`（删本地）→ `git tag -a v1.1.12`（在含工作流的新提交上重建）
  → `git push origin :refs/tags/v1.1.12`（删远端旧 tag）→ `git push origin refs/tags/v1.1.12`
  （这次才等同「新建 tag」，才触发工作流）。
* 工作流确实跑起来了：run #1「发布 Release」，event=push、ref=v1.1.12、head=`aec581f`，
  run id **37192180760**。但拿到 classic 令牌后改回本地直传，用
  `POST /actions/runs/37192180760/cancel` **把它取消了**，免得 CI 再构建出另一套 `app-*.apk`
  跟本地实测过的包装进同一个 Release。工作流文件留在仓库里，以后推 tag 就能自动出包
  （注意 CI 出的包名是 `app-*.apk`，与本地的 `njtc-schedule-*.apk` 不同名）。

### 9.18.5 PowerShell 5.1 上的两个坑（脚本必须绕开）

* **`$ErrorActionPreference='Stop'` 会让 git 的正常提示变成致命错误**：`git push` 往 stderr 写
  `Everything up-to-date`、`warning: LF will be replaced by CRLF` 时会被包成 `NativeCommandError`，
  脚本直接在 push tag 那步死掉。解法：调 git 时临时 `$ErrorActionPreference='Continue'`、
  `2>&1 | Out-String` 收输出，然后自己看 `$LASTEXITCODE` 是否 0。
* **脚本刻意不用 `param()`**：因为统一用
  `Invoke-Expression (Get-Content -Raw -Encoding UTF8 '<path>')` 执行（避免 PowerShell 5.1 把内联
  中文/全角括号搞乱），带 `param()` 的脚本在这种执行方式下参数不好传；改成「从 `$env:GH_PAT`
  或已有变量取默认值」。

## 9.19 出厂作息换成学校统一作息（2026-05-06 起）+ 一轮代码优化

#### 9.19.1 作息改了什么

依据教务处《关于执行全年统一作息时间的通知》（2026-04-29 发布，自 2026-05-06 起执行）。
每节仍是 45 分钟，上午第 2 节后与下午第 2 节后各有一段大课间休息。

| | 旧（2026-05-06 前） | 新 | 变化 |
| --- | --- | --- | --- |
| 上午 1-4 节 | 08:00 / 08:55 / 10:00 / 10:55 | 08:20 / 09:15 / 10:20 / 11:15 | 整段后移 20 分钟 |
| 下午 5-8 节 | 14:30 / 15:25 / 16:30 / 17:25 | 14:20 / 15:15 / 16:20 / 17:15 | 整段提前 10 分钟 |
| 晚上 9-11 节 | 19:00 / 19:55 / 20:50 | 19:00 / 19:55 / 20:50 | 不变 |

一共要动四个地方，**漏一个就会显示两套时间**：
`lib/models/period.dart` 的 `defaultPeriods`、
`android/.../widget/WidgetData.kt` 的 `DEFAULT_PERIODS`（Kotlin 没同步过数据时的兜底）、
`preview.html` 的 `PERIODS`、以及下面这条最容易漏的版本号。
`widget_today_preview.xml` 与 `tool/make_widget_preview.py` 是「添加小组件」面板上的静态示例，
也一并同步了（`drawable-nodpi/widget_preview.png` 需重跑脚本重新生成）。

#### 9.19.2 最隐蔽的坑：改默认值对老用户**不生效**

`AppState.init()` 是「存档存在就用存档，没有才用默认」。所以老用户只要打开过
「设置 → 节次时间」并点过保存（哪怕一个字没改），本地就躺着一份旧作息存档，
升级后它会继续挡着新的 `defaultPeriods` —— **课程提醒会一直按已经作废的时间响**，
而且界面上看起来一切正常，极难发现。

解法是给存档加版本号：`PeriodStore.currentVersion`（改出厂作息时 +1）。`load()` 时若
`version < currentVersion` 且存档与 `legacyDefaultPeriods`（旧出厂默认）**逐节相同**，
说明用户只是原样保存过、并没真调过 → 返回 null 让它回落到新作息；
对不上的（用户真改过）原样保留。**判断基准 `legacyDefaultPeriods` 不能删。**

#### 9.19.3 周次算法有三份，其中一份没做日期归一化（真 bug）

同一件事在三处各写了一遍：

* `AppState._autoDetectWeek`：`now.difference(start).inDays ~/ 7 + 1` —— 用了带时分秒的 `now`
* `HomePage._realWeek`：`today.difference(first).inDays ~/ 7 + 1` —— 已归一化到当天
* `TimetableGrid._todayColumn`：又抄了一遍归一化版

之前没炸纯属运气：所有写 `startDate` 的地方（解析器、日期选择器）都填的是当地午夜，
`difference().inDays` 截出来刚好等于日历天数差。但只要 `startDate` 带上时间分量，
第一处每跨一天的头几小时就会少算一天 —— **「初始周」偏一天，且网格高亮的今天和
「回到本周」跳的周不是同一周**。

修法：抽 `lib/models/semester.dart` 的 `weekOfSemester()`（内部用 `epochDayOf` 相减），
三处全部改为调用它。这也正好补上了红线第 1 条一直在强调、偏偏这几处没遵守的
「算天用 epochDay」。新增 `test/semester_test.dart` 把它钉死，含一条针对性回归用例。

> ⚠️ 顺带一个发现：**`flutter test` 跑在 UTC 时区下**。回归用例原本写成
> `DateTime.parse('2026-08-31T00:00:00.000Z')` 再断言 `hour == 8`（东八区下成立），
> 实测却是 0，用例直接红。改成 `DateTime(2026, 8, 31, 8, 0)` 本地构造才稳定 ——
> 以后写时间相关用例**不要依赖运行环境的时区**。

#### 9.19.4 「课堂倒计时」和「当前时间线」其实是冻结的

`lib/` 全目录原先没有任何 `Timer` / `Stream`，而这两个功能都需要随时间推进：
`_buildCountdown()` 和 `_nowLineY()` 都只在 `build()` 里读一次 `DateTime.now()`。
App 开着两小时，倒计时仍显示开屏那一刻的读数，红线也停在原位 —— README 却宣传了这两项。

加了 `lib/widgets/minute_ticker.dart`（对齐到下一个整分、`resumed` 时校准一次）：

* **刻意做成局部 builder**，只包住倒计时那一小块和时间线那一条。
  若让首页整体计时重建，每分钟都会把整张课表网格连同布局算法重排一遍。
* 测试环境自动关掉定时器（读 `FLUTTER_TEST` 环境变量，与 `HolidaySyncService` 同一约定），
  否则 `Timer.periodic` 会把 `pumpAndSettle()` 拖到超时 —— 和
  `_syncAfterChange` 故意不 await `WidgetService.sync` 是同一个坑。
* 时间线用 `Positioned.fill` + `Transform.translate` 而不是直接改 `Positioned` 的 `top`：
  **Stack 只认直接的 `Positioned` 子节点**，中间隔一层 `MinuteTicker` 就不当定位元素了，
  会整块跑到左上角去。

#### 9.19.5 顺手修的小问题

* `AppState.init()` 把全部课表 JSON **解析了两遍**（`loadActive()` 内部又调一次 `loadAll()`），
  而 `getActiveId()` 早就写好了却从没被调用过（全仓零引用）。改成取 id 后在已加载列表里找。
* `home_page.dart` 四个方法签名写的是 `dynamic tt`，放着现成的 `Timetable` 不用 ——
  字段写错只有运行时才发现、IDE 重构失效，这也是 `_realWeek` 能和 `_autoDetectWeek`
  悄悄漂移的原因之一。`analyze` 对 `dynamic` 不报警，所以这条藏得住。
* `removeTimetable()` 换成备选课表时漏了 `_autoDetectWeek()`（`setActive()` 里是有的），
  新课表 `totalWeeks` 更小时 `_currentWeek` 会停在越界的周；
  另外删空后没清激活记录，留了个指向不存在课表的 id（补了 `TimetableStore.clearActive()`）。

#### 9.19.6 一个被否掉的改动：给网格布局加缓存

本来打算按 `(课表, 周次, 显示开关)` 缓存 `_layout()` 结果以配合每分钟刷新。做完发现两件事，
于是**撤掉了**：

1. `Timetable` 是可变对象，`updateTimetable(tt)` 传进来的常常是同一个实例，
   靠 `identityHashCode` + 课程条数做指纹会在「改了某门课的时间但课程数不变」时漏掉失效，
   **课表改了网格却不刷新** —— 为省一点 CPU 引入这种 bug 不划算。
2. 更关键的是重新推演后发现**缓存本来就不必要**：`MinuteTicker` 的 `setState` 只重建
   它自己那棵子树，并不会带动 `TimetableGrid` rebuild；全量重排本来就只在
   切周 / 改课表 / 切显示开关时发生，都是低频操作。

教训：加缓存前先确认「重建到底是谁触发的」，局部 ticker 不会向上冒泡。

#### 9.19.7 验证

* `flutter analyze` → **No issues found!**
* `flutter test` → **210 个用例全部通过**（原 196 + 新增 14：
  `semester_test.dart` 10 条、出厂作息升级迁移 3 条、原有用例改断言 1 条）
  —— 这是**当时**的数；后续 9.20、9.21 又加了用例，当前总数为 229。
* 受影响的 `period_settings_test` / `widget_service_test` / `timetable_grid_test` /
  `home_page_test` / `app_flow_test` 均单独跑过。
* ⚠️ 提醒相关的**原生 E2E 没跑**（需要真机 / 模拟器）。作息时间直接影响
  `ReminderScheduler` 的排布结果，发布前建议在模拟器上补跑
  `integration_test/reminder_e2e_test.dart` 与 `holiday_reminder_e2e_test.dart`。

## 9.20 v1.1.13 —— 桌面小组件节假日感知 + 收尾

> 9.18 / 9.19 的优化（统一周次算法、解冻倒计时、出厂作息迁移、节假日日历）都还在
> `1.1.12+14` 的代码基上，这一版正式把版本号抬到 `1.1.13+15`，并补齐一处遗漏：
> **原生桌面小组件此前完全不知道节假日**，放假那天仍会把课画到桌面上。

### 9.20.1 桌面小组件也要「放假不画课」

首页课表与倒计时已经在 9.19 里接了 `HolidayCalendar`，但原生小组件走的是
`WidgetBridge` → `NjtcWidgetStore` → `WidgetData.build` 这条**不依赖 Flutter** 的链路，
之前只推了课表和节次时间，没推节假日。本次补全：

* `WidgetService.sync` 新增 `holidays` 参数，把 `HolidayCalendar` 序列化成
  `{"h":[{"e":epochDay,"n":"名称"}, …], "m":[{"e":epochDay,"w":周几,"n":"备注"}, …]}` 一并下发
  （用 epochDay 而非日期串，与原生侧 `todayEpochDay` 用同一套 UTC 天数算法）。
* `NjtcWidgetStore` 新增 `holidays` 字段持久化；`WidgetBridge` 透传。
* `WidgetData.build` 解析后：放假日直接返回「今天放假 · <名称>」且**不画任何课**；
  调休补班日按 `w` 指定的周几排课，并在页脚标注「补周X · …」。

三条 `sync` 调用点（启动、课表变更、设置页手动同步）都已传入 `state.holidays`。
未推送过节假日时（老存档 / 测试环境）行为与旧版完全一致。

### 9.20.2 验证

* `flutter analyze` → **No issues found!**
* `flutter test` → 全量用例通过（`widget_service_test` 新增「节假日日历随 sync 下发」断言）。
* 原生侧 Kotlin 改动属逻辑补全，建议发布前在真机 / 模拟器上确认：放假当天桌面组件不显示课程、
  调休补班当天显示对应周几的课程。

* 版本：`pubspec.yaml` `1.1.13+15`，`settings_page.dart` 关于页 `v1.1.13`。

## 9.21 v1.1.14 —— 改日历漏推桌面小组件（回归修复）+ 倒计时跨长假期

> 起因：v1.1.13 发布后用户让另一个 agent 又改了一轮，回来要求核对。复查发现两处问题：
> 三处改日历的路径**都没把新日历推给原生小组件**（发布出去才暴露的回归），
> 以及 `nextClassOccurrence` 的扫描窗口只有 8 天，长假结束后首页会整段空白。

### 9.21.1 改日历不推小组件（v1.1.13 带出来的真 bug）

v1.1.13 给 `WidgetService.sync` 加了 `holidays` 参数，并声称「三条调用点都传了」——
实际传的只是**课表变更**那条路径。另有三处会改 `_holidays`：

* `AppState.updateHolidays()`（设置页手动改 / 导入）
* `AppState.resetHolidays()`（恢复内置日历）
* `AppState.syncHolidaysFromNetwork()`（启动时的静默联网同步）

它们此前只调 `syncReminders()`，于是桌面小组件继续拿**旧日历**画：放假那天照样把课画出来，
补班日照旧按原来的周几画。手动点「立即联网更新」之所以看起来正常，是因为设置页那条路径
自己又单独调了一次 `sync`，把漏掉的那次掩盖过去了。

修法：把「推小组件」收敛成一个私有出口，凡是动了课表 / 节次 / 日历的地方都从这一个口出去：

```dart
void _pushWidget() {
  // 故意不 await：widget 测试里没桩时那个 Future 会一直挂着，
  // 一 await 就把 pumpAndSettle() 拖死（和 _syncAfterChange 是同一个坑）。
  unawaited(WidgetService.sync(timetable: _active, holidays: _holidays));
}
```

`updateHolidays()` / `resetHolidays()` / `syncHolidaysFromNetwork()`（**静默同步也要推**，
它不走 `notifyListeners`）以及 `init()` 全部改走它；`_syncAfterChange()` 也改成先推小组件
再排提醒。

回归用例（`test/holiday_sync_test.dart` 新 group「日历变了就要推给桌面小组件（回归：曾经漏掉）」）：
mock 掉 `cn.edu.njtc.njtc_schedule/widget` 通道收集 `update` 调用，三条分别断言
手动改日历 / 恢复内置 / 静默联网之后收到的 `h`、`m` 载荷（联网那条断言 36 天放假、6 天补班）。

### 9.21.2 长假之后首页什么都不显示

`nextClassOccurrence` 的窗口是 `scanDays = 8`（含今天，即只看 7 天）。春节 / 国庆叠中秋
这类假可以连放 9 天以上，会把窗口整段盖住 → 返回 null；旧代码此时直接 `SizedBox.shrink()`，
于是**整个假期首页那块都是空的**，用户看不出发生了什么。

* 窗口放宽到 **21 天**（3 周足够跨过最长假期；越界只会多扫几天，代价可以忽略）。
* 找不到下一节课时不再什么都不显示：如果今天正是放假日，就显示「今天放假 · <节假日名>」
  （新的 `_buildCountdownIdle`），与网格表头、桌面小组件同一套说法；其余情况
  （学期没开始 / 学期结束 / 课表本来就没课）保持原样什么都不显示。
* 顺手修 `_dayLabel`：间隔 ≥ 3 天的现在写成「M月D日 周X」——长假之后只写「周一」，
  根本看不出是哪一周。

回归用例：`test/semester_test.dart` 加「连放 9 天假（春节那种）也能找到假期后的第一节课」
（带 `scanDays: 8` 的对照组，钉住「窗口必须够长」这条）；`test/home_page_test.dart`
加两条 widget 用例（放假且无课 → 「今天放假」；放假但下周有课 → 报下一节课且带日期）。

### 9.21.3 文档里的测试数字过时

`README.md:143`、`README.md:417`、`AGENTS.md:4`、`AGENTS.md:15` 都写「210 个用例」，
而 v1.1.13 提交时实际已经是 223 条。同一个数字散在四处就一定会漂，本次一并改为 **229**。
`CHANGELOG.md` 里 v1.1.12 那条「详见 9.18 / 9.19」也指错了章节（9.18 是发布流程、
9.19 属于 v1.1.13），已改为 9.17 / 9.18。

### 9.21.4 原生 E2E 里的时间写死了（v1.1.13 埋的，本轮才发现）

`integration_test/reminder_e2e_test.dart` 断言「明天上午第 1 节的时段预告 = `07:30`」，
这一串时刻（`7:30 / 7:45 / 7:55 / 8:50 / 9:35 / 9:55`）是 **08:00 那套旧作息**算出来的。
9.19 把第 1 节挪到 **08:20** 之后，真实值变成 `07:50 / 08:05 / 08:15 / 09:10 / 09:55 / 10:15`，
断言必然失败——但 `flutter test` **不会跑 `integration_test/`**，
所以这十条断言从 v1.1.13 起就一直红着没人知道（`AGENTS.md` 里「动了提醒排程要跑 E2E」那条，
当时改作息的人没执行）。

修法不是把数字改成 07:50（下次再改作息还会歪），而是**从节次时间推导**：

```dart
// 断言里的时间一律从节次时间推导（periodOfSection），不要写死 07:30 这种字面量
DateTime _startAt(int section, DateTime day) { … }
String _before(DateTime t, int minutes) => _hm(t.subtract(Duration(minutes: minutes)));
…
expect(preview[0].timeText.endsWith(_before(aStart, 30)), isTrue);
expect(preview[1].timeText.endsWith(_before(aStart, 15)), isTrue);
expect(preview[3].timeText.endsWith(_before(a2Start, 5)), isTrue);
expect(preview[4].timeText.endsWith(_before(a2End, 5)), isTrue);   // 下课预告
expect(preview[5].timeText.endsWith(_before(bStart, 5)), isTrue);
```

**教训**：凡是「用户可配置的默认值」（作息时间、提前分钟数、节假日）都不该在测试里写字面量；
再就是 `integration_test/` 不在 `flutter test` 的范围内，**改完作息必须手动跑一遍这三条原生 E2E**
（`reminder` / `holiday_reminder` / `widget_render`），否则红了也看不见。

同批核对：`integration_test/holiday_reminder_e2e_test.dart` 只用 `_dateText(tomorrow)` 比对日期、
不比时刻，所以不受作息变更影响；`widget_render_e2e_test.dart` 两处新增用例也不写时刻。

### 9.21.5 CI 出包的资产名也统一成 ASCII

v1.1.13 的 Release 里资产叫 `app-arm64-v8a-release.apk` 这种 Gradle 原始名，跟本仓库
`README.md` / `AGENTS.md` 里约定的 `njtc-schedule-<版本>-<abi>.apk` 不一致，用户下载时也分不清
哪个是哪个。`.github/workflows/release.yml` 里加了一步「统一资产名（ASCII）」：
从 `pubspec.yaml` 取版本号（不依赖 tag 名，`workflow_dispatch` 手动跑也对），把四个产物
`mv` 成 `njtc-schedule-<ver>-{arm64-v8a,armeabi-v7a,x86_64,universal}.apk` 再上传，
`files:` 用通配符匹配、`fail_on_unmatched_files: true` 兜底。
**别在 GitHub 上给 `v1.1.13` 补传**（它已经带着那个 85 MB 的 debug 包了），本轮直接发 `v1.1.14`。

另外 `v1.1.13` 的 Release 里那个 `app-arm64-v8a-debug.apk` 不是 CI 传的（`release.yml` 只列了
`*-release.apk`），是手工传包时把 `build/app/outputs/flutter-apk/` 下的 debug 产物也带上了——
**手工传包前先看清文件清单**。

### 9.21.6 验证

* `flutter analyze` → No issues found!
* `flutter test` → **229 条全绿**（v1.1.13 的 223 + 本次新增 6）。
* 原生 E2E（模拟器 `Medium_Phone_API_37.0` / `emulator-5554`，API 37）：
  * `widget_render_e2e_test.dart` → **4 条全过**，探针里的放假/补班输出：
    `{"footer":"今天放假 · 国庆节","rows":[]}`、`{"footer":"补周一 · 共 1 门…","rows":["10:20-12:00 被补出来的课@明德楼A203"]}`。
  * `reminder_e2e_test.dart` → **1 条全过**（修掉 9.21.4 的写死时刻之后），
    实测 `next=2026-10-08(周四) 07:50`、`scheduled=12`、`exact=true`。
* 版本：`pubspec.yaml` `1.1.14+16`，`settings_page.dart` 关于页 `v1.1.14`。
* 本地四个包（`D:\DSH\build_v114.ps1`，aapt2 校验过 `versionName=1.1.14`）：
  universal 55.17 MB / code 16，armeabi-v7a 17.25 MB / 1016，arm64-v8a 19.45 MB / 2016，
  x86_64 20.89 MB / 4016。

### 9.21.7 推送与 CI 出包（v1.1.14 已发布）

* 提交 `909e615`（15 文件、+595/−42）→ `git push origin main`（`4992760..909e615`）；
  再推 annotated 标签 `v1.1.14`，触发 GitHub Actions
  [run 37577079553](https://github.com/Sirin-NJTC/njtc_schedule/actions/runs/37577079553)
  → `success`，13 个步骤全绿（含新增的「统一资产名（ASCII）」那一步）。
* Release [v1.1.14](https://github.com/Sirin-NJTC/njtc_schedule/releases/tag/v1.1.14)（id 405418137）
  **正好 4 个资产、没有 debug 包**：
  `njtc-schedule-1.1.14-universal.apk` 55.18 MB、`-arm64-v8a.apk` 19.45 MB、
  `-armeabi-v7a.apk` 17.26 MB、`-x86_64.apk` 20.89 MB（CI 与本地体积略有出入属不同构建环境，正常）。
* 匿名 `HEAD` 验证下载地址可用：
  `…/releases/download/v1.1.14/njtc-schedule-1.1.14-arm64-v8a.apk` → `200`、
  `Content-Length=20399694`、`Content-Type=application/vnd.android.package-archive`。
* 纯文档提交（如本段）不会触发 `release.yml`——它只认 `v*` 标签；标签仍指向 `909e615`。
* 出包当时是**没有真机**的（构建、E2E 全在模拟器 `Medium_Phone_API_37.0` 上跑，
  vivo 手机 `10CG681D4N004KB` 没插）；后来手机插上了，补做了真机验证，见 9.21.8。

### 9.21.8 真机验证（vivo V2520A / Android 17）

1.1.14 装到真机上跑了一遍，**没有发现新 bug**，三条改动都拿到了真机证据。

* 装机：`adb install -r 内师课程表-1.1.14-arm64-v8a.apk`，
  `versionCode 2014 → 2016`、`versionName 1.1.12 → 1.1.14`，
  **课表、学期起始日期、开关状态全都保留**（没有走卸载安装）。
* 启动顺序就是这次要修的那件事，logcat 原文：
  ```
  NjtcWidget: 渲染#32 10月7日 周三 第6周 行数=0 页脚=今天没课，好好休息   ← 原生开机重建，读的是旧快照
  NjtcWidget: 刷新小组件 1 个 ids=32
  NjtcWidget: 渲染#32 10月7日 周三 第6周 行数=0 页脚=今天放假 · 国庆节    ← Dart 推完日历之后
  NjtcWidget: 已同步小组件数据 hasTimetable=true timetable=3996B periods=355B holidays=995B
  ```
  桌面小组件实拍见 `screenshots/widget_holiday_v114.png`，
  界面（列头「放假」+ 倒计时「明天 16:30 国家安全教育」）见 `screenshots/home_holiday_v114.png`。
* 「法定节假日 → 立即联网更新」这条路（v1.1.13 漏推的三条之一，**以前改完日历小组件不动**）：
  ```
  I/flutter: HolidaySync: ok=true note=2026 年 放假=36 补班=6 silent=false
  NjtcWidget: 刷新小组件 1 个 ids=32
  NjtcWidget: 渲染#32 10月7日 周三 第6周 行数=0 页脚=今天放假 · 国庆节
  NjtcWidget: 已同步小组件数据 …holidays=995B
  NjtcReminder: 排布完成：共 61 个提醒闹钟（推导 61 个，上限 240），窗口 14 天，精确闹钟=true，
                最近一次=2026-10-08(周四) 16:00
  ```
  页面上的来源串也跟着变成「来自联网更新（10月7日 13:57）· 放假 36 天 · 补班 6 天」。
* 放假当天确实不排课：`dumpsys alarm` 里 62 条 `COURSE_REMINDER` 从 **10-08** 才开始，
  10-07（国庆）一条都没有；最近一次 `10-08 16:00` 与首页倒计时「明天 16:30」对得上。
* 顺手排掉的一个**假警报**：`dumpsys alarm` 里 10-10（周六，历法里写着「补周三的课」）一条提醒都没有，
  一开始怀疑是补班日没生效。把「设置 → 显示非本周课程」关掉后发现
  **第 6 周周三本来就没课**（本周只有周四「国家安全教育」、周五「高等数学Ⅰ（上）」两门，
  周三那三门要在第 7 周才上），所以 10-10 补出来是空的 —— 数据如此，不是 bug。
  学期起始日期 `2026-08-31` 也不是手输的，是教务页脚「本学期 2026-08-31 正式上课…」解析出来的。
* 排查用的截图留在 `D:\DSH\shots\`（临时目录，不进仓库）；仓库里只放了上面两张。
* 没做的验证：「改补班日 / 恢复内置」这两条**手动改日历**的推送路径只在单测里覆盖，
  真机上没去点——那会往用户存档里写东西（`source` 会变成 `manual`，之后不再自动联网核对），
  不划算。网络那条路径已经真机跑通，三条路径调用的是同一个 `_pushWidget()`。


## 9.22 v1.2.0 —— 课表全览 + 多格式导入（doc/docx/pdf/网页/文本）+ 本地离线 OCR

用户在 1.1.14 之后追加了三件事：

1. 「课表放大全览展示」；
2. 「导入支持 doc/docx/pdf 等更多格式」；
3. 「本地离线图片 OCR 导入」（离线、不联网、不上传）。

三件事凑一版，`pubspec.yaml` 从 `1.1.14+16` 直接跳到 **`1.2.0+17`**（功能级改动，
不是修 bug，所以升 minor）。单测 229 → **272**，E2E 从 6 个文件变 **7 个**。

### 9.22.1 课表全览：复用同一张网格，交给 InteractiveViewer

需求是「课表太小，想放大看整周」。**没有新写渲染代码**，而是把既有网格参数化：

* `lib/widgets/timetable_grid.dart` 的 widget 新增三个字段：
  `dayWidth`、`sectionHeight`、`zoomable`，默认值就是原来写死的
  `defaultDayWidth = 118`、`defaultSectionHeight = 74`（`zoomable = false`）。
  State 里原来的 `static const double dayWidth / sectionHeight` 改成
  `double get dayWidth => widget.dayWidth;` 这样的转发 getter，
  **整套布局算式一行没动**——这是「复用而不是重写」的关键，改完首页像素级不变。
* 全览页 `lib/pages/week_overview_page.dart` 传 `dayWidth: 176, sectionHeight: 112,
  zoomable: true`，缩放交给
  `InteractiveViewer(minScale: 0.35, maxScale: 3.0, boundaryMargin: EdgeInsets.all(120),
  constrained: false)`。
* **坑**：`zoomable` 模式下必须去掉网格内部原来那两层 `SingleChildScrollView`。
  留着的话，横向那层会先把拖动事件吃掉，`InteractiveViewer` 永远收不到手势，
  表现是「双指缩放能用、单指拖动却纹丝不动」。所以 `build()` 里是二选一：
  zoomable 走 `InteractiveViewer`，否则走原来的两层滚动。
* **复位缩放**：「复位缩放」按钮想复位的是网格内部的 `TransformationController`，
  页面拿不到它。做法是 `KeyedSubtree(key: ValueKey('week-overview-$_resetToken'))`，
  点按钮 `_resetToken++` 换 key → 网格整棵重建 → 缩放自然回到 1.0。
  比重写控制器省事，也不破坏封装。
* 翻周只改页面自己的 `int? _week`（`null` = 跟随首页当前周），**绝不动
  `AppState.currentWeek`**：全览页翻到第 5 周，返回首页还得是本周。
  这条写成了用例（翻周后断言 `state.currentWeek` 没变）。
* 入口在首页头部：`Icons.grid_view_rounded` → `Navigator.pushNamed('/overview')`
  （命名路由注册在 `lib/main.dart`）。

### 9.22.2 多格式导入：先看文件头，再分流

`lib/pages/import_page.dart` 里统一收口到 `_importBytes(name, bytes)`，
按**文件头**（不信后缀，用户改过后缀的文件太多了）分流：

| 文件头 / 特征 | 走哪条路 |
| --- | --- |
| `D0 CF 11 E0 A1 B1 1A E1`（OLE2） | 自带 `XlsReader`（老 .xls）；捞不到课表时再试 `DocReader.ole2ToText` |
| `50 4B 03 04`（zip） | 里面是 `word/document.xml` → `DocxReader`；否则 `excel` 包（.xlsx） |
| `%PDF-` | `OcrService.recognizePdf`（系统 PdfRenderer 渲染后 OCR） |
| `\x89PNG` / `\xFF\xD8\xFF` / `GIF8` / `BM` / `RIFF….WEBP` | `OcrService.recognizeImage` |
| `{\rtf` | `DocReader.rtfToText` |
| `<html` / `<table` | 去标签，`</td>` 之间当分列 |
| 其它 | `DocumentParser.decodeText`（BOM → UTF-8 → GBK 依次嗅探） |

新增的三个「读者」都在 `lib/services/` 下：`document_parser.dart`（编码嗅探 +
`parseFreeText` 入口）、`docx_reader.dart`（自己解 zip + `word/document.xml`，
不引第三方 docx 包）、`doc_reader.dart`（.doc 的 OLE2 文本流 + RTF 控制字）。

两个踩出来的坑：

* **`.docx` 单元格里的制表符不能当换行更不能当分列**。第一版把 `w:tab` 翻译成 `\t`，
  于是「课名 / 周次 / 地点 / 教师」被 `TimetableParser.parseGrid` 当成**换了一列**，
  地点整个消失（用例里 `math.location` 期望 `明德楼A103`、实际空字符串才暴露）。
  现在 `_table` 把格内各段用 `/` 拼起来——`/` 正是 `parseCell` 认的分隔符，
  绕一圈刚好接上既有解析器。
* **`.doc` 挖不出文本时要返回 `null`**，不能返回空串：返回空串界面走的是
  「解析出 0 门课」，返回 `null` 才能提示「这个文件读不出文字，换个格式试试」。
  另外老 .doc 的正文是 UTF-16LE，`0x0D` 是「这一行结束」的信号——
  自己合成测试夹具时两行之间必须插一个 `0x0D`，否则两行会被粘成一句。

### 9.22.3 离线 OCR：tesseract4android + 系统自带的 PdfRenderer

* 引擎选 **JitPack 上的 `cz.adaptech.tesseract4android:tesseract4android:4.9.0`**
  （`android/build.gradle.kts` 加 jitpack 仓库）。
  **为什么不用 pdfrx / pdfium**：那条路要把 native assets / build hooks 引进构建链，
  Windows 本地还得开开发者模式，CI 也跟着脆。PDF 干脆交给 Android 自带的
  `PdfRenderer` 渲染成位图再 OCR——文字版 PDF 和扫描版走同一条路，APK 也不涨体积。
* 语言模型：`chi_sim`（tessdata_best，12.5MB）+ `eng`（tessdata_fast，3.9MB）。
  **不进仓库**（`.gitignore` 里忽略 `android/app/src/main/assets/tessdata/`）；
  本地用 `tool/fetch_tessdata.ps1` 拉，CI 在 `flutter analyze` 之前下载（见 `.github/workflows/release.yml`）。
* 运行时 `OcrBridge.ensureTessData()` 把 assets 复制到 `filesDir/tessdata/`
  （Tesseract 只认这种目录结构），大小一致就跳过；
  `setVariable("preserve_interword_spaces", "1")`——课表靠列间距分列，丢了空格没法还原；
  `psm = 6`；超大图降采样、小图放大；PDF 每页按 1600px 宽渲染、**先铺白底**
  （`PdfRenderer` 渲染出来是透明底，不铺白底 OCR 会当成黑底），最多取 8 页。
* OCR 全程在后台线程（`runAsync`），识别完 post 回主线程；结果先给用户过一眼
  （「确认识别结果」对话框）再解析导入，因为 OCR 出来的文字总有几处要手改。

### 9.22.4 Kotlin / AGP 踩坑（本轮最费时间的一节）

1. **KDoc 里的 `/*` 会开一个嵌套注释**。Kotlin 支持嵌套块注释，注释里写
   `assets/tessdata/*.traineddata` 就等于开了一个永不闭合的注释，
   整个文件报 `Syntax error: Unclosed comment`，**报的位置还是文件末尾**，
   查了半天才发现问题在文档注释里。→ 改成写「`assets/tessdata/` 下的
   `.traineddata` 文件」。
2. **第三方 API 别凭记忆写**。`TessBaseAPI` 没有 `end()`（用 `recycle()`）、
   `meanConfidence` 是方法不是属性、`getUTF8Text()` 在 Kotlin 里不会合成
   `utF8Text`。这些直接从 AAR 里 `javap` 出来看，一分钟的事：
   ```
   javap -classpath <解压后的 classes.jar> com.googlecode.tesseract.android.TessBaseAPI
   ```
3. **`traineddata` 必须 `noCompress`**。AGP 默认压缩 assets，
   `assets.openFd()` 读压缩过的条目会抛
   `This file can not be opened as a file descriptor; it is probably compressed`。
   **这个错误的表现极具误导性**：`recognizeImage` 里我有 try/catch，异常被翻译成中文错误；
   而 `info` 是裸的 `result.success(info())`，异常从 handler 里抛出去，
   Dart 侧看到的是 **`MissingPluginException`**——看起来像「桥没注册」，
   差点往 MethodChannel 名字、`GeneratedPluginRegistrant` 方向查。
   修法两层：`android { androidResources { noCompress += "traineddata" } }`，
   并且把 handler 整体包 try/catch 回 `result.error(...)`——
   **桥里任何异常都不许「什么都不回」**，那会把原生异常伪装成协议错误。
4. 置信度那个真 bug：`recognizeBitmap()` 先 `engine.clear()` 再让调用方取
   `meanConfidence()`，而 `clear()` 会把识别结果一起清掉，于是**置信度恒为 0**，
   界面上「识别置信度偏低，请核对」的提示就永远挂着。
   现在改成 `private fun recognizeBitmap(...): Pair<String, Int>`，
   在 `clear()` **之前**把 `meanConfidence()` 取走。

### 9.22.5 测试与 E2E

* 单测 229 → 272：`test/document_parser_test.dart`、`test/docx_reader_test.dart`、
  `test/doc_reader_test.dart`、`test/ocr_service_test.dart`、`test/week_overview_page_test.dart`。
  OCR 那条在单测里只测**通道层**（用 `OcrService.override` 假的 MethodChannel 返回），
  真引擎留给 E2E。
* `test/week_overview_page_test.dart` 一开始红：内置节假日日历把国庆那一周整体标成放假，
  网格里这些课 `active = false`，而 `showInactiveCourses` 默认 false ⇒ 课被整个滤掉，
  `find.byType(CourseCard)` 当然找不到。用例里补一句
  `await state.updateHolidays(const HolidayCalendar())` 把日历清空即可——
  这些用例只关心全览页本身，不需要跟节假日撞车。
* 原生 E2E `integration_test/ocr_e2e_test.dart`（模拟器上跑，App 会被卸载重装）：
  * 「图片 OCR」**自带输入**：用 `ui.PictureRecorder` + `TextPainter` 现场画两行课表
    再喂给 OCR，所以不依赖任何夹具，也不受分区存储限制；
  * 「PDF OCR」的夹具 `test/fixtures/ocr_sample.pdf`（`tool/make_ocr_fixture.py`
    用 Pillow 生成，同时生成 PNG）**作为 asset 打进包**。原因是踩出来的：
    `flutter test integration_test/...` 跑之前会**卸载重装 App**，
    `adb push` 到 `/sdcard/Android/data/<pkg>/files/` 的夹具根本活不到测试开始
    （第一次跑打印的就是「跳过 PDF 用例」）。33KB 换这条用例自包含，值。
  * `OcrService.info()` 是原样透传原生 map：字段是
    `channel` / `tessdataDir` / `files`（`{name: {assetBytes, installed}}`）/ `languages`。
    写断言时别按 `langs` / `models` 猜（第一版就是这么猜错的）。
  * 真跑证据（模拟器 API 37）：
    ```
    OCR info → {channel: cn.edu.njtc.njtc_schedule/ocr,
                tessdataDir: /data/user/0/cn.edu.njtc.njtc_schedule/files/tessdata,
                files: {chi_sim.traineddata: {assetBytes: 13077423, installed: false},
                        eng.traineddata: {assetBytes: 4113088, installed: false}},
                languages: chi_sim+eng}
    OCR 图片 → 1888x432
      星期一 高等数学 明德楼A103 (3-4节)7-18周
      星期二 Python程序设计 格致楼205 (5-673)7-18/4)
    OCR PDF  → 共 1 页，识别 1 页
    ```
    最后一串括号里的数字被认花了——**这是 OCR 的正常水平，也是「先让用户过一眼」
    那个确认框存在的原因**；用例只断言稳定的那几个词（课名、星期几）。
* **真机（vivo V2520A / Android 17 / arm64）冒烟**：模拟器是 x86_64，
  tesseract 的 **arm64 原生库只有真机才验证得到**，所以这一趟不能省。
  `adb install -r` 覆盖安装后 `versionCode=2017`、**课表与设置全部保留**、
  桌面小组件照旧；进「导入课程表 → 拍照 / 相册 OCR 识别」，从相册选一张图，
  跑完弹「确认识别结果」**置信度 83% (1440×3168)**、文字可编辑 —— 离线 OCR 在真机上成立。
  冒烟时**只点「取消」**：这台机器上装的是真实课表，点「解析导入」会把用户的课表覆盖掉。
* 顺手记两条 adb 交互的坑（下次别重踩）：
  * `read_image` 给的预览是 878×1932，设备是 1440×3168 ⇒
    **预览坐标要 ×1.64 才是 `adb shell input tap` 的坐标**（截图说明里那个 ×1.04 是对
    1380×3036 的 normalized 副本而言）。按 ×1.04 算会把点击打到课表网格上，
    弹出课程详情弹窗，白折腾两轮。
  * 底部导航「导入」在 1440×3168 上大约是 `input tap 566 3050`；
    模态弹层用 `input keyevent KEYCODE_BACK` **关不掉**，点遮罩（如 `720 300`）才关。
  * 截图务必 `screencap -p /sdcard/x.png` + `adb pull`；`adb exec-out screencap -p > x.png`
    经 PowerShell 重定向会写出坏 PNG。

### 9.22.6 教训

* 现象和原因之间可能隔着好几层：`MissingPluginException` ← handler 抛异常 ←
  assets 被压缩 ← `openFd` 不支持压缩条目。**报错原文先原样读一遍再定方向**，
  别急着往最熟悉的那条猜测上套。
* 测试夹具「放哪儿」是由测试运行方式决定的：会卸载重装的 E2E，
  夹具只能跟着 APK 走（asset），共享目录里的东西活不过安装。
* 复用比重写便宜：全览页能做到零像素回归，靠的是「网格只加参数、不改算式」。

### 9.22.7 出包与 CI（v1.2.0）

* 本地出包用新增的 `D:\DSH\build_v120.ps1`（照 `build_v114.ps1` 改），开头多了一步
  **语言模型存在性检查**：仓库里没有 `assets/tessdata/*.traineddata`，
  忘了跑 `tool/fetch_tessdata.ps1` 的话构建出来的包会在真机上 OCR 报错
  （或者 `flutter build` 直接因为 pubspec 里声明的 asset 不存在而失败）。
  体积（本地）：arm64 43.46 MB / v7a 39.31 MB / x86_64 45.31 MB / universal 92.81 MB。
* **CI 也要在 analyze 之前下载语言模型**（`.github/workflows/release.yml` 新增一步）：
  `chi_sim` 取 `tessdata_best`、`eng` 取 `tessdata_fast`，从 `raw.githubusercontent.com`
  `curl -fL --retry 3` 拉；`.gitignore` 忽略 `android/app/src/main/assets/tessdata/`。
* 推 `v1.2.0` 标签 → 工作流 `37583456946` **一次通过**（含「下载 OCR 语言模型」步骤），
  Release `内师课程表 v1.2.0` 产出 4 个 ASCII 资产，名字与体积：
  `njtc-schedule-1.2.0-arm64-v8a.apk` 45,570,226 B /
  `-armeabi-v7a.apk` 41,232,332 B / `-x86_64.apk` 47,507,449 B /
  `-universal.apk` 97,332,251 B（与本地包仅差几百字节，属重建差异）。
* 源码 zip（`D:\DSH\make_zip.ps1`）这轮把 `android/app/src/main/assets/tessdata`
  加进排除表 —— 否则 16 MB 语言模型会混进「源码」包里；重打后 147 文件 / 11183 KB，
  关键条目全部 OK。


## 9.23 v1.3.0 —— 节假日按节日合并显示 + 放假时长自主调整

用户这轮的原话是「节假日同一个节日合并显示，并支持时长自主调整 再次检查是否有bug并自行尝试修复，
完成后编写更新日志并连同新版本全部推送至github」。功能只落在**页面与模型层**，
存储格式与原生契约一个字没动，这也是这轮敢做得比较快的原因。

### 9.23.1 合并显示：只加一个「显示用的视图」，存储仍是逐天

* 存档与下发到 Kotlin 的东西**完全没变**：还是逐天的 `HolidayDay`（`yyyy-MM-dd|name`）与
  `makeups`（`epochDay → 按周几上课`）。原生侧 `holidays: Set<Long>` / `makeups: Map<Long,Int>`
  的契约因此不用动，老用户升级上来、以及已经排好的闹钟都不会受影响。
* 新增 `HolidayRange`（`name` + 连续 `days`），`HolidayCalendar.holidayRanges` 负责切段：
  先按日期排序，然后「`festivalKeyOf(name)` 相同 **且** epochDay 正好差 1」就并进同一个 run。
  页面一行 = 一个 `HolidayRange`，`dateText`/`countText`/`subtitle` 都在这个类里拼。
* 节日名归一 `festivalKeyOf()`：把后缀 `假期 / 放假 / 假日 / 休假` 循环剥掉
  （数据源里是「国庆节 / 国庆节假期」这种写法）；春节那几天在联网数据里各叫各的
  （除夕 / 初一 / 初二…），于是 `_springAliases` + `^初[一二三四五六七八九十]$` 一律归成「春节」。
  **剥空了要回原文**：名字本身就叫「假期」时不能归一成空字符串（用例盯着这条）。
* `sorted()` 顺手改成 `_dedupeByDay()`：同一天只留**先出现的**那条。老存档 / 手改存档里
  可能出现重复日期，以前 `holidayName()` 只看得到先来的那条、列表却画两行，像 bug。
  现在读写显示三处都按 epochDay 去重，`HolidayDay` 与 `MakeupDay` 共用同一个泛型函数。

### 9.23.2 「时长自主调整」= 区间写回（`withHolidayRange`）

编辑器不做「加减天数就用 delta 去增删」那种写法（取消 / 反复加减会把日子弄乱），
而是**每次保存都把整段当成 (start, end, name) 写回**，语义只有三条：

1. `replacing`（被编辑的那段原来的日子）+ 新范围覆盖到的日子，先全部拿掉；
2. 新范围内**重叠的别的假期段一并接管** —— 同一天只留一条，名字取这次填的；
   所以把中秋往后延到 10/1，那天就从国庆变成中秋（国庆自动缩成 10/2~10/7）。
   被接管的那天会把原主记进 `HolidayDay.originName`，**将来这段缩短 / 删掉时自动还给它**
   （见 9.23.5 F1：不记的话，10/1 会变成「谁都不是的普通工作日」，提醒也就不再跳过它）。
   同一节日的不同写法（`国庆节` / `国庆节假期`）不算接管，不记。
3. 新范围压到的**补班日直接删掉**（放假优先）—— 与原生 `ReminderScheduler` 里
   「先判放假、再看补班」的顺序一致，否则会出现「放了假却还按补班排课」。
   反过来，「添加补班日」时如果那天正在放假，**直接拦下来并提示**（v1.3.0 修）：
   以前会悄悄删掉那天的放假，而排程里放假优先、补班会被忽略，桌面上却照补班画课。

另外两条护栏：起始/结束写反自动正序；长度超过 `maxHolidayRangeDays = 120` 按上限截断
（`_clamp()` 在编辑器里同步做同样的事，「延长一天」到 120 天会禁用）。
保存前的提示来自 `rangesOverlapping(days, excluding: 正在编辑的段)` 与 `_hitMakeups`：
「与「国庆节」重叠的那几天会归到这一行」「这段里 N 天排了补班，保存后会删掉那些补班安排（放假优先）」。

### 9.23.3 编辑器用底部弹层而不是对话框

`showModalBottomSheet(isScrollControlled: true)` + `MediaQuery.viewInsets.bottom` 内边距：
日期选择器要叠在上面，用 `AlertDialog` 会被键盘 / 日期面板挤变形。
弹层里是「名称输入框 + 开始 / 结束（点开日期选择器）+ `时长：N 天` + 缩短 / 延长两个按钮」。
「保存」时比对起止 epochDay 与归一后的名字，都一样就只提示「没有改动」、不写盘、不重排提醒
（**这条当初没做到**：老代码两个分支都照样调 `_apply`，见 9.23.5 F2，v1.3.0 修）。

### 9.23.4 测试：272 → 310（+38）

* 模型层 `test/holiday_calendar_test.dart` 新增三组 25 条：归一与合并（后缀 / 春节别名 /
  断开不合并 / 相邻不同节日不合并 / 重复日期去重）、时长调整（延长缩短 / 起止写反 / 接管重叠段 /
  压掉补班日 / 120 天截断 / 空名字 / 删整段 / `rangesOverlapping`）、
  接管与归还（F1 的延长→缩短 / 延长→删除 / 同一节日不记 / 连接管两次 / 存档往返 + `^` 前缀格式 /
  空名字兜底）。
* 页面 `test/holiday_settings_test.dart` 13 → 26 条：原来按**逐天**断言的用例全要改成合并后的期望
  （`find.text('2026-10-01  周四')` 已经不存在，改成断 `国庆节` + `10月1日（周四） – 10月7日（周三） · 共 7 天`），
  删「第一行」现在等于删掉中秋整段（13 → 10 天 / 3 → 2 段），另加 9 条编辑器用例，
  复查后再补 4 条：原样保存不动存档 / 改开始日期保时长 / 删接管段会还给国庆 / `openEditor` 的确认框文案。
* 这轮踩的坑（都记一笔）：
  1. `find.text('没有改动')` **精确匹配会失败**：测试环境里 `updateHolidays()` 排提醒必然失败
     （非 Android），SnackBar 文案变成「没有改动，但提醒没排上：当前平台不支持课程提醒（仅 Android 版可用）。」
     —— 断言要用 `textContaining`。这一条以后写所有 `_apply` 的断言都适用。
  2. 内置国庆那 7 天的名字是「国庆节 + 国庆节假期」，`holidayName()` 返回的是**原文**
     （10-02 是「国庆节假期」），要断言合并后的名字得看 `holidayRanges[i].name`（归一后的）。
  3. 延长假期是**真的加天数**：中秋 09-25~27 延到 10-01 之后总数是 16 天而不是 13 天
     （10-01 只是换了主人，另外 4 天是新增的），一开始把期望写成「总数不变」错了。
  4. 合并显示之后，测试里所有「删一天 → 12 天」的旧断言都得重算。
  5. **改存档格式时要先想老数据**：给「接管记录」挑编码时第一版写成了 `日期|名字|原主`（三段），
     结果把老存档里「名字本身带竖线」（`2026-10-01|国庆|中秋连休`）的行拆坏了 ——
     已经有一条老用例盯着这件事。最后改成**行首加 `^` 前缀**（`^国庆节|2026-10-01|中秋节`）：
     老行的日期字段永远以数字开头，两边都不打架。

### 9.23.5 复查（用户要求「再次检查是否有bug」）→ 4 个真 bug 与修法

`flutter analyze` 0 issue、`flutter test` **310 passed**、原生
`integration_test/holiday_reminder_e2e_test.dart` 在 API 37 模拟器上重跑通过
（`放假 → scheduled=0`、关掉开关 `scheduled=3`、补班日 `scheduled=6 next=2026-10-08(周四)`）。

除了自查，还让一个独立子代理逐行读了 `holiday_calendar.dart` 与 `holiday_settings_page.dart`
的新增部分（不与写代码的上下文共享，专门唱反调）。它确认了红线都没破（`epochDay` 全程 UTC、
`update()` 不抛、`source == manual` 不被覆盖、新路径都经 `AppState.updateHolidays()` 因而都会推小组件、
原生契约未变），并挖出 4 个真问题 —— 都已修 + 补用例：

* **F1（会丢假期的真 bug）「延长吃掉别的节日后再缩短，那天就谁都不是了」**：
  接管时把 10-01 直接改名成「中秋节」，原主信息没了；缩回 9/25~9/27 时它被当作「这段不要了」删掉，
  于是 10-01 变成普通工作日（**提醒又会在那天响**），界面上看起来国庆缺了个口子，且无法挽救。
  修法：`HolidayDay` 加 `originName`，接管时记原主、缩回 / 删段时**归还**
  （`^原主|日期|名字` 进存档；同节日不同写法不记；连接管两次只留最早那层主人）。
* **F2（静默降级）「『没有改动』其实不是空操作」**：老代码两个分支都调 `_apply`，
  于是原样保存也会①把内置的「国庆节假期」改名写回存档、②删掉这段里的补班日、
  ③把 `source` 盖成 `manual` —— **联网更新从此永远不再覆盖这份日历**，卡片还会显示「手动调整过」。
  修法：`kept == true` 时 `_toast('没有改动'); return;`，一次盘都不写。
* **F3（UX 陷阱）「把开始日期选到结束之后，整段被压成 1 天」**：`_clamp()` 原来直接 `to = from`。
  想「整体往后挪假期」的人会先改开始，结果结束塌成同一天、保存后 7 天只剩 1 天。
  修法：`_clamp({int? keepLength})` —— 改开始时保持原时长（结束跟着挪），至少 1 天、最多 120 天。
* **F4（并发覆盖）「编辑器里拿的是 build 时的旧日历」**：启动静默联网更新刚好在弹层打开期间落地时，
  保存会用「内置版 + 你这一处改动」覆盖掉刚拿到的官方日历，还把 `source` 变成 `manual`。
  修法：所有写盘路径一律以 `state.holidays`（当前实时日历）为基准，不用 `build` 里那份快照。

顺手修的几处 nitpick：编辑器 `initState` 里补 `_clamp()`（存档里若有 >120 天的段，显示与加减会算歪）；
`_pickEnd` 的上限改用 `dateOfEpochDay(epochDayOf(_start) + 119)`（不再用本地 `Duration`，守红线 1）；
空名字的存量数据在列表里显示成「法定节假日」而不是空白标题；两个日期选择器把 `initialDate`
收进 2020~2035（存档里若躺着 2035 年以后的段，直接当 `initialDate` 会触发断言）；
跨年区间的文案两边都带年份。

复查报告里明确「看着可疑但核对过没问题、别去追」的点：`dateOfEpochDay` 确实是 `epochDayOf` 的逆、
`_spanDays` / `_bump` / `_clamp` 的含首尾算术没有 off-by-one、120 天上限三处都兜住了、
`sorted()` 先按天去重再排序（结果是确定的、不会因不稳定排序抖动）、
`rangesOverlapping` 的 `excluding` 在「一天只有一条」的前提下等价于排除自身、
`festivalKeyOf` 对真实接口数据（`X节` 系列 + 春节的 `除夕/初一…`）能正确合并且不会跨节日串味。

另外：1.2.0 那轮 `build_v120.ps1` 里的自检路径写错了（过滤 `assets/flutter_assets/*tessdata*`，
而语言模型的真实路径是 `assets/tessdata/`），所以那句「tessdata in apk?」当时什么都没打印
（当时是另开命令确认的）。`build_v130.ps1` 已改成 `assets/tessdata/*` 并把 `raw / stored` 都打出来，
`stored == raw` 就说明 `noCompress` 生效。

**真机冒烟（vivo V2520A / Android 17 / arm64，装的是用户本人真实课表，只看不改）**：
`adb install -r` 覆盖安装 → `versionCode=2018 versionName=1.3.0`，课表与设置全部保留。
`设置 → 法定节假日` 卡片写着「放假 36 天 · 补班 6 天 · 放假不提醒」（这份日历已经联网更新成官方数据），
点进去「放假日」卡片右上角是 **`36 天 · 8 段`**，下面正是合并后的行：
元旦 1/1–1/3（3 天）、春节 2/15–2/23（**9 天**，内置数据里那 9 天名字是「除夕 / 初一…」，
归一后并成一行）、清明节 4/4–4/6、劳动节 5/1–5/5、端午节 6/19–6/21、中秋节 9/25–9/27、
国庆节 10/1–10/7、元旦（2027）1/1–1/3；点「春节」那行弹出「调整假期」：
名称 `春节`、开始 `2026-02-15 周日`、结束 `2026-02-23 周一`、`时长：9 天` + `−` / `＋`、
底部 `删除这一段` / `取消` / `保存`；**点「取消」后卡片仍是 `36 天 · 8 段`**（没动真实数据）。
「关于」页显示 `内师课程表 v1.3.0` 与新加的那段节假日说明。
截图存 `screenshots/holiday_merged_v130.png`、`holiday_rows_v130.png`、`holiday_editor_v130.png`
（README 已引用）。

> 真机交互的两个坑（下次少走弯路）：①`read_image` 给的预览是 878×1932，设备是 1440×3168，
> **预览坐标 ×1.64 才是 `adb shell input tap` 的坐标**（不是图注里那个 ×1.04 的 normalized 副本）；
> ②如果手机正被使用（前台是别的 App），`am start` 之后立刻盲点会点进那个 App ——
> 先 `dumpsys window | grep mCurrentFocus` 确认前台是自己的 App 再点。

### 9.23.6 出包与 CI（v1.3.0）

* `pubspec.yaml` `1.3.0+18`（versionCode 18 / 1018 / 2018 / 4018），
  `lib/pages/settings_page.dart` 关于页版本串与新增功能说明同步改掉。
* 本地出包 `D:\DSH\build_v130.ps1`（照 `build_v120.ps1` 改，`$ver='1.3.0'`，
  保留语言模型存在性检查 + aapt2 badging + sha256）。修 bug **之后**重打了一遍
  （先出的那四个包是修复前的产物，sha256 已作废）：
  universal 92.85MB `AA23128261E564615B223679E7FDE146E8D8648037E6AB3CB3711AB7B00957FD`、
  armeabi-v7a 39.35MB `91EF4187E23C6E78C413F21E87EE8ABB4A27E51C23917F106FB90BEE8A34FE5A`、
  arm64-v8a 43.46MB `67C913005CFE28E82F4A1D791416E3C4EB8557312DBD4EEE0C38667BE8FBA7A0`、
  x86_64 45.31MB `7577D65CF58BAAD022B9FE87EE497A9986D68E9B1F5C4CE6C754BC6248241034`；
  包内 `assets/tessdata/chi_sim.traineddata raw=12.47MB stored=12.47MB`（`noCompress` 仍生效）。
* 推 `v1.3.0` 标签触发 Release 工作流（标签必须打在工作流已存在的提交上）：
  run **37586399250** 一次全绿，Release「内师课程表 v1.3.0」四个 ASCII 资产 ——
  arm64-v8a 45,570,370 B / armeabi-v7a 41,265,248 B / x86_64 47,507,601 B / universal 97,365,167 B。
* 提交：`8843548`（10 文件 / +1577 −96）→ 推送 `78fe9c6..8843548` → tag `v1.3.0`；
  随后 `6de38a1` 补真机截图与冒烟记录。源码包 `D:\DSH\njtc_schedule_source.zip` = 150 文件 / 12020.4 KB
  （`make_zip.ps1` 的 excludePaths 仍排除 `android\app\src\main\assets\tessdata`）。




