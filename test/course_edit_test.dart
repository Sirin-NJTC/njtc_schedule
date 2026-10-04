/// 手动添加 / 编辑 / 删除课程的测试（不依赖导入）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/app_state.dart';
import 'package:njtc_schedule/models/course.dart';
import 'package:njtc_schedule/models/timetable.dart';
import 'package:njtc_schedule/pages/home_page.dart';
import 'package:njtc_schedule/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Course _math() => const Course(
      name: '高等数学Ⅰ（上）',
      teacher: '曾玉祥',
      location: '明德楼A103',
      dayOfWeek: 1,
      startSection: 1,
      endSection: 2,
      startWeek: 1,
      endWeek: 20,
    );

Future<AppState> _state({bool withTimetable = true}) async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState();
  await state.init();
  if (withTimetable) {
    await state.addTimetable(Timetable(
      id: 't1',
      name: '测试课表',
      totalWeeks: 20,
      startDate: DateTime(2026, 8, 31),
      courses: [_math()],
    ));
  }
  return state;
}

Future<void> _pumpHome(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(1200, 2400);
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
  testWidgets('首页右上角「+」能新增一门课', (tester) async {
    final state = await _state();
    await _pumpHome(tester, state);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(find.text('添加课程'), findsWidgets);

    await tester.enterText(find.byType(TextField).at(0), '大学物理');
    await tester.enterText(find.byType(TextField).at(1), '王老师');
    await tester.enterText(find.byType(TextField).at(2), '格致楼205');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, '添加课程'));
    await tester.pumpAndSettle();

    final courses = state.active!.courses;
    expect(courses.length, 2, reason: '新增应该追加，不影响原有课程');
    final added = courses.last;
    expect(added.name, '大学物理');
    expect(added.teacher, '王老师');
    expect(added.location, '格致楼205');
    expect(added.dayOfWeek, 1);
    expect(added.startSection, 1);
    expect(added.endSection, 2);
    expect(added.startWeek, 1);
    expect(added.endWeek, 20);
    // 保存后编辑页已关闭，新课程出现在首页课表上
    expect(find.text('添加课程'), findsNothing);
    expect(find.text('大学物理'), findsOneWidget);
  });

  testWidgets('课程名称为空时提示且不保存', (tester) async {
    final state = await _state();
    await _pumpHome(tester, state);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '添加课程'));
    await tester.pumpAndSettle();

    expect(find.text('请先填写课程名称'), findsOneWidget);
    expect(state.active!.courses.length, 1, reason: '校验不通过不应该写入');
  });

  testWidgets('详情弹窗「编辑」改完是替换而不是新增', (tester) async {
    final state = await _state();
    await _pumpHome(tester, state);

    await tester.tap(find.text('高等数学Ⅰ（上）').first);
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsOneWidget);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '高等数学Ⅱ（下）');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '保存修改'));
    await tester.pumpAndSettle();

    final courses = state.active!.courses;
    expect(courses.length, 1, reason: '编辑不应产生第二门课');
    expect(courses.first.name, '高等数学Ⅱ（下）');
    expect(courses.first.location, '明德楼A103', reason: '没改的字段要保留');
    expect(find.text('高等数学Ⅱ（下）'), findsOneWidget);
  });

  testWidgets('详情弹窗「删除」二次确认后课程消失', (tester) async {
    final state = await _state();
    await _pumpHome(tester, state);

    await tester.tap(find.text('高等数学Ⅰ（上）').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.textContaining('确定删除'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();

    expect(state.active!.courses, isEmpty);
    expect(find.text('高等数学Ⅰ（上）'), findsNothing);
  });

  testWidgets('没有任何课表时「手动添加课程」会自动建一份课表', (tester) async {
    final state = await _state(withTimetable: false);
    await _pumpHome(tester, state);

    expect(find.text('还没有课程表'), findsOneWidget);
    await tester.tap(find.text('手动添加课程'));
    await tester.pumpAndSettle();

    expect(state.active, isNotNull, reason: '应该自动创建一份课表');
    expect(state.active!.name, '我的课表');
    expect(state.timetables.length, 1);

    await tester.enterText(find.byType(TextField).at(0), '体育');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '添加课程'));
    await tester.pumpAndSettle();

    expect(state.active!.courses.single.name, '体育');
  });
}
