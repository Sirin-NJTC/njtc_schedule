/// DOCX（Word 2007+，.docx）正文提取。
///
/// docx 本质是个 zip，正文在 `word/document.xml`。这里只做「把文字按大致版面取出来」：
/// 段落是一行，表格行的单元格之间用制表符分隔（正好接上
/// [DocumentParser.asGrid] / [TimetableParser.parseGrid] 的表格解析）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// DOCX 读取器。
class DocxReader {
  DocxReader._();

  /// 是否是 zip（docx/xlsx/pptx 都是 PK 开头）。旧 .doc 不是。
  static bool looksLikeZip(Uint8List bytes) =>
      bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;

  /// 提取正文文字；不是合法 docx 时返回 null。
  static String? readText(Uint8List bytes) {
    if (!looksLikeZip(bytes)) return null;
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final entry = archive.findFile('word/document.xml');
      if (entry == null) return null;
      final content = entry.content;
      if (content is! List<int>) return null;
      final xmlText = utf8.decode(content, allowMalformed: true);
      final doc = XmlDocument.parse(xmlText);
      final out = StringBuffer();
      _walk(doc.rootElement, out);
      return out.toString();
    } catch (_) {
      // 加密的 docx、损坏的 zip、不是 Word 文件…… 一律当作「读不出来」
      return null;
    }
  }

  static void _walk(XmlElement element, StringBuffer out) {
    for (final child in element.childElements) {
      switch (child.name.local) {
        case 'tbl':
          _table(child, out);
        case 'p':
          _paragraph(child, out, indent: '');
        case 'tr':
        case 'tc':
          // 表格外的裸行/格（规范里不该有，容错一下）
          _walk(child, out);
        default:
          _walk(child, out);
      }
    }
  }

  /// 段落 → 一行。`w:t` 是文字，`w:tab`/`w:br` 分别当制表符和换行。
  static void _paragraph(XmlElement paragraph, StringBuffer out,
      {required String indent}) {
    final text = _paragraphText(paragraph, tabSep: '\t');
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) out.writeln('$indent$trimmed');
    }
  }

  /// 段落里的文字：`w:t` 是正文，`w:tab` 按 [tabSep] 写，`w:br`/`w:cr` 写换行。
  static String _paragraphText(XmlElement paragraph, {required String tabSep}) {
    final sb = StringBuffer();
    for (final node in paragraph.descendants) {
      if (node is! XmlElement) continue;
      switch (node.name.local) {
        case 't':
          sb.write(node.innerText);
        case 'tab':
          sb.write(tabSep);
        case 'br':
        case 'cr':
          sb.write('\n');
        default:
          break;
      }
    }
    return sb.toString();
  }

  /// 表格 → 每行单元格用制表符分隔。
  static void _table(XmlElement table, StringBuffer out) {
    for (final row in table.childElements.where((e) => e.name.local == 'tr')) {
      final cells = <String>[];
      for (final cell in row.childElements.where((e) => e.name.local == 'tc')) {
        // 格内分段用 `/` 接起来 —— 这正是 `TimetableParser.parseCell` 认的
        //「课名/周次/地点/教师/教学班」顺序。**不能用换行**：换行会被当成
        // 网格的下一行，把整行的列对齐打乱（地点/教师就落到别的星期去了）。
        final segs = <String>[];
        for (final p in cell.childElements.where((e) => e.name.local == 'p')) {
          segs.addAll(_paragraphText(p, tabSep: '/')
              .split(RegExp(r'[/\n]+'))
              .map((e) => e.replaceAll(RegExp(r'\s+'), ' ').trim())
              .where((e) => e.isNotEmpty));
        }
        cells.add(segs.join('/'));
      }
      out.writeln(cells.join('\t'));
    }
  }
}
