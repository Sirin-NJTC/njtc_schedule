/// 老格式（`.doc` / `.rtf` / `.html`）的文字提取 —— 教务系统「导出 Word / 导出网页」
/// 那三种常见形态：真 Word 97 二进制、RTF、把网页存成 .doc。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/services/doc_reader.dart';
import 'package:njtc_schedule/services/document_parser.dart';

Uint8List _u(List<int> b) => Uint8List.fromList(b);

/// UTF-16LE 编码（Word 正文在二进制 .doc 里就是这么存的）。
List<int> _utf16le(String s) {
  final out = <int>[];
  for (final u in s.codeUnits) {
    out..add(u & 0xFF)..add((u >> 8) & 0xFF);
  }
  return out;
}

void main() {
  group('格式嗅探', () {
    test('OLE2 复合文档头（Word 97 二进制 / Excel .xls 共用）', () {
      expect(
        DocReader.looksLikeOle2(_u([
          0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
          0x00, 0x01, 0x02,
        ])),
        isTrue,
      );
      expect(DocReader.looksLikeOle2(_u(utf8.encode('{\\rtf1'))), isFalse);
      expect(DocReader.looksLikeOle2(Uint8List(3)), isFalse);
    });

    test('RTF 一定以 {\\rtf 开头', () {
      expect(DocReader.looksLikeRtf(_u(utf8.encode('{\\rtf1\\ansi x}'))), isTrue);
      expect(DocReader.looksLikeRtf(_u(utf8.encode('<html>'))), isFalse);
      expect(DocReader.looksLikeRtf(_u(utf8.encode('{\\r'))), isFalse);
    });

    test('头部 4KB 有 html/table 标记就算网页', () {
      expect(DocReader.looksLikeHtml(_u(utf8.encode('<html><body>x'))), isTrue);
      expect(DocReader.looksLikeHtml(_u(utf8.encode('<TABLE><TR>'))), isTrue);
      expect(DocReader.looksLikeHtml(_u(utf8.encode('星期一 高等数学'))), isFalse);
    });
  });

  group('RTF', () {
    test('\\uNNNN 转义（新版 Word）解出中文并解析成课', () {
      // 「星期一 高等数学 明德楼A103 (3-4节)7-18周」，中文用 \uNNNN 写
      const rtf = '{\\rtf1\\ansi\\ansicpg936 '
          '\\u26143?\\u26399?\\u19968? '
          '\\u39640?\\u31561?\\u25968?\\u23398? '
          '\\u26126?\\u24503?\\u27004?A103 (3-4节)7-18周\\par}';
      final text = DocReader.readText(_u(utf8.encode(rtf)));
      expect(text, isNotNull);
      expect(text!, contains('星期一'));
      expect(text, contains('高等数学'));

      final tt = DocumentParser.parse(text);
      expect(tt.courses, isNotEmpty);
      final c = tt.courses.first;
      expect(c.name, '高等数学');
      expect(c.dayOfWeek, 1);
      expect(c.location, '明德楼A103');
      expect(c.startSection, 3);
      expect(c.endSection, 4);
      expect(c.startWeek, 7);
      expect(c.endWeek, 18);
    });

    test('\\\'hh 字节按 GBK 解（老 Word 存中文的方式）', () {
      // 星=D0C7 期=C6DA 一=D2BB，整段只有 GBK 字节，没有混进 UTF-8 汉字
      const rtf = '{\\rtf1\\ansi\\ansicpg936 \\\'d0\\\'c7\\\'c6\\\'da\\\'d2\\\'bb\\par}';
      final text = DocReader.readText(_u(utf8.encode(rtf)));
      expect(text, '星期一');
    });

    test('字体表 / 颜色表 / 图片组整组跳过，不把垃圾混进课表', () {
      const rtf = '{\\rtf1\\ansi'
          '{\\fonttbl{\\f0\\fnil\\fcharset134 SimSun;}}'
          '{\\colortbl;\\red0\\green0\\blue0;}'
          '{\\*\\generator Riched20 10.0.19041;}'
          '星期一 大学英语 明德楼B309 (1-2节)1-16周\\par}';
      final text = DocReader.readText(_u(utf8.encode(rtf)))!;
      expect(text, contains('大学英语'));
      expect(text, isNot(contains('SimSun')));
      expect(text, isNot(contains('Riched20')));
      expect(text, isNot(contains('colortbl')));
    });
  });

  group('HTML', () {
    test('表格标签变成制表符 / 换行，实体还原', () {
      const html = '<html><head><style>td{color:red}</style></head><body>'
          '<table>'
          '<tr><td>节次</td><td>星期一</td><td>星期二</td></tr>'
          '<tr><td>上午一</td><td>高等数学Ⅰ（上）/(3-4节)7-18周/ 明德楼A103/曾玉祥</td><td></td></tr>'
          '<tr><td>下午三</td><td></td><td>Python程序设计/(5-6节)7-18周/ 格致楼205/徐双</td></tr>'
          '<tr><td>说明</td><td>课程&amp;地点&nbsp;以教务系统为准</td></tr>'
          '</table></body></html>';
      final text = DocReader.readText(_u(utf8.encode(html)))!;
      expect(text, isNot(contains('color:red')), reason: '<style> 要整段丢掉');
      expect(text, isNot(contains('<td>')));
      expect(text, contains('课程&地点 以教务系统为准'));

      final tt = DocumentParser.parse(text);
      expect(tt.courses.any((c) => c.name.contains('高等数学') && c.dayOfWeek == 1),
          isTrue);
      expect(tt.courses.any((c) => c.name.contains('Python') && c.dayOfWeek == 2),
          isTrue);
    });
  });

  group('OLE2（Word 97 二进制）', () {
    test('从二进制里扫出 UTF-16LE 正文并解析成课', () {
      // 真 .doc 的 FAT/流结构这里不还原，只把「OLE2 头 + UTF-16LE 正文」拼出来，
      // 验证启发式扫描这条兜底路真的能捞到字。段落之间的 \r（UTF-16LE 里
      // 是 0D 00）是 Word 的换段符，扫描时靠它把两门课切成两行。
      final bytes = _u([
        0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
        ..._utf16le('星期一 高等数学 明德楼A103 (3-4节)7-18周'),
        ..._utf16le('\r'),
        ..._utf16le('星期二 Python程序设计 格致楼205 (5-6节)7-18周'),
        ..._utf16le('\r'),
      ]);
      expect(DocReader.looksLikeOle2(bytes), isTrue);

      final text = DocReader.readText(bytes)!;
      expect(text, contains('星期一'));
      expect(text, contains('高等数学'));
      expect(text, contains('Python程序设计'));

      final tt = DocumentParser.parse(text);
      expect(tt.courses.length, 2);
      expect(tt.courses[0].dayOfWeek, 1);
      expect(tt.courses[0].location, '明德楼A103');
      expect(tt.courses[1].name, 'Python程序设计');
      expect(tt.courses[1].dayOfWeek, 2);
    });

    test('二进制里捞不出字时返回 null（让界面提示换格式）', () {
      final bytes = _u([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
      expect(DocReader.readText(bytes), isNull);
    });
  });

  group('纯文本 / CSV', () {
    test('UTF-8 文本原样收下', () {
      final text = DocReader.readText(
        _u(utf8.encode('星期一 大学生心理健康教育 明德楼B309 (1-2节)1-16周')),
      );
      expect(text, '星期一 大学生心理健康教育 明德楼B309 (1-2节)1-16周');
    });

    test('GBK 文本不乱码', () {
      // 「星期一」的 GBK：D0C7 C6DA D2BB
      final text = DocReader.readText(_u([0xD0, 0xC7, 0xC6, 0xDA, 0xD2, 0xBB]));
      expect(text, '星期一');
    });

    test('空字节返回 null', () {
      expect(DocReader.readText(Uint8List(0)), isNull);
      expect(DocReader.readText(_u(utf8.encode('   \n  '))), isNull);
    });
  });
}
