/// 法定节假日的**联网更新**。
///
/// 数据源：`https://timor.tech/api/holiday/year/<年>`，返回形如
///
/// ```json
/// {"code":0,"holiday":{
///   "10-01":{"holiday":true,"name":"国庆节","date":"2026-10-01"},
///   "10-10":{"holiday":false,"name":"国庆节后补班","after":true,"target":"国庆节","date":"2026-10-10"}}}
/// ```
///
/// 规则：`holiday: true` 是**放假日**；`holiday: false` 是**调休补班日**。
/// 未公布的年份返回空 `holiday`（`{"code":0,"holiday":{}}`），那不是错误。
///
/// 接口**不告诉**补班那天按周几上课（国务院通知也不写，各校自定），所以这里按
/// 惯例推导，并在备注里写明「请核对」：
/// * 补班日在假期**之后**（`after: true`）→ 取假期内**最后一个工作日**的周几；
///   例：2026 元旦 01-01(四)~01-03(六) 放假、01-04(日) 补班 → 按周五。
/// * 补班日在假期**之前**（`after: false`）→ 取假期内**第一个工作日**的周几；
///   例：2026 春节 02-15(日)~02-23(一) 放假、02-14(六) 补班 → 按周一。
///
/// 只在设置页手动点「联网更新」时联网；另外 App 启动时若**从没联网更新过**或
/// 距上次更新超过 30 天，会静默试一次（失败不影响任何东西，`FLUTTER_TEST`
/// 环境下不联网）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/holiday_calendar.dart';

/// 联网更新失败（网络不通 / HTTP 非 200 / 接口改了格式）。
class HolidaySyncException implements Exception {
  HolidaySyncException(this.message);

  /// 给用户看的一句话。
  final String message;

  @override
  String toString() => message;
}

/// 某一年的联网数据。
class HolidayYearData {
  const HolidayYearData({
    required this.year,
    this.holidays = const <HolidayDay>[],
    this.makeups = const <MakeupDay>[],
  });

  final int year;
  final List<HolidayDay> holidays;
  final List<MakeupDay> makeups;

  /// 这一年接口没给数据（还没公布）。
  bool get isEmpty => holidays.isEmpty && makeups.isEmpty;

  @override
  String toString() => '$year 年：放假 ${holidays.length} 天 · 补班 ${makeups.length} 天';
}

/// 一次联网更新的结果。
class HolidaySyncOutcome {
  const HolidaySyncOutcome({
    required this.ok,
    required this.calendar,
    this.note = '',
    this.years = const <int>[],
  });

  /// 是否成功；失败时 [calendar] 就是原样返回的旧日历（调用方不该覆盖存档）。
  final bool ok;
  final HolidayCalendar calendar;

  /// 成功时是「更新了哪几年」，失败时是错误原因。
  final String note;

  /// 本次覆盖到的年份。
  final List<int> years;
}

/// 节假日联网更新。
class HolidaySyncService {
  HolidaySyncService._();

  /// 接口地址（年份拼在后面）。
  static const String apiBase = 'https://timor.tech/api/holiday/year';

  /// 单年请求超时。
  static const Duration timeout = Duration(seconds: 12);

  static const String userAgent = 'njtc_schedule (+android)';

  /// 测试用：替换真正的 HTTP 请求（返回响应体）。
  @visibleForTesting
  static Future<String> Function(Uri uri)? getOverride;

  /// 测试用：强制打开「会自动同步」，用来验「启动时到底会不会静默更新」
  /// （`flutter test` 下 [autoSyncEnabled] 恒为 false，否则用例会打真网络）。
  @visibleForTesting
  static bool forceAutoSync = false;

  /// 是否允许自动同步：Web 与 `flutter test` 环境下不联网（测试要确定性）。
  static bool get autoSyncEnabled =>
      !kIsWeb &&
      (forceAutoSync || Platform.environment['FLUTTER_TEST'] != 'true');

  /// 学期跨年，所以默认取今年与明年。
  static List<int> yearsFor(DateTime now) => <int>[now.year, now.year + 1];

  /// 跑一次联网更新；**不抛异常**，失败也返回结果（`ok == false`）。
  static Future<HolidaySyncOutcome> update(
    HolidayCalendar base, {
    DateTime? now,
    Iterable<int>? years,
  }) async {
    final wanted = (years ?? yearsFor(now ?? DateTime.now())).toList()..sort();
    try {
      final fetched = await fetch(wanted);
      final covered = fetched.where((y) => !y.isEmpty).toList();
      if (covered.isEmpty) {
        return HolidaySyncOutcome(
          ok: false,
          calendar: base,
          note: '接口还没公布 ${wanted.join('、')} 年的放假安排',
          years: wanted,
        );
      }
      return HolidaySyncOutcome(
        ok: true,
        calendar: merge(base, fetched),
        note: covered.map((y) => '${y.year} 年').join('、'),
        years: covered.map((y) => y.year).toList(),
      );
    } on HolidaySyncException catch (e) {
      return HolidaySyncOutcome(
        ok: false,
        calendar: base,
        note: e.message,
        years: wanted,
      );
    } catch (e) {
      return HolidaySyncOutcome(
        ok: false,
        calendar: base,
        note: '联网更新失败：$e',
        years: wanted,
      );
    }
  }

  /// 逐年前往接口取数据（任何一年失败都算整体失败）。
  static Future<List<HolidayYearData>> fetch(Iterable<int> years) async {
    final out = <HolidayYearData>[];
    for (final y in years) {
      final uri = Uri.parse('$apiBase/$y');
      final String body;
      try {
        body = await _get(uri);
      } on HolidaySyncException {
        rethrow;
      } catch (e) {
        throw HolidaySyncException('连不上接口（$e）');
      }
      out.add(parseYear(body, y));
    }
    return out;
  }

  static Future<String> _get(Uri uri) async {
    final override = getOverride;
    if (override != null) return override(uri);
    final resp = await http
        .get(uri, headers: <String, String>{
          'User-Agent': userAgent,
          'Accept': 'application/json',
        })
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw HolidaySyncException('接口返回 HTTP ${resp.statusCode}');
    }
    return resp.body;
  }

  /// 解析一年的返回体（纯函数，便于测）。
  ///
  /// 未公布的年份返回空的 [HolidayYearData]；格式不对才抛 [HolidaySyncException]。
  static HolidayYearData parseYear(String body, int year) {
    final Object? root;
    try {
      root = jsonDecode(body);
    } catch (_) {
      throw HolidaySyncException('接口返回的不是 JSON');
    }
    if (root is! Map) throw HolidaySyncException('接口返回的不是 JSON 对象');
    final code = root['code'];
    if (code != null && code != 0) {
      final msg = root['msg'] == null ? '' : ' ${root['msg']}';
      throw HolidaySyncException('接口返回 code=$code$msg');
    }
    final raw = root['holiday'];
    if (raw is! Map || raw.isEmpty) {
      return HolidayYearData(year: year);
    }

    final holidays = <HolidayDay>[];
    final holidayDays = <int>{};
    final pending = <_RawMakeup>[];
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final date = _dateOf(value['date'], entry.key, year);
      if (date == null) continue;
      final name = (value['name'] as String?)?.trim() ?? '';
      if (value['holiday'] == true) {
        holidays.add(HolidayDay(date, name.isEmpty ? '法定节假日' : name));
        holidayDays.add(epochDayOf(date));
      } else {
        pending.add(
          _RawMakeup(
            date: date,
            name: name.isEmpty ? '调休补班' : name,
            after: value['after'] == true,
            target: (value['target'] as String?)?.trim() ?? '',
          ),
        );
      }
    }

    final makeups = <MakeupDay>[];
    for (final m in pending) {
      final weekday = deriveMakeupWeekday(
            date: m.date,
            after: m.after,
            holidayEpochDays: holidayDays,
          ) ??
          m.date.weekday;
      makeups.add(MakeupDay(m.date, weekday, '联网：${m.name}'));
    }

    // 同一天既放假又补班时以放假为准（原生侧也是先判放假），免得列表自相矛盾。
    final cleaned = <MakeupDay>[
      for (final m in makeups)
        if (!holidayDays.contains(epochDayOf(m.date))) m,
    ];
    return HolidayYearData(year: year, holidays: holidays, makeups: cleaned)
        ._sorted();
  }

  /// 按惯例推导补班日「按周几上课」。
  ///
  /// 找不到假期（接口只给了补班日）或假期里没有工作日时返回 null，调用方退回
  /// 这天自己的周几。
  static int? deriveMakeupWeekday({
    required DateTime date,
    required bool after,
    required Set<int> holidayEpochDays,
  }) {
    if (holidayEpochDays.isEmpty) return null;
    // after=true：补班在假期后面 → 往回找假期；after=false：往前找。
    final step = after ? -1 : 1;
    var probe = date;
    int? hit;
    for (var i = 0; i < 30; i++) {
      probe = probe.add(Duration(days: step));
      if (holidayEpochDays.contains(epochDayOf(probe))) {
        hit = epochDayOf(probe);
        break;
      }
    }
    if (hit == null) return null;
    // 把那一段连续的假期完整展开。
    var start = hit;
    while (holidayEpochDays.contains(start - 1)) {
      start -= 1;
    }
    var end = hit;
    while (holidayEpochDays.contains(end + 1)) {
      end += 1;
    }
    final workdays = <int>[];
    for (var e = start; e <= end; e++) {
      final d = DateTime.fromMillisecondsSinceEpoch(
        e * Duration.millisecondsPerDay,
        isUtc: true,
      );
      if (d.weekday <= DateTime.friday) workdays.add(d.weekday);
    }
    if (workdays.isEmpty) return null;
    return after ? workdays.last : workdays.first;
  }

  /// 把联网数据合进现有日历：**联网覆盖到的年份整年替换**，没覆盖到的年份
  /// （比如接口还没公布的明年、或者用户自己加的日子）保持不动。
  static HolidayCalendar merge(
    HolidayCalendar base,
    Iterable<HolidayYearData> fetched,
  ) {
    final list = fetched.where((y) => !y.isEmpty).toList();
    final covered = list.map((y) => y.year).toSet();

    // 后写的覆盖先写的：先放用户原有的（不在覆盖年份里的），再放联网的。
    final holidays = <int, HolidayDay>{};
    for (final h in base.holidays) {
      if (!covered.contains(h.date.year)) holidays[epochDayOf(h.date)] = h;
    }
    for (final h in list.expand((y) => y.holidays)) {
      holidays[epochDayOf(h.date)] = h;
    }
    final makeups = <int, MakeupDay>{};
    for (final m in base.makeups) {
      if (!covered.contains(m.date.year)) makeups[epochDayOf(m.date)] = m;
    }
    for (final m in list.expand((y) => y.makeups)) {
      makeups[epochDayOf(m.date)] = m;
    }
    return HolidayCalendar(
      holidays: holidays.values.toList(),
      makeups: makeups.values.toList(),
    ).sorted();
  }

  /// 联网更新会覆盖掉多少条「现有日历里有、联网数据里没有」的记录（覆盖年份内）。
  ///
  /// 只用来在动手前提醒用户「你自己加的那几天会被冲掉」。
  static int countDropped(
    HolidayCalendar base,
    Iterable<HolidayYearData> fetched,
  ) {
    final list = fetched.where((y) => !y.isEmpty).toList();
    final covered = list.map((y) => y.year).toSet();
    final keepHolidays = list.expand((y) => y.holidays).map((h) => epochDayOf(h.date)).toSet();
    final keepMakeups = list.expand((y) => y.makeups).map((m) => epochDayOf(m.date)).toSet();
    var dropped = 0;
    for (final h in base.holidays) {
      if (covered.contains(h.date.year) && !keepHolidays.contains(epochDayOf(h.date))) {
        dropped++;
      }
    }
    for (final m in base.makeups) {
      if (covered.contains(m.date.year) && !keepMakeups.contains(epochDayOf(m.date))) {
        dropped++;
      }
    }
    return dropped;
  }
}

/// 接口里一条补班日的原始信息（周几还要推导）。
class _RawMakeup {
  const _RawMakeup({
    required this.date,
    required this.name,
    required this.after,
    required this.target,
  });

  final DateTime date;
  final String name;
  final bool after;
  final String target;

  @override
  String toString() => '$_RawMakeup($date, $name, after: $after, target: $target)';
}

extension on HolidayYearData {
  HolidayYearData _sorted() => HolidayYearData(
        year: year,
        holidays: [...holidays]..sort((a, b) => a.date.compareTo(b.date)),
        makeups: [...makeups]..sort((a, b) => a.date.compareTo(b.date)),
      );
}

/// `2026-10-01` / `10-01`（配年份）→ DateTime；认不出来返回 null。
DateTime? _dateOf(Object? raw, Object? key, int year) {
  final text = raw is String ? raw : (key is String ? key : null);
  if (text == null) return null;
  final parts = text.split('-');
  try {
    if (parts.length == 3) {
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    }
    if (parts.length == 2) {
      return DateTime(year, int.parse(parts[0]), int.parse(parts[1]));
    }
  } catch (_) {
    return null;
  }
  return null;
}
