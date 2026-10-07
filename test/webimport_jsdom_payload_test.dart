/// 「注入脚本 → 原生载荷 → Dart 解析」整条链路的离线回归测试。
///
/// 和 [web_import_test.dart] 的区别：那边喂的是**手写**的 HTML / 载荷，
/// 只能证明解析层认得这种结构；这边喂的是
/// **`WebImportActivity.kt` 里那段真 `EXTRACT_JS` 在真 DOM（jsdom）上跑出来的载荷**，
/// 存在 `test/fixtures/extract_payload_jsdom.json`。
///
/// 为什么值得单独一个文件：此前 EXTRACT_JS 只做过「语法检查」和「把其中一小段函数
/// 抠出来喂假 DOM」，也就是说它**从未在真实 DOM 上执行过一次**。真机报「读取不到」
/// 时，无法区分是 JS 抠不到、接口没回、还是解析层吃不下。这条测试把上半段钉住：
/// 只要 `EXTRACT_JS` 改动导致它抠不出东西（`.kbcontent` 丢了、表格选错了、
/// 端点推错了），载荷会变，这里的断言就会红。
///
/// 载荷重新生成（改了 `EXTRACT_JS` 就要跑一次）：
///   node D:/DSH/_verify/verify_extract_pipeline.mjs
/// 该脚本用 jsdom 起真 DOM 跑 `EXTRACT_JS`，29 条断言后重写这个 fixture。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/models/course.dart';
import 'package:njtc_schedule/services/jwxt_service.dart';
import 'package:njtc_schedule/services/zf_html_parser.dart';

const String _fixturePath = 'test/fixtures/extract_payload_jsdom.json';

Map<String, dynamic> _payload() {
  final file = File(_fixturePath);
  expect(
    file.existsSync(),
    isTrue,
    reason: '缺少 $_fixturePath，用 node D:/DSH/_verify/verify_extract_pipeline.mjs 生成',
  );
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Course _find(List<Course> courses, int day, int section, String name) =>
    courses.firstWhere(
      (c) =>
          c.dayOfWeek == day &&
          c.startSection == section &&
          c.name == name,
      orElse: () => throw StateError(
        '找不到 周$day 第$section节 $name，实际有：'
        '${courses.map((c) => '周${c.dayOfWeek}(${c.startSection}-${c.endSection})${c.name}').join(' / ')}',
      ),
    );

void main() {
  group('EXTRACT_JS 真 DOM 载荷（jsdom 产物）', () {
    test('载荷本身就是「脚本抠到了东西」的样子', () {
      final payload = _payload();
      expect(payload['title'], '学生课表');
      expect('${payload['url']}', contains('xskbcx_cxXskbcxIndex.html'));
      // 页面没有内联 JSON：这条链路必须靠 DOM 兜底，而不是靠某个内联全局变量
      expect(payload['jsonRows'], isNull);
      expect('${payload['tableHtml']}', contains('kbcontent'));
      expect('${payload['tableHtml']}'.length, greaterThan(800));
      expect(payload['kbFilled'], 9);
      expect(payload['tableCount'], 2);
    });

    test('端点推断：正方页面 _cxXskbcxIndex.html → 数据接口 _cxXsKb.html', () {
      final endpoints = (_payload()['endpoints'] as List).cast<String>();
      expect(endpoints, isNotEmpty);
      // 这条是 1.1.6 主修之一：老代码在内江师范的反向代理部署下推不出端点、
      // 直接 return null，于是永远拿不到接口数据，教师/地点只能靠抠 DOM。
      expect(
        endpoints.first,
        'https://jxglpt-test.proxy.njtc.edu.cn/jwglxt/kbcx/xskbcx_cxXsKb.html',
      );
      expect(
        endpoints.any((u) => u.endsWith('/kbcx/xskbcx_cxXsKb.html')),
        isTrue,
        reason: 'context-path 猜错时还要有第二条路',
      );
    });

    test('解析层能把这坨载荷变成 9 门课', () {
      final result = JwxtService.parsePayload(_payload());
      expect(result.ok, isTrue, reason: result.message);
      final tt = result.timetable!;
      expect(tt.courses.length, 9);
      // 自动命名会带上抓到的学期/专业
      expect(tt.name, '2026-2027年第1学期 示例工程 课表');
    });

    test('学期 / 专业 / 总周数 从「正文」兜住（课表表格外的那截也带回来了）', () {
      final tt = JwxtService.parsePayload(_payload()).timetable!;
      // 注意：载荷里的 tableHtml 只有 #kbtable（2921 字节），
      // 「2026-2027学年第1学期 / 专业：示例工程 / 共20周」在表格**外面**的 #head 里，
      // 靠的是 payload['text']（整页正文）而不是 tableHtml。这两半缺一不可。
      expect(tt.semester, '2026-2027年第1学期');
      expect(tt.major, '示例工程');
      expect(tt.totalWeeks, 20);
    });

    test('教师 / 教室 / 课号 / 周次 / 节次 全都没丢', () {
      final tt = JwxtService.parsePayload(_payload()).timetable!;
      final ai = _find(tt.courses, 1, 1, '示例课程甲');
      expect(ai.teacher, '示例老师A');
      expect(ai.location, '格致楼216');
      expect(ai.courseCode, 'ZB1040282-07');
      expect(ai.className, '演示26.8');
      expect(ai.startWeek, 7);
      expect(ai.endWeek, 18);
      expect(ai.endSection, 2);
      expect(ai.oddEven, 0);
    });

    test('单双周这类语义在整条链路上没被磨掉', () {
      final tt = JwxtService.parsePayload(_payload()).timetable!;
      // 同一格（周二 5-6 节）里一门单周、一门双周，必须各自带住自己的 oddEven
      final dan = _find(tt.courses, 2, 5, '示例课程乙');
      expect(dan.oddEven, 1, reason: '单周');
      expect(dan.startWeek, 7);
      expect(dan.endWeek, 17);
      expect(dan.teacher, '示例老师D');
      expect(dan.location, '格致楼112');
      final shuang = _find(tt.courses, 2, 5, '示例课程丙');
      expect(shuang.oddEven, 2, reason: '双周');
      expect(shuang.startWeek, 8);
      expect(shuang.endWeek, 12);
      expect(shuang.location, '明德楼A310');
    });

    test('一格里多门课被切开、且按星期+节次稳定排序', () {
      final tt = JwxtService.parsePayload(_payload()).timetable!;
      final thu = tt.courses.where((c) => c.dayOfWeek == 4).toList();
      expect(thu.length, 3, reason: '周四那格一格里塞了三门课');
      expect(
        thu.map((c) => '${c.startWeek}-${c.endWeek}').toList(),
        ['6-10', '11-15', '16-18'],
        reason: '同一节次里的多门课按周次先后排',
      );
      final order = tt.courses
          .map((c) => c.dayOfWeek * 100 + c.startSection)
          .toList();
      final sorted = [...order]..sort();
      expect(order, sorted, reason: '接口路径会排序，DOM 路径也该稳定');
    });

    test('载荷路径与「整页 HTML 直接解析」结果逐门一致（不丢格、不丢字段）', () {
      // 这是本文件存在的核心理由：EXTRACT_JS 只把 `#kbtable` 的 outerHTML 带回来
      // （2921 字节，整页 4637 字节），少了 #head、那张 other-table 和 HTML 外壳。
      // 如果哪天它选错表、少抠一格、把 title 属性吃掉，这里就会红。
      final full = File('test/fixtures/zf_xskb_list.html').readAsStringSync();
      final direct = ZfHtmlParser.parseCourses(full);
      final viaPayload =
          JwxtService.parsePayload(_payload()).timetable!.courses;

      String key(Course c) => '${c.name}|${c.dayOfWeek}|'
          '${c.startSection}-${c.endSection}|${c.startWeek}-${c.endWeek}|'
          '${c.oddEven}|${c.teacher}|${c.location}|${c.courseCode}|'
          '${c.className}';
      final a = direct.map(key).toSet();
      final b = viaPayload.map(key).toSet();
      expect(a.length, direct.length, reason: '整页解析本身不该有重复');
      expect(b.length, viaPayload.length, reason: '载荷解析本身不该有重复');
      expect(
        b.difference(a),
        isEmpty,
        reason: '载荷路径多出来的课（脚本抠错了？）',
      );
      expect(
        a.difference(b),
        isEmpty,
        reason: '载荷路径丢掉的课（表格选错 / 少抠一格？）',
      );
      expect(b, equals(a));
    });
  });
}
