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

/// epochDay → 本地「只含年月日」的日期（[epochDayOf] 的逆运算，不碰时区）。
DateTime dateOfEpochDay(int epochDay) {
  final d = DateTime.fromMillisecondsSinceEpoch(
    epochDay * Duration.millisecondsPerDay,
    isUtc: true,
  );
  return DateTime(d.year, d.month, d.day);
}

/// 一段假期最多几天（编辑器里也按这个限制，防止手滑选中十年）。
const int maxHolidayRangeDays = 120;

/// 把一个假日的名字归一成「同一个节日」的键。
///
/// 数据源里同一个节日的每一天名字不一定一样：内置那份写的是
/// 「国庆节 / 国庆节假期」，联网数据里春节那几天是「除夕 / 初一 / 初二…」。
/// 归一之后才能把同一次假期合并成一行显示。
String festivalKeyOf(String name) {
  var s = name.trim();
  const suffixes = <String>['假期', '放假', '假日', '休假'];
  var changed = true;
  while (changed) {
    changed = false;
    for (final suffix in suffixes) {
      if (s.length > suffix.length && s.endsWith(suffix)) {
        s = s.substring(0, s.length - suffix.length);
        changed = true;
      }
    }
  }
  // 春节的每一天在数据源里都有自己的叫法，统一归到「春节」。
  if (_springAliases.contains(s) || _springDayPattern.hasMatch(s)) return '春节';
  return s.isEmpty ? name.trim() : s;
}

const Set<String> _springAliases = <String>{
  '除夕',
  '小年',
  '大年三十',
  '年三十',
  '正月',
  '春节',
};

final RegExp _springDayPattern = RegExp(r'^初[一二三四五六七八九十]$');

/// 合并显示 / 编辑用的一段**连续**假期（同一个节日、日期挨着）。
///
/// 存储还是逐天存的（[HolidayDay]），这个类只是页面上的「一行」：
/// 写进存档、下发给原生侧的东西一个字节都没变。
class HolidayRange {
  const HolidayRange({required this.name, required this.days});

  /// 归一后的节日名（`国庆节假期` → `国庆节`），页面上的标题就是它。
  final String name;

  /// 这段里的每一天，日期升序且连续。
  final List<HolidayDay> days;

  DateTime get start => days.first.date;

  DateTime get end => days.last.date;

  int get dayCount => days.length;

  bool get isSingleDay => dayCount == 1;

  /// 这段占用的 epochDay 集合。
  Set<int> get epochDays => days.map((d) => epochDayOf(d.date)).toSet();

  /// `10月1日（周四）– 10月7日（周三）`；只有一天时是 `10月1日（周四）`。
  String get dateText {
    final s = '${start.month}月${start.day}日（${_weekText(start)}）';
    if (isSingleDay) return s;
    return '$s – ${end.month}月${end.day}日（${_weekText(end)}）';
  }

  /// `共 7 天`。
  String get countText => '共 $dayCount 天';

  /// 行副标题：`10月1日（周四）– 10月7日（周三） · 共 7 天`。
  String get subtitle => '$dateText · $countText';

  /// 这段里**接管**来的那些天原本属于哪些节日（去重，顺序按日期）。
  ///
  /// 只用来给用户提示：「删掉这一段，其中 1 天会还给国庆节」。
  List<String> get borrowedNames {
    final seen = <String>{};
    final out = <String>[];
    for (final d in days) {
      final o = d.originName;
      if (o != null && seen.add(o)) out.add(o);
    }
    return out;
  }

  /// 这段里有几天是接管来的（删掉 / 缩短会还给别的节日）。
  int get borrowedCount => days.where((d) => d.originName != null).length;

  @override
  String toString() => 'HolidayRange($name, $dateText)';
}

/// `周四` 这样的中文标签（ISO：1=周一 … 7=周日）。
String _weekText(DateTime d) => '周${MakeupDay.weekdayLabels[d.weekday - 1]}';

/// 一个放假日（法定节假日 / 调休放假日）。
class HolidayDay {
  /// 日期（只用到年月日）。
  final DateTime date;

  /// 名称，如「国庆节」「中秋节假期」。
  final String name;

  /// 被别的假期段**接管**之前，这一天的名字（原本**属于别的节日**时才记）。
  ///
  /// 例：把中秋往后延到 10 月 1 日，那天原本是国庆 —— 它会改名成「中秋节」，
  /// 同时把「国庆节」记在这里；等中秋缩回去（或那段被删掉），这一天会还原成国庆。
  /// 同一节日的不同写法（「国庆节」vs「国庆节假期」）不算接管，不记。
  final String? originName;

  const HolidayDay(this.date, this.name, {this.originName});

  /// 带接管记录的行用这个前缀开头（日期行永远以数字开头，不会撞）。
  static const String _originPrefix = '^';

  /// 存档 / 下发给原生侧的一行文本：`2026-10-01|国庆节`；
  /// 被接管过的日子在最前面加一段（`^` 开头）：`^国庆节|2026-10-01|中秋节`。
  ///
  /// 用开头的 `^` 而不是「多一个字段」来标记，是为了让老存档里
  /// 名字本身带竖线的行（`2026-10-01|国庆|中秋连休`）照样读得对。
  String toWire() {
    if (originName == null) return '${_ymd(date)}|$name';
    return '$_originPrefix${_escapeBar(originName!)}|${_ymd(date)}|$name';
  }

  /// 解析 [toWire] 的产物；格式不对返回 null（宁可少一天，也不要崩）。
  static HolidayDay? parse(String raw) {
    final parts = raw.split('|');
    if (raw.startsWith(_originPrefix)) {
      if (parts.length < 3) return null;
      final date = _parseYmd(parts[1]);
      if (date == null) return null;
      return HolidayDay(
        date,
        parts.sublist(2).join('|'),
        originName: parts[0].substring(_originPrefix.length),
      );
    }
    if (parts.length < 2) return null;
    final date = _parseYmd(parts[0]);
    if (date == null) return null;
    return HolidayDay(date, parts.sublist(1).join('|'));
  }

  @override
  String toString() =>
      '${_ymd(date)} $name${originName == null ? '' : '（原 $originName）'}';
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

  /// 按日期排序 + **同一天只留一条**的副本（UI 列表与存档都用它）。
  ///
  /// 去重是给手改存档 / 老版本数据兜底的：同一天出现两条时，`holidayName()`
  /// 只会看到先来的那条，可列表会显示成两行，看起来像 bug。
  HolidayCalendar sorted() {
    final h = _dedupeByDay(holidays);
    final m = _dedupeByDay(makeups);
    h.sort((a, b) => a.date.compareTo(b.date));
    m.sort((a, b) => a.date.compareTo(b.date));
    return HolidayCalendar(holidays: h, makeups: m);
  }

  /// 把放假日按「同一个节日 + 日期连续」合并成一段一段，给页面显示与编辑用。
  ///
  /// 例：内置那份 2026-10-01 ~ 10-07 名字是「国庆节 / 国庆节假期」，
  /// 归一后是同一个节日、日期又连着，于是合并成一行「国庆节」。
  List<HolidayRange> get holidayRanges {
    final days = _dedupeByDay(holidays)
      ..sort((a, b) => a.date.compareTo(b.date));
    final out = <HolidayRange>[];
    var i = 0;
    while (i < days.length) {
      final key = festivalKeyOf(days[i].name);
      final run = <HolidayDay>[days[i]];
      var j = i + 1;
      while (j < days.length &&
          festivalKeyOf(days[j].name) == key &&
          epochDayOf(days[j].date) == epochDayOf(run.last.date) + 1) {
        run.add(days[j]);
        j++;
      }
      out.add(HolidayRange(
        name: key.isEmpty ? '法定节假日' : key,
        days: run,
      ));
      i = j;
    }
    return out;
  }

  /// 与 [epochDays] 有重叠的假期段（用来提示「会接管哪一段的几天」）。
  ///
  /// [excluding] 是正在编辑的那一段，自己不算重叠。
  List<HolidayRange> rangesOverlapping(
    Set<int> epochDays, {
    HolidayRange? excluding,
  }) {
    final skip = excluding?.epochDays ?? const <int>{};
    return [
      for (final r in holidayRanges)
        if (r.epochDays.any(skip.contains) == false &&
            r.epochDays.intersection(epochDays).isNotEmpty)
          r,
    ];
  }

  /// 把 [start] ~ [end] 这一段假期（名字 [name]）写进日历。
  ///
  /// * [replacing] 是要被替换掉的那段（编辑时传原来那段的日子；新增时留空）。
  /// * 新范围**接管**与它重叠的其它假期（同一天只留一条，名字取这次填的），
  ///   被接管的日子会用 [HolidayDay.originName] 记住原来的节日，
  ///   将来这段缩短 / 删掉时**自动还给**那个节日。
  /// * 新范围里如果压到了补班日，那些补班安排会被删掉 —— 放假优先，
  ///   这也是原生侧 `ReminderScheduler` 的判断顺序。
  ///
  /// 天数超过 [maxHolidayRangeDays] 时按上限截断（防止手滑选成十年）。
  HolidayCalendar withHolidayRange(
    DateTime start,
    DateTime end, {
    required String name,
    Iterable<DateTime> replacing = const <DateTime>[],
  }) {
    final a = epochDayOf(start);
    final b = epochDayOf(end);
    var from = a <= b ? a : b;
    var to = a <= b ? b : a;
    if (to - from + 1 > maxHolidayRangeDays) {
      to = from + maxHolidayRangeDays - 1;
    }
    final dropped = replacing.map(epochDayOf).toSet();
    final taken = <int>{for (var e = from; e <= to; e++) e};
    final label = name.trim().isEmpty ? '法定节假日' : name.trim();
    final before = <int, HolidayDay>{
      for (final h in holidays) epochDayOf(h.date): h,
    };

    final kept = <HolidayDay>[];
    for (final h in holidays) {
      final e = epochDayOf(h.date);
      if (taken.contains(e)) continue; // 这几天由新范围重写
      if (!dropped.contains(e)) {
        kept.add(h); // 没碰到的日子原样留着
      } else if (h.originName != null) {
        kept.add(HolidayDay(h.date, h.originName!)); // 还给当初接管的那个节日
      }
      // 剩下的就是被缩短 / 挪走、本来也没主的那些天：直接没掉
    }
    final next = <HolidayDay>[
      ...kept,
      for (var e = from; e <= to; e++)
        HolidayDay(
          dateOfEpochDay(e),
          label,
          originName: _takenOverFrom(before[e], label),
        ),
    ];
    final nextMakeups = <MakeupDay>[
      for (final m in makeups)
        if (!taken.contains(epochDayOf(m.date))) m,
    ];
    return HolidayCalendar(holidays: next, makeups: nextMakeups).sorted();
  }

  /// 删掉一整段假期（合并显示后「删除」就是删这一行）。
  ///
  /// 这段里**接管来**的日子会还给它原本的节日 —— 「删除」只表示
  /// 「这些天不再是这一段的假期」，不该顺手把别的节日吃掉。
  HolidayCalendar withoutHolidayRange(HolidayRange range) {
    final gone = range.epochDays;
    final kept = <HolidayDay>[];
    for (final h in holidays) {
      final e = epochDayOf(h.date);
      if (!gone.contains(e)) {
        kept.add(h);
      } else if (h.originName != null) {
        kept.add(HolidayDay(h.date, h.originName!));
      }
    }
    return HolidayCalendar(holidays: kept, makeups: makeups).sorted();
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

/// 按 [epochDayOf] 去重，保留先出现的那条（返回可改动的新列表）。
List<T> _dedupeByDay<T>(List<T> items) {
  DateTime dateOf(T item) {
    if (item is HolidayDay) return item.date;
    if (item is MakeupDay) return item.date;
    throw ArgumentError('只支持 HolidayDay / MakeupDay，收到 ${item.runtimeType}');
  }

  final seen = <int>{};
  final out = <T>[];
  for (final item in items) {
    if (seen.add(epochDayOf(dateOf(item)))) out.add(item);
  }
  return out;
}

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 存档字段里的 `|` 换成全角竖线：它是字段分隔符，名字里带一个就会串行。
///
/// 顺带把接管记录也多一层保护 —— 只有 `日期|名字` 与 `日期|名字|接管前名字`
/// 两种形状能被解析出来。
String _escapeBar(String s) => s.replaceAll('|', '｜');

/// 接管记录：这一天原本属于**别的节日**时，把那个节日的名字记下来。
///
/// 同一节日的不同写法（`国庆节` / `国庆节假期`）不算接管，不记；
/// 已经被接管过的日子保留**最早那层**主人（连被接管两次也不会丢）。
String? _takenOverFrom(HolidayDay? old, String label) {
  if (old == null) return null;
  if (old.originName != null) return old.originName;
  final oldName = old.name.trim();
  if (oldName.isEmpty || oldName == label) return null;
  if (festivalKeyOf(oldName) == festivalKeyOf(label)) return null;
  return oldName;
}

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
