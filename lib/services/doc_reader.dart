/// 老格式文档的文字提取：`.doc`（OLE2 复合文档 / 其实是 RTF / 其实是 HTML）、
/// `.rtf`、`.html`、`.txt`、`.csv`。
///
/// 为什么不能直接用 docx 那套：`.doc` 完全没有统一结构 —— 教务系统「导出 Word」有三种
/// 常见形态（真的 Word 97 二进制、RTF、把网页存成 .doc），所以这里按内容猜格式，
/// 每个分支都尽力把文字抠出来，抠不出来就返回 null 让上层给提示。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'document_parser.dart';

/// 旧格式文档读取器。
class DocReader {
  DocReader._();

  /// OLE2 复合文档头（Word 97-2003 .doc、Excel .xls 都是它）。
  static const List<int> ole2Magic = [
    0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1,
  ];

  static bool looksLikeOle2(Uint8List bytes) {
    if (bytes.length < ole2Magic.length) return false;
    for (var i = 0; i < ole2Magic.length; i++) {
      if (bytes[i] != ole2Magic[i]) return false;
    }
    return true;
  }

  /// RTF 一定以 `{\rtf` 开头。
  static bool looksLikeRtf(Uint8List bytes) {
    if (bytes.length < 5) return false;
    return bytes[0] == 0x7B && // {
        bytes[1] == 0x5C && // \
        bytes[2] == 0x72 && // r
        bytes[3] == 0x74 && // t
        bytes[4] == 0x66; // f
  }

  /// 头部 4KB 里有 html/table 标记就当作网页。
  static bool looksLikeHtml(Uint8List bytes) {
    final head = DocumentParser.decodeText(
      bytes.sublist(0, math.min(4096, bytes.length)),
    ).toLowerCase();
    return head.contains('<html') ||
        head.contains('<!doctype html') ||
        head.contains('<table') ||
        head.contains('<meta charset');
  }

  /// 统一入口：按内容猜格式并提取文字；实在没有文字时返回 null。
  static String? readText(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    if (looksLikeRtf(bytes)) return _blankToNull(rtfToText(bytes));
    if (looksLikeOle2(bytes)) return _blankToNull(ole2ToText(bytes));
    if (looksLikeHtml(bytes)) {
      return _blankToNull(htmlToText(DocumentParser.decodeText(bytes)));
    }
    return _blankToNull(
      DocumentParser.normalize(DocumentParser.decodeText(bytes)),
    );
  }

  static String? _blankToNull(String text) =>
      text.trim().isEmpty ? null : text;

  // ------------------------------------------------------------------ HTML

  /// HTML → 文字：`</td>` 变制表符、`</tr>`/`</p>`/`<br>` 变换行，其余标签丢掉。
  static String htmlToText(String html) {
    var s = html
        .replaceAll(
          RegExp(r'<(script|style|head)\b.*?</\1>',
              dotAll: true, caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</t[dh]>', caseSensitive: false), '\t')
        .replaceAll(
          RegExp(r'</(p|div|tr|li|h[1-6]|table)>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]*>'), '');
    return DocumentParser.normalize(_unescapeHtml(s));
  }

  static String _unescapeHtml(String s) {
    var out = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
    // 数字实体 &#123; / &#x1F600;
    out = out.replaceAllMapped(RegExp(r'&#(x?[0-9A-Fa-f]+);'), (m) {
      final raw = m.group(1)!;
      final code = raw.startsWith('x') || raw.startsWith('X')
          ? int.tryParse(raw.substring(1), radix: 16)
          : int.tryParse(raw);
      if (code == null || code <= 0 || code > 0x10FFFF) return '';
      return String.fromCharCode(code);
    });
    return out;
  }

  // ------------------------------------------------------------------- RTF

  /// 整组跳过的目的地：字体表、颜色表、样式表、文档信息、生成器……
  static const Set<String> _skipGroups = {
    'fonttbl',
    'colortbl',
    'stylesheet',
    'info',
    'pict',
    'object',
    'generator',
    'listtable',
    'listoverridetable',
    'rsidtbl',
    'themedata',
    'datastore',
    'latentstyles',
    'xmlnstbl',
    'filetbl',
  };

  /// RTF → 文字。`\'hh` 按 GBK 解（中文 RTF 都是这么存的），`\uNNNN` 直接取码点。
  static String rtfToText(Uint8List bytes) {
    final out = StringBuffer();
    final pending = <int>[];
    final saved = <bool>[];
    var skipping = false;

    void flush() {
      if (pending.isEmpty) return;
      out.write(DocumentParser.decodeText(Uint8List.fromList(pending)));
      pending.clear();
    }

    var i = 0;
    while (i < bytes.length) {
      final c = bytes[i];

      if (c == 0x7B) {
        // { 组开始：看看这一组是不是要整组跳过
        saved.add(skipping);
        i++;
        var j = i;
        var star = false;
        if (j < bytes.length && bytes[j] == 0x5C) {
          j++;
          if (j < bytes.length && bytes[j] == 0x2A) {
            star = true;
            j++;
          }
          final start = j;
          while (j < bytes.length && _isAlpha(bytes[j])) {
            j++;
          }
          final word = String.fromCharCodes(bytes.sublist(start, j));
          if (star || _skipGroups.contains(word)) skipping = true;
        }
        continue;
      }

      if (c == 0x7D) {
        // }
        flush();
        if (saved.isNotEmpty) skipping = saved.removeLast();
        i++;
        continue;
      }

      if (skipping) {
        i++;
        continue;
      }

      if (c == 0x5C) {
        // 反斜杠 → 控制字 / 转义
        i++;
        if (i >= bytes.length) break;
        final n = bytes[i];
        if (n == 0x27) {
          // \'hh：一个字节，中文 RTF 里是 GBK 的一半
          final hex = String.fromCharCodes(
            bytes.sublist(i + 1, math.min(i + 3, bytes.length)),
          );
          final v = int.tryParse(hex, radix: 16);
          if (v != null) pending.add(v);
          i += 3;
          continue;
        }
        if (!_isAlpha(n)) {
          if (n == 0x7E) {
            // \~ 不换行空格
            flush();
            out.write(' ');
          }
          i++;
          continue;
        }
        final start = i;
        while (i < bytes.length && _isAlpha(bytes[i])) {
          i++;
        }
        final word = String.fromCharCodes(bytes.sublist(start, i));
        var sign = 1;
        var num = 0;
        var hasNum = false;
        if (i < bytes.length && bytes[i] == 0x2D) {
          sign = -1;
          i++;
        }
        while (i < bytes.length && bytes[i] >= 0x30 && bytes[i] <= 0x39) {
          num = num * 10 + (bytes[i] - 0x30);
          hasNum = true;
          i++;
        }
        // 控制字后面那个空格是分隔符，不算正文
        if (i < bytes.length && bytes[i] == 0x20) i++;
        switch (word) {
          case 'par':
          case 'line':
          case 'sect':
          case 'page':
          case 'row':
            flush();
            out.write('\n');
          case 'tab':
          case 'cell':
            flush();
            out.write('\t');
          case 'u':
            if (hasNum) {
              var cp = sign * num;
              if (cp < 0) cp += 65536;
              flush();
              out.writeCharCode(cp);
              // \uNNNN 后面那个 ? 是给老版本 Word 的替代字符，跳过
              if (i < bytes.length && bytes[i] == 0x3F) i++;
            }
          default:
            break;
        }
        continue;
      }

      if (c == 0x0D || c == 0x0A) {
        i++;
        continue;
      }

      pending.add(c);
      i++;
    }
    flush();
    return DocumentParser.normalize(out.toString());
  }

  // ------------------------------------------------------------------ OLE2

  /// Word 97 二进制 .doc → 文字（启发式）。
  ///
  /// 不去解析 FAT 表/WordDocument 流（那要写半个 .doc 解析器），而是在整个文件里找
  /// **成串的 UTF-16LE 文本**（Word 存中文正文就是 UTF-16LE），按奇偶两种对齐各扫一遍，
  /// 取中文更多的那个。宁可粗糙也别让用户卡在「不支持的文件格式」上 —— 结果不理想时
  /// 界面会建议改用「另存为 .docx」或直接截图 OCR。
  static String ole2ToText(Uint8List bytes) {
    final a = _scanUtf16(bytes, 0);
    final b = _scanUtf16(bytes, 1);
    return (b.cjk > a.cjk ? b : a).text;
  }

  static ({String text, int cjk}) _scanUtf16(Uint8List bytes, int offset) {
    final out = StringBuffer();
    final run = <int>[];
    var cjk = 0;

    void flush() {
      if (run.length >= 4) {
        out.write(String.fromCharCodes(run));
        out.write('\n');
      }
      run.clear();
    }

    for (var i = offset; i + 1 < bytes.length; i += 2) {
      final cp = bytes[i] | (bytes[i + 1] << 8);
      if (_isPlausibleChar(cp)) {
        run.add(cp);
        if (cp >= 0x4E00 && cp <= 0x9FFF) cjk++;
      } else {
        flush();
      }
    }
    flush();
    return (text: DocumentParser.normalize(out.toString()), cjk: cjk);
  }

  static bool _isPlausibleChar(int cp) {
    if (cp == 0x09) return true;
    if (cp >= 0x20 && cp <= 0x7E) return true; // ASCII 可见
    if (cp >= 0x4E00 && cp <= 0x9FFF) return true; // 中日韩汉字
    if (cp >= 0x3000 && cp <= 0x303F) return true; // 中文标点
    if (cp >= 0xFF00 && cp <= 0xFFEF) return true; // 全角
    if (cp >= 0x2010 && cp <= 0x203B) return true; // — – ‘ ’ “ ” …
    if (cp == 0x00B7 || cp == 0x2022 || cp == 0x00A0) return true;
    return false;
  }

  static bool _isAlpha(int b) =>
      (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A);
}
