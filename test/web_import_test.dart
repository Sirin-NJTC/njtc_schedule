/// 「网页登录导入」解析链路测试。
///
/// 覆盖 `lib/services/jwxt_service.dart`（抓取结果的解析与兜底）与
/// `lib/services/zf_html_parser.dart` 的 `textGrid`（HTML 表格 → 纯文本网格）。
///
/// 这里**不启动 WebView**：原生侧只负责把页面 HTML/文本抓回来，
/// 解析全部在 Dart 侧完成，所以可以直接喂 HTML 断言，
/// 相当于把「登录成功后我到底能不能拿到正确课表」这件事离线验证掉。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/models/course.dart';
import 'package:njtc_schedule/services/jwxt_service.dart';
import 'package:njtc_schedule/services/zf_html_parser.dart';

String _fixture() => File('test/fixtures/zf_xskb_list.html').readAsStringSync();

Map<String, dynamic> _payload({
  String tableHtml = '',
  String text = '',
  String title = '',
  String url = 'https://jwxt.njtc.edu.cn/jsxsd/xskb/xskb_list.do',
}) =>
    <String, dynamic>{
      'url': url,
      'title': title,
      'tableHtml': tableHtml,
      'text': text,
      'tableCount': tableHtml.isEmpty ? 0 : 1,
    };

/// 模拟「不是正方 `kbcontent` 结构、但课程格里已经是 `/` 分隔文本」的教务系统页面。
const String _slashTextTableHtml = '''
<table id="kbtable">
  <tr><th>节次</th><th>星期一</th><th>星期二</th></tr>
  <tr><td>1-2节</td>
      <td>示例课程甲/(1-2节)7-18周/格致楼216/示例老师A/ZB1040282-07/演示26.8</td>
      <td></td></tr>
  <tr><td>3-4节</td><td></td>
      <td>示例课程戊/(3-4节)1-16周/明德楼A101/李四/GB001-01/演示26.8</td></tr>
</table>
''';

/// 从浏览器直接复制表格时，`innerText` 出来的是制表符分隔的文本。
const String _tabSeparatedText = '节次\t星期一\t星期二\n'
    '1-2节\t示例课程甲/(1-2节)7-18周/格致楼216/示例老师A\t\n'
    '3-4节\t\t示例课程戊/(3-4节)1-16周/明德楼A101/李四\n';

Course _find(List<Course> courses, int day, int section, String name) =>
    courses.firstWhere(
      (c) => c.dayOfWeek == day && c.startSection == section && c.name == name,
      orElse: () => throw StateError(
        '未找到课程：星期$day 第$section节 $name；'
        '实际有 ${courses.map((c) => '${c.dayOfWeek}/${c.startSection}/${c.name}').join(', ')}',
      ),
    );

void main() {
  group('ZfHtmlParser.textGrid', () {
    test('把课表表格还原成含表头的纯文本二维数组', () {
      final grid = ZfHtmlParser.textGrid(_fixture());
      expect(grid, isNotEmpty);
      expect(
        grid.any((row) => row.any((c) => c.contains('星期一'))),
        isTrue,
        reason: '应保留「星期」表头，parseGrid 靠它建立 列→星期 映射',
      );
      expect(
        grid.any((row) => row.any((c) => c.contains('示例课程甲'))),
        isTrue,
      );
    });

    test('非表格 HTML 返回空网格', () {
      expect(ZfHtmlParser.textGrid('<div>成绩查询</div>'), isEmpty);
      expect(ZfHtmlParser.textGrid(''), isEmpty);
    });
  });

  group('JwxtService.parsePayload —— 正方课表页', () {
    test('整页 HTML 解析出 9 门次课程与学期信息', () {
      final result = JwxtService.parsePayload(
        _payload(
          tableHtml: _fixture(),
          title: '学生课表',
          text: '2026-2027年第1学期 专业：示例工程 本学期共20周 2026-08-31正式上课',
        ),
        name: '网页导入',
      );

      expect(result.ok, isTrue, reason: result.message);
      final tt = result.timetable!;
      expect(tt.courses.length, 9);
      expect(tt.name, '网页导入');
      expect(tt.semester, '2026-2027年第1学期');
      expect(tt.major, '示例工程');
      expect(tt.totalWeeks, 20);
      expect(tt.startDate, DateTime(2026, 8, 31));
    });

    test('课程字段完整（教师/地点/代码/周次/节次）', () {
      final result = JwxtService.parsePayload(_payload(tableHtml: _fixture()));
      final c = _find(result.timetable!.courses, 1, 1, '示例课程甲');
      expect(c.teacher, '示例老师A');
      expect(c.location, '格致楼216');
      expect(c.courseCode, 'ZB1040282-07');
      expect(c.startWeek, 7);
      expect(c.endWeek, 18);
      expect(c.endSection, 2);
    });

    test('没有学期信息时给出安全默认值（20 周 / 空学期）', () {
      final result = JwxtService.parsePayload(_payload(tableHtml: _fixture()));
      final tt = result.timetable!;
      expect(tt.semester, '');
      expect(tt.totalWeeks, 20);
      expect(tt.startDate, isNull);
      expect(tt.name, contains('课表'), reason: '自动命名');
    });
  });

  group('JwxtService.parsePayload —— 其它教务系统结构', () {
    test('格内是 `/` 分隔文本的 HTML 表格也能解析', () {
      final result = JwxtService.parsePayload(
        _payload(tableHtml: _slashTextTableHtml, title: '我的课表'),
      );
      expect(result.ok, isTrue, reason: result.message);
      final courses = result.timetable!.courses;
      expect(courses.length, 2);

      final ai = _find(courses, 1, 1, '示例课程甲');
      expect(ai.location, '格致楼216');
      expect(ai.teacher, '示例老师A');
      expect(ai.courseCode, 'ZB1040282-07');
      expect(ai.startWeek, 7);
      expect(ai.endWeek, 18);

      final math = _find(courses, 2, 3, '示例课程戊');
      expect(math.location, '明德楼A101');
      expect(math.startWeek, 1);
      expect(math.endWeek, 16);
    });

    test('只有制表符文本（浏览器复制）时走文本兜底', () {
      final result = JwxtService.parsePayload(
        _payload(text: _tabSeparatedText, title: '学生课表'),
      );
      expect(result.ok, isTrue, reason: result.message);
      final courses = result.timetable!.courses;
      expect(courses.length, 2);
      expect(_find(courses, 1, 1, '示例课程甲').location, '格致楼216');
      expect(_find(courses, 2, 3, '示例课程戊').teacher, '李四');
    });
  });

  group('JwxtService.parsePayload —— 失败路径', () {
    test('页面不是课表时给出可操作的提示', () {
      final result = JwxtService.parsePayload(
        _payload(
          tableHtml: '<table><tr><td>成绩查询</td><td>2026</td></tr></table>',
          text: '成绩查询 2026-2027 学年',
        ),
      );
      expect(result.ok, isFalse);
      expect(result.status, WebImportStatus.failed);
      expect(result.message, contains('没有识别到课表'));
      expect(result.message, contains('课表查询'));
    });

    test('抓取结果里连文本都没有时不会崩，仍然返回失败结果', () {
      final result = JwxtService.parsePayload(const <String, dynamic>{});
      expect(result.ok, isFalse);
      expect(result.timetable, isNull);
      expect(result.pageUrl, '');
    });

    test('失败时把抓到的页面文本带出来，便于改用粘贴导入', () {
      final result = JwxtService.parsePayload(
        _payload(text: '欢迎使用教务系统'),
      );
      expect(result.ok, isFalse);
      expect(result.rawText, '欢迎使用教务系统');
    });
  });

  group('JwxtService.parsePayload —— 正方 jwglxt JSON 接口', () {
    // 真实接口的一行（字段名来自正方 V9 `xskbcx_cxXskbcxIndex.html?doType=query`）
    Map<String, dynamic> row({
      String kcmc = '示例课程甲',
      String xm = '示例老师A',
      String cdmc = '格致楼216',
      String xqj = '1',
      String jcs = '1-2',
      String zcd = '7-18周',
    }) =>
        {
          'kcmc': kcmc,
          'xm': xm,
          'cdmc': cdmc,
          'xqj': xqj,
          'jcs': jcs,
          'zcd': zcd,
        };

    test('kbList 行 → 课程，字段与节次/周次都对', () {
      final courses = ZfHtmlParser.coursesFromJwglxtJson([row()]);
      expect(courses.length, 1);
      final c = courses.first;
      expect(c.name, '示例课程甲');
      expect(c.teacher, '示例老师A');
      expect(c.location, '格致楼216');
      expect(c.dayOfWeek, 1);
      expect(c.startSection, 1);
      expect(c.endSection, 2);
      expect(c.startWeek, 7);
      expect(c.endWeek, 18);
      expect(c.oddEven, 0);
    });

    test('单双周、单节次、离散周次都按原语义解析', () {
      final odd = ZfHtmlParser.coursesFromJwglxtJson([
        row(zcd: '1-15周(单)', jcs: '3'),
      ]);
      expect(odd.single.oddEven, 1);
      expect(odd.single.startSection, 3);
      expect(odd.single.endSection, 3);
      expect(odd.single.startWeek, 1);
      expect(odd.single.endWeek, 15);

      // 逗号分隔的离散周次：逐段产出，不补空隙（否则会凭空多出没课的周）
      final split = ZfHtmlParser.coursesFromJwglxtJson([
        row(zcd: '1,3,5-9周'),
      ]);
      expect(split.map((c) => '${c.startWeek}-${c.endWeek}').toList(),
          ['1-1', '3-3', '5-9']);
    });

    test('同义字段名（kcm/xq/xqj 之外的变体）也能认', () {
      final courses = ZfHtmlParser.coursesFromJwglxtJson([
        {
          'kcm': '示例课程子',
          'jsxm': '示例老师K',
          'jxcdmc': '格致楼201',
          'xq': '5',
          'sksj': '第7-8节',
          'skzc': '2-16周(双)',
        },
      ]);
      expect(courses.length, 1);
      expect(courses.first.name, '示例课程子');
      expect(courses.first.teacher, '示例老师K');
      expect(courses.first.location, '格致楼201');
      expect(courses.first.dayOfWeek, 5);
      expect(courses.first.startSection, 7);
      expect(courses.first.endSection, 8);
      expect(courses.first.oddEven, 2);
    });

    test('缺名称 / 缺星期 / 缺节次 / 缺周次的行会被丢弃，不产出幽灵课', () {
      expect(ZfHtmlParser.coursesFromJwglxtJson([row(kcmc: '')]), isEmpty);
      expect(ZfHtmlParser.coursesFromJwglxtJson([row(xqj: '9')]), isEmpty);
      expect(ZfHtmlParser.coursesFromJwglxtJson([row(jcs: '')]), isEmpty);
      expect(ZfHtmlParser.coursesFromJwglxtJson([row(zcd: '')]), isEmpty);
    });

    test('payload 里带 jsonRows 时走「路径 0」，学期从 xnm/xqm 推出来', () {
      final result = JwxtService.parsePayload({
        'url': 'https://jxglpt.example/kbcx/xskbcx_cxXskbcxIndex.html',
        'title': '学生课表',
        'text': '课表查询',
        'tableHtml': '',
        'jsonRows': [
          row(),
          row(kcmc: '示例课程戊', xm: '示例老师B', cdmc: '明德楼A103', jcs: '3-4'),
        ],
        'xnm': '2026',
        'xqm': '3',
      }, name: '演示26.8课表');

      expect(result.ok, isTrue, reason: result.message);
      expect(result.message, contains('教务接口'));
      final tt = result.timetable!;
      expect(tt.courses.length, 2);
      expect(tt.semester, '2026-2027年第1学期');
      // 总周数由 max(zcd) 反推（页面上没有「共 N 周」时）
      expect(tt.totalWeeks, 18);
    });

    test('jsonRows 解析不出课程时，回落到 DOM 路径', () {
      final result = JwxtService.parsePayload({
        'url': 'https://jxglpt.example/kbcx/xskbcx_cxXskbcxIndex.html',
        'title': '学生课表',
        'text': '',
        'tableHtml': '',
        // 只有一行脏数据：没有课程名，路径 0 必须放弃而不是返回空课表
        'jsonRows': [
          {'xqj': '1', 'jcs': '1-2', 'zcd': '1-16周'},
        ],
        'xnm': '2026',
        'xqm': '3',
      });
      expect(result.status, WebImportStatus.failed);
    });

    test('semesterFromCodes 认不出学期码时返回空串', () {
      expect(ZfHtmlParser.semesterFromCodes('2026', '3'), '2026-2027年第1学期');
      expect(ZfHtmlParser.semesterFromCodes('2026', '12'), '2026-2027年第2学期');
      expect(ZfHtmlParser.semesterFromCodes('2026', '99'), '');
      expect(ZfHtmlParser.semesterFromCodes('', '3'), '');
    });
  });

  group('JwxtService 平台约束', () {
    test('非 Android 平台不调用原生通道，直接给出可读提示', () async {
      // flutter test 跑在桌面/CI 上，Platform.isAndroid 为 false
      expect(JwxtService.supported, isFalse);
      final result = await JwxtService.importFromWeb();
      expect(result.ok, isFalse);
      expect(result.status, WebImportStatus.failed);
      expect(result.message, contains('Android'));
    });
  });
}
