/// 本地持久化 —— 用户自定义的节次时间表。
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/period.dart';

/// 节次时间的存取。
///
/// 存的是 `["08:20-09:05", "09:15-10:00", ...]` 这种紧凑字符串，
/// **下标即节次-1**（第 1 节在第 0 位），所以不存节次号也不会错位。
class PeriodStore {
  static const String _key = 'njtc_periods';
  static const String _keyVersion = 'njtc_periods_version';

  /// 出厂作息的版本号。**改了 `defaultPeriods` 就把这个数 +1**。
  ///
  /// 有了它才能区分「用户自己调过的时间」和「当初原样保存的旧默认值」：
  /// 后者在升级后应当让位给新作息，前者必须原样保留。
  static const int currentVersion = 2;

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
    final list = normalizePeriods(parsed);

    // 出厂作息换过版（学校 2026-05-06 起执行统一作息）：
    // 老存档如果和**当时的出厂默认**一字不差，说明用户只是打开页面原样保存过，
    // 并没有真的调过时间 —— 那就丢掉它，让 App 用上新作息，否则课程提醒会
    // 一直按已经作废的时间响。用户真正改过的那份不会匹配上，照旧返回。
    final version = prefs.getInt(_keyVersion) ?? 1;
    if (version < currentVersion && _sameAs(list, legacyDefaultPeriods)) {
      return null;
    }
    return list;
  }

  /// 保存节次时间。
  static Future<void> save(List<Period> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      normalizePeriods(list).map((e) => e.encode()).toList(),
    );
    await prefs.setInt(_keyVersion, currentVersion);
  }

  /// 清除自定义（恢复出厂作息）。
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_keyVersion);
  }

  /// 两份节次表是否逐节相同（只比时间，不看 label）。
  static bool _sameAs(List<Period> a, List<Period> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].encode() != b[i].encode()) return false;
    }
    return true;
  }
}
