/// 真机 / 模拟器上的端到端验证：
/// Dart 侧计划 → MethodChannel → 原生闹钟排布 → 真实发送通知（含原子通知字段）。
///
/// 运行方式：
/// ```bash
/// flutter test integration_test/reminder_e2e_test.dart -d <device-id>
/// ```
///
/// 跑完之后可以在宿主机上复核原生侧的真实状态：
/// ```bash
/// adb shell dumpsys alarm | grep -i njtc
/// adb shell dumpsys notification --noredact | grep -A 24 "notification.superx"
/// ```
///
/// 本用例会**故意保留**排布好的计划与已发出的通知，方便上面两条命令复核。
///
/// 课程刻意排到**明天上午**，这样三条提前提醒（7:30 / 7:45 / 7:55）一定在未来，
/// 计划里必然同时出现「时段预告」「单节提醒」「下节课预告」三种条目，断言可确定。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:njtc_schedule/models/course.dart';
import 'package:njtc_schedule/models/reminder_prefs.dart';
import 'package:njtc_schedule/models/timetable.dart';
import 'package:njtc_schedule/services/reminder_service.dart';

const String kCourseA = '端到端测试课程A';
const String kCourseA2 = '端到端测试课程A'; // 与 A 连堂：同名、同地点、节次紧接
const String kCourseB = '端到端测试课程B';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('课表 → 原生闹钟 → 通知 / 原子通知字段 全链路', (tester) async {
    expect(
      ReminderService.supported,
      isTrue,
      reason: '该用例必须在 Android 真机或模拟器上运行',
    );

    final now = DateTime.now();
    // 明天是星期几 —— 课程全部排在这一天，保证所有触发点都在未来
    final tomorrow = now.add(const Duration(days: 1));
    final dow = tomorrow.weekday;

    final tt = Timetable(
      id: 'e2e-reminder',
      name: '端到端验证课表',
      semester: '2026-2027年第1学期',
      major: '机器人工程',
      totalWeeks: 20,
      // 起始日期取一周前 → 今天处于第 2 周，保证课程在第 1..20 周内生效
      startDate: now.subtract(const Duration(days: 7)),
      courses: [
        // 上午第一节（时段首课）→ 应拿到 30 分钟时段预告 + 15 分钟 + 5 分钟
        Course(
          name: kCourseA,
          teacher: '测试教师',
          location: '明德楼B216',
          dayOfWeek: dow,
          startSection: 1,
          endSection: 1,
          startWeek: 1,
          endWeek: 20,
          courseCode: 'ZB1040282-07',
          className: '智26.8',
        ),
        // 与 A 连堂（同名/同地点/节次紧接）→ A 不应发「下节课预告」
        Course(
          name: kCourseA2,
          teacher: '测试教师',
          location: '明德楼B216',
          dayOfWeek: dow,
          startSection: 2,
          endSection: 2,
          startWeek: 1,
          endWeek: 20,
          courseCode: 'ZB1040282-07',
          className: '智26.8',
        ),
        // 第三节、不同课 → A2 应发「下节课预告」（预告 B）
        Course(
          name: kCourseB,
          teacher: '另一位教师',
          location: '明德楼A101',
          dayOfWeek: dow,
          startSection: 3,
          endSection: 3,
          startWeek: 1,
          endWeek: 20,
          courseCode: 'ZB1040283-01',
          className: '智26.8',
        ),
      ],
    );

    final prefs = ReminderPrefs(
      enabled: true,
      leadMinutes: const {30, 15, 5},
      endReminder: true,
      vivoAtomic: true,
    );

    final payload = ReminderService.buildPlanPayload(tt, prefs);
    expect(payload, isNotNull, reason: '设置了 startDate 时必须能生成计划');
    expect(payload!['leadScopes'], <String>['sessionPreview', 'sessionFirst', 'all']);

    debugPrint('[E2E] 课程排到 周$dow 第1/2/3节；今天第 2 周');

    // ── 1. 下发计划：原生侧排布闹钟 ──
    final result = await ReminderService.syncPlan(payload);
    debugPrint('[E2E] syncPlan → ok=${result.ok} scheduled=${result.scheduled} '
        'horizon=${result.horizonDays} exact=${result.exact} '
        'next=${result.nextTriggerText} note=${result.note}');
    expect(result.ok, isTrue, reason: result.note);
    expect(result.scheduled, greaterThan(0), reason: '应至少排出一个闹钟');
    expect(result.nextTriggerAt, greaterThan(0));

    // ── 2. 查询原生状态 ──
    final status = await ReminderService.status();
    debugPrint('[E2E] status → platform=${status.platformSupported} '
        'vivo=${status.isVivo} island=${status.isIslandCapable} '
        'brand=${status.brand} sdk=${status.androidSdk} '
        'notif=${status.notificationsEnabled} exact=${status.exactAlarmAllowed} '
        'battery=${status.ignoringBatteryOptimizations} '
        'hasPlan=${status.hasPlan} count=${status.scheduledCount}');
    expect(status.platformSupported, isTrue);
    expect(status.hasPlan, isTrue);
    expect(status.scheduledCount, greaterThan(0));

    // ── 3. 预告列表：时段预告 / 单节提醒 / 下节课预告 三种都应在 ──
    final preview = await ReminderService.preview(limit: 8);
    debugPrint('[E2E] preview(${preview.length}) →');
    for (final item in preview) {
      debugPrint('        ${item.timeText}  [${item.kind}]  ${item.label}  '
          '${item.courseName} @${item.location}${item.isEnd ? '  [下课]' : ''}');
    }
    expect(preview.length, greaterThanOrEqualTo(6));

    // 明天上午第一节，7:30 的时段预告排在最前
    expect(preview[0].kind, 'sessionPreview', reason: '30 分钟档必须是时段预告');
    expect(preview[0].courseName, kCourseA);
    expect(preview[0].timeText.endsWith('07:30'), isTrue, reason: preview[0].timeText);
    expect(preview[0].isEnd, isFalse);

    // 时间顺序：7:30 预告(A) → 7:45(A) → 7:55(A) → 8:50(A2) → 9:35 下课(A2→B) → 9:55(B)
    expect(
      preview.take(6).map((e) => e.kind).toList(),
      <String>['sessionPreview', 'lead', 'lead', 'lead', 'endPreview', 'lead'],
      reason: '连堂的 A 不应产生下节课预告',
    );
    expect(preview[1].courseName, kCourseA);
    expect(preview[3].courseName, kCourseA2);
    expect(preview[4].isEnd, isTrue);
    expect(preview[4].courseName, contains(kCourseB), reason: '下课预告应指向下一节课');
    expect(preview[5].courseName, kCourseB);
    // 这一整天只应有一条下节课预告（A→A2 是连堂，被正确跳过）
    expect(preview.take(6).where((e) => e.kind == 'endPreview').length, 1);

    // ── 4. 三条通道各发一条真通知（会挂载 vivo superx 字段）──
    final modeEnd = await ReminderService.testNow(
      isEnd: true,
      courseName: kCourseA,
    );
    debugPrint('[E2E] testNow(下节课预告) → $modeEnd');
    expect(modeEnd, isNotEmpty);
    expect(modeEnd.contains('失败'), isFalse, reason: modeEnd);

    final modePrev = await ReminderService.testNow(
      sessionPreview: true,
      courseName: kCourseA,
    );
    debugPrint('[E2E] testNow(时段预告) → $modePrev');
    expect(modePrev, isNotEmpty);
    expect(modePrev.contains('失败'), isFalse, reason: modePrev);

    final modeLead = await ReminderService.testNow(
      isEnd: false,
      courseName: kCourseA,
    );
    debugPrint('[E2E] testNow(上课提醒) → $modeLead');
    expect(modeLead, isNotEmpty);
    expect(modeLead.contains('失败'), isFalse, reason: modeLead);

    // ── 5. 保持窗口：让宿主机有时间用 dumpsys 取到真实的闹钟与通知记录 ──
    // 集成测试一旦结束，Flutter 会把 App 卸载，闹钟与通知随之消失，
    // 所以这里刻意多停留一段时间，给外部取证留出窗口。
    debugPrint('[E2E] 保持 75 秒以便宿主机 dumpsys 取证…');
    await Future<void>.delayed(const Duration(seconds: 75));
    debugPrint('[E2E] 保持结束。');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
