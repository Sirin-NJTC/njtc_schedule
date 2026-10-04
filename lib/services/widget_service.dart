/// 桌面小组件（今日课程）—— Dart 侧把课表推给原生，并请求重画。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/period.dart';
import '../models/timetable.dart';

/// 与原生 [WidgetBridge]（`android/.../widget/WidgetBridge.kt`）对话。
///
/// 为什么是「推」而不是让原生自己去读 `shared_preferences`：
/// Flutter 的存档是异步落盘的，原生那边另开一个 SharedPreferences 实例时
/// 有可能读到旧值；推过去存进原生自己的文件，顺序就确定了。
class WidgetService {
  WidgetService._();

  static const MethodChannel _channel =
      MethodChannel('cn.edu.njtc.njtc_schedule/widget');

  /// 只有 Android 才有原生桌面小组件。
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 把课表与节次时间推给原生侧，并立刻刷新桌面上的小组件。
  ///
  /// 失败一律吞掉：小组件是锦上添花，绝不能因为它影响课表本身的增删改。
  static Future<void> sync({
    Timetable? timetable,
    List<Period>? periods,
  }) async {
    if (!supported) return;
    final list = periods ?? activePeriods;
    try {
      await _channel.invokeMethod<bool>('update', <String, dynamic>{
        'hasTimetable': timetable != null,
        'timetable': timetable?.toJsonString(),
        'periods': jsonEncode(
          list
              .map((p) => <String, dynamic>{
                    's': p.section,
                    'a': p.startText,
                    'b': p.endText,
                  })
              .toList(),
        ),
      });
    } catch (_) {
      // 原生侧没注册（比如测试环境）或出错，都不该冒泡。
    }
  }

  /// 只重画，不换数据。
  static Future<void> refresh() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('refresh');
    } catch (_) {}
  }

  /// 问原生「小组件现在实际会显示成什么样」。
  ///
  /// 原生侧会把 `widget_today` 布局真的 inflate 一遍再读回 TextView 的文字，
  /// 所以这里拿到的是**渲染结果**，不是我们以为该显示什么。
  /// 桌面上显示不对时用它取证；集成测试也靠它断言。
  /// 拿不到（非 Android / 通道未注册）时返回 null。
  static Future<Map<String, dynamic>?> probe() async {
    if (!supported) return null;
    try {
      final r = await _channel.invokeMethod<Map<dynamic, dynamic>>('probe');
      return r?.cast<String, dynamic>();
    } catch (e) {
      // 这里**不能**像 sync/refresh 那样闷掉：probe 是拿来查问题的，
      // 查问题的人必须看得到原生侧到底报了什么。
      debugPrint('WidgetService.probe 失败：$e');
      return null;
    }
  }
}
