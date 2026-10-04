/// 法定节假日 / 调休补班日日历。
///
/// 用途只有一个：**放假那天别弹课程提醒**（可选开关），以及
/// **调休补班那天按「周几」的课表排提醒**（比如「10 月 10 日周六补周三的课」）。
///
/// 内置的日期是按公开日历整理的（学期内会遇到的：中秋 / 国庆 / 元旦），
/// 但**学校的具体调休安排以学校通知为准**，所以这份日历在
/// 「设置 → 法定节假日」里可以自行增删改。
library;

/// 本地日期 → epochDay（1970-01-01 起的天数，按 UTC 算，只取年月日）。
///
/// 与原生 `DayMath` 的算法一致，两侧对同一日期必须得到同一个数字。
int epochDayOf(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

/// 一个放假日（法定节假日 / 调休放假日）。
class HolidayDay {
  /// 日期（只用到年月日）。
  final DateTime date;

  /// 名称，如「国庆节」「中秋节假期」。
  final String name;

  const HolidayDay(this.date, this.name);

  /// 存档 / 下发给原生侧的一行文本：`2026-10-01|国庆节`。
  String toWire() => '${_ymd(date)}|$name';

  /// 解析 [toWire] 的产物；格式不对返回 null（宁可少一天，也不要崩）。
  static HolidayDay? parse(String raw) {
    final parts = raw.split('|');
    if (parts.length < 2) return null;
    final date = _parseYmd(parts[0]);
    if (date == null) return null;
    return HolidayDay(date, parts.sublist(1).join('|'));
  }

  @override
  String toString() => '${_ymd(date)} $name';
}

/// 一个调休补班日：这天虽然可能是周末，但**按 [weekday] 的课表上课**。
///
/// 例：学校通知「10 月 10 日（周六）补 10 月 7 日（周三）的课」时，
/// 就加一条 `MakeupDay(2026-10-10, 3, '补周三的课')`。
class MakeupDay {
  /// 补班日期。
  final DateTime date;

  /// 这天按周几的课表上课（ISO：1=周一 … 7=周日）。
  final int weekday;

  /// 备注，如「补周三的课」。
  final String note;

  const MakeupDay(this.date, this.weekday, this.note);

  /// 「周三」这样的中文标签。
  static const List<String> weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  /// 周几的中文名，如「周三」。
  String get weekdayText => '周${weekdayLabels[(weekday - 1).clamp(0, 6)]}';

  /// 存档 / 下发的一行文本：`2026-10-10|3|补周三的课`。
  String toWire() => '${_ymd(date)}|$weekday|$note';

  static MakeupDay? parse(String raw) {
    final parts = raw.split('|');
    if (parts.length < 2) return null;
    final date = _parseYmd(parts[0]);
    final weekday = int.tryParse(parts[1]);
    if (date == null || weekday == null || weekday < 1 || weekday > 7) {
      return null;
    }
    return MakeupDay(date, weekday, parts.length > 2 ? parts.sublist(2).join('|') : '');
  }

  @override
  String toString() => '${_ymd(date)} 按$weekdayText上课 $note'.trim();
}

/// 节假日日历。
class HolidayCalendar {
  /// 放假日（这些天不排提醒）。
  final List<HolidayDay> holidays;

  /// 调休补班日（这些天按指定周几的课表排提醒）。
  final List<MakeupDay> makeups;

  const HolidayCalendar({
    this.holidays = const <HolidayDay>[],
    this.makeups = const <MakeupDay>[],
  });

  /// 出厂内置：2026-2027 学年秋季学期会遇到的法定节假日。
  ///
  /// 只列**放假日**，补班日留空 —— 补班怎么补各校不同（「周六补周三的课」
  /// 这种安排来自学校通知），猜错会让提醒多响或漏响，交给用户在页面上加。
  factory HolidayCalendar.builtin() {
    const raw = <String, String>{
      '2026-09-25': '中秋节',
      '2026-09-26': '中秋节假期',
      '2026-09-27': '中秋节假期',
      '2026-10-01': '国庆节',
      '2026-10-02': '国庆节假期',
      '2026-10-03': '国庆节假期',
      '2026-10-04': '国庆节假期',
      '2026-10-05': '国庆节假期',
      '2026-10-06': '国庆节假期',
      '2026-10-07': '国庆节假期',
      '2027-01-01': '元旦',
      '2027-01-02': '元旦假期',
      '2027-01-03': '元旦假期',
    };
    final days = <HolidayDay>[];
    for (final e in raw.entries) {
      final d = _parseYmd(e.key);
      if (d != null) days.add(HolidayDay(d, e.value));
    }
    return HolidayCalendar(holidays: days);
  }

  /// 是否什么都没配。
  bool get isEmpty => holidays.isEmpty && makeups.isEmpty;

  /// 放假日（快查用）。
  Set<int> get holidayEpochDays =>
      holidays.map((h) => epochDayOf(h.date)).toSet();

  /// 补班日：epochDay → 按周几上课。
  Map<int, int> get makeupEpochDays => <int, int>{
        for (final m in makeups) epochDayOf(m.date): m.weekday,
      };

  /// 这天是否放假。
  bool isHoliday(DateTime day) =>
      holidayEpochDays.contains(epochDayOf(day));

  /// 这天的假日名称；不是假日返回 null。
  String? holidayName(DateTime day) {
    final key = epochDayOf(day);
    for (final h in holidays) {
      if (epochDayOf(h.date) == key) return h.name;
    }
    return null;
  }

  /// 这天是否调休补班；是则返回「按周几上课」。
  int? weekdayOverride(DateTime day) => makeupEpochDays[epochDayOf(day)];

  /// 按日期排序后的副本（UI 列表与存档都用它，避免顺序乱跳）。
  HolidayCalendar sorted() {
    final h = [...holidays]..sort((a, b) => a.date.compareTo(b.date));
    final m = [...makeups]..sort((a, b) => a.date.compareTo(b.date));
    return HolidayCalendar(holidays: h, makeups: m);
  }

  /// 下发到原生侧的补班日数组。
  List<Map<String, Object?>> makeupPayload() => makeups
      .map((m) => <String, Object?>{
            'epochDay': epochDayOf(m.date),
            'weekday': m.weekday,
          })
      .toList();

  /// UI 副标题：`放假 13 天 · 补班 0 天`。
  String get summaryText {
    if (isEmpty) return '未设置任何节假日';
    return '放假 ${holidays.length} 天 · 补班 ${makeups.length} 天';
  }

  HolidayCalendar copyWith({
    List<HolidayDay>? holidays,
    List<MakeupDay>? makeups,
  }) {
    return HolidayCalendar(
      holidays: holidays ?? this.holidays,
      makeups: makeups ?? this.makeups,
    ).sorted();
  }

  @override
  String toString() =>
      'HolidayCalendar(holidays: ${holidays.length}, makeups: ${makeups.length})';
}

// ---------------------------------------------------------------- 工具

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? _parseYmd(String s) {
  final parts = s.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}
