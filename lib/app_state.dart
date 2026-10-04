/// 应用状态 —— 全局状态管理（Provider）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/display_prefs.dart';
import '../models/holiday_calendar.dart';
import '../models/period.dart';
import '../models/reminder_prefs.dart';
import '../models/timetable.dart';
import '../services/holiday_sync_service.dart';
import '../services/reminder_service.dart';
import '../services/widget_service.dart';
import '../storage/display_store.dart';
import '../storage/holiday_store.dart';
import '../storage/period_store.dart';
import '../storage/reminder_store.dart';
import '../storage/timetable_store.dart';

/// 全局应用状态。
class AppState extends ChangeNotifier {
  List<Timetable> _timetables = [];
  Timetable? _active;
  int _currentWeek = 1;
  bool _loaded = false;

  ReminderPrefs _reminderPrefs = ReminderPrefs();
  ReminderDeviceStatus? _reminderStatus;
  ReminderSyncResult? _lastSync;
  bool _syncing = false;

  DisplayPrefs _displayPrefs = DisplayPrefs();
  HolidayCalendar _holidays = HolidayCalendar.builtin();
  HolidayMeta _holidayMeta = const HolidayMeta();

  List<Timetable> get timetables => _timetables;
  Timetable? get active => _active;
  int get currentWeek => _currentWeek;
  bool get loaded => _loaded;

  /// 课表显示偏好（周六日 / 非本周课程）。
  DisplayPrefs get displayPrefs => _displayPrefs;

  /// 法定节假日 + 调休补班日日历（提醒排布要用）。
  HolidayCalendar get holidays => _holidays;

  /// 这份日历哪来的（内置 / 联网 / 手动）与上次联网更新时间。
  HolidayMeta get holidayMeta => _holidayMeta;

  /// 提醒偏好。
  ReminderPrefs get reminderPrefs => _reminderPrefs;

  /// 设备 / 权限 / 排布状态（首次刷新前为 null）。
  ReminderDeviceStatus? get reminderStatus => _reminderStatus;

  /// 最近一次排布结果。
  ReminderSyncResult? get lastSync => _lastSync;

  /// 当前平台是否支持原生课程提醒（仅 Android）。
  bool get remindersSupported => ReminderService.supported;

  /// 课程提醒当前是否处于「已开启且可生效」状态。
  bool get remindersActive =>
      remindersSupported && _reminderPrefs.hasAnyTrigger && _active != null;

  /// 当前生效的节次时间表（用户可在「设置 → 节次时间」里改）。
  List<Period> get periods => activePeriods;

  /// 节次时间是否已被用户改过（与出厂作息不同）。
  bool get hasCustomPeriods => periodsCustomized();

  /// 初始化，从本地加载。
  Future<void> init() async {
    _timetables = await TimetableStore.loadAll();
    _active = await TimetableStore.loadActive();
    _reminderPrefs = await ReminderStore.load();
    _displayPrefs = await DisplayStore.load();
    _holidays = await HolidayStore.load();
    _holidayMeta = await HolidayStore.loadMeta();
    // 节次时间要在 syncReminders() 之前就位：提醒排布是拿这份时间算的
    final savedPeriods = await PeriodStore.load();
    if (savedPeriods != null) {
      setActivePeriods(savedPeriods);
    } else {
      resetActivePeriods();
    }
    _loaded = true;
    _autoDetectWeek();
    notifyListeners();

    // 启动时对齐一次原生排布（原生侧有 14 天滚动窗口 + 每日巡检闹钟，
    // 这里主要是让「应用被杀/重装后」的计划与实际课表保持一致）。
    await refreshReminderStatus();
    await syncReminders();
    // 桌面小组件也同步一份（它可能在 App 没启动时就被系统唤醒去画）。
    // 同样不 await：见 _syncAfterChange 里的说明。
    unawaited(WidgetService.sync(timetable: _active));
    // 节假日日历：从没联网更新过、或距上次超过 30 天就静默试一次。
    // 不 await（不能拖慢启动），失败什么都不改；测试环境不联网。
    if (HolidaySyncService.autoSyncEnabled && _shouldAutoSyncHolidays()) {
      unawaited(syncHolidaysFromNetwork(silent: true));
    }
  }

  /// 该不该自动联网更新节假日日历。
  ///
  /// ⚠️ **手动改过的日历不自动覆盖**：用户在节假日页删/加的日子是他的选择，
  /// 启动时悄悄换掉比不更新更糟。想强制更新就点页面上的「立即联网更新」。
  bool _shouldAutoSyncHolidays() {
    if (_holidayMeta.source == HolidayStore.sourceManual) return false;
    if (_holidayMeta.source != HolidayStore.sourceNet) return true;
    final at = _holidayMeta.updatedAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > const Duration(days: 30);
  }

  /// 自动检测当前教学周。
  void _autoDetectWeek() {
    if (_active == null || _active!.startDate == null) {
      _currentWeek = 1;
      return;
    }
    final start = _active!.startDate!;
    final now = DateTime.now();
    final diff = now.difference(start).inDays;
    final week = (diff ~/ 7) + 1;
    if (week < 1) {
      _currentWeek = 1;
    } else if (week > _active!.totalWeeks) {
      _currentWeek = _active!.totalWeeks;
    } else {
      _currentWeek = week;
    }
  }

  /// 切换当前周。
  void setCurrentWeek(int week) {
    final max = _active?.totalWeeks ?? 20;
    _currentWeek = week.clamp(1, max);
    notifyListeners();
  }

  /// 下一周。
  void nextWeek() => setCurrentWeek(_currentWeek + 1);

  /// 上一周。
  void prevWeek() => setCurrentWeek(_currentWeek - 1);

  /// 添加课表。
  Future<void> addTimetable(Timetable tt) async {
    _timetables.add(tt);
    await TimetableStore.save(tt);
    // 若没有激活课表，自动激活第一个
    if (_active == null) {
      await setActive(tt.id);
    }
    notifyListeners();
    await _syncAfterChange();
  }

  /// 更新课表。
  Future<void> updateTimetable(Timetable tt) async {
    final idx = _timetables.indexWhere((e) => e.id == tt.id);
    if (idx >= 0) {
      _timetables[idx] = tt;
    }
    await TimetableStore.save(tt);
    if (_active?.id == tt.id) {
      _active = tt;
    }
    notifyListeners();
    await _syncAfterChange();
  }

  /// 删除课表。
  Future<void> removeTimetable(String id) async {
    _timetables.removeWhere((e) => e.id == id);
    await TimetableStore.delete(id);
    if (_active?.id == id) {
      _active = _timetables.isNotEmpty ? _timetables.first : null;
      if (_active != null) {
        await TimetableStore.setActive(_active!.id);
      }
    }
    notifyListeners();
    await _syncAfterChange();
  }

  /// 设置激活课表。
  Future<void> setActive(String id) async {
    for (final t in _timetables) {
      if (t.id == id) {
        _active = t;
        await TimetableStore.setActive(id);
        _autoDetectWeek();
        notifyListeners();
        await _syncAfterChange();
        return;
      }
    }
  }

  /// 设置学期起始日期。
  Future<void> setStartDate(String id, DateTime date) async {
    final tt = _timetables.firstWhere((e) => e.id == id);
    tt.startDate = date;
    await TimetableStore.save(tt);
    _autoDetectWeek();
    notifyListeners();
    await _syncAfterChange();
  }

  /// 重命名课表。
  Future<void> renameTimetable(String id, String newName) async {
    final tt = _timetables.firstWhere((e) => e.id == id);
    tt.name = newName;
    await TimetableStore.save(tt);
    notifyListeners();
  }

  // ------------------------------------------------------------ 节次时间

  /// 保存自定义节次时间并立刻重排提醒。
  ///
  /// 课表网格上显示的节次时间、首页倒计时、以及原生侧的提醒时刻全都读同一份
  /// [activePeriods]，所以改完必须重排一次，否则闹钟还停在旧作息上。
  Future<void> updatePeriods(List<Period> list) async {
    setActivePeriods(list);
    await PeriodStore.save(activePeriods);
    notifyListeners();
    await _syncAfterChange();
  }

  /// 恢复出厂作息。
  Future<void> resetPeriods() async {
    resetActivePeriods();
    await PeriodStore.clear();
    notifyListeners();
    await _syncAfterChange();
  }

  // ------------------------------------------------------------ 课表显示

  /// 更新课表显示偏好（周六日 / 非本周课程）。
  ///
  /// 纯展示开关，与提醒排布无关，因此不需要重排闹钟，只通知界面重画。
  Future<void> updateDisplayPrefs(DisplayPrefs prefs) async {
    _displayPrefs = prefs;
    await DisplayStore.save(prefs);
    notifyListeners();
  }

  // ------------------------------------------------------------ 节假日

  /// 更新法定节假日 / 调休补班日日历，并立即重排提醒。
  ///
  /// 必须重排：放假意味着那几天不该有闹钟，改完日历不重排就还是按旧日历响。
  ///
  /// [source] 记录这份日历怎么来的（[HolidayStore.sourceManual] /
  /// [HolidayStore.sourceNet] / [HolidayStore.sourceBuiltin]），设置页据此显示
  /// 「数据来源」。
  Future<ReminderSyncResult> updateHolidays(
    HolidayCalendar calendar, {
    String source = HolidayStore.sourceManual,
    DateTime? updatedAt,
  }) async {
    _holidays = calendar.sorted();
    await HolidayStore.save(_holidays);
    await _saveHolidayMeta(source: source, updatedAt: updatedAt);
    notifyListeners();
    return syncReminders();
  }

  /// 恢复内置的那份节假日日历。
  Future<ReminderSyncResult> resetHolidays() async {
    await HolidayStore.clear();
    _holidays = HolidayCalendar.builtin();
    await _saveHolidayMeta(source: HolidayStore.sourceBuiltin);
    notifyListeners();
    return syncReminders();
  }

  /// 联网更新法定节假日 / 调休补班日日历。
  ///
  /// 不抛异常：失败时 [HolidaySyncOutcome.ok] 为 false、日历原样不动，调用方
  /// 把 [HolidaySyncOutcome.note] 显示给用户即可。[silent] 为 true 时（启动时
  /// 的静默同步）连界面提示都不做。
  Future<HolidaySyncOutcome> syncHolidaysFromNetwork({bool silent = false}) async {
    final outcome = await HolidaySyncService.update(_holidays);
    // 真机取证的唯一线索：logcat 里能看到这次联网到底成不成、拿到多少天。
    debugPrint(
      'HolidaySync: ok=${outcome.ok} note=${outcome.note} '
      '放假=${outcome.calendar.holidays.length} 补班=${outcome.calendar.makeups.length} '
      'silent=$silent',
    );
    if (!outcome.ok) return outcome;
    _holidays = outcome.calendar;
    await HolidayStore.save(_holidays);
    await _saveHolidayMeta(
      source: HolidayStore.sourceNet,
      updatedAt: DateTime.now(),
    );
    if (!silent) notifyListeners();
    // 静默同步也要重排：新拿到的放假日必须真的从闹钟里去掉。
    await syncReminders();
    return outcome;
  }

  Future<void> _saveHolidayMeta({
    required String source,
    DateTime? updatedAt,
  }) async {
    _holidayMeta = HolidayMeta(source: source, updatedAt: updatedAt);
    await HolidayStore.saveMeta(source: source, updatedAt: updatedAt);
  }

  // ------------------------------------------------------------ 课程提醒

  /// 更新提醒偏好并立即重排。
  Future<ReminderSyncResult> updateReminderPrefs(ReminderPrefs prefs) async {
    _reminderPrefs = prefs;
    await ReminderStore.save(prefs);
    notifyListeners();
    return syncReminders();
  }

  /// 刷新设备 / 权限状态。
  Future<void> refreshReminderStatus() async {
    _reminderStatus = await ReminderService.status();
    notifyListeners();
  }

  /// 把当前课表与偏好下发到原生侧并重排闹钟。
  Future<ReminderSyncResult> syncReminders() async {
    if (!ReminderService.supported) {
      _lastSync = const ReminderSyncResult(
        ok: false,
        note: '当前平台不支持课程提醒（仅 Android 版可用）。',
      );
      return _lastSync!;
    }
    if (_syncing) {
      return _lastSync ??
          const ReminderSyncResult(ok: false, note: '正在排布中…');
    }
    _syncing = true;
    try {
      final tt = _active;
      if (tt == null) {
        await ReminderService.cancelAll();
        _lastSync = const ReminderSyncResult(ok: true, note: '还没有课表，已清除提醒。');
        return _lastSync!;
      }

      final payload =
          ReminderService.buildPlanPayload(tt, _reminderPrefs, _holidays);
      if (payload == null) {
        // 没有学期起始日期时无法计算「第几周」，排布出来的提醒会永远按第 1 周重复。
        await ReminderService.cancelAll();
        _lastSync = const ReminderSyncResult(
          ok: false,
          note: '课表还没有学期起始日期，无法计算周次。请在「设置 → 学期起始日期」中设置后再开启提醒。',
        );
        return _lastSync!;
      }

      _lastSync = await ReminderService.syncPlan(payload);
      _reminderStatus = await ReminderService.status();
      return _lastSync!;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// 课表变化后的静默重排：不阻塞 UI，失败也不影响本地状态。
  Future<void> _syncAfterChange() async {
    // 桌面小组件顺带同步。**故意不 await**：它要过一次平台通道，
    // 在 widget 测试里没有桩时那个 Future 会一直挂着，一 await 就会把
    // `pumpAndSettle()` 拖死（轮询空转到超时）。反正它自己吞异常，
    // 早一点晚一点画出来都无所谓。
    unawaited(WidgetService.sync(timetable: _active));
    try {
      await syncReminders();
    } catch (_) {
      // 原生侧异常不应影响课表本身的增删改。
    }
  }
}
