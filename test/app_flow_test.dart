/// 端到端流程测试 —— 真实 `.xls` → `XlsReader` → `TimetableParser` → 课表网格。
///
/// 这是「导入课表」功能的主干链路：学校教务系统导出的是老式 `.xls`
/// （OLE2 / BIFF8）文件，`XlsReader` 把它读成二维网格，`TimetableParser`
/// 解析成 `Timetable`，最后 `TimetableGrid` 必须真的把课程画到屏幕上。
/// 所以这里**不 mock 任何一环**：用真实字节一路跑到 widget 树里，
/// 再用 `find.text` 把课程名从渲染结果里找出来。
///
/// 与 `xls_reader_test.dart` / `timetable_parser_test.dart` 的分工：
/// 那两个文件只验证解析结果（数据层），本文件验证「数据真的上了屏幕」（渲染层）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/models/course.dart';
import 'package:njtc_schedule/models/timetable.dart';
import 'package:njtc_schedule/services/timetable_parser.dart';
import 'package:njtc_schedule/services/xls_reader.dart';
import 'package:njtc_schedule/theme.dart';
import 'package:njtc_schedule/widgets/course_card.dart';
import 'package:njtc_schedule/widgets/timetable_grid.dart';

/// 用于渲染断言的周次：真实课表的第 9 周（单周，且落在所有常规课的周次区间内）。
///
/// 选第 9 周的理由：
/// * 上午/下午的常规课（6-18 周、7-18 周等）全部在课；
/// * 7-10 周的两门短课（形势与政策Ⅰ、职业规划与就业创业指导Ⅰ）还在课；
/// * 第 9 周是单周，「思想道德与法治(7-17周单)」在课，而它的单双周互补课
///   「大学生心理健康教育(8-12周双)」不上课 —— 两类单双周课程都能被覆盖到。
const int sampleWeek = 9;

/// 第 [sampleWeek] 周屏幕上应出现的 `CourseCard` 数量。
///
/// 推导（数据来自真实文件，测试里会从模型再独立算一遍）：
/// 20 条课程记录中第 9 周在课的有 15 条，其余 5 条不在第 9 周
/// （大学生心理健康教育 8-12周双、Python程序设计 11-17周、
/// 大学物理V（上）11-15周、高等数学Ⅰ（上）16-18周、
/// 思想道德与法治 12-14周双）。
/// `TimetableGrid._layout` 会给**每一条**在课课程创建一个 `CourseCard`
/// （同一格的多门课会并排显示，不再互相覆盖），所以屏幕上的卡片数
/// == 第 9 周在课课程数。
/// 第 9 周这 15 条两两不同格（互补/连排的课不会同时在第 9 周在课），
/// 于是卡片数正好是 15，与「按 (星期, 起始节次) 去重后的格数」相同。
///
/// 注意 15 < 20：真实课表里同一格可以有多门课
/// （周二 5-6 节单双周互补、周四 7-8 节连排三门、周五 5-6 节先后两门），
/// 只是它们分散在不同周次，任何单独一周都看不到全部 20 条。
const int sampleWeekCardCount = 15;

void main() {
  final fixture = File('test/fixtures/njtc_sample.xls');

  /// `markTestSkipped` 不能在 `setUpAll` 里调用，所以用标志位在每个 test 内部跳过。
  var fixtureMissing = false;

  late List<List<String>> grid;
  late Timetable timetable;

  setUpAll(() {
    if (!fixture.existsSync()) {
      fixtureMissing = true;
      return;
    }
    // 真实 .xls 字节 → XlsReader → TimetableParser → Timetable
    grid = XlsReader.readFirstSheet(
      Uint8List.fromList(fixture.readAsBytesSync()),
    )!;
    timetable = TimetableParser.parseGrid(grid, name: '智26.8课表');
  });

  /// 放大测试画布后真实渲染 [TimetableGrid]。
  ///
  /// 默认测试画布只有 800×600 逻辑像素，横向的 7 天网格（约 940px）放不下；
  /// 放大到 1600×2400 让整张 7 天 × 10 节的表格都被布局出来。
  Future<void> pumpGrid(WidgetTester tester, int week) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: TimetableGrid(timetable: timetable, currentWeek: week),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('真实 .xls → Timetable → TimetableGrid 端到端', () {
    test('真实字节读出 8×9 网格并解析出 20 门课程', () {
      if (fixtureMissing) {
        markTestSkipped('缺少样例文件 ${fixture.path}');
        return;
      }

      // 1) 真实文件确实被 XlsReader 读出来了
      expect(grid.length, 8, reason: '真实课表共 8 行');
      expect(grid.first.length, 9, reason: '真实课表共 9 列');
      expect(grid[0][0], '2026-2027年第1学期');

      // 2) 解析结果：课程数 / 学期 / 专业
      expect(timetable.name, '智26.8课表');
      expect(timetable.courses.length, 20, reason: '真实课表共 20 条课程记录');
      expect(timetable.semester, '2026-2027年第1学期');
      expect(timetable.major, '机器人工程');

      // 3) 只有周一到周五有课，且周次没有被解析成默认的 1-20
      final days = timetable.courses.map((c) => c.dayOfWeek).toSet().toList()
        ..sort();
      expect(days, [1, 2, 3, 4, 5]);
      expect(
        timetable.courses.every((c) => c.startWeek == 1 && c.endWeek == 20),
        false,
        reason: '周次全部退化为 1-20，说明时间字段没解析到',
      );
    });

    testWidgets('TimetableGrid 把真实课程名渲染到屏幕上', (tester) async {
      if (fixtureMissing) {
        markTestSkipped('缺少样例文件 ${fixture.path}');
        return;
      }
      await pumpGrid(tester, sampleWeek);

      // 表头（7 天 + 节次列）也真的画出来了，证明是整个网格在渲染
      for (final day in ['周一', '周二', '周三', '周四', '周五', '周六', '周日']) {
        expect(find.text(day), findsOneWidget, reason: '缺少表头 $day');
      }
      expect(find.text('第1节'), findsOneWidget);
      expect(find.text('第10节'), findsOneWidget);

      // 真实课程名。同一门课可能排在不同天，用 findsNWidgets 断言实际张数，
      // 张数本身就从侧面证明了「每个起始格一张卡片」的渲染规则。
      expect(find.text('人工智能导论'), findsNWidgets(2),
          reason: '周一 1-2 节 + 周二 7-8 节');
      expect(find.text('高等数学Ⅰ（上）'), findsNWidgets(3),
          reason: '周一 3-4 节 + 周三 3-4 节 + 周五 7-8 节');
      expect(find.text('Python程序设计'), findsNWidgets(2),
          reason: '周三 5-6 节 + 周四 3-4 节');
      expect(find.text('大学体育Ⅰ'), findsOneWidget);
      expect(find.text('国家安全教育'), findsOneWidget,
          reason: '周四 7-8 节，6-10 周');
      expect(find.text('大学物理V（上）'), findsOneWidget,
          reason: '周五 3-4 节；周四 7-8 节那门 11-15 周，第 9 周不上');
      expect(find.text('形势与政策Ⅰ'), findsOneWidget);
      expect(find.text('大学生心理健康教育'), findsOneWidget,
          reason: '周四 1-2 节；周二 5-6 节那门是双周课，第 9 周不上');
      expect(find.text('思想道德与法治'), findsNWidgets(2),
          reason: '周三 1-2 节 + 周二 5-6 节（第 9 周是单周）');
      expect(find.text('职业规划与就业创业指导Ⅰ'), findsOneWidget,
          reason: '周五 5-6 节，7-10 周；11-17 周才换成 Python程序设计');
    });

    testWidgets('屏幕上的 CourseCard 数量与真实排课的起始格数一致', (tester) async {
      if (fixtureMissing) {
        markTestSkipped('缺少样例文件 ${fixture.path}');
        return;
      }
      await pumpGrid(tester, sampleWeek);

      // 独立从数据推导一次：第 9 周在课课程按 (星期, 起始节次) 去重后的格数。
      final startCells = <String>{};
      for (final course in timetable.courses) {
        if (!course.isActiveOnWeek(sampleWeek)) continue;
        startCells.add('d${course.dayOfWeek}s${course.startSection}');
      }
      expect(startCells.length, sampleWeekCardCount,
          reason: '第 9 周在课课程的起始格数');

      // 真实渲染出的卡片数必须等于在课课程数：
      // 新版 `_layout` 给每一条在课课程都建 CourseCard（冲突课并排），
      // 所以卡片数 == 在课课程数 == 起始格数（第 9 周无同格课程）。
      expect(find.byType(CourseCard), findsNWidgets(sampleWeekCardCount));

      // 15 < 20，说明同格多课互相覆盖确实发生了（真实课表特征），
      // 这一条让 15 这个数字不是随手写死的。
      expect(sampleWeekCardCount, lessThan(timetable.courses.length));
    });
  });

  group('用真实课表数据验证周次筛选', () {
    test('单周课程的 isActiveOnWeek 在区间内外的表现', () {
      if (fixtureMissing) {
        markTestSkipped('缺少样例文件 ${fixture.path}');
        return;
      }

      // 周二 5-6 节的思想道德与法治：7-17 周，单周
      final Course odd = timetable.courses.firstWhere(
        (c) => c.oddEven == 1,
        orElse: () => throw StateError('真实课表中应有单周课程'),
      );
      expect(odd.name, '思想道德与法治');
      expect(odd.dayOfWeek, 2);
      expect(odd.startWeek, 7);
      expect(odd.endWeek, 17);

      expect(odd.isActiveOnWeek(7), true, reason: '7 是区间内单周');
      expect(odd.isActiveOnWeek(9), true, reason: '9 是区间内单周');
      expect(odd.isActiveOnWeek(8), false, reason: '8 是区间内偶数周');
      expect(odd.isActiveOnWeek(10), false, reason: '10 是区间内偶数周');
      expect(odd.isActiveOnWeek(6), false, reason: '在起始周之前');
      expect(odd.isActiveOnWeek(18), false, reason: '在结束周之后');

      // 同格的单双周互补课：8-12 周，双周
      final Course even = timetable.courses.firstWhere(
        (c) => c.oddEven == 2 && c.dayOfWeek == 2 && c.startSection == 5,
        orElse: () => throw StateError('周二 5-6 节应有双周课程'),
      );
      expect(even.name, '大学生心理健康教育');
      expect(even.isActiveOnWeek(8), true);
      expect(even.isActiveOnWeek(10), true);
      expect(even.isActiveOnWeek(9), false, reason: '9 是奇数周');
      expect(even.isActiveOnWeek(13), false, reason: '超出 12 周');
    });

    testWidgets('切换周次后网格渲染真的跟着变（单周 ↔ 双周互换）', (tester) async {
      if (fixtureMissing) {
        markTestSkipped('缺少样例文件 ${fixture.path}');
        return;
      }

      // 第 9 周（单周）：周二 5-6 节是思想道德与法治
      await pumpGrid(tester, 9);
      expect(find.text('思想道德与法治'), findsNWidgets(2),
          reason: '周三 1-2 节 + 周二 5-6 节（单周）');
      expect(find.text('大学生心理健康教育'), findsOneWidget,
          reason: '只剩周四 1-2 节');
      expect(find.byType(CourseCard), findsNWidgets(sampleWeekCardCount));

      // 第 8 周（双周）：同一格换成大学生心理健康教育，思想道德与法治只剩周三那门
      await pumpGrid(tester, 8);
      expect(find.text('思想道德与法治'), findsOneWidget,
          reason: '周二 5-6 节那门是单周课，第 8 周不上');
      expect(find.text('大学生心理健康教育'), findsNWidgets(2),
          reason: '周四 1-2 节 + 周二 5-6 节（双周）');
      expect(find.byType(CourseCard), findsNWidgets(sampleWeekCardCount),
          reason: '单双周互补，卡片总数不变');
    });
  });
}
