/// `XlsReader` 的单元测试。
///
/// 用**合成的 .xls 固件**（`test/fixtures/sample_timetable.xls`）作为样例：
/// 它的结构、字段顺序、合并单元格读出来的样子都和真实教务系统导出的
/// .xls（OLE2 / BIFF8）一致，但课程 / 教师 / 教室全是虚构的
/// （`示例课程甲` / `示例老师A` / `格致楼201`），可以放心放在公开仓库里。
/// 固件由 `tool/make_xls_fixture.py` 生成（依赖 `xlwt`）。
///
/// 说明：`excel` 包只支持 .xlsx（zip + XML），读不了教务系统这种老式
/// .xls（OLE2 / BIFF8），所以 `lib/services/xls_reader.dart` 里自己实现了读取。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/services/timetable_parser.dart';
import 'package:njtc_schedule/services/xls_reader.dart';

void main() {
  group('XlsReader 文件类型识别', () {
    test('OLE2 头（老式 .xls）应被识别', () {
      final ole = Uint8List.fromList(
          [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
      expect(XlsReader.looksLikeXls(ole), true);
    });

    test('zip 头（.xlsx）不应被误认为 .xls', () {
      // .xlsx 是 zip 容器，头为 PK\x03\x04
      final zip = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0]);
      expect(XlsReader.looksLikeXls(zip), false);
    });

    test('过短的数据不应抛异常', () {
      expect(XlsReader.looksLikeXls(Uint8List.fromList([0xD0, 0xCF])), false);
      expect(XlsReader.readFirstSheet(Uint8List.fromList([1, 2, 3])), null);
    });
  });

  group('XlsReader 读取课表固件', () {
    final file = File('test/fixtures/sample_timetable.xls');

    test('读出完整的 8×9 网格', () {
      if (!file.existsSync()) {
        markTestSkipped('缺少样例文件 ${file.path}');
        return;
      }
      final grid = XlsReader.readFirstSheet(
          Uint8List.fromList(file.readAsBytesSync()));

      expect(grid, isNotNull);
      expect(grid!.length, 8, reason: '固件共 8 行');
      expect(grid.first.length, 9, reason: '固件共 9 列');

      // 表头
      expect(grid[0][0], '2026-2027年第1学期');
      expect(grid[0][7], '专业：示例工程');
      expect(grid[1][0], '节次');
      expect(grid[1][2], '星期一');
      expect(grid[1][8], '星期日');

      // 时段列
      expect(grid[2][0], '上午');
      expect(grid[2][1], '一');
      expect(grid[6][0], '晚上');
      expect(grid[6][1], '五');

      // 页脚
      expect(grid[7][0].startsWith('注--'), true);

      // 单元格内容：完整保留了 课程/(节次)周次/ 地点/教师/课程代码/教学班 各字段
      final cell = grid[2][2];
      expect(cell.contains('示例课程甲'), true);
      expect(cell.contains('(1-2节)7-18周'), true);
      expect(cell.contains('格致楼201'), true);
      expect(cell.contains('AA0000001-01'), true);

      // 一格多课：单元格内用 \r\n 分隔
      expect(grid[4][3].contains('\r\n'), true, reason: '周二 5-6 节有单双周两门课');
      expect(grid[5][5].split('\r\n').length, 3, reason: '周四 7-8 节连排三门课');
    });

    test('端到端：.xls → 课表 20 门课', () {
      if (!file.existsSync()) {
        markTestSkipped('缺少样例文件 ${file.path}');
        return;
      }
      final grid = XlsReader.readFirstSheet(
          Uint8List.fromList(file.readAsBytesSync()));
      expect(grid, isNotNull);

      final tt = TimetableParser.parseGrid(grid!);
      expect(tt.semester, '2026-2027年第1学期');
      expect(tt.major, '示例工程');
      expect(tt.courses.length, 20);

      final days = tt.courses.map((c) => c.dayOfWeek).toSet().toList()..sort();
      expect(days, [1, 2, 3, 4, 5], reason: '只有周一到周五有课');

      // 不得出现「周次退化为默认 1-20」的解析失败特征
      expect(tt.courses.every((c) => c.startWeek == 1 && c.endWeek == 20), false);
    });
  });
}
