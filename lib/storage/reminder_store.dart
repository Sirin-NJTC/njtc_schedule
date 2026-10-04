/// 课程提醒偏好的本地持久化（shared_preferences）。
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder_prefs.dart';

/// 提醒偏好存取。
class ReminderStore {
  ReminderStore._();

  static const String _keyEnabled = 'njtc_reminder_enabled';
  static const String _keyLeads = 'njtc_reminder_leads';
  static const String _keyEnd = 'njtc_reminder_end';
  static const String _keyEndPreview = 'njtc_reminder_end_preview_minutes';
  static const String _keyVivoAtomic = 'njtc_reminder_vivo_atomic';
  static const String _keySkipHolidays = 'njtc_reminder_skip_holidays';

  /// 读取偏好；从未保存过时返回默认值（提前 30/15/5 分钟 + 下课前 5 分钟预告）。
  static Future<ReminderPrefs> load() async {
    final sp = await SharedPreferences.getInstance();
    final rawLeads = sp.getStringList(_keyLeads);
    final leads = rawLeads
        ?.map(int.tryParse)
        .whereType<int>()
        .where(ReminderPrefs.leadOptions.contains)
        .toSet();
    return ReminderPrefs(
      enabled: sp.getBool(_keyEnabled) ?? true,
      leadMinutes: leads == null || leads.isEmpty
          ? {...ReminderPrefs.defaultLeadMinutes}
          : leads,
      endReminder: sp.getBool(_keyEnd) ?? true,
      endPreviewMinutes: sp.getInt(_keyEndPreview) ??
          ReminderPrefs.defaultEndPreviewMinutes,
      vivoAtomic: sp.getBool(_keyVivoAtomic) ?? true,
      skipHolidays: sp.getBool(_keySkipHolidays) ?? true,
    );
  }

  /// 保存偏好。
  static Future<void> save(ReminderPrefs prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyEnabled, prefs.enabled);
    await sp.setStringList(
      _keyLeads,
      prefs.sortedLeads.map((e) => e.toString()).toList(),
    );
    await sp.setBool(_keyEnd, prefs.endReminder);
    await sp.setInt(_keyEndPreview, prefs.endPreviewMinutes);
    await sp.setBool(_keyVivoAtomic, prefs.vivoAtomic);
    await sp.setBool(_keySkipHolidays, prefs.skipHolidays);
  }
}
