/// 解析器单元测试 —— 验证教务系统课表格式解析。
///
/// 关键回归点：
/// - 真实数据格式是 `课程名/(1-2节)7-18周/ 地点/教师/教学班/班级`，
///   时间信息在 **第 2 个字段**而不是第 1 个。曾因只从 parts[0] 取时间，
///   导致所有课程周次退化成默认 1-20 周、单双周信息丢失。
/// - 周次正则必须带「周」，否则 `1-2节` 会被误读成周次 1-2。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/models/course.dart';
import 'package:njtc_schedule/services/timetable_parser.dart';

/// 内江师范学院教务系统真实导出的课表（智26.8，2026-2027 学年第 1 学期）。
/// 数据来源：`智26.8课表(20260831155948995).xls` 经 xlrd 读取后的原始单元格。
const List<List<String>> realGrid = [
  [
    '2026-2027年第1学期', '2026-2027年第1学期', '2026-2027年第1学期',
    '智26.8课表', '智26.8课表', '智26.8课表', '智26.8课表',
    '专业：机器人工程', '专业：机器人工程',
  ],
  ['节次', '', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'],
  [
    '上午', '一',
    '人工智能导论/(1-2节)7-18周/ 明德楼B216/韩云/(2026-2027-1)-ZB1040282-07/智26.8',
    '',
    '思想道德与法治/(1-2节)7-18周/ 明德楼B214/代维/(2026-2027-1)-GB0640014-10/智26.7;智26.8',
    '大学生心理健康教育/(1-2节)6-18周/ 明德楼B301/彭玉发/(2026-2027-1)-GB1240005-29/智26.7;智26.8',
    '形势与政策Ⅰ/(1-2节)7-10周/ 培训中心201/刘欢/(2026-2027-1)-GB0640008-22/智26.7;智26.8',
    '', '',
  ],
  [
    '上午', '二',
    '高等数学Ⅰ（上）/(3-4节)7-18周/ 明德楼A103/曾玉祥/(2026-2027-1)-JC0247023-10/智26.8',
    '',
    '高等数学Ⅰ（上）/(3-4节)7-18周/ 明德楼B204/曾玉祥/(2026-2027-1)-JC0247023-10/智26.8',
    'Python程序设计/(3-4节)6-18周/ 格致楼113/徐双/(2026-2027-1)-JC1040051-01/智26.8',
    '大学物理V（上）/(3-4节)7-17周/ 明德楼B314/张熙程/(2026-2027-1)-JC0340059-08/智26.8',
    '', '',
  ],
  [
    '下午', '三',
    '',
    '思想道德与法治/(5-6节)7-17周(单)/ 明德楼B112/代维/(2026-2027-1)-GB0640014-10/智26.7;智26.8\r\n'
        '大学生心理健康教育/(5-6节)8-12周(双)/ 明德楼A310/彭玉发/(2026-2027-1)-GB1240005-29/智26.7;智26.8',
    'Python程序设计/(5-6节)7-18周/ 格致楼205/徐双/(2026-2027-1)-JC1040051-01/智26.8',
    '大学体育Ⅰ/(5-6节)1-18周/ 田径场04/张明莲/(2026-2027-1)-GB0840001-25/智26.7;智26.8',
    '职业规划与就业创业指导Ⅰ/(5-6节)7-10周/ 明德楼A415/张小梅/(2026-2027-1)-GB2040011-53/智26.8\r\n'
        'Python程序设计/(5-6节)11-17周/ 格致楼109/徐双/(2026-2027-1)-JC1040051-01/智26.8',
    '', '',
  ],
  [
    '下午', '四',
    '',
    '人工智能导论/(7-8节)7-18周/ 明德楼B218/韩云/(2026-2027-1)-ZB1040282-07/智26.8',
    '',
    '国家安全教育/(7-8节)6-10周/ 明德楼B213/陈洪英/(2026-2027-1)-GB0640024-01/地26.2;美26.2;智26.8\r\n'
        '大学物理V（上）/(7-8节)11-15周/ 明德楼B105/张熙程/(2026-2027-1)-JC0340059-08/智26.8\r\n'
        '高等数学Ⅰ（上）/(7-8节)16-18周/ 明德楼B119/曾玉祥/(2026-2027-1)-JC0247023-10/智26.8',
    '高等数学Ⅰ（上）/(7-8节)6-18周/ 明德楼A203/曾玉祥/(2026-2027-1)-JC0247023-10/智26.8',
    '', '',
  ],
  [
    '晚上', '五',
    '思想道德与法治/(9-10节)12-14周(双)/ 明德楼B303/代维/(2026-2027-1)-GB0640014-10/智26.7;智26.8',
    '', '', '', '', '', '',
  ],
  [
    '注--内容顺序为：课程<>周次<>地点<>教师<>教学班<>教学班组成          本学期2026-08-31正式上课至2027-01-17结束，共20周.                                     打印时间：2026-08-31',
    '', '', '', '', '', '', '',
  ],
];

/// 按 星期 + 起始节次 + 课程名 查找课程。
Course findCourse(List<Course> courses, int day, int section, String name) {
  return courses.firstWhere(
    (c) => c.dayOfWeek == day && c.startSection == section && c.name.contains(name),
    orElse: () => throw StateError('未找到课程: 周$day 第$section节 $name'),
  );
}

void main() {
  group('TimetableParser.parseCell', () {
    test('解析单门课程的标准格式', () {
      final courses = TimetableParser.parseCell(
        '人工智能导论/(1-2节)7-18周/ 明德楼B216/韩云/(2026-2027-1)-ZB1040282-07/智26.8',
        dayOfWeek: 1,
        slotIndex: 0,
      );
      expect(courses.length, 1);
      final c = courses.first;
      expect(c.name, '人工智能导论');
      expect(c.teacher, '韩云');
      expect(c.location, '明德楼B216');
      expect(c.startSection, 1);
      expect(c.endSection, 2);
      expect(c.startWeek, 7);
      expect(c.endWeek, 18);
      expect(c.oddEven, 0);
      expect(c.courseCode, 'ZB1040282-07');
      expect(c.className, '智26.8');
    });

    test('解析单双周课程', () {
      final courses = TimetableParser.parseCell(
        '思想道德与法治/(5-6节)7-17周(单)/ 明德楼B112/代维/(2026-2027-1)-GB0640014-10/智26.7;智26.8',
        dayOfWeek: 2,
        slotIndex: 2,
      );
      final c = courses.first;
      expect(c.oddEven, 1); // 单周
      expect(c.startWeek, 7);
      expect(c.endWeek, 17);
      expect(c.startSection, 5);
      expect(c.endSection, 6);
      expect(c.courseCode, 'GB0640014-10');
    });

    test('双周课程', () {
      final courses = TimetableParser.parseCell(
        '思想道德与法治/(9-10节)12-14周(双)/ 明德楼B303/代维/(2026-2027-1)-GB0640014-10/智26.7;智26.8',
        dayOfWeek: 1,
        slotIndex: 4,
      );
      final c = courses.first;
      expect(c.oddEven, 2); // 双周
      expect(c.startWeek, 12);
      expect(c.endWeek, 14);
    });

    test('回归：节次数字不得被误读为周次', () {
      // `(1-2节)7-18周` —— 若周次正则不带「周」，`1-2` 会被当成周次。
      final courses = TimetableParser.parseCell(
        '某课程/(1-2节)7-18周/ A楼101/张老师/(2026-2027-1)-AB1234567-01/班级',
        dayOfWeek: 1,
      );
      final c = courses.first;
      expect(c.startWeek, 7, reason: '周次应为 7-18，而不是被 1-2节 污染');
      expect(c.endWeek, 18);
      expect(c.startSection, 1);
      expect(c.endSection, 2);
    });

    test('回归：时间字段不在第 1 段时仍能正确解析', () {
      // 变体格式：课程名与时间同段
      final courses = TimetableParser.parseCell(
        '高等数学(3-4节)5-16周/ 明德楼A103/曾玉祥/(2026-2027-1)-JC0247023-10/智26.8',
        dayOfWeek: 3,
      );
      final c = courses.first;
      expect(c.name, '高等数学');
      expect(c.startSection, 3);
      expect(c.endSection, 4);
      expect(c.startWeek, 5);
      expect(c.endWeek, 16);
      expect(c.location, '明德楼A103');
      expect(c.teacher, '曾玉祥');
    });

    test('回归：地点粘在课名里时要把地点拆出来（真机就是这种形态）', () {
      // 内江师范走反向代理后，正方页面没有 title 标注、也没有单独的地址列，
      // 一格里只有一行 `课名 地点 (节次)周次` —— 真机日志里表现为
      // 「… 明德楼B309 @」（@ 后面是空的教师+空地点），用户看到的就是「没有教室」。
      final courses = TimetableParser.parseCell(
        '大学生心理健康教育 明德楼B309 (1-2节)1-16周',
        dayOfWeek: 4,
      );
      final c = courses.first;
      expect(c.name, '大学生心理健康教育');
      expect(c.location, '明德楼B309');
      expect(c.startSection, 1);
      expect(c.endSection, 2);
      expect(c.startWeek, 1);
      expect(c.endWeek, 16);
    });

    test('回归：格内只有地点时不得把课程名拆空', () {
      final courses = TimetableParser.parseCell(
        '明德楼B309 (1-2节)1-16周',
        dayOfWeek: 4,
      );
      expect(courses.first.name, '明德楼B309');
      expect(courses.first.location, isEmpty);
    });

    test('解析一个单元格内多门课（换行分隔）', () {
      final courses = TimetableParser.parseCell(
        '思想道德与法治/(5-6节)7-17周(单)/ 明德楼B112/代维/(2026-2027-1)-GB0640014-10/智26.7;智26.8\n'
            '大学生心理健康教育/(5-6节)8-12周(双)/ 明德楼A310/彭玉发/(2026-2027-1)-GB1240005-29/智26.7;智26.8',
        dayOfWeek: 2,
        slotIndex: 2,
      );
      expect(courses.length, 2);
      expect(courses[0].oddEven, 1);
      expect(courses[0].startWeek, 7);
      expect(courses[1].oddEven, 2);
      expect(courses[1].startWeek, 8);
      expect(courses[1].endWeek, 12);
    });

    test('一格三门课（周四 7-8 节连排）', () {
      // 下午四 行的「星期四」列（col 5 → dayOfWeek 4）
      final courses = TimetableParser.parseCell(
        realGrid[5][5],
        dayOfWeek: 4,
        slotIndex: 3,
      );
      expect(courses.length, 3);
      expect(courses[0].name, '国家安全教育');
      expect(courses[0].startWeek, 6);
      expect(courses[0].endWeek, 10);
      expect(courses[1].name, '大学物理V（上）');
      expect(courses[1].startWeek, 11);
      expect(courses[1].endWeek, 15);
      expect(courses[2].name, '高等数学Ⅰ（上）');
      expect(courses[2].startWeek, 16);
      expect(courses[2].endWeek, 18);
    });
  });

  group('TimetableParser.parseGrid（真实课表全量回归）', () {
    final tt = TimetableParser.parseGrid(realGrid);

    test('表头信息', () {
      expect(tt.semester, '2026-2027年第1学期');
      expect(tt.major, '机器人工程');
    });

    test('课程总数与分布', () {
      expect(tt.courses.length, 20, reason: '真实课表共 20 条课程记录');
      final days = tt.courses.map((c) => c.dayOfWeek).toSet();
      expect(days, {1, 2, 3, 4, 5}, reason: '仅周一至周五有课，周末为空');
    });

    test('每门课都有完整的课程名/地点/教师/节次/周次', () {
      for (final c in tt.courses) {
        expect(c.name, isNotEmpty);
        expect(c.location, isNotEmpty, reason: '${c.name} 地点缺失');
        expect(c.teacher, isNotEmpty, reason: '${c.name} 教师缺失');
        expect(c.startSection, greaterThan(0), reason: '${c.name} 节次缺失');
        expect(c.endSection, greaterThanOrEqualTo(c.startSection));
        expect(c.startWeek, greaterThan(0), reason: '${c.name} 周次缺失');
        expect(c.endWeek, greaterThanOrEqualTo(c.startWeek));
        expect(c.courseCode, isNotEmpty, reason: '${c.name} 课程代码缺失');
      }
    });

    test('不得出现「周次默认值 1-20」的解析失败特征', () {
      // 旧 bug 的表现：所有课程周次退化成 1-20
      final allDefault = tt.courses.every((c) => c.startWeek == 1 && c.endWeek == 20);
      expect(allDefault, false, reason: '周次全部为 1-20，说明时间字段未解析到');
    });

    test('周一课程', () {
      final c = findCourse(tt.courses, 1, 1, '人工智能导论');
      expect(c.location, '明德楼B216');
      expect(c.teacher, '韩云');
      expect(c.startWeek, 7);
      expect(c.endWeek, 18);

      final c2 = findCourse(tt.courses, 1, 3, '高等数学');
      expect(c2.location, '明德楼A103');
      expect(c2.teacher, '曾玉祥');

      final c3 = findCourse(tt.courses, 1, 9, '思想道德与法治');
      expect(c3.oddEven, 2, reason: '周一晚 9-10 节为双周课');
      expect(c3.startWeek, 12);
      expect(c3.endWeek, 14);
      expect(c3.location, '明德楼B303');
    });

    test('周二 5-6 节同格两门课（单双周互补）', () {
      final list = tt.courses
          .where((c) => c.dayOfWeek == 2 && c.startSection == 5)
          .toList();
      expect(list.length, 2);
      final single = list.firstWhere((c) => c.oddEven == 1);
      final double_ = list.firstWhere((c) => c.oddEven == 2);
      expect(single.name, '思想道德与法治');
      expect(single.startWeek, 7);
      expect(single.endWeek, 17);
      expect(single.location, '明德楼B112');
      expect(double_.name, '大学生心理健康教育');
      expect(double_.startWeek, 8);
      expect(double_.endWeek, 12);
      expect(double_.location, '明德楼A310');
    });

    test('周四 7-8 节连续三门课', () {
      final list = tt.courses
          .where((c) => c.dayOfWeek == 4 && c.startSection == 7)
          .toList();
      expect(list.length, 3);
      expect(list.map((c) => c.name), contains('国家安全教育'));
      expect(list.map((c) => c.name), contains('大学物理V（上）'));
      expect(list.map((c) => c.name), contains('高等数学Ⅰ（上）'));
    });

    test('周五 5-6 节两门课', () {
      final list = tt.courses
          .where((c) => c.dayOfWeek == 5 && c.startSection == 5)
          .toList();
      expect(list.length, 2);
      expect(list.map((c) => c.name), contains('职业规划与就业创业指导Ⅰ'));
      expect(list.map((c) => c.name), contains('Python程序设计'));
    });

    test('教学班组成保留（含分号分隔的多班）', () {
      // 周二 5-6 节（单周）的思想道德与法治，教学班为「智26.7;智26.8」
      final c = findCourse(tt.courses, 2, 5, '思想道德与法治');
      expect(c.className, '智26.7;智26.8');
      expect(c.courseCode, 'GB0640014-10');
      expect(c.teacher, '代维');
      expect(c.oddEven, 1);
    });
  });

  group('Timetable.coursesOn / byDay', () {
    test('按周次筛选', () {
      final tt = TimetableParser.parseGrid(realGrid);
      // 第 7 周：单周课与不区分单双周的课都应出现
      final week7 = tt.coursesOn(2, 7);
      expect(week7.any((c) => c.name == '思想道德与法治'), true, reason: '7 是单周');
      expect(week7.any((c) => c.name == '大学生心理健康教育'), false,
          reason: '该课 8-12 周双周，第 7 周不上');

      // 第 8 周：双周课出现，单周课不出现
      final week8 = tt.coursesOn(2, 8);
      expect(week8.any((c) => c.name == '大学生心理健康教育'), true);
      expect(week8.any((c) => c.name == '思想道德与法治'), false, reason: '8 是双周');
    });
  });

  group('Course.isActiveOnWeek', () {
    test('单双周判断', () {
      const single = Course(
        name: 'x',
        teacher: '',
        location: '',
        dayOfWeek: 1,
        startSection: 1,
        endSection: 2,
        startWeek: 7,
        endWeek: 17,
        oddEven: 1, // 单周
      );
      expect(single.isActiveOnWeek(7), true);
      expect(single.isActiveOnWeek(8), false); // 偶数周
      expect(single.isActiveOnWeek(9), true);

      const both = Course(
        name: 'y',
        teacher: '',
        location: '',
        dayOfWeek: 1,
        startSection: 1,
        endSection: 2,
        startWeek: 7,
        endWeek: 17,
        oddEven: 2, // 双周
      );
      expect(both.isActiveOnWeek(8), true);
      expect(both.isActiveOnWeek(7), false);
      expect(both.isActiveOnWeek(6), false); // 不在范围
    });
  });

  group('页脚学期信息（课程提醒的依赖）', () {
    test('从页脚解析学期起始日期与总周数', () {
      final tt = TimetableParser.parseGrid(realGrid);
      expect(tt.startDate, isNotNull, reason: '页脚含「本学期2026-08-31正式上课」');
      expect(tt.startDate!.year, 2026);
      expect(tt.startDate!.month, 8);
      expect(tt.startDate!.day, 31);
      expect(tt.totalWeeks, 20, reason: '页脚含「共20周」');
    });

    test('2026-08-31 是周一，与按 epochDay 取模算周次的原生算法一致', () {
      expect(DateTime(2026, 8, 31).weekday, DateTime.monday);
      final tt = TimetableParser.parseGrid(realGrid);
      final start = tt.startDate!;
      expect(((start.add(const Duration(days: 0)).difference(start)).inDays ~/ 7) + 1, 1);
      expect(((start.add(const Duration(days: 6)).difference(start)).inDays ~/ 7) + 1, 1);
      expect(((start.add(const Duration(days: 7)).difference(start)).inDays ~/ 7) + 1, 2);
      expect(((start.add(const Duration(days: 20 * 7)).difference(start)).inDays ~/ 7) + 1, 21);
    });

    test('页脚缺失时不写入错误的起始日期，周数兜底为 20', () {
      final noFooter = realGrid
          .where((row) => !row[0].trim().startsWith('注'))
          .toList();
      final tt = TimetableParser.parseGrid(noFooter);
      expect(tt.startDate, isNull);
      expect(tt.totalWeeks, 20);
    });
  });

  group('TimetableParser.parseFreeText（整页文字兜底）', () {
    test('回归：地点与时间混在一行时，地点要落到 location 上', () {
      // 走反向代理后拿不到接口、也拿不到 title 标注时，只能整页文字兜底。
      // 这种行以前会把地点丢掉（location 恒为空串），真机就表现为「没有教室」。
      final tt = TimetableParser.parseFreeText(
        '星期一 大学生心理健康教育 明德楼B309 (1-2节)1-16周\n'
        '星期四 Python程序设计 格致楼113 5-6节 1-16周',
      );
      expect(tt.courses.length, 2);

      final first = tt.courses[0];
      expect(first.name, '大学生心理健康教育');
      expect(first.location, '明德楼B309');
      expect(first.dayOfWeek, 1);
      expect(first.startSection, 1);
      expect(first.endSection, 2);
      expect(first.startWeek, 1);
      expect(first.endWeek, 16);

      final second = tt.courses[1];
      expect(second.name, 'Python程序设计');
      expect(second.location, '格致楼113');
      expect(second.dayOfWeek, 4);
      expect(second.startSection, 5);
      expect(second.endSection, 6);
    });

    test('不认识的行直接跳过，不产生垃圾课程', () {
      final tt = TimetableParser.parseFreeText('教务系统 首页 退出登录\n2026年10月4日');
      expect(tt.courses, isEmpty);
    });
  });
}
