/// 桌面小组件（今日课程）的**渲染取证**。
///
/// 这条测试回答的不是「我以为小组件会显示什么」，而是让原生把 `widget_today` 布局
/// 真的 inflate 一遍（`RemoteViews.apply()`）再读回 TextView 的文字 —— 桌面上显示
/// 不对时，这里是唯一能说清「到底画了什么」的地方（不用解锁手机、不用截图猜）。
///
/// 两个用例：
/// 1. 只读：按原生存档里的**真实**数据探一次，不动存档 —— 真机上跑这条；
/// 2. 写入：注入「今天两门课」的课表，断言日期/周次/课程行/页脚都画对了 —— 它会把
///    存档里的课表换掉，所以只在模拟器上全跑；真机上跑请加 `--plain-name 真实存档`。
///
/// ```
/// flutter test integration_test/widget_render_e2e_test.dart -d <device>
/// flutter test integration_test/widget_render_e2e_test.dart -d <真机> --plain-name 真实存档
/// ```
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:njtc_schedule/models/course.dart';
import 'package:njtc_schedule/models/timetable.dart';
import 'package:njtc_schedule/services/widget_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实存档：小组件现在会画成什么样（只读，不改存档）', (tester) async {
    expect(WidgetService.supported, isTrue, reason: '小组件只在 Android 上有意义');

    final probe = await WidgetService.probe();
    expect(probe, isNotNull, reason: 'probe 通道没回话：原生 WidgetBridge 没注册？');
    debugPrint('小组件渲染探针（真实存档）= ${jsonEncode(probe)}');

    for (final key in ['date', 'week', 'empty', 'emptyVisible', 'footer', 'rows']) {
      expect(probe!.containsKey(key), isTrue, reason: '探针少了字段 $key');
    }
    // 「今天」的日期总该有；一个连日期都画不出来的小组件才是真的坏了。
    expect((probe!['date'] as String).isNotEmpty, isTrue, reason: 'date 是空的');
  });

  testWidgets('注入今天两门课：日期/周次/课程行都画得出来（会改存档）', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: now.weekday - 1));
    final dow = now.weekday;

    final tt = Timetable(
      id: 'e2e-widget-render',
      name: '小组件渲染测试',
      semester: '2026-2027年第1学期',
      totalWeeks: 20,
      startDate: monday,
      courses: [
        Course(
          name: '人工智能导论',
          teacher: '韩云',
          location: '明德楼B216',
          dayOfWeek: dow,
          startSection: 1,
          endSection: 2,
          startWeek: 1,
          endWeek: 20,
        ),
        Course(
          name: '高等数学Ⅰ（上）',
          teacher: '曾玉祥',
          location: '明德楼A203',
          dayOfWeek: dow,
          startSection: 3,
          endSection: 4,
          startWeek: 1,
          endWeek: 20,
        ),
        // 别的星期几的课，用来验证「只画今天」这件事真的生效
        Course(
          name: '不该被画出来的课',
          teacher: '张三',
          location: '明德楼Z999',
          dayOfWeek: dow == 1 ? 2 : 1,
          startSection: 5,
          endSection: 6,
          startWeek: 1,
          endWeek: 20,
        ),
      ],
    );

    await WidgetService.sync(timetable: tt);
    final probe = (await WidgetService.probe())!;
    debugPrint('小组件渲染探针（注入后）= ${jsonEncode(probe)}');

    expect(probe['date'], contains('${now.month}月${now.day}日'));
    expect(probe['week'], '第1周');
    expect(probe['emptyVisible'], isFalse, reason: '今天有课，不该显示「今天没课」');
    final rows = (probe['rows'] as List).cast<String>();
    expect(rows.length, 2, reason: '只该画出今天的两门课，实际：$rows');
    expect(rows[0], contains('人工智能导论'));
    expect(rows[0], contains('明德楼B216'));
    expect(rows[1], contains('高等数学Ⅰ（上）'));
    expect(probe['footer'], contains('2 门'), reason: '页脚该说共 2 门，实际：${probe['footer']}');
  });
}
