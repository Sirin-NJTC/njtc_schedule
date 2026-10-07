/// `.docx` 读取：把 zip 里的 `word/document.xml` 抠成「制表符表格 + 换行」的文字。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/services/document_parser.dart';
import 'package:njtc_schedule/services/docx_reader.dart';

/// 攒一个最小可用的 docx（其实只要 zip 里有 `word/document.xml` 就够了）。
Uint8List _docx(String body) {
  const head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>';
  const tail = '</w:body></w:document>';
  final data = utf8.encode('$head$body$tail');
  final archive = Archive()
    ..addFile(ArchiveFile('word/document.xml', data.length, data));
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

/// 课表文档的正文：两行说明 + 一张「节次 × 星期」表。
const String _body = '<w:p><w:r><w:t>2026-2027年第1学期</w:t></w:r></w:p>'
    '<w:p><w:r><w:t>专业：机器人工程</w:t></w:r></w:p>'
    '<w:tbl>'
    '<w:tr>'
    '<w:tc><w:p><w:r><w:t>节次</w:t></w:r></w:p></w:tc>'
    '<w:tc><w:p><w:r><w:t>星期一</w:t></w:r></w:p></w:tc>'
    '<w:tc><w:p><w:r><w:t>星期二</w:t></w:r></w:p></w:tc>'
    '</w:tr>'
    '<w:tr>'
    '<w:tc><w:p><w:r><w:t>上午一</w:t></w:r></w:p></w:tc>'
    '<w:tc><w:p><w:r><w:t>高等数学Ⅰ（上）/(3-4节)7-18周</w:t><w:tab/>'
    '<w:t>明德楼A103</w:t><w:tab/><w:t>曾玉祥</w:t></w:r></w:p></w:tc>'
    '<w:tc><w:p/></w:tc>'
    '</w:tr>'
    '<w:tr>'
    '<w:tc><w:p><w:r><w:t>下午三</w:t></w:r></w:p></w:tc>'
    '<w:tc><w:p/></w:tc>'
    '<w:tc><w:p><w:r><w:t>Python程序设计/(5-6节)7-18周/ 格致楼205/徐双</w:t></w:r></w:p></w:tc>'
    '</w:tr>'
    '</w:tbl>';

void main() {
  test('looksLikeZip 只认 PK 头', () {
    expect(DocxReader.looksLikeZip(_docx(_body)), isTrue);
    expect(DocxReader.looksLikeZip(Uint8List.fromList(utf8.encode('星期一'))),
        isFalse);
    expect(DocxReader.looksLikeZip(Uint8List(0)), isFalse);
  });

  test('表格被抠成制表符分列的文本', () {
    final text = DocxReader.readText(_docx(_body));
    expect(text, isNotNull);
    final lines = text!.split('\n');
    expect(lines[0], '2026-2027年第1学期');
    expect(lines[1], '专业：机器人工程');
    expect(lines[2].split('\t'), ['节次', '星期一', '星期二']);
    // 单元格里的 w:tab 也要变成制表符，否则课程名/地点/老师会粘成一坨
    expect(lines[3].split('\t').first, '上午一');
    expect(lines[3], contains('高等数学Ⅰ（上）'));
    expect(lines[3], contains('明德楼A103'));
    expect(lines[4], contains('Python程序设计'));
  });

  test('抠出来的文字能直接解析成课程（docx → 课表 一条龙）', () {
    final tt = DocumentParser.parse(DocxReader.readText(_docx(_body))!,
        name: 'docx 导入');
    expect(tt.courses.length, 2);
    final math = tt.courses.firstWhere((c) => c.name.contains('高等数学'));
    expect(math.dayOfWeek, 1);
    expect(math.startSection, 3);
    expect(math.endSection, 4);
    expect(math.location, '明德楼A103');
    expect(math.teacher, '曾玉祥');
    expect(tt.courses.any((c) => c.name.contains('Python') && c.dayOfWeek == 2),
        isTrue);
    expect(tt.semester, '2026-2027年第1学期');
    expect(tt.major, '机器人工程');
    expect(tt.totalWeeks, 20);
  });

  test('w:br / w:cr 变换行，段落换行不丢', () {
    final bytes = _docx(
      '<w:p><w:r><w:t>星期一</w:t><w:br/><w:t>高等数学</w:t><w:cr/>'
      '<w:t>明德楼A103</w:t></w:r></w:p>',
    );
    final text = DocxReader.readText(bytes);
    expect(text!.trim().split('\n'), ['星期一', '高等数学', '明德楼A103']);
  });

  test('zip 里没有 word/document.xml（或不是 zip）→ null，交给上层给提示', () {
    final archive = Archive()
      ..addFile(ArchiveFile('readme.txt', 3, utf8.encode('abc')));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
    expect(DocxReader.readText(bytes), isNull);
    expect(DocxReader.readText(Uint8List.fromList(utf8.encode('不是 zip'))), isNull);
    expect(DocxReader.readText(Uint8List(0)), isNull);
  });
}
