/// 桌面小组件桥（`WidgetService`）的单元测试。
///
/// 这里只测「Dart 侧到底往原生推了什么」——推过去之后怎么画，
/// 由 `android/.../widget/WidgetData.kt` 负责，只能在真机/模拟器上看。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/models/course.dart';
import 'package:njtc_schedule/models/holiday_calendar.dart';
import 'package:njtc_schedule/models/period.dart';
import 'package:njtc_schedule/models/timetable.dart';
import 'package:njtc_schedule/services/widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cn.edu.njtc.njtc_schedule/widget');
  final calls = <MethodCall>[];

  void mockHandler(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  Timetable sample() => Timetable(
        id: 'tt-1',
        name: '我的课表',
        semester: '2026-2027年第1学期',
        major: '机器人工程',
        totalWeeks: 20,
        startDate: DateTime(2026, 8, 31),
        courses: [
          const Course(
            name: '高等数学Ⅰ（上）',
            teacher: '张老师',
            location: '明德楼A103',
            dayOfWeek: 1,
            startSection: 1,
            endSection: 2,
            startWeek: 1,
            endWeek: 16,
          ),
        ],
      );

  setUp(() {
    calls.clear();
    resetActivePeriods();
    mockHandler((_) async => true);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('WidgetService', () {
    test('Android 上启用，其它平台直接跳过（连一次通道调用都没有）', () async {
      expect(WidgetService.supported, isTrue);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(WidgetService.supported, isFalse);
      await WidgetService.sync(timetable: sample());
      await WidgetService.refresh();
      expect(calls, isEmpty);
    });

    test('sync 把课表和节次时间一起推过去', () async {
      await WidgetService.sync(timetable: sample());

      expect(calls, hasLength(1));
      expect(calls.single.method, 'update');

      final args = Map<String, dynamic>.from(calls.single.arguments as Map);
      expect(args['hasTimetable'], isTrue);

      // 课表就是 Timetable.toJsonString() 的原样
      final tt = jsonDecode(args['timetable'] as String) as Map<String, dynamic>;
      expect(tt['name'], '我的课表');
      expect(tt['totalWeeks'], 20);
      expect((tt['courses'] as List).length, 1);
      expect((tt['courses'] as List).first['location'], '明德楼A103');

      // 节次时间是给原生用的精简格式：s=节次、a=开始、b=结束
      final periods = jsonDecode(args['periods'] as String) as List;
      expect(periods, hasLength(defaultPeriods.length));
      expect(periods.first, {'s': 1, 'a': '08:20', 'b': '09:05'});
      expect(periods.last, {
        's': defaultPeriods.length,
        'a': defaultPeriods.last.startText,
        'b': defaultPeriods.last.endText,
      });
    });

    test('推的是用户自定义过的作息', () async {
      final custom = [
        const Period(
          section: 1,
          label: '第1节',
          startHour: 7,
          startMinute: 40,
          endHour: 8,
          endMinute: 25,
        ),
        const Period(
          section: 2,
          label: '第2节',
          startHour: 8,
          startMinute: 35,
          endHour: 9,
          endMinute: 20,
        ),
      ];
      await WidgetService.sync(timetable: sample(), periods: custom);

      final args = Map<String, dynamic>.from(calls.single.arguments as Map);
      expect(jsonDecode(args['periods'] as String), [
        {'s': 1, 'a': '07:40', 'b': '08:25'},
        {'s': 2, 'a': '08:35', 'b': '09:20'},
      ]);
    });

    test('没有课表时 hasTimetable=false、timetable 为 null（原生据此提示去导入）', () async {
      await WidgetService.sync(timetable: null);

      final args = Map<String, dynamic>.from(calls.single.arguments as Map);
      expect(args['hasTimetable'], isFalse);
      expect(args['timetable'], isNull);
      expect(args['periods'], isA<String>());
    });

    test('sync 把节假日日历也一起推过去（放假 + 调休补班）', () async {
      final cal = HolidayCalendar(
        holidays: [HolidayDay(DateTime(2026, 10, 1), '国庆节')],
        makeups: [MakeupDay(DateTime(2026, 10, 10), 3, '补周三的课')],
      );
      await WidgetService.sync(timetable: sample(), holidays: cal);

      final args = Map<String, dynamic>.from(calls.single.arguments as Map);
      final h = jsonDecode(args['holidays'] as String) as Map<String, dynamic>;
      expect(
        h['h'],
        [
          {'e': epochDayOf(DateTime(2026, 10, 1)), 'n': '国庆节'},
        ],
      );
      expect(
        h['m'],
        [
          {'e': epochDayOf(DateTime(2026, 10, 10)), 'w': 3, 'n': '补周三的课'},
        ],
      );
    });

    test('原生侧抛错只吞掉，不冒泡给调用方', () async {
      mockHandler((_) async => throw PlatformException(code: 'boom'));

      await expectLater(WidgetService.sync(timetable: sample()), completes);
      await expectLater(WidgetService.refresh(), completes);
      expect(calls, hasLength(2));
    });

    test('refresh 只让它重画，不带数据', () async {
      await WidgetService.refresh();
      expect(calls.single.method, 'refresh');
      expect(calls.single.arguments, isNull);
    });
  });
}
