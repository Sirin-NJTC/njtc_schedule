/// 课表显示偏好的本地持久化（shared_preferences）。
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/display_prefs.dart';

/// 显示偏好存取。
class DisplayStore {
  DisplayStore._();

  static const String _keyShowWeekend = 'njtc_display_show_weekend';
  static const String _keyShowInactive = 'njtc_display_show_inactive';

  /// 读取偏好；从未保存过时返回默认值（显示周六日 + 只显示本周课程）。
  static Future<DisplayPrefs> load() async {
    final sp = await SharedPreferences.getInstance();
    return DisplayPrefs(
      showWeekend: sp.getBool(_keyShowWeekend) ?? true,
      showInactiveCourses: sp.getBool(_keyShowInactive) ?? false,
    );
  }

  /// 保存偏好。
  static Future<void> save(DisplayPrefs prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyShowWeekend, prefs.showWeekend);
    await sp.setBool(_keyShowInactive, prefs.showInactiveCourses);
  }
}
