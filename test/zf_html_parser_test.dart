/// 正方教务系统课表**网页**解析器测试（`lib/services/zf_html_parser.dart`）。
///
/// 用 `test/fixtures/zf_xskb_list.html` 模拟教务系统学生课表页的真实结构
/// （rowspan/colspan、kbcontent、title 标注字段、`<hr>` 分隔多门课、周次在前节次在后）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/models/course.dart';
import 'package:njtc_schedule/services/zf_html_parser.dart';

String _fixture() =>
    File('test/fixtures/zf_xskb_list.html').readAsStringSync();

/// 按「星期 + 起始节次 + 课程名」找课。
Course _find(List<Course> courses, int day, int section, String name) =>
    courses.firstWhere(
      (c) => c.dayOfWeek == day && c.startSection == section && c.name == name,
      orElse: () => throw StateError(
        '未找到课程：星期$day 第$section节 $name；'
        '实际有 ${courses.map((c) => '${c.dayOfWeek}/${c.startSection}/${c.name}').join(', ')}',
      ),
    );

int _count(List<Course> courses, String name) =>
    courses.where((c) => c.name == name).length;

void main() {
  group('ZfHtmlParser 网页课表解析', () {
    test('识别课表页', () {
      final html = _fixture();
      expect(ZfHtmlParser.looksLikeTimetable(html), isTrue);
      expect(ZfHtmlParser.looksLikeTimetable('<html><body>没有课表</body></html>'),
          isFalse);
    });

    test('解析出全部 9 门次课程，且不受 rowspan 影响重复', () {
      final courses = ZfHtmlParser.parseCourses(_fixture());
      expect(courses.length, 9);
      // 示例课程甲在「周一 1-2 节」和「周二 7-8 节」各一次；
      // 课程格 rowspan=2 若被按行展开会变成 4 次。
      expect(_count(courses, '示例课程甲'), 2);
      expect(_count(courses, '示例课程乙'), 2);
    });

    test('字段齐全：课程名 / 教师 / 地点 / 课程代码 / 教学班组成', () {
      final courses = ZfHtmlParser.parseCourses(_fixture());
      final c = _find(courses, 1, 1, '示例课程甲');
      expect(c.teacher, '示例老师A');
      expect(c.location, '格致楼216');
      expect(c.courseCode, 'ZB1040282-07');
      expect(c.className, '演示26.8');
      expect(c.startSection, 1);
      expect(c.endSection, 2);
      expect(c.startWeek, 7);
      expect(c.endWeek, 18);
      expect(c.oddEven, 0);
    });

    test('同一格多门课（<hr> 分隔）与单双周', () {
      final courses = ZfHtmlParser.parseCourses(_fixture());
      final tue = courses
          .where((c) => c.dayOfWeek == 2 && c.startSection == 5)
          .toList();
      expect(tue.length, 2);

      final sx = _find(courses, 2, 5, '示例课程乙');
      expect(sx.oddEven, 1); // 单周
      expect(sx.startWeek, 7);
      expect(sx.endWeek, 17);
      expect(sx.location, '格致楼112');
      expect(sx.teacher, '示例老师D');
      expect(sx.courseCode, 'GB0640014-10');
      expect(sx.className, '演示26.7;演示26.8');

      final xl = _find(courses, 2, 5, '示例课程丙');
      expect(xl.oddEven, 2); // 双周
      expect(xl.startWeek, 8);
      expect(xl.endWeek, 12);
      expect(xl.location, '明德楼A310');
    });

    test('一格三门课连排（周四 7-8 节）', () {
      final courses = ZfHtmlParser.parseCourses(_fixture());
      final thu = courses
          .where((c) => c.dayOfWeek == 4 && c.startSection == 7)
          .toList();
      expect(thu.length, 3);
      expect(thu.map((c) => c.startWeek).toList(), [6, 11, 16]);
      expect(thu.map((c) => c.endWeek).toList(), [10, 15, 18]);
      expect(
        thu.map((c) => c.name).toList(),
        ['示例课程癸', '示例课程庚', '示例课程戊'],
      );
    });

    test('晚上 9-10 节与双周（节次由单元格自带信息给出）', () {
      final courses = ZfHtmlParser.parseCourses(_fixture());
      final c = _find(courses, 1, 9, '示例课程乙');
      expect(c.startSection, 9);
      expect(c.endSection, 10);
      expect(c.startWeek, 12);
      expect(c.endWeek, 14);
      expect(c.oddEven, 2);
      expect(c.location, '格致楼303');
      expect(c.teacher, '示例老师D');
    });

    test('没有课的星期不会凭空生成课程', () {
      final courses = ZfHtmlParser.parseCourses(_fixture());
      expect(courses.where((c) => c.dayOfWeek == 3), isEmpty); // 周三
      expect(courses.where((c) => c.dayOfWeek == 5), isEmpty); // 周五
      expect(courses.where((c) => c.dayOfWeek == 6), isEmpty); // 周六
      expect(courses.where((c) => c.dayOfWeek == 7), isEmpty); // 周日
    });

    test('从页面文本抽取学期 / 专业 / 总周数 / 起始日期', () {
      final tt = ZfHtmlParser.parseTimetable(_fixture(), name: '网页导入');
      expect(tt, isNotNull);
      expect(tt!.semester, '2026-2027年第1学期');
      expect(tt.major, '示例工程');
      expect(tt.totalWeeks, 20);
      expect(tt.startDate, DateTime(2026, 8, 31));
      expect(tt.name, '网页导入');
      expect(tt.courses.length, 9);
    });

    test('非课表页面返回空结果', () {
      expect(ZfHtmlParser.parseCourses('<html><body>成绩查询</body></html>'),
          isEmpty);
      expect(ZfHtmlParser.parseTimetable('<div>登录中…</div>'), isNull);
    });
  });

  group('ZfHtmlParser 同一格多门课的分隔符', () {
    /// 一批正方版本不用 `<hr>`，而是在 HTML 里直接写一行连续短横线（`-----`）。
    const dashed = '''
<html><head><title>学生课表</title></head><body>
<div id="head">2026-2027学年 第1学期&nbsp;&nbsp;专业：示例工程</div>
<table id="kbtable" class="table table-bordered">
  <tr>
    <th>节次</th>
    <td>星期一</td><td>星期二</td><td>星期三</td>
    <td>星期四</td><td>星期五</td><td>星期六</td><td>星期日</td>
  </tr>
  <tr>
    <td rowspan="2">上午<br>一<br>1-2节</td>
    <td rowspan="2"><div class="kbcontent">示例课程戊<br><font title="教师">示例老师B</font><br><font title="周次(节次)">1-16周(1-2节)</font><br><font title="地点">明德楼A103</font></div>-----<div class="kbcontent">示例课程子<br><font title="教师">示例老师K</font><br><font title="周次(节次)">1-16周(1-2节)</font><br><font title="地点">格致楼201</font></div></td>
    <td></td><td></td><td></td><td></td><td></td><td></td>
  </tr>
  <tr></tr>
</table>
</body></html>
''';

    test('`-----` 分隔的两门课都会被解析出来', () {
      final courses = ZfHtmlParser.parseCourses(dashed);
      expect(courses.length, 2, reason: '同格两门课必须切开');

      final math = _find(courses, 1, 1, '示例课程戊');
      expect(math.teacher, '示例老师B');
      expect(math.location, '明德楼A103');
      expect(math.endSection, 2);
      expect(math.startWeek, 1);
      expect(math.endWeek, 16);

      final en = _find(courses, 1, 1, '示例课程子');
      expect(en.teacher, '示例老师K');
      expect(en.location, '格致楼201');
    });

    test('单个短横线（课程代码里的）不会被误当成分隔符', () {
      final courses = ZfHtmlParser.parseCourses(dashed);
      final math = _find(courses, 1, 1, '示例课程戊');
      expect(math.name.contains('-'), isFalse);
      // 课程代码形如 ZB1040282-07，只有一个短横线，不能被切碎
      final withCode = ZfHtmlParser.parseCourses(
        dashed.replaceAll(
          '<font title="地点">明德楼A103</font>',
          '<font title="地点">明德楼A103</font><br><font title="教学班">ZB1040282-07</font>',
        ),
      );
      expect(withCode.length, 2);
      expect(_find(withCode, 1, 1, '示例课程戊').courseCode, 'ZB1040282-07');
    });
  });

  group('ZfHtmlParser.extractMeta', () {
    test('周次列表取最小/最大', () {
      final meta = ZfHtmlParser.extractMeta('本学期共18周');
      expect(meta.totalWeeks, 18);
    });

    test('识别不到时给出安全默认值', () {
      final meta = ZfHtmlParser.extractMeta('欢迎使用教务系统');
      expect(meta.semester, '');
      expect(meta.major, '');
      expect(meta.totalWeeks, 0);
      expect(meta.startDate, isNull);
    });
  });
}
