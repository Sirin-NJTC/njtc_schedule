/// 真机 / 模拟器上的端到端验证：法定节假日与调休补班日**真的**影响原生闹钟。
///
/// 为什么单独一个文件：`ReminderPlan` 的三条钩子（放假整天 `continue`、补班改
/// `isoDow`、`skipHolidays` 开关）都发生在 Kotlin 侧的 `computeInstances()` 里，
/// Dart 单测只能验到「载荷里带了什么」，验不到「原生有没有照做」。
///
/// 运行方式（**务必用模拟器**：跑完 App 会被卸载，真机上会把用户的课表一起删掉）：
/// ```bash
/// flutter test integration_test/holiday_reminder_e2e_test.dart -d emulator-5554
/// ```
///
/// 课程一律只排**第 2 周**（今天所在的那一周，`startDate = 今天 - 7 天`），
/// 这样「一周一次」的重复不会掺进来，断言可以写得确定：
/// 1. 明天（第 2 周的周一/周日）标成放假日 + 开关打开 → 一个闹钟都没有；
/// 2. 同一份计划把开关关掉 → 明天的课照排（证明第 1 条是日历在起作用）；
/// 3. 明天标成「按另一个周几上课」的补班日：不排时首个提醒是后天，加上补班日后
///    首个提醒变成明天 —— 补班日确实把日期映射成了另一个周几。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:njtc_schedule/models/course.dart';
import 'package:njtc_schedule/models/holiday_calendar.dart';
import 'package:njtc_schedule/models/reminder_prefs.dart';
import 'package:njtc_schedule/models/timetable.dart';
import 'package:njtc_schedule/services/reminder_service.dart';

/// `ReminderScheduler.formatTime` 的同一套格式：`2026-10-05(周一) 07:30`
String _dateText(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

Course _course({
  required String name,
  required int dayOfWeek,
  required int startWeek,
  required int endWeek,
}) =>
    Course(
      name: name,
      teacher: '测试教师',
      location: '明德楼B216',
      dayOfWeek: dayOfWeek,
      startSection: 1,
      endSection: 1,
      startWeek: startWeek,
      endWeek: endWeek,
      courseCode: 'ZB1040282-07',
      className: '智26.8',
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('放假日不排提醒 / 关掉开关照排 / 补班日换个周几排', (tester) async {
    expect(
      ReminderService.supported,
      isTrue,
      reason: '该用例必须在 Android 真机或模拟器上运行',
    );

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dayAfter = today.add(const Duration(days: 2));
    final dow = tomorrow.weekday;
    // 补班日要映射到的另一个周几（就是后天那一天，课程排在后天）
    final otherDow = dayAfter.weekday;

    // startDate 取一周前 → 今天与明天都属于第 2 周，课程只排第 2 周
    Timetable timetableWith(Course c, String id) => Timetable(
          id: id,
          name: '节假日端到端验证课表',
          semester: '2026-2027年第1学期',
          totalWeeks: 20,
          startDate: today.subtract(const Duration(days: 7)),
          courses: [c],
        );

    final holidayTt = timetableWith(
      _course(name: '明天的课', dayOfWeek: dow, startWeek: 2, endWeek: 2),
      'e2e-holiday',
    );
    final makeupTt = timetableWith(
      _course(name: '后天的课', dayOfWeek: otherDow, startWeek: 2, endWeek: 2),
      'e2e-holiday-makeup',
    );

    final prefs = ReminderPrefs(
      enabled: true,
      leadMinutes: const {30, 15, 5},
      endReminder: true,
      vivoAtomic: true,
    );

    debugPrint('[E2E] 今天=${_dateText(today)} 明天=${_dateText(tomorrow)}(周$dow) '
        '后天=${_dateText(dayAfter)}(周$otherDow)');

    // ── 场景 1：明天放假 + 开关打开 → 这节课整周唯一的一次被跳过 ──
    final holidayCal = HolidayCalendar(
      holidays: [HolidayDay(tomorrow, '端到端测试假日')],
    );
    var payload = ReminderService.buildPlanPayload(holidayTt, prefs, holidayCal)!;
    expect(payload['skipHolidays'], isTrue);
    expect(payload['holidays'], contains(epochDayOf(tomorrow)));

    var result = await ReminderService.syncPlan(payload);
    debugPrint('[E2E] 放假 → ok=${result.ok} scheduled=${result.scheduled} '
        'next=${result.nextTriggerText} note=${result.note}');
    expect(result.scheduled, 0, reason: '明天放假，这周的课一个闹钟都不该排：${result.note}');
    var status = await ReminderService.status();
    expect(status.scheduledCount, 0);
    expect(await ReminderService.preview(limit: 8), isEmpty);

    // ── 场景 2：同一份计划，把「放假当天不提醒」关掉 → 照排 ──
    final offPrefs = prefs.copyWith(skipHolidays: false);
    payload = ReminderService.buildPlanPayload(holidayTt, offPrefs, holidayCal)!;
    expect(payload['skipHolidays'], isFalse);

    result = await ReminderService.syncPlan(payload);
    debugPrint('[E2E] 放假但开关关掉 → scheduled=${result.scheduled} '
        'next=${result.nextTriggerText}');
    expect(result.scheduled, greaterThan(0), reason: '开关关掉就该照常提醒');
    expect(result.nextTriggerText.contains(_dateText(tomorrow)), isTrue,
        reason: '首个提醒应该落在明天：${result.nextTriggerText}');

    // ── 场景 3：补班日把明天当作「后天那个周几」 ──
    // 先不带补班日：课程排在后天，首个提醒应该在后天
    payload = ReminderService.buildPlanPayload(makeupTt, prefs)!;
    result = await ReminderService.syncPlan(payload);
    debugPrint('[E2E] 无补班日 → scheduled=${result.scheduled} '
        'next=${result.nextTriggerText}');
    expect(result.nextTriggerText.contains(_dateText(dayAfter)), isTrue,
        reason: '没有补班日时首个提醒应在后天：${result.nextTriggerText}');
    final withoutMakeup = result.scheduled;

    // 带上补班日：明天按 otherDow 上课，于是明天的课也要排，且成为首个提醒
    final makeupCal = HolidayCalendar(
      makeups: [MakeupDay(tomorrow, otherDow, '端到端补班')],
    );
    payload = ReminderService.buildPlanPayload(makeupTt, prefs, makeupCal)!;
    expect((payload['makeups'] as List).isNotEmpty, isTrue);

    result = await ReminderService.syncPlan(payload);
    debugPrint('[E2E] 带补班日 → scheduled=${result.scheduled} '
        'next=${result.nextTriggerText} note=${result.note}');
    expect(result.scheduled, greaterThan(withoutMakeup),
        reason: '补班日应该多排一天（明天）');
    expect(result.nextTriggerText.contains(_dateText(tomorrow)), isTrue,
        reason: '补班日的提醒应排到明天：${result.nextTriggerText}');

    final preview = await ReminderService.preview(limit: 8);
    debugPrint('[E2E] 补班 preview(${preview.length}) →');
    for (final item in preview) {
      debugPrint('        ${item.timeText}  [${item.kind}]  ${item.label}  '
          '${item.courseName} @${item.location}');
    }
    expect(preview, isNotEmpty);
    expect(preview.first.courseName, '后天的课');
    expect(preview.first.timeText.contains(_dateText(tomorrow)), isTrue,
        reason: preview.first.timeText);

    // ── 收尾：撤掉测试计划，别在设备上留一堆闹钟 ──
    await ReminderService.cancelAll();
    debugPrint('[E2E] 已 cancelAll()');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
