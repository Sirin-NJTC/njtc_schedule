/// 首页（`HomePage`）的周次交互测试：周次选择器、「回到本周」、周次上下限。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/app_state.dart';
import 'package:njtc_schedule/models/course.dart';
import 'package:njtc_schedule/models/holiday_calendar.dart';
import 'package:njtc_schedule/models/timetable.dart';
import 'package:njtc_schedule/pages/home_page.dart';
import 'package:njtc_schedule/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 今天零点。
DateTime get _today {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// 让「今天」正好落在第 2 周。
DateTime get _startOfWeek2 => _today.subtract(const Duration(days: 7));

Course _course() => const Course(
      name: '高等数学Ⅰ（上）',
      teacher: '曾玉祥',
      location: '明德楼A103',
      dayOfWeek: 1,
      startSection: 1,
      endSection: 2,
      startWeek: 1,
      endWeek: 20,
    );

Future<AppState> _state({DateTime? startDate, int totalWeeks = 20}) async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState();
  await state.init();
  await state.addTimetable(Timetable(
    id: 't1',
    name: '测试课表',
    semester: '2026-2027年第1学期',
    major: '机器人工程',
    totalWeeks: totalWeeks,
    startDate: startDate,
    courses: [_course()],
  ));
  return state;
}

/// 一张课表 + 一个「今天放假」的日历。
///
/// [courses] 默认空：没有课可上时倒计时才会落到那张「今天放假」的卡片上。
Future<AppState> _holidayState({
  required DateTime holiday,
  String name = '国庆节',
  List<Course> courses = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState();
  await state.init();
  await state.addTimetable(Timetable(
    id: 't1',
    name: '测试课表',
    semester: '2026-2027年第1学期',
    major: '机器人工程',
    totalWeeks: 20,
    startDate: _startOfWeek2,
    courses: courses,
  ));
  await state.updateHolidays(
    HolidayCalendar(holidays: [HolidayDay(holiday, name)]),
  );
  return state;
}

Future<void> _pumpHome(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const HomePage(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('周次条中间可点开「选择周次」弹窗', (tester) async {
    final state = await _state(startDate: _startOfWeek2);
    await _pumpHome(tester, state);

    expect(find.text('第 2 周'), findsOneWidget);
    expect(find.text('选择周次'), findsNothing);

    await tester.tap(find.text('第 2 周'));
    await tester.pumpAndSettle();

    expect(find.text('选择周次'), findsOneWidget);
    expect(find.text('共 20 周'), findsOneWidget);
    // 弹窗里 20 个周次格子
    expect(find.text('第 1 周'), findsOneWidget);
    expect(find.text('第 20 周'), findsOneWidget);
  });

  testWidgets('在弹窗里选周会切换当前周并关闭弹窗', (tester) async {
    final state = await _state(startDate: _startOfWeek2);
    await _pumpHome(tester, state);

    await tester.tap(find.text('第 2 周'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 5 周'));
    await tester.pumpAndSettle();

    expect(state.currentWeek, 5);
    expect(find.text('选择周次'), findsNothing);
    expect(find.text('第 5 周'), findsOneWidget);
  });

  testWidgets('弹窗里本周带「本周」标记', (tester) async {
    final state = await _state(startDate: _startOfWeek2);
    await _pumpHome(tester, state);

    await tester.tap(find.text('第 2 周'));
    await tester.pumpAndSettle();

    expect(find.text('本周'), findsOneWidget);
  });

  testWidgets('翻到别的周会出现「回到本周」，点了回到第 2 周', (tester) async {
    final state = await _state(startDate: _startOfWeek2);
    await _pumpHome(tester, state);

    expect(find.text('回到本周 · 第 2 周'), findsNothing);

    state.setCurrentWeek(5);
    await tester.pumpAndSettle();
    expect(find.text('第 5 周'), findsOneWidget);
    expect(find.text('回到本周 · 第 2 周'), findsOneWidget);

    await tester.tap(find.text('回到本周 · 第 2 周'));
    await tester.pumpAndSettle();

    expect(state.currentWeek, 2);
    expect(find.text('回到本周 · 第 2 周'), findsNothing);
  });

  testWidgets('第 1 周时左箭头禁用，最后一周时右箭头禁用', (tester) async {
    final state = await _state(startDate: _startOfWeek2, totalWeeks: 3);
    await _pumpHome(tester, state);

    // 让「今天」落在第 3 周（也是最后一周）
    state.setCurrentWeek(3);
    await tester.pumpAndSettle();

    final left = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_left),
    );
    final right = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(right.onPressed, isNull, reason: '已是最后一周');
    expect(left.onPressed, isNotNull);

    state.setCurrentWeek(1);
    await tester.pumpAndSettle();
    final left1 = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_left),
    );
    expect(left1.onPressed, isNull, reason: '已是第 1 周');
  });

  testWidgets('没设学期起始日期时不显示「回到本周」，但提示去设置', (tester) async {
    final state = await _state(startDate: null);
    await _pumpHome(tester, state);

    expect(find.textContaining('回到本周'), findsNothing);
    expect(find.textContaining('未设置学期起始日期'), findsOneWidget);
  });

  testWidgets('空课表显示空状态与「导入课表」按钮', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.init();
    await _pumpHome(tester, state);

    expect(find.text('还没有课程表'), findsOneWidget);
    expect(find.text('导入课表'), findsOneWidget);
  });

  testWidgets('今天放假又没有下一节课 → 倒计时位置改成「今天放假」', (tester) async {
    final state = await _holidayState(holiday: _today, name: '国庆节');
    await _pumpHome(tester, state);

    expect(find.text('今天放假'), findsOneWidget);
    expect(find.text('国庆节'), findsOneWidget);
    expect(find.text('下一节课'), findsNothing);
  });

  testWidgets('今天放假但下周还有课 → 报下一节课，隔得远就带上日期', (tester) async {
    final state = await _holidayState(
      holiday: _today,
      name: '国庆节',
      courses: [_course()],
    );
    await _pumpHome(tester, state);

    expect(find.text('今天放假'), findsNothing, reason: '还有课要上时不能只说放假');
    expect(find.text('下一节课'), findsOneWidget);

    // 今天的课被假吃掉了，下一节就是下周一第一节（新作息 08:20）。
    final gap = (8 - _today.weekday) % 7 == 0 ? 7 : (8 - _today.weekday) % 7;
    final monday = _today.add(Duration(days: gap));
    final label = gap >= 3
        ? '${monday.month}月${monday.day}日 周一 08:20'
        : '${gap == 1 ? '明天' : '后天'} 08:20';
    expect(find.text(label), findsOneWidget,
        reason: '长假之后只写「周一」看不出是几月几号');
  });
}
