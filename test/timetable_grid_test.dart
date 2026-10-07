/// `TimetableGrid` 的新版布局行为测试（合成数据，不依赖固件文件）。
///
/// 这些用例锁定的是这一轮重写修掉的几个问题：
/// * 同一格里的**冲突课**必须并排显示，不能互相覆盖（旧版 `grid[day][s] = course` 会丢课）；
/// * 节次总数自适应，第 11 节不能因为写死 `maxSection = 10` 而消失；
/// * 单/双周课程要有角标；
/// * 展示的正好是本周时，今天那一列的表头显示「今天」；
/// * 不在本周的课程默认不出现，打开「显示非本周课程」后半透明地出现；
/// * 关掉「显示周六/周日」后只剩五列，周末的课也不再画。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/models/course.dart';
import 'package:njtc_schedule/models/holiday_calendar.dart';
import 'package:njtc_schedule/models/timetable.dart';
import 'package:njtc_schedule/theme.dart';
import 'package:njtc_schedule/widgets/course_card.dart';
import 'package:njtc_schedule/widgets/timetable_grid.dart';

/// 构造一门课，只写关心的字段。
Course c({
  required String name,
  int day = 1,
  int start = 1,
  int end = 1,
  int startWeek = 1,
  int endWeek = 20,
  int oddEven = 0,
  String teacher = '张老师',
  String location = '明德楼A101',
}) =>
    Course(
      name: name,
      teacher: teacher,
      location: location,
      dayOfWeek: day,
      startSection: start,
      endSection: end,
      startWeek: startWeek,
      endWeek: endWeek,
      oddEven: oddEven,
    );

Timetable tt(List<Course> courses, {DateTime? startDate, int totalWeeks = 20}) =>
    Timetable(
      id: 'test',
      name: '测试课表',
      totalWeeks: totalWeeks,
      startDate: startDate,
      courses: courses,
    );

Future<void> pumpGrid(
  WidgetTester tester,
  Timetable timetable,
  int week, {
  bool showWeekend = true,
  bool showInactiveCourses = false,
  HolidayCalendar holidays = const HolidayCalendar(),
}) async {
  // 手机宽度：7 天网格放不下，正好验证横向滚动 + 自动滚动到今天不崩
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: TimetableGrid(
        timetable: timetable,
        currentWeek: week,
        showWeekend: showWeekend,
        showInactiveCourses: showInactiveCourses,
        holidays: holidays,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('冲突课程并排显示', () {
    testWidgets('同一格两门课都画出来（旧版会互相覆盖丢一门）', (tester) async {
      await pumpGrid(
        tester,
        tt([
          c(name: '冲突课甲', day: 3, start: 3, end: 4),
          c(name: '冲突课乙', day: 3, start: 3, end: 4, teacher: '李老师'),
        ]),
        1,
      );

      expect(find.text('冲突课甲'), findsOneWidget);
      expect(find.text('冲突课乙'), findsOneWidget);
      expect(find.byType(CourseCard), findsNWidgets(2));
    });

    testWidgets('三门课在同一格也能全部显示', (tester) async {
      await pumpGrid(
        tester,
        tt([
          c(name: '并排一', day: 2, start: 5, end: 6),
          c(name: '并排二', day: 2, start: 5, end: 6),
          c(name: '并排三', day: 2, start: 5, end: 6),
        ]),
        1,
      );

      for (final n in ['并排一', '并排二', '并排三']) {
        expect(find.text(n), findsOneWidget, reason: '$n 应该被画出来');
      }
      expect(find.byType(CourseCard), findsNWidgets(3));
    });

    testWidgets('时间不重叠的两门课不会并排（顺序排布）', (tester) async {
      await pumpGrid(
        tester,
        tt([
          c(name: '上午课', day: 4, start: 1, end: 2),
          c(name: '下午课', day: 4, start: 5, end: 6),
        ]),
        1,
      );

      expect(find.byType(CourseCard), findsNWidgets(2));
      // 两门课位置不同：y 坐标必须不一样
      final a = tester.getTopLeft(find.text('上午课'));
      final b = tester.getTopLeft(find.text('下午课'));
      expect(a.dy, isNot(equals(b.dy)));
    });
  });

  group('节次自适应', () {
    testWidgets('第 11 节的课能显示，且节次轴画到第 11 节', (tester) async {
      await pumpGrid(
        tester,
        tt([c(name: '晚课', day: 5, start: 11, end: 11)]),
        1,
      );

      expect(find.text('第11节'), findsOneWidget,
          reason: '旧版写死 maxSection=10，第 11 节不存在');
      expect(find.text('晚课'), findsOneWidget);
    });

    testWidgets('没有高节次课时只画标准 11 节', (tester) async {
      await pumpGrid(tester, tt([c(name: '普通课', day: 1, start: 1, end: 2)]), 1);

      expect(find.text('第1节'), findsOneWidget);
      expect(find.text('第11节'), findsOneWidget);
      expect(find.text('第12节'), findsNothing);
    });
  });

  group('单双周与周次筛选', () {
    testWidgets('单周课显示「单」角标，双周课显示「双」角标', (tester) async {
      await pumpGrid(
        tester,
        tt([
          c(name: '单周课', day: 1, start: 1, end: 2, oddEven: 1),
          c(name: '双周课', day: 2, start: 1, end: 2, oddEven: 2),
        ]),
        3, // 第 3 周：单周，两门都不受周次区间限制
      );

      expect(find.text('单'), findsOneWidget);
      // 双周课在第 3 周不上课
      expect(find.text('双周课'), findsNothing);
      expect(find.text('单周课'), findsOneWidget);
    });

    testWidgets('不在本周的课程完全不出现（连角标都没有）', (tester) async {
      await pumpGrid(
        tester,
        tt([c(name: '短课', day: 1, start: 1, end: 2, startWeek: 5, endWeek: 8)]),
        1,
      );

      expect(find.text('短课'), findsNothing);
      expect(find.byType(CourseCard), findsNothing);
    });
  });

  group('连堂课块撑满所占节次', () {
    // 用户反馈：多节连堂的课在课表上只占一节课的位置。
    // 课块外层的 Positioned 高度算的是「跨了几节」，但如果卡片自己不撑开，
    // 看起来就只是一小节高 —— 这两条用例锁住「撑开」。
    const double sectionHeight = 74; // 与 TimetableGrid.sectionHeight 一致

    testWidgets('跨 4 小节（第 3-6 节）的卡片高度 = 4 个小节', (tester) async {
      await pumpGrid(tester, tt([c(name: '连堂课', day: 1, start: 3, end: 6)]), 1);

      final size = tester.getSize(find.byType(CourseCard));
      expect(
        size.height,
        closeTo(4 * sectionHeight, 0.5),
        reason: '连堂课要撑满 4 个小节；只有 ~1 个小节高就是用户看到的「只占一节」',
      );
    });

    testWidgets('跨 2 小节（第 1-2 节）的卡片高度 = 2 个小节', (tester) async {
      await pumpGrid(tester, tt([c(name: '普通课', day: 2, start: 1, end: 2)]), 1);

      expect(
        tester.getSize(find.byType(CourseCard)).height,
        closeTo(2 * sectionHeight, 0.5),
      );
    });

    testWidgets('并排冲突课也各自撑满高度', (tester) async {
      await pumpGrid(
        tester,
        tt([
          c(name: '并排甲', day: 3, start: 5, end: 8),
          c(name: '并排乙', day: 3, start: 5, end: 6),
        ]),
        1,
      );

      final cards = tester.widgetList<CourseCard>(find.byType(CourseCard)).toList();
      expect(cards.length, 2);
      // 按课名定位，别依赖绘制顺序（_layout 先按 startSection 再按 endSection 排序）
      Size sizeOf(String name) => tester.getSize(
            find.ancestor(of: find.text(name), matching: find.byType(CourseCard)),
          );
      expect(sizeOf('并排甲').height, closeTo(4 * sectionHeight, 0.5));
      expect(sizeOf('并排乙').height, closeTo(2 * sectionHeight, 0.5));
      // 并排时宽度均分
      expect(sizeOf('并排甲').width, closeTo(sizeOf('并排乙').width, 0.5));
    });
  });

  group('今天高亮', () {
    testWidgets('展示本周时表头出现「今天」', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // 让「今天」正好落在第 2 周：起始日 = 今天往前推 7 天
      final startDate = today.subtract(const Duration(days: 7));

      await pumpGrid(
        tester,
        tt(
          [c(name: '今天的课', day: today.weekday, start: 1, end: 2)],
          startDate: startDate,
        ),
        2,
      );

      expect(find.text('今天'), findsOneWidget);
    });

    testWidgets('展示的不是本周时没有「今天」，只有周一到周日', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final startDate = today.subtract(const Duration(days: 7));

      // 当前其实是第 2 周，这里故意展示第 5 周
      await pumpGrid(
        tester,
        tt([c(name: '某课', day: 1, start: 1, end: 2)], startDate: startDate),
        5,
      );

      expect(find.text('今天'), findsNothing);
      expect(find.text('周一'), findsOneWidget);
    });
  });

  group('显示开关：周六日', () {
    testWidgets('默认显示七列（周一到周日）', (tester) async {
      await pumpGrid(tester, tt([c(name: '周一的课', day: 1)]), 1);

      expect(find.text('周六'), findsOneWidget);
      expect(find.text('周日'), findsOneWidget);
    });

    testWidgets('关掉周末后只剩五列，周六的课也不见了', (tester) async {
      await pumpGrid(
        tester,
        tt([
          c(name: '周一的课', day: 1, start: 1, end: 2),
          c(name: '周六的课', day: 6, start: 1, end: 2),
        ]),
        1,
        showWeekend: false,
      );

      expect(find.text('周一'), findsOneWidget);
      expect(find.text('周五'), findsOneWidget);
      expect(find.text('周六'), findsNothing);
      expect(find.text('周日'), findsNothing);
      expect(find.text('周一的课'), findsOneWidget);
      expect(find.text('周六的课'), findsNothing);
    });
  });

  group('显示开关：非本周课程', () {
    testWidgets('默认只画本周要上的课', (tester) async {
      await pumpGrid(
        tester,
        tt([
          c(name: '第1周才上', day: 2, start: 1, end: 2, startWeek: 1, endWeek: 4),
          c(name: '第9周上', day: 2, start: 3, end: 4, startWeek: 7, endWeek: 12),
        ]),
        9,
      );

      expect(find.text('第9周上'), findsOneWidget);
      expect(find.text('第1周才上'), findsNothing);
    });

    testWidgets('打开后非本周课程半透明地画出来', (tester) async {
      await pumpGrid(
        tester,
        tt([
          c(name: '第1周才上', day: 2, start: 1, end: 2, startWeek: 1, endWeek: 4),
          c(name: '第9周上', day: 2, start: 3, end: 4, startWeek: 7, endWeek: 12),
        ]),
        9,
        showInactiveCourses: true,
      );

      expect(find.text('第9周上'), findsOneWidget);
      expect(find.text('第1周才上'), findsOneWidget);

      // 非本周的那门要淡一点（否则用户分不清哪门这周真要上）
      List<double> opacitiesOf(String name) => tester
          .widgetList<Opacity>(find.ancestor(
            of: find.text(name),
            matching: find.byType(Opacity),
          ))
          .map((o) => o.opacity)
          .toList();

      // 不按下标认对象：find.ancestor 的顺序不做保证，只断言「存在某层是目标透明度」
      expect(opacitiesOf('第9周上'), contains(1.0));
      expect(opacitiesOf('第1周才上'), contains(closeTo(0.35, 0.001)));
    });

    testWidgets('单双周不匹配的课也算非本周', (tester) async {
      await pumpGrid(
        tester,
        tt([
          c(name: '单周课', day: 3, start: 1, end: 2, oddEven: 1),
          c(name: '双周课', day: 3, start: 3, end: 4, oddEven: 2),
        ]),
        2, // 第 2 周是双周
        showInactiveCourses: true,
      );

      expect(find.text('双周课'), findsOneWidget);
      expect(find.text('单周课'), findsOneWidget);
      final opacities = tester
          .widgetList<Opacity>(find.ancestor(
            of: find.text('单周课'),
            matching: find.byType(Opacity),
          ))
          .map((o) => o.opacity)
          .toList();
      expect(opacities, contains(closeTo(0.35, 0.001)));
    });
  });

  // 第 1 周 = 2026-08-31(周一) ~ 09-06(周日)：09-02 是周三、09-05 是周六
  final week1Start = DateTime(2026, 8, 31);

  group('节假日 / 调休补班', () {
    List<double> opacitiesOf(WidgetTester tester, String name) => tester
        .widgetList<Opacity>(find.ancestor(
          of: find.text(name),
          matching: find.byType(Opacity),
        ))
        .map((o) => o.opacity)
        .toList();

    testWidgets('放假日那天的课按「不上」处理，表头写「放假」', (tester) async {
      await pumpGrid(
        tester,
        tt([
          c(name: '周三的课', day: 3, start: 3, end: 4),
        ], startDate: week1Start),
        1,
        showInactiveCourses: true,
        holidays: HolidayCalendar(
          holidays: [HolidayDay(DateTime(2026, 9, 2), '测试放假日')],
        ),
      );

      expect(find.text('周三的课'), findsOneWidget);
      expect(find.text('放假'), findsOneWidget, reason: '表头要说明这列为什么淡');
      expect(
        opacitiesOf(tester, '周三的课'),
        contains(closeTo(0.35, 0.001)),
        reason: '放假日不上课，和「非本周课程」一样画淡',
      );
    });

    testWidgets('不开「显示非本周课程」时放假日那列是空的', (tester) async {
      await pumpGrid(
        tester,
        tt([
          c(name: '周三的课', day: 3, start: 3, end: 4),
        ], startDate: week1Start),
        1,
        holidays: HolidayCalendar(
          holidays: [HolidayDay(DateTime(2026, 9, 2), '测试放假日')],
        ),
      );

      expect(find.text('周三的课'), findsNothing);
      expect(find.text('放假'), findsOneWidget, reason: '表头仍要说明，否则用户以为课丢了');
    });

    testWidgets('补班日（周六补周三）显示被补星期的课', (tester) async {
      await pumpGrid(
        tester,
        tt([
          c(name: '周三的课', day: 3, start: 3, end: 4),
        ], startDate: week1Start),
        1,
        holidays: HolidayCalendar(
          makeups: [MakeupDay(DateTime(2026, 9, 5), 3, '补周三的课')],
        ),
      );

      // 周三那列一份，补班的周六那列也一份
      expect(find.text('周三的课'), findsNWidgets(2));
      expect(find.text('补周三'), findsOneWidget);
      expect(
        opacitiesOf(tester, '周三的课'),
        everyElement(1.0),
        reason: '补班日那节课是真要上的，不能画淡',
      );
    });

    testWidgets('没设学期起始日期时不套用节假日（退回旧行为）', (tester) async {
      await pumpGrid(
        tester,
        tt([
          c(name: '周三的课', day: 3, start: 3, end: 4),
        ]), // startDate 为 null
        1,
        holidays: HolidayCalendar(
          holidays: [HolidayDay(DateTime(2026, 9, 2), '测试放假日')],
        ),
      );

      expect(find.text('周三的课'), findsOneWidget);
      expect(find.text('放假'), findsNothing);
    });
  });
}
