/// 学期周次换算的测试。
///
/// 这里最要紧的是「startDate 带时间分量」那条：它正式过去三个调用点算法
/// 不一致时会算错的地方，改回手写 `difference().inDays` 就会立刻红。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/models/course.dart';
import 'package:njtc_schedule/models/holiday_calendar.dart';
import 'package:njtc_schedule/models/period.dart' show defaultPeriods;
import 'package:njtc_schedule/models/semester.dart';

void main() {
  // 学期 2026-08-31（周一）开学，共 20 周
  final start = DateTime(2026, 8, 31);

  group('weekOfSemester', () {
    test('开学当天是第 1 周', () {
      expect(
        weekOfSemester(startDate: start, day: start, totalWeeks: 20),
        1,
      );
    });

    test('第 7 天跨入第 2 周，第 6 天还在第 1 周', () {
      expect(
        weekOfSemester(
          startDate: start,
          day: DateTime(2026, 9, 6), // 开学后第 6 天
          totalWeeks: 20,
        ),
        1,
      );
      expect(
        weekOfSemester(
          startDate: start,
          day: DateTime(2026, 9, 7), // 开学后第 7 天
          totalWeeks: 20,
        ),
        2,
      );
    });

    test('没设学期起始日期时返回 null', () {
      expect(
        weekOfSemester(startDate: null, day: start, totalWeeks: 20),
        isNull,
      );
    });

    test('超出学期范围时夹到首尾周', () {
      // 开学前
      expect(
        weekOfSemester(
          startDate: start,
          day: DateTime(2026, 8, 1),
          totalWeeks: 20,
        ),
        1,
      );
      // 学期结束后
      expect(
        weekOfSemester(
          startDate: start,
          day: DateTime(2027, 3, 1),
          totalWeeks: 20,
        ),
        20,
      );
    });

    test('startDate 带时间分量时结果不变（回归）', () {
      // 这条正是过去三处算法不一致会算错的地方：
      // 老实现写的是 `now.difference(start).inDays`，start 一旦不是当地午夜，
      // 每跨一天的前几个小时都会少算一天 —— 9-7 早上会被算成第 1 周。
      //
      // 刻意用「本地时间 + 明确时分」构造，不要写成 `DateTime.parse('...Z')`
      // 再去断言 hour：flutter test 跑在 UTC 时区下，那条前置断言不成立。
      final shifted = DateTime(2026, 8, 31, 8, 0);
      expect(
        weekOfSemester(
          startDate: shifted,
          day: DateTime(2026, 9, 7, 7, 0),
          totalWeeks: 20,
        ),
        2,
        reason: '9-7 距 8-31 整 7 天，应是第 2 周；老算法会算成第 1 周',
      );
    });

    test('同一天，带不带时分秒结果一致', () {
      for (final hour in [0, 7, 8, 12, 23]) {
        expect(
          weekOfSemester(
            startDate: DateTime(2026, 8, 31, hour, 30),
            day: DateTime(2026, 9, 7, 7, 0),
            totalWeeks: 20,
          ),
          2,
          reason: 'startDate 是 8-31 $hour:30 时都该是第 2 周',
        );
      }
    });
  });

  group('rawWeekOf', () {
    test('不夹取越界值（weekOfSemester 会夹）', () {
      expect(rawWeekOf(startDate: start, day: DateTime(2026, 8, 1)), lessThan(1));
      expect(rawWeekOf(startDate: start, day: DateTime(2027, 3, 1)), greaterThan(20));
      expect(
        weekOfSemester(startDate: start, day: DateTime(2027, 3, 1), totalWeeks: 20),
        20,
        reason: '显示用的那份要夹住',
      );
    });

    test('没设起始日期时返回 null', () {
      expect(rawWeekOf(startDate: null, day: start), isNull);
    });
  });

  group('currentWeekOf', () {
    test('语义等同于 weekOfSemester 取今天', () {
      expect(
        currentWeekOf(start, 20),
        weekOfSemester(startDate: start, day: DateTime.now(), totalWeeks: 20),
      );
    });

    test('没设起始日期时返回 null', () {
      expect(currentWeekOf(null, 20), isNull);
    });
  });

  group('startOfWeek', () {
    test('第 1 周就是开学日，之后每周 +7 天', () {
      final w1 = startOfWeek(startDate: start, week: 1)!;
      expect('${w1.month}/${w1.day}', '8/31');
      final w2 = startOfWeek(startDate: start, week: 2)!;
      expect('${w2.month}/${w2.day}', '9/7');
      final w5 = startOfWeek(startDate: start, week: 5)!;
      expect('${w5.month}/${w5.day}', '9/28');
    });

    test('跨月、跨年都算得对', () {
      final w = startOfWeek(startDate: start, week: 18)!;
      expect('${w.month}/${w.day}', '12/28');
    });

    test('没设起始日期时返回 null', () {
      expect(startOfWeek(startDate: null, week: 3), isNull);
    });
  });

  // ── 下一节课扫描（首页倒计时用）────────────────────────────────
  group('nextClassOccurrence', () {
    // 2026-10-07 是周三；学期 2026-08-31 起算，这天是第 6 周
    final now = DateTime(2026, 10, 7, 12, 0);

    NextClassOccurrence? find({
      required List<Course> courses,
      HolidayCalendar holidays = const HolidayCalendar(),
      DateTime? from,
      int totalWeeks = 20,
    }) =>
        nextClassOccurrence(
          courses: courses,
          holidays: holidays,
          startDate: start,
          totalWeeks: totalWeeks,
          periods: defaultPeriods,
          from: from ?? now,
        );

    test('今天的下一节课（第一二节已过，取第三节）', () {
      final got = find(
        courses: [
          const Course(
            name: '早八',
            teacher: '张老师',
            location: 'A101',
            dayOfWeek: 3,
            startSection: 1,
            endSection: 2,
            startWeek: 1,
            endWeek: 20,
          ),
          const Course(
            name: '三四节',
            teacher: '李老师',
            location: 'A102',
            dayOfWeek: 3,
            startSection: 3,
            endSection: 4,
            startWeek: 1,
            endWeek: 20,
          ),
        ],
        // 09:00 —— 第 1 节（08:20 起）已经开始，第 3 节（10:20 起）还没到
        from: DateTime(2026, 10, 7, 9, 0),
      )!;
      expect(got.course.name, '三四节', reason: '第 3 节 10:20 上课，还没到');
      expect(got.isToday, isTrue);
      expect(got.startsAt, DateTime(2026, 10, 7, 10, 20));
    });

    test('今天的课上完了 → 找明天的（旧版这里直接消失）', () {
      final got = find(
        courses: [
          const Course(
            name: '今天唯一的一节',
            teacher: '张老师',
            location: 'A101',
            dayOfWeek: 3,
            startSection: 1,
            endSection: 2,
            startWeek: 1,
            endWeek: 20,
          ),
          const Course(
            name: '明天周四的课',
            teacher: '王老师',
            location: 'B201',
            dayOfWeek: 4,
            startSection: 1,
            endSection: 2,
            startWeek: 1,
            endWeek: 20,
          ),
        ],
        from: DateTime(2026, 10, 7, 15, 0), // 第 1 节早就结束了
      )!;
      expect(got.course.name, '明天周四的课');
      expect(got.isToday, isFalse);
      expect(got.startsAt, DateTime(2026, 10, 8, 8, 20));
    });

    test('放假日跳过，不顺延到放假那天的课', () {
      final holiday = HolidayCalendar(
        holidays: [HolidayDay(DateTime(2026, 10, 7), '测试放假日')],
      );
      final got = find(
        holidays: holiday,
        courses: [
          const Course(
            name: '放假日那天的课',
            teacher: '张老师',
            location: 'A101',
            dayOfWeek: 3,
            startSection: 3,
            endSection: 4,
            startWeek: 1,
            endWeek: 20,
          ),
          const Course(
            name: '明天周四的课',
            teacher: '王老师',
            location: 'B201',
            dayOfWeek: 4,
            startSection: 1,
            endSection: 2,
            startWeek: 1,
            endWeek: 20,
          ),
        ],
      )!;
      expect(got.course.name, '明天周四的课', reason: '今天是放假日，整天不上课');
    });

    test('补班日按「补周几」找课', () {
      // 2026-10-10 是周六，学校通知「周六补周三的课」
      final makeup = HolidayCalendar(
        makeups: [MakeupDay(DateTime(2026, 10, 10), 3, '补周三的课')],
      );
      final got = find(
        holidays: makeup,
        courses: [
          const Course(
            name: '周三的课',
            teacher: '张老师',
            location: 'A101',
            dayOfWeek: 3,
            startSection: 3,
            endSection: 4,
            startWeek: 1,
            endWeek: 20,
          ),
        ],
        from: DateTime(2026, 10, 10, 7, 0), // 周六早上
      )!;
      expect(got.course.name, '周三的课', reason: '补班日要按周三的课表上');
      expect(got.startsAt, DateTime(2026, 10, 10, 10, 20));
    });

    test('学期结束后不再报课', () {
      expect(
        find(
          courses: [
            const Course(
              name: '第 20 周的课',
              teacher: '张老师',
              location: 'A101',
              dayOfWeek: 3,
              startSection: 1,
              endSection: 2,
              startWeek: 1,
              endWeek: 20,
            ),
          ],
          from: DateTime(2027, 3, 1), // 学期早就结束了
          totalWeeks: 20,
        ),
        isNull,
        reason: 'rawWeek 超过总周数就该停，不能夹回第 20 周凭空多一周课',
      );
    });

    test('没设学期起始日期 / 没有课程时返回 null', () {
      expect(
        nextClassOccurrence(
          courses: [
            const Course(
              name: 'x',
              teacher: '',
              location: '',
              dayOfWeek: 3,
              startSection: 1,
              endSection: 2,
              startWeek: 1,
              endWeek: 20,
            ),
          ],
          holidays: const HolidayCalendar(),
          startDate: null,
          totalWeeks: 20,
          periods: defaultPeriods,
          from: now,
        ),
        isNull,
      );
      expect(find(courses: []), isNull);
    });
  });
}
