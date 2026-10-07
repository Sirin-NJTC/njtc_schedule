/// 文档 / 图片识别出的「文字」→ 课表。
///
/// 所有非 Excel 的导入方式（docx、doc、PDF、图片 OCR、txt/csv）最后都汇到这里：
/// 先按行列对齐的表格试一次 [TimetableParser.parseGrid]，不行再退回逐行自由文本
/// [TimetableParser.parseFreeText]。这样新增格式不用各写一套解析。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';

import '../models/timetable.dart';
import 'timetable_parser.dart';

/// 把任意文档文字解析成课表。
class DocumentParser {
  DocumentParser._();

  /// 字节 → 文字。先按 UTF-8 严格解（解不动就说明不是 UTF-8），再退 GBK。
  ///
  /// 教务系统导出的 HTML/RTF/CSV 在 Windows 上多半是 GBK 编码，直接当 UTF-8 解会满屏乱码。
  static String decodeText(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    // UTF-8 BOM
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    // UTF-16 BOM（老 Word 另存的 txt 可能是这个）
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: false);
    }
    try {
      final text = utf8.decode(bytes); // 严格模式：GBK 文本基本一定会抛
      if (!text.contains('\uFFFD')) return text;
    } on FormatException {
      // 落到 GBK
    }
    return const GbkCodec(allowInvalid: true).decode(bytes);
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  /// 识别出来的文字 → 课表。
  static Timetable parse(String rawText, {String name = ''}) {
    final text = normalize(rawText);
    if (text.trim().isEmpty) {
      return Timetable(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name.isEmpty ? '导入课表' : name,
        courses: const [],
      );
    }
    final grid = asGrid(text);
    if (grid != null) {
      final t = TimetableParser.parseGrid(grid, name: name);
      if (t.courses.isNotEmpty) return t;
    }
    return TimetableParser.parseFreeText(text, name: name);
  }

  /// 清掉 OCR / 文档里常见的噪声，让后面的解析器好干活：
  /// 全角空格、竖线表格线、成串的点、多余空行、页眉页脚残留的页码。
  static String normalize(String text) {
    var s = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u00A0', ' ') // 不换行空格
        .replaceAll('　', ' ') // 全角空格
        .replaceAll(RegExp(r'[│┃┆┇╎╏|]'), '\t') // 表格竖线当列分隔
        .replaceAll(RegExp(r'[─━═]+'), ' ') // 横线
        .replaceAll(RegExp(r'\.{3,}|·{3,}'), ' '); // 目录点线
    final lines = s
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'[ \t]+$'), ''))
        .where((l) => l.trim().isNotEmpty)
        .where((l) => !RegExp(r'^\s*(第\s*\d+\s*页|\d+\s*/\s*\d+)\s*$').hasMatch(l))
        .toList();
    return lines.join('\n');
  }

  /// 如果整段文字看着是「行列对齐的表格」，切成二维表；否则返回 null。
  ///
  /// 判据：出现「星期X」表头，或者多数行都能切出 3 列以上。
  static List<List<String>>? asGrid(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length < 4) return null;
    final splitter = RegExp(r'\t| {2,}');
    final rows = lines
        .map((l) => l.split(splitter).map((c) => c.trim()).toList())
        .toList();
    final hasHeader =
        lines.any((l) => RegExp(r'星期[一二三四五六日天]').hasMatch(l));
    final wide = rows.where((r) => r.length >= 3).length;
    if (!hasHeader && wide < rows.length * 0.6) return null;
    return rows;
  }
}
