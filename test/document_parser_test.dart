/// 多格式导入共用的「文字层」：编码猜测、噪声规整、成表 → 课程。
///
/// 这一层是 docx / doc / pdf / 图片 OCR / txt / csv 的共同出口，
/// 所以这里把「GBK 别乱码」「全角空格与竖线当分隔符」「页码行别混进课表」钉住。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/services/document_parser.dart';

Uint8List _u(List<int> b) => Uint8List.fromList(b);

Uint8List _utf16(String s, {required bool littleEndian}) {
  final out = <int>[];
  for (final u in s.codeUnits) {
    if (littleEndian) {
      out..add(u & 0xFF)..add((u >> 8) & 0xFF);
    } else {
      out..add((u >> 8) & 0xFF)..add(u & 0xFF);
    }
  }
  return Uint8List.fromList(out);
}

void main() {
  group('DocumentParser.decodeText（编码猜测）', () {
    test('纯 UTF-8 原样解出', () {
      expect(DocumentParser.decodeText(_u(utf8.encode('高等数学Ⅰ（上）'))),
          '高等数学Ⅰ（上）');
    });

    test('UTF-8 BOM 不留在正文里', () {
      final bytes = _u([0xEF, 0xBB, 0xBF, ...utf8.encode('大学英语')]);
      expect(DocumentParser.decodeText(bytes), '大学英语');
    });

    test('UTF-16LE / UTF-16BE（带 BOM）都能解', () {
      final le = _u([0xFF, 0xFE, ..._utf16('思想道德与法治', littleEndian: true)]);
      final be = _u([0xFE, 0xFF, ..._utf16('思想道德与法治', littleEndian: false)]);
      expect(DocumentParser.decodeText(le), '思想道德与法治');
      expect(DocumentParser.decodeText(be), '思想道德与法治');
    });

    test('GBK 文本（不是合法 UTF-8）用 GBK 兜住，不是满屏乱码', () {
      // 「体育」的 GBK 编码：CC E5 D3 FD。教务系统导出的 HTML/CSV 常是 GBK。
      expect(DocumentParser.decodeText(_u([0xCC, 0xE5, 0xD3, 0xFD])), '体育');
    });

    test('空字节不炸', () {
      expect(DocumentParser.decodeText(Uint8List(0)), '');
    });
  });

  group('DocumentParser.normalize（清噪声）', () {
    test('全角空格与竖线表格线都变成分隔符', () {
      final out = DocumentParser.normalize('上午　一│高等数学Ⅰ（上）');
      expect(out, contains('上午'));
      expect(out, contains('\t'), reason: '竖线要变成制表符');
      expect(out, isNot(contains('　')), reason: '全角空格不该留着');
      expect(out, isNot(contains('│')));
    });

    test('页码行与空行丢掉，正文字数不变', () {
      final out = DocumentParser.normalize('星期一 高等数学\n\n第 2 页\n3/5\n星期二 大学英语');
      expect(out.split('\n'), ['星期一 高等数学', '星期二 大学英语']);
    });
  });

  group('DocumentParser.parse（文字 → 课程）', () {
    // 教务系统导出的「表格形」文字：制表符分列 + 星期表头 + 页脚学期信息。
    const table = '2026-2027年第1学期\t\t智26.8课表\t专业：机器人工程\n'
        '节次\t\t星期一\t星期二\n'
        '上午\t一\t高等数学Ⅰ（上）/(3-4节)7-18周/ 明德楼A103/曾玉祥/x\t\n'
        '下午\t三\t\tPython程序设计/(5-6节)7-18周/ 格致楼205/徐双/x\n'
        '注--内容顺序为：课程<>周次<>地点<>教师   本学期2026-08-31正式上课至2027-01-17结束，共20周';

    test('表格形文字走 parseGrid：课程、地点、周次、学期都对', () {
      final tt = DocumentParser.parse(table, name: 'OCR 结果');
      expect(tt.courses.length, 2);

      final math = tt.courses.firstWhere((c) => c.name.contains('高等数学'));
      expect(math.dayOfWeek, 1);
      expect(math.startSection, 3);
      expect(math.endSection, 4);
      expect(math.startWeek, 7);
      expect(math.endWeek, 18);
      expect(math.location, '明德楼A103');
      expect(math.teacher, '曾玉祥');

      final py = tt.courses.firstWhere((c) => c.name.contains('Python'));
      expect(py.dayOfWeek, 2);
      expect(py.startSection, 5);
      expect(py.location, '格致楼205');

      // 页脚的「本学期…正式上课」与「共20周」也要跟着走
      expect(tt.semester, '2026-2027年第1学期');
      expect(tt.major, '机器人工程');
      expect(tt.startDate, DateTime(2026, 8, 31));
      expect(tt.totalWeeks, 20);
      expect(tt.name, 'OCR 结果');
    });

    test('逐行文字走 parseFreeText（表格判据不够时）', () {
      final tt = DocumentParser.parse(
        '星期一 大学生心理健康教育 明德楼B309 (1-2节)1-16周\n'
        '星期四 Python程序设计 格致楼113 5-6节 1-16周',
      );
      expect(tt.courses.length, 2);
      expect(tt.courses[0].dayOfWeek, 1);
      expect(tt.courses[0].location, '明德楼B309');
      expect(tt.courses[1].dayOfWeek, 4);
      expect(tt.courses[1].startSection, 5);
    });

    test('空 / 纯噪声文字：返回空课表而不是抛异常', () {
      expect(DocumentParser.parse('').courses, isEmpty);
      expect(DocumentParser.parse('第 1 页\n2/3\n---').courses, isEmpty);
      expect(DocumentParser.parse('', name: 'x').name, 'x');
    });

    test('asGrid 判据：没表头又不够宽的时候不要瞎切', () {
      expect(DocumentParser.asGrid('星期一 高等数学'), isNull);
      expect(DocumentParser.asGrid('星期一 高等数学\n星期二 大学英语'), isNull,
          reason: '只有 2 行，凑不出表格');
      expect(DocumentParser.asGrid(table), isNotNull);
    });
  });
}
