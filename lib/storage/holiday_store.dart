/// 法定节假日 / 调休补班日日历的本地持久化（shared_preferences）。
///
/// 存法：两条字符串列表，每条一行（`HolidayDay.toWire()` / `MakeupDay.toWire()`），
/// 人可读、出问题时用 `adb shell run-as` 或日志一眼能看懂。
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/holiday_calendar.dart';

/// 节假日日历存取。
class HolidayStore {
  HolidayStore._();

  static const String _keyHolidays = 'njtc_holidays';
  static const String _keyMakeups = 'njtc_holiday_makeups';
  static const String _keySource = 'njtc_holiday_source';
  static const String _keyUpdatedAt = 'njtc_holiday_updated_at';

  /// 日历来源：出厂内置（**估算值**）。
  static const String sourceBuiltin = 'builtin';

  /// 日历来源：联网更新拿到官方公布的数据。
  static const String sourceNet = 'net';

  /// 日历来源：用户在页面上手动加/改过。
  static const String sourceManual = 'manual';

  /// 读取日历；从未保存过时返回**内置的那份**（首次打开就有放假日）。
  ///
  /// 注意：用户如果把节假日全删光，存的是「空的两个列表」而不是「没有键」，
  /// 所以能区分「没设置过」和「设置成空的」。
  static Future<HolidayCalendar> load() async {
    final sp = await SharedPreferences.getInstance();
    final rawHolidays = sp.getStringList(_keyHolidays);
    final rawMakeups = sp.getStringList(_keyMakeups);
    if (rawHolidays == null && rawMakeups == null) {
      return HolidayCalendar.builtin();
    }
    return HolidayCalendar(
      holidays: (rawHolidays ?? const <String>[])
          .map(HolidayDay.parse)
          .whereType<HolidayDay>()
          .toList(),
      makeups: (rawMakeups ?? const <String>[])
          .map(MakeupDay.parse)
          .whereType<MakeupDay>()
          .toList(),
    ).sorted();
  }

  /// 保存日历。
  static Future<void> save(HolidayCalendar calendar) async {
    final sp = await SharedPreferences.getInstance();
    final sorted = calendar.sorted();
    await sp.setStringList(
      _keyHolidays,
      sorted.holidays.map((h) => h.toWire()).toList(),
    );
    await sp.setStringList(
      _keyMakeups,
      sorted.makeups.map((m) => m.toWire()).toList(),
    );
  }

  /// 清掉存档（回到「没设置过」状态，下次 [load] 又是内置那份）。
  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_keyHolidays);
    await sp.remove(_keyMakeups);
    await sp.remove(_keySource);
    await sp.remove(_keyUpdatedAt);
  }

  /// 存「这份日历哪来的、什么时候更新的」（与日历正文分开存）。
  static Future<void> saveMeta({
    required String source,
    DateTime? updatedAt,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keySource, source);
    if (updatedAt == null) {
      await sp.remove(_keyUpdatedAt);
    } else {
      await sp.setInt(_keyUpdatedAt, updatedAt.millisecondsSinceEpoch);
    }
  }

  /// 读来源信息；从没存过就当「内置」。
  static Future<HolidayMeta> loadMeta() async {
    final sp = await SharedPreferences.getInstance();
    final source = sp.getString(_keySource) ?? sourceBuiltin;
    final millis = sp.getInt(_keyUpdatedAt);
    return HolidayMeta(
      source: source,
      updatedAt:
          millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis),
    );
  }
}

/// 日历来源信息。
class HolidayMeta {
  const HolidayMeta({this.source = HolidayStore.sourceBuiltin, this.updatedAt});

  final String source;
  final DateTime? updatedAt;

  @override
  String toString() => 'HolidayMeta($source, $updatedAt)';
}
