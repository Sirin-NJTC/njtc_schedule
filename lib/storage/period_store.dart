/// 本地持久化 —— 用户自定义的节次时间表。
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/period.dart';

/// 节次时间的存取。
///
/// 存的是 `["08:00-08:45", "08:55-09:40", ...]` 这种紧凑字符串，
/// **下标即节次-1**（第 1 节在第 0 位），所以不存节次号也不会错位。
class PeriodStore {
  static const String _key = 'njtc_periods';

  /// 读取用户改过的节次时间；没存过或存坏了都返回 null（表示用出厂默认）。
  static Future<List<Period>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key);
    if (raw == null || raw.isEmpty) return null;

    final parsed = <Period>[];
    for (var i = 0; i < raw.length; i++) {
      final p = Period.decode(i + 1, raw[i]);
      if (p != null) parsed.add(p);
    }
    if (parsed.isEmpty) return null;
    return normalizePeriods(parsed);
  }

  /// 保存节次时间。
  static Future<void> save(List<Period> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      normalizePeriods(list).map((e) => e.encode()).toList(),
    );
  }

  /// 清除自定义（恢复出厂作息）。
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
