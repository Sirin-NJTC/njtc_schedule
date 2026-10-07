/// 学期周次换算 —— 全局只有这一个算法。
///
/// 这套算法原先散落三处、写法还不一致：
/// * `AppState._autoDetectWeek` 用带时分秒的 `DateTime.difference`
/// * `HomePage._realWeek` 用归一化到当天的写法
/// * `TimetableGrid._todayColumn` 又抄了一遍归一化的写法
///
/// 只要 `startDate` 带上时间分量（比如跨时区解析成上午 8 点），第一处就会和
/// 另外两处算出不同结果——初始周偏一天，且「回到本周」跳的周与网格高亮的
/// 今天不是同一周。现在统一收敛到本文件，三处共用。
///
/// ⚠️ 遵循项目红线：跨语言算「天」一律用 epochDay，不要手写
/// `DateTime.difference()` —— 它会把时分秒算进去。
library;

import 'course.dart';
import 'holiday_calendar.dart' show HolidayCalendar, epochDayOf;
import 'period.dart' show Period;

/// **未截断**的教学周：学期开始前为 0 或负数，学期结束后大于总周数。
///
/// [weekOfSemester] 是给「显示第几周」用的，会把越界值夹到 `[1, totalWeeks]`；
/// 但「这一天到底有没有课」不能夹——学期都结束了，把第 21 周夹回第 20 周
/// 会凭空多出一周课。需要判断越界的场合（如下一节课扫描）用这个。
int? rawWeekOf({required DateTime? startDate, required DateTime day}) {
  if (startDate == null) return null;
  return (epochDayOf(day) - epochDayOf(startDate)) ~/ 7 + 1;
}

/// [day] 处在学期第几周（1-based），越界自动夹到 `[1, totalWeeks]`。
///
/// [startDate] 为空（用户还没在「设置 → 学期起始日期」里设过）时返回 null，
/// 调用方据此决定回落到第 1 周，还是提示用户去设置。
int? weekOfSemester({
  required DateTime? startDate,
  required DateTime day,
  required int totalWeeks,
}) {
  final raw = rawWeekOf(startDate: startDate, day: day);
  if (raw == null) return null;
  if (raw < 1) return 1;
  if (raw > totalWeeks) return totalWeeks;
  return raw;
}

/// 今天处在第几周。语义上就是 [weekOfSemester] 取 `DateTime.now()`。
int? currentWeekOf(DateTime? startDate, int totalWeeks) => weekOfSemester(
      startDate: startDate,
      day: DateTime.now(),
      totalWeeks: totalWeeks,
    );

/// 第 [week] 周的起始日期（周一），周次选择器里显示「这周对应几号」用。
///
/// 由 epochDay 反推，不走 `DateTime.add(Duration)` —— 后者在夏令时地区会
/// 把 23/25 小时的一天算进去，中国没有夏令时所以平时看不出来，但没必要冒险。
DateTime? startOfWeek({required DateTime? startDate, required int week}) {
  if (startDate == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(
    (epochDayOf(startDate) + (week - 1) * 7) * Duration.millisecondsPerDay,
    isUtc: true,
  );
}

/// 「接下来那节课」：从 [from] 起向未来逐天扫描，找到第一节还没开始的课。
///
/// 与旧版倒计时的三点差别（都是真问题）：
/// 1. 旧版只看**今天**，今天的课上完后面板就消失了，其实明天早上还有课；
/// 2. 旧版拿「正在查看的周」过滤课程，用户翻到别的周，今天真实的课反而被藏掉；
/// 3. 完全不看节假日/调休——放假日那天照样报「即将上课」，补班日（周六补周三）
///    却找不到该上的课。现在 [holidays] 会同时修正这两类日期。
///
/// 学期结束后（rawWeek > totalWeeks）停止扫描返回 null。
/// 用 `DateTime(y, m, d + offset)` 做日期递进：Dart 会自动进位月份，
/// 且不受夏令时影响（`add(Duration)` 在夏令时地区会偏一小时）。
///
/// [scanDays] 是窗口长度（**含今天**，即往后看 `scanDays - 1` 天）。默认 21 天
/// 不是拍脑袋：法定假期可以连放 8 天以上（春节、国庆叠中秋），窗口只给一周
/// 的话「整段假期都在放假 → 找不到课 → 首页倒计时整周空着」，而 3 周足够跨过
/// 任何一段假期找到下一节课。
class NextClassOccurrence {
  const NextClassOccurrence({
    required this.course,
    required this.startsAt,
    required this.isToday,
  });

  final Course course;

  /// 这节课的开始时刻（已按 [Period] 的作息换算到 [startsAt] 所在那天）。
  final DateTime startsAt;

  /// 是否就在 [from] 当天（决定 UI 显示「即将上课」还是「下节课」）。
  final bool isToday;
}

NextClassOccurrence? nextClassOccurrence({
  required List<Course> courses,
  required HolidayCalendar holidays,
  required DateTime? startDate,
  required int totalWeeks,
  required List<Period> periods,
  required DateTime from,
  int scanDays = 21,
}) {
  if (startDate == null || courses.isEmpty) return null;

  for (var offset = 0; offset < scanDays; offset++) {
    // 只取年月日（时分秒抹掉），日期递进靠构造器自动进位
    final date = DateTime(from.year, from.month, from.day + offset);
    final rawWeek = rawWeekOf(startDate: startDate, day: date);
    if (rawWeek == null || rawWeek > totalWeeks) return null; // 学期已结束

    // 放假日整天不上课；补班日按日历指定的星期上（如「周六补周三」）
    if (holidays.isHoliday(date)) continue;
    final effDow = holidays.weekdayOverride(date) ?? date.weekday;

    NextClassOccurrence? best;
    for (final course in courses) {
      if (course.dayOfWeek != effDow) continue;
      if (!course.isActiveOnWeek(rawWeek)) continue;
      final period = _periodOf(periods, course.startSection);
      if (period == null) continue;
      final start = DateTime(
        date.year,
        date.month,
        date.day,
        period.startHour,
        period.startMinute,
      );
      if (!start.isAfter(from)) continue; // 已开始（或正在上）的跳过
      if (best == null || start.isBefore(best.startsAt)) {
        best = NextClassOccurrence(course: course, startsAt: start, isToday: offset == 0);
      }
    }
    if (best != null) return best;
  }
  return null;
}

Period? _periodOf(List<Period> periods, int section) {
  for (final p in periods) {
    if (p.section == section) return p;
  }
  return null;
}
