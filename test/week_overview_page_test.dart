/// 课表全览页：整周放大一页、翻周、缩放复位、从首页进得去。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/app_state.dart';
import 'package:njtc_schedule/models/course.dart';
import 'package:njtc_schedule/models/holiday_calendar.dart';
import 'package:njtc_schedule/models/timetable.dart';
import 'package:njtc_schedule/pages/home_page.dart';
import 'package:njtc_schedule/pages/week_overview_page.dart';
import 'package:njtc_schedule/theme.dart';
import 'package:njtc_schedule/widgets/course_card.dart';
import 'package:njtc_schedule/widgets/timetable_grid.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 今天零点。
DateTime get _today {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// 让「今天」正好落在第 2 周。
DateTime get _startOfWeek2 => _today.subtract(const Duration(days: 7));

Course _course({String name = '示例课程戊', int day = 1}) => Course(
      name: name,
      teacher: '示例老师B',
      location: '明德楼A103',
      dayOfWeek: day,
      startSection: 3,
      endSection: 4,
      startWeek: 1,
      endWeek: 20,
    );

Future<AppState> _state({List<Course>? courses, int totalWeeks = 20}) async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState();
  await state.init();
  await state.addTimetable(Timetable(
    id: 't1',
    name: '测试课表',
    semester: '2026-2027年第1学期',
    major: '示例工程',
    totalWeeks: totalWeeks,
    startDate: _startOfWeek2,
    courses: courses ?? [_course()],
  ));
  // 内置日历里国庆那一周整体是放假的，放假日的课默认不画（会被当成「这周不上」），
  // 于是「今天有课」这件事就跟日历撞车了 —— 这些用例只关心全览页本身，先清空日历。
  await state.updateHolidays(const HolidayCalendar());
  return state;
}

Future<void> _pump(WidgetTester tester, AppState state, {Widget? home}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: home ?? const WeekOverviewPage(),
      routes: {'/overview': (_) => const WeekOverviewPage()},
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('打开就是首页所在的那一周，并标出「本周」', (tester) async {
    final state = await _state();
    await _pump(tester, state);

    expect(find.text('课表全览'), findsOneWidget);
    expect(find.text('第 2 周'), findsOneWidget);
    expect(find.text('本周'), findsOneWidget);
    expect(find.textContaining('双指缩放'), findsOneWidget);
  });

  testWidgets('用的是放大的网格参数 + 可缩放模式', (tester) async {
    final state = await _state();
    await _pump(tester, state);

    final grid = tester.widget<TimetableGrid>(find.byType(TimetableGrid));
    expect(grid.currentWeek, 2);
    expect(grid.zoomable, isTrue, reason: '全览页必须交给 InteractiveViewer，否则没法缩放');
    expect(grid.dayWidth, greaterThan(TimetableGrid.defaultDayWidth));
    expect(grid.sectionHeight, greaterThan(TimetableGrid.defaultSectionHeight));
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(CourseCard), findsWidgets, reason: '放大后课还得画出来');
  });

  testWidgets('左右箭头翻周，「回到本周」一键回来', (tester) async {
    final state = await _state();
    await _pump(tester, state);

    expect(find.text('回到本周'), findsNothing, reason: '本来就在本周');

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('第 3 周'), findsOneWidget);
    expect(find.text('本周'), findsNothing);
    expect(find.text('回到本周'), findsOneWidget);
    // 只翻全览页自己的周次，不动全局状态（不然首页会被带跑）
    expect(state.currentWeek, 2);

    await tester.tap(find.text('回到本周'));
    await tester.pumpAndSettle();
    expect(find.text('第 2 周'), findsOneWidget);
    expect(find.text('回到本周'), findsNothing);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('第 1 周'), findsOneWidget);
  });

  testWidgets('第 1 周左箭头禁用，最后一周右箭头禁用', (tester) async {
    final state = await _state(totalWeeks: 2);
    await _pump(tester, state);

    state.setCurrentWeek(1);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_left))
          .onPressed,
      isNull,
    );

    state.setCurrentWeek(2);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_right))
          .onPressed,
      isNull,
      reason: '共 2 周，已是最后一周',
    );
  });

  testWidgets('点周次打开选择器，选完跳过去', (tester) async {
    final state = await _state();
    await _pump(tester, state);

    await tester.tap(find.text('第 2 周'));
    await tester.pumpAndSettle();
    expect(find.text('选择周次'), findsOneWidget);

    await tester.tap(find.text('第5周'));
    await tester.pumpAndSettle();
    expect(find.text('第 5 周'), findsOneWidget);
    expect(find.text('选择周次'), findsNothing);
  });

  testWidgets('复位缩放按钮重新铺一张网格（不会崩）', (tester) async {
    final state = await _state();
    await _pump(tester, state);

    await tester.tap(find.byTooltip('复位缩放'));
    await tester.pumpAndSettle();
    expect(find.byType(TimetableGrid), findsOneWidget);
    expect(find.text('第 2 周'), findsOneWidget);
  });

  testWidgets('首页右上角的「课表全览」按钮能打开这一页', (tester) async {
    final state = await _state();
    await _pump(tester, state, home: const HomePage());

    expect(find.byTooltip('课表全览（放大看整周）'), findsOneWidget);
    await tester.tap(find.byTooltip('课表全览（放大看整周）'));
    await tester.pumpAndSettle();

    expect(find.text('课表全览'), findsOneWidget);
    expect(find.byType(WeekOverviewPage), findsOneWidget);
  });

  testWidgets('没有课表时给一句提示，不白屏', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.init();
    await _pump(tester, state);

    expect(find.text('还没有课程表'), findsOneWidget);
    expect(find.byType(TimetableGrid), findsNothing);
  });
}
