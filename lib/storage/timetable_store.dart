/// 本地持久化 —— 课表存储与多课表管理。
library;

import 'package:shared_preferences/shared_preferences.dart';
import '../models/timetable.dart';

/// 课表存储服务。
class TimetableStore {
  static const String _keyPrefix = 'njtc_timetable_';
  static const String _keyList = 'njtc_timetable_list';
  static const String _keyActive = 'njtc_timetable_active';

  /// 获取全部课表。
  static Future<List<Timetable>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_keyList) ?? [];
    final result = <Timetable>[];
    for (final id in ids) {
      final json = prefs.getString('$_keyPrefix$id');
      if (json != null) {
        try {
          result.add(Timetable.fromJsonString(json));
        } catch (_) {}
      }
    }
    return result;
  }

  /// 保存课表（新增或更新）。
  static Future<void> save(Timetable tt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_keyPrefix${tt.id}', tt.toJsonString());

    final ids = prefs.getStringList(_keyList) ?? [];
    if (!ids.contains(tt.id)) {
      ids.add(tt.id);
    }
    await prefs.setStringList(_keyList, ids);
  }

  /// 删除课表。
  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$id');
    final ids = prefs.getStringList(_keyList) ?? [];
    ids.remove(id);
    await prefs.setStringList(_keyList, ids);
  }

  /// 获取当前激活课表 id。
  static Future<String?> getActiveId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyActive);
  }

  /// 设置激活课表。
  static Future<void> setActive(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyActive, id);
  }

  /// 获取当前激活课表。
  static Future<Timetable?> loadActive() async {
    final prefs = await SharedPreferences.getInstance();
    final activeId = prefs.getString(_keyActive);
    final all = await loadAll();
    if (activeId != null) {
      for (final tt in all) {
        if (tt.id == activeId) return tt;
      }
    }
    // 回退：返回第一个
    return all.isNotEmpty ? all.first : null;
  }

  /// 清空全部课表。
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_keyList) ?? [];
    for (final id in ids) {
      await prefs.remove('$_keyPrefix$id');
    }
    await prefs.remove(_keyList);
    await prefs.remove(_keyActive);
  }
}
