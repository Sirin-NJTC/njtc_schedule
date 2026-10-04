/// 课程提醒桥接层 —— 与 Android 原生 `ReminderBridge` 通信。
///
/// 原生侧负责真正的闹钟排布（AlarmManager）、开机自恢复与 vivo 原子通知投递；
/// Dart 侧只负责：把课表 + 偏好打包成 JSON 计划下发、读取设备/权限状态、预览提醒时间。
///
/// 非 Android 平台（含 `flutter test` 的 Dart VM）所有方法都会安全短路，
/// 不会抛 `MissingPluginException`。
library;

import 'dart:convert' show jsonEncode;
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../models/course.dart';
import '../models/period.dart';
import '../models/reminder_prefs.dart';
import '../models/timetable.dart';
import '../theme.dart';

/// 原生 MethodChannel 名（须与 `ReminderBridge.kt` 保持一致）。
const String kReminderChannel = 'cn.edu.njtc.njtc_schedule/reminder';

/// 设备与权限状态。
class ReminderDeviceStatus {
  const ReminderDeviceStatus({
    this.platformSupported = false,
    this.isVivo = false,
    this.isIslandCapable = false,
    this.romVersion = '',
    this.sceneEnabled,
    this.brand = '',
    this.manufacturer = '',
    this.model = '',
    this.osVersion = '',
    this.androidSdk = 0,
    this.androidRelease = '',
    this.notificationsEnabled = false,
    this.exactAlarmAllowed = false,
    this.ignoringBatteryOptimizations = false,
    this.hasPlan = false,
    this.scheduledCount = 0,
    this.lastSyncAt = 0,
    this.applyHint = '',
  });

  /// 是否运行在 Android 上（其它平台提醒功能不可用）。
  final bool platformSupported;

  /// 是否 vivo / iQOO 设备。
  final bool isVivo;

  /// 是否可能支持原子岛（vivo 官方判定：OriginOS ≥ 5.0 且未禁用原子岛）。
  final bool isIslandCapable;

  /// OriginOS 版本号（如 `5.0`），非 vivo 或取不到时为空串。
  final String romVersion;

  /// 反射查询到的原子通知场景开关；`null` 表示该 ROM 未提供此接口。
  final bool? sceneEnabled;

  final String brand;
  final String manufacturer;
  final String model;
  final String osVersion;
  final int androidSdk;
  final String androidRelease;

  /// 通知权限（Android 13+ 需运行时授予）。
  final bool notificationsEnabled;

  /// 精确闹钟权限（Android 12+ 需单独授予，否则提醒可能被延迟）。
  final bool exactAlarmAllowed;

  /// 是否已在电池优化白名单内（vivo 上还建议额外开启自启动）。
  final bool ignoringBatteryOptimizations;

  /// 原生侧是否已保存提醒计划。
  final bool hasPlan;

  /// 原生侧当前已排布的闹钟数量。
  final int scheduledCount;

  /// 上次同步时间（毫秒时间戳，0 表示从未同步）。
  final int lastSyncAt;

  /// vivo 准入提示文案（由原生侧给出）。
  final String applyHint;

  /// 是否可以正常投递提醒。
  bool get ready => platformSupported && notificationsEnabled;

  /// 设备名称展示用。
  String get deviceLabel {
    final s = '$brand $model'.trim();
    return s.isEmpty ? '未知设备' : s;
  }

  static ReminderDeviceStatus fromMap(Map<Object?, Object?> m) {
    T? pick<T>(String key) {
      final v = m[key];
      return v is T ? v : null;
    }

    return ReminderDeviceStatus(
      platformSupported: pick<bool>('platformSupported') ?? true,
      isVivo: pick<bool>('isVivo') ?? false,
      isIslandCapable: pick<bool>('isIslandCapable') ?? false,
      romVersion: pick<String>('romVersion') ?? '',
      sceneEnabled: pick<bool>('sceneEnabled'),
      brand: pick<String>('brand') ?? '',
      manufacturer: pick<String>('manufacturer') ?? '',
      model: pick<String>('model') ?? '',
      osVersion: pick<String>('osVersion') ?? '',
      androidSdk: pick<int>('androidSdk') ?? 0,
      androidRelease: pick<String>('androidRelease') ?? '',
      notificationsEnabled: pick<bool>('notificationsEnabled') ?? false,
      exactAlarmAllowed: pick<bool>('exactAlarmAllowed') ?? false,
      ignoringBatteryOptimizations:
          pick<bool>('ignoringBatteryOptimizations') ?? false,
      hasPlan: pick<bool>('hasPlan') ?? false,
      scheduledCount: pick<int>('scheduledCount') ?? 0,
      lastSyncAt: num.tryParse('${m['lastSyncAt'] ?? 0}')?.toInt() ?? 0,
      // 原生侧的真实 key 是 alwaysShowAtomicHint（见 ReminderBridge.statusMap）
      applyHint: pick<String>('alwaysShowAtomicHint') ?? '',
    );
  }
}

/// 一次排布的结果。
class ReminderSyncResult {
  const ReminderSyncResult({
    this.ok = false,
    this.scheduled = 0,
    this.horizonDays = 0,
    this.exact = false,
    this.note = '',
    this.nextTriggerAt = 0,
    this.nextTriggerText = '',
  });

  final bool ok;

  /// 已排布的闹钟数量。
  final int scheduled;

  /// 排布窗口天数（原生侧固定 14 天滚动窗口）。
  final int horizonDays;

  /// 是否用上了精确闹钟。
  final bool exact;

  /// 原生侧说明（无课、未开启等都从这里返回）。
  final String note;

  final int nextTriggerAt;

  /// 最近一次提醒的可读时间，如 `2026-10-05(周一) 09:45`。
  final String nextTriggerText;

  static ReminderSyncResult fromMap(Map<Object?, Object?> m) {
    T? pick<T>(String key) {
      final v = m[key];
      return v is T ? v : null;
    }

    return ReminderSyncResult(
      ok: pick<bool>('ok') ?? true,
      scheduled: pick<int>('scheduled') ?? 0,
      horizonDays: pick<int>('horizonDays') ?? 0,
      exact: pick<bool>('exact') ?? false,
      note: pick<String>('note') ?? '',
      nextTriggerAt: num.tryParse('${m['nextTriggerAt'] ?? 0}')?.toInt() ?? 0,
      nextTriggerText: pick<String>('nextTriggerText') ?? '',
    );
  }
}

/// 一条即将触发的提醒（预览用）。
class ReminderPreviewItem {
  const ReminderPreviewItem({
    required this.triggerAt,
    required this.timeText,
    required this.courseName,
    required this.location,
    required this.label,
    required this.isEnd,
    this.kind = 'lead',
  });

  final int triggerAt;
  final String timeText;
  final String courseName;
  final String location;
  final String label;
  final bool isEnd;

  /// 提醒种类：`lead` 单节课提醒 / `sessionPreview` 时段预告 / `endPreview` 下节课预告。
  final String kind;

  static ReminderPreviewItem fromMap(Map<Object?, Object?> m) {
    return ReminderPreviewItem(
      triggerAt: num.tryParse('${m['triggerAt'] ?? 0}')?.toInt() ?? 0,
      timeText: '${m['timeText'] ?? ''}',
      courseName: '${m['courseName'] ?? ''}',
      location: '${m['location'] ?? ''}',
      label: '${m['label'] ?? ''}',
      isEnd: m['isEnd'] == true,
      kind: '${m['kind'] ?? (m['isEnd'] == true ? 'endPreview' : 'lead')}',
    );
  }
}

/// 提醒服务（全部方法在非 Android 平台上安全返回默认值）。
class ReminderService {
  ReminderService._();

  static const MethodChannel _channel = MethodChannel(kReminderChannel);

  /// 当前平台是否支持提醒（仅 Android）。
  ///
  /// 注意这里用 `dart:io` 的 `Platform` 而非 `defaultTargetPlatform`：
  /// 后者在 `flutter test` 中默认是 android，会导致测试误入原生分支。
  static bool get supported {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// 读取设备 / 权限 / 排布状态。
  static Future<ReminderDeviceStatus> status() async {
    if (!supported) {
      return const ReminderDeviceStatus();
    }
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>('status');
      if (raw == null) return const ReminderDeviceStatus();
      return ReminderDeviceStatus.fromMap(raw);
    } catch (_) {
      return const ReminderDeviceStatus(platformSupported: true);
    }
  }

  /// 下发提醒计划并重排闹钟。
  static Future<ReminderSyncResult> syncPlan(Map<String, dynamic> payload) async {
    if (!supported) {
      return const ReminderSyncResult(
        ok: false,
        note: '当前平台不支持课程提醒（仅 Android）。',
      );
    }
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'sync',
        <String, dynamic>{'plan': _encode(payload)},
      );
      if (raw == null) {
        return const ReminderSyncResult(ok: false, note: '原生侧未返回结果。');
      }
      return ReminderSyncResult.fromMap(raw);
    } catch (e) {
      return ReminderSyncResult(ok: false, note: '排布失败：$e');
    }
  }

  /// 取消全部提醒闹钟。
  static Future<void> cancelAll() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } catch (_) {
      // 取消失败不阻塞 UI
    }
  }

  /// 预览接下来会触发的提醒。
  static Future<List<ReminderPreviewItem>> preview({int limit = 8}) async {
    if (!supported) return const <ReminderPreviewItem>[];
    try {
      final raw = await _channel
          .invokeListMethod<Object?>('preview', <String, dynamic>{'limit': limit});
      if (raw == null) return const <ReminderPreviewItem>[];
      return raw
          .whereType<Map<Object?, Object?>>()
          .map(ReminderPreviewItem.fromMap)
          .toList();
    } catch (_) {
      return const <ReminderPreviewItem>[];
    }
  }

  /// 立即发一条测试提醒（不写计划，用于检查样式与权限）。
  ///
  /// [isEnd] 为 true 时发「下节课预告」，[sessionPreview] 为 true 时发「时段预告」，
  /// 两者都不传则为普通的单节课提醒。
  static Future<String> testNow({
    bool isEnd = false,
    bool sessionPreview = false,
    String? courseName,
  }) async {
    if (!supported) return '当前平台不支持通知。';
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'testNow',
        <String, dynamic>{
          'isEnd': isEnd,
          'sessionPreview': sessionPreview,
          if (courseName != null && courseName.isNotEmpty) 'courseName': courseName,
        },
      );
      // 原生侧的真实 key 是 mode（见 ReminderBridge.sendTest）
      return '${raw?['mode'] ?? raw?['message'] ?? '已发送'}';
    } catch (e) {
      return '发送失败：$e';
    }
  }

  /// 请求通知权限（Android 13+）。返回 `false` 表示需要用户手动去设置里开启。
  static Future<bool> requestNotificationPermission() async {
    if (!supported) return false;
    try {
      final ok = await _channel
          .invokeMethod<bool>('requestNotificationPermission');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openNotificationSettings() => _invoke('openNotificationSettings');

  static Future<void> openExactAlarmSettings() => _invoke('openExactAlarmSettings');

  static Future<void> openBatteryOptimizationSettings() =>
      _invoke('openBatteryOptimizationSettings');

  /// 打开 vivo 自启动管理页，返回实际跳转的组件名。
  static Future<String> openAutoStartSettings() async {
    if (!supported) return '';
    try {
      return await _channel.invokeMethod<String>('openAutoStartSettings') ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> _invoke(String method) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {
      // 跳转失败无副作用
    }
  }

  // ------------------------------------------------------------ 计划打包

  /// 把课表 + 偏好打包成原生侧 `ReminderPlan.fromJson` 期望的结构。
  ///
  /// 返回 `null` 表示**无法排布**：课表尚未设置学期起始日期时，
  /// 「当前第几周」无从计算，此时排布出来的提醒会一直按第 1 周重复，必须拒绝。
  ///
  /// 提醒规则（用户确认）：
  /// - 提前 30 分钟 → 仅上午/下午/晚上第一节，内容是**该时段全部课程**的预告；
  /// - 提前 15 分钟 → 仅上午/下午/晚上第一节，单节课提醒；
  /// - 提前 5 分钟 → 当天每一节课；
  /// - 下课前 `endPreviewMinutes` 分钟 → 预告下一节课，**连堂不提醒**。
  static Map<String, dynamic>? buildPlanPayload(
    Timetable timetable,
    ReminderPrefs prefs,
  ) {
    final start = timetable.startDate;
    if (start == null) return null;

    final leads = prefs.sortedLeads;
    return <String, dynamic>{
      'enabled': prefs.enabled,
      'leadMinutes': leads,
      // 与 leadMinutes 一一对应且顺序一致，原生侧据此判断哪一档只对时段首课生效
      'leadScopes': leads.map((m) => LeadScope.forLead(m).wire).toList(),
      'endReminder': prefs.endReminder,
      'endPreviewMinutes': prefs.endPreviewMinutes,
      'vivoAtomic': prefs.vivoAtomic,
      'semesterStartEpochDay': _epochDay(start),
      'totalWeeks': timetable.totalWeeks,
      'periods': activePeriods
          .map((p) => <String, dynamic>{
                'section': p.section,
                'startMin': p.startHour * 60 + p.startMinute,
                'endMin': p.endHour * 60 + p.endMinute,
              })
          .toList(),
      'courses': timetable.courses.map(_coursePayload).toList(),
    };
  }

  static Map<String, dynamic> _coursePayload(Course c) => <String, dynamic>{
        'name': c.name,
        'location': c.location,
        'teacher': c.teacher,
        'dayOfWeek': c.dayOfWeek,
        'startSection': c.startSection,
        'endSection': c.endSection,
        'startWeek': c.startWeek,
        'endWeek': c.endWeek,
        'oddEven': c.oddEven,
        // 与 UI 卡片配色保持同源：原生侧用下标取 NotificationFactory.COURSE_COLORS
        'colorIndex':
            AppTheme.courseColors.indexOf(AppTheme.colorForCourse(c.name)),
      };

  /// 本地日期 → epochDay（1970-01-01 起的天数），与原生 `DayMath` 算法一致。
  static int _epochDay(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  static String _encode(Map<String, dynamic> payload) => jsonEncode(payload);
}
