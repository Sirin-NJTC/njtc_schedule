import 'dart:typed_data';

/// 极简 `.xls`（BIFF8 / OLE2 复合文档）读取器 —— 纯 Dart，零第三方依赖。
///
/// **为什么需要它**：内江师范学院教务系统导出的课程表是**老式 `.xls`（BIFF8）**
/// 文件（OLE2 复合文档，文件头 `D0 CF 11 E0 A1 B1 1A E1`），而 Dart 生态里
/// 常用的 `excel` 包只支持 `.xlsx`（本质是 zip + XML 容器），遇到 `.xls`
/// 会直接解析失败。为了让同学「下载下来的文件直接就能导入」，这里自己实现了
/// 读取 `.xls` 所需的最小功能集。
///
/// 已实现范围（够用即止，不做完整 Excel 复刻）：
/// * OLE2 容器：FAT / MiniFAT / 目录项，定位并读出 `Workbook` 流
/// * BIFF8 记录：`BOF` / `BOUNDSHEET` / `SST` / `LABELSST` / `LABEL` /
///   `RK` / `NUMBER` / `MULRK` / `BLANK` / `MULBLANK`
/// * SST 共享字符串表（含 `CONTINUE` 跨记录续接与压缩/非压缩混排）
///
/// 未实现：公式计算、单元格格式/日期序号转换、多工作表合并（只取第一个工作表）。
class XlsReader {
  XlsReader._();

  // ── BIFF 记录类型 ──
  static const int _bof = 0x0809;
  static const int _eof = 0x000A;
  static const int _boundSheet = 0x0085;
  static const int _sst = 0x00FC;
  static const int _continue = 0x003C;
  static const int _labelSst = 0x00FD;
  static const int _label = 0x0204;
  static const int _rk = 0x027E;
  static const int _number = 0x0203;
  static const int _mulRk = 0x00BD;
  static const int _formula = 0x0006;
  static const int _string = 0x0207;

  /// 判断字节流是否为 OLE2 复合文档（即老式 `.xls`）。
  ///
  /// 有些 `.xls` 其实是 `.xlsx` 改了后缀，需要用这个来区分走哪条解析路径。
  static bool looksLikeXls(Uint8List bytes) {
    if (bytes.length < 8) return false;
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != _oleSignature[i]) return false;
    }
    return true;
  }

  /// 读取第一个工作表的全部单元格，返回二维字符串网格。
  ///
  /// 失败（非 OLE2、找不到 Workbook 流、非 BIFF8 等）时返回 `null`，
  /// 调用方应回退到其它导入方式。
  static List<List<String>>? readFirstSheet(Uint8List bytes) {
    final stream = _extractWorkbookStream(bytes);
    if (stream == null) return null;

    final records = _parseRecords(stream);
    if (records.isEmpty) return null;

    // ── 第一遍：全局子流（SST 共享字符串 + 各工作表位置）──
    List<String> sst = const <String>[];
    int? firstSheetOffset;
    var inGlobals = false;
    var sawBof = false;

    for (final rec in records) {
      if (rec.type == _bof) {
        final dt = rec.data.length >= 4
            ? (rec.data[2] | (rec.data[3] << 8))
            : 0;
        if (dt == 0x0005) {
          inGlobals = true;
          sawBof = true;
          continue;
        }
        // 走到第一个工作表子流，全局子流结束
        break;
      }
      if (!inGlobals) {
        // 容错：有些文件没有明确 BOF 标记
        if (rec.type == _sst || rec.type == _boundSheet) sawBof = true;
        if (!sawBof) continue;
      }
      if (rec.type == _sst) {
        sst = _parseSst(records, records.indexOf(rec));
      } else if (rec.type == _boundSheet && firstSheetOffset == null) {
        if (rec.data.length >= 4) {
          firstSheetOffset = _u32(rec.data, 0);
        }
      }
    }

    if (firstSheetOffset == null) return null;

    // ── 第二遍：定位第一个工作表子流并读取单元格 ──
    var startIdx = -1;
    for (var i = 0; i < records.length; i++) {
      if (records[i].offset == firstSheetOffset && records[i].type == _bof) {
        startIdx = i;
        break;
      }
    }
    if (startIdx < 0) {
      // 容错：偏移对不上时，退而使用「第一个非全局 BOF」
      for (var i = 0; i < records.length; i++) {
        if (records[i].type == _bof && i > 0) {
          final dt = records[i].data.length >= 4
              ? (records[i].data[2] | (records[i].data[3] << 8))
              : 0;
          if (dt != 0x0005) {
            startIdx = i;
            break;
          }
        }
      }
    }
    if (startIdx < 0) return null;

    // 收集单元格：(row, col) -> 文本
    final cells = <int, Map<int, String>>{};
    var maxRow = -1;
    var maxCol = -1;
    var pendingFormulaCell = <int>[0, 0]; // 公式结果（STRING 记录）

    void put(int row, int col, String value) {
      if (row < 0 || col < 0) return;
      (cells[row] ??= <int, String>{})[col] = value;
      if (row > maxRow) maxRow = row;
      if (col > maxCol) maxCol = col;
    }

    for (var i = startIdx; i < records.length; i++) {
      final rec = records[i];
      if (rec.type == _eof && i > startIdx) break;

      switch (rec.type) {
        case _labelSst:
          if (rec.data.length >= 10) {
            final row = _u16(rec.data, 0);
            final col = _u16(rec.data, 2);
            final idx = _u32(rec.data, 6);
            put(row, col, idx < sst.length ? sst[idx] : '');
          }
          break;

        case _label: // BIFF8: row(2) col(2) ixfe(2) XLUnicodeString
          if (rec.data.length >= 6) {
            final row = _u16(rec.data, 0);
            final col = _u16(rec.data, 2);
            final text = _readBiff8String(rec.data, 6);
            put(row, col, text.value);
          }
          break;

        case _rk:
          if (rec.data.length >= 10) {
            final row = _u16(rec.data, 0);
            final col = _u16(rec.data, 2);
            put(row, col, _formatNumber(_rkToDouble(_u32(rec.data, 6))));
          }
          break;

        case _number:
          if (rec.data.length >= 14) {
            final row = _u16(rec.data, 0);
            final col = _u16(rec.data, 2);
            final bd = ByteData.sublistView(rec.data);
            put(row, col, _formatNumber(bd.getFloat64(6, Endian.little)));
          }
          break;

        case _mulRk:
          if (rec.data.length >= 6) {
            final row = _u16(rec.data, 0);
            final colFirst = _u16(rec.data, 2);
            final n = (rec.data.length - 6) ~/ 6;
            for (var k = 0; k < n; k++) {
              final o = 4 + k * 6 + 2; // 跳过 ixfe
              put(row, colFirst + k,
                  _formatNumber(_rkToDouble(_u32(rec.data, o))));
            }
          }
          break;

        case _formula:
          if (rec.data.length >= 14) {
            pendingFormulaCell = [_u16(rec.data, 0), _u16(rec.data, 2)];
            // 公式的字符串结果随后由 STRING 记录给出；
            // 数值结果直接取缓存值（偏移 6 处的 double）。
            final bd = ByteData.sublistView(rec.data);
            final v = bd.getFloat64(6, Endian.little);
            if (v == v && v.abs() < 1e300) {
              put(pendingFormulaCell[0], pendingFormulaCell[1],
                  _formatNumber(v));
            }
          }
          break;

        case _string:
          // 紧跟在 FORMULA 之后的字符串结果
          final text = _readBiff8String(rec.data, 0);
          put(pendingFormulaCell[0], pendingFormulaCell[1], text.value);
          break;

        // BLANK / MULBLANK：显式空单元格，保留为空串，扩展网格范围即可
        case 0x0201:
          if (rec.data.length >= 6) {
            put(_u16(rec.data, 0), _u16(rec.data, 2), '');
          }
          break;

        case 0x00BE:
          if (rec.data.length >= 6) {
            final row = _u16(rec.data, 0);
            final colFirst = _u16(rec.data, 2);
            final colLast = _u16(rec.data, rec.data.length - 2);
            for (var c = colFirst; c <= colLast; c++) {
              put(row, c, '');
            }
          }
          break;
      }
    }

    if (maxRow < 0 || maxCol < 0) {
      return <List<String>>[];
    }

    // 补齐为矩形网格
    return List<List<String>>.generate(
      maxRow + 1,
      (r) => List<String>.generate(
        maxCol + 1,
        (c) => cells[r]?[c] ?? '',
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  //  OLE2 复合文档
  // ══════════════════════════════════════════════════════

  /// 从 OLE2 容器中取出 `Workbook`（或旧名 `Book`）流的字节。
  static Uint8List? _extractWorkbookStream(Uint8List bytes) {
    if (bytes.length < 512) return null;
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != _oleSignature[i]) return null;
    }

    final bd = ByteData.sublistView(bytes);
    final sectorShift = bd.getUint16(0x1E, Endian.little);
    final miniSectorShift = bd.getUint16(0x20, Endian.little);
    if (sectorShift < 7 || sectorShift > 20) return null;

    final sectorSize = 1 << sectorShift;
    final miniSectorSize = 1 << miniSectorShift;
    final numFatSectors = bd.getUint32(0x2C, Endian.little);
    final firstDirSector = bd.getUint32(0x30, Endian.little);
    final miniCutoff = bd.getUint32(0x38, Endian.little);
    final firstMiniFatSector = bd.getUint32(0x3C, Endian.little);
    final firstDifatSector = bd.getUint32(0x44, Endian.little);
    final numDifatSectors = bd.getUint32(0x48, Endian.little);

    // ── DIFAT → FAT 扇区号列表 ──
    final difat = <int>[];
    for (var i = 0; i < 109; i++) {
      final s = bd.getUint32(0x4C + i * 4, Endian.little);
      if (s >= 0xFFFFFFFA) break;
      difat.add(s);
    }
    var nextDifat = firstDifatSector;
    var guard = 0;
    while (nextDifat < 0xFFFFFFFA &&
        nextDifat != 0 &&
        guard++ < numDifatSectors + 16) {
      final off = _sectorOffset(nextDifat, sectorSize);
      if (off + sectorSize > bytes.length) break;
      final perSector = sectorSize ~/ 4;
      for (var i = 0; i < perSector - 1; i++) {
        final s = bd.getUint32(off + i * 4, Endian.little);
        if (s < 0xFFFFFFFA) difat.add(s);
      }
      nextDifat = bd.getUint32(off + (perSector - 1) * 4, Endian.little);
    }

    // ── 组装 FAT ──
    final perSector = sectorSize ~/ 4;
    final fatLen = (numFatSectors > 0 && numFatSectors < 0xFFFFFFFA)
        ? numFatSectors * perSector
        : difat.length * perSector;
    final fat = List<int>.filled(fatLen, 0xFFFFFFFF);
    var fi = 0;
    for (final fatSector in difat) {
      if (fi >= fatLen) break;
      final off = _sectorOffset(fatSector, sectorSize);
      if (off + sectorSize > bytes.length) break;
      for (var i = 0; i < perSector; i++) {
        fat[fi++] = bd.getUint32(off + i * 4, Endian.little);
      }
    }

    /// 沿 FAT 链读出一个普通流
    Uint8List? readFatStream(int start, int size) {
      final out = BytesBuilder(copy: false);
      var cur = start;
      var guard2 = 0;
      while (cur < 0xFFFFFFFA &&
          guard2++ < fat.length + 16 &&
          out.length < size + sectorSize) {
        final off = _sectorOffset(cur, sectorSize);
        if (off < 0 || off >= bytes.length) break;
        final end = (off + sectorSize <= bytes.length)
            ? off + sectorSize
            : bytes.length;
        out.add(Uint8List.sublistView(bytes, off, end));
        if (cur >= fat.length) break;
        cur = fat[cur];
      }
      final all = out.takeBytes();
      return size > 0 && size <= all.length
          ? Uint8List.sublistView(all, 0, size)
          : all;
    }

    // ── 目录项 ──
    final dirBytes = readFatStream(firstDirSector, 0);
    if (dirBytes == null || dirBytes.length < 128) return null;

    var rootStart = -1;
    var rootSize = 0;
    var wbStart = -1;
    var wbSize = 0;

    for (var o = 0; o + 128 <= dirBytes.length; o += 128) {
      final nameLen = _u16(dirBytes, o + 0x40);
      if (nameLen == 0) continue;
      final type = dirBytes[o + 0x42];
      if (type != 2 && type != 5) continue; // 2=流 5=根
      final start = _u32(dirBytes, o + 0x74);
      final size = _u32(dirBytes, o + 0x78);
      final name = _decodeUtf16(dirBytes, o, nameLen > 2 ? nameLen - 2 : 0);

      if (type == 5) {
        rootStart = start;
        rootSize = size;
      } else if (name == 'Workbook' || name == 'Book') {
        wbStart = start;
        wbSize = size;
      }
    }

    if (wbStart < 0) return null;
    if (wbSize == 0) wbSize = 1 << 20; // 大小未知时给个上限

    // 大流走 FAT；小流（< miniCutoff）走 MiniFAT
    if (wbSize >= miniCutoff || rootStart < 0) {
      return readFatStream(wbStart, wbSize);
    }

    // ── MiniFAT 路径 ──
    final miniStream = readFatStream(rootStart, rootSize);
    if (miniStream == null) return null;
    final miniFatBytes = readFatStream(firstMiniFatSector, 0);
    if (miniFatBytes == null) return null;
    final miniFat =
        List<int>.generate(miniFatBytes.length ~/ 4, (i) => _u32(miniFatBytes, i * 4));

    final out = BytesBuilder(copy: false);
    var cur = wbStart;
    var guard3 = 0;
    while (cur < 0xFFFFFFFA &&
        guard3++ < miniFat.length + 16 &&
        out.length < wbSize + miniSectorSize) {
      final off = cur * miniSectorSize;
      if (off < 0 || off >= miniStream.length) break;
      final end = (off + miniSectorSize <= miniStream.length)
          ? off + miniSectorSize
          : miniStream.length;
      out.add(Uint8List.sublistView(miniStream, off, end));
      if (cur >= miniFat.length) break;
      cur = miniFat[cur];
    }
    final all = out.takeBytes();
    return wbSize <= all.length ? Uint8List.sublistView(all, 0, wbSize) : all;
  }

  static const List<int> _oleSignature = [
    0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
  ];

  static int _sectorOffset(int sector, int sectorSize) =>
      (sector + 1) * sectorSize;

  // ══════════════════════════════════════════════════════
  //  BIFF 记录
  // ══════════════════════════════════════════════════════

  static List<_Record> _parseRecords(Uint8List stream) {
    final out = <_Record>[];
    var pos = 0;
    while (pos + 4 <= stream.length) {
      final type = _u16(stream, pos);
      final len = _u16(stream, pos + 2);
      if (pos + 4 + len > stream.length) break;
      out.add(_Record(
        type: type,
        offset: pos,
        data: Uint8List.sublistView(stream, pos + 4, pos + 4 + len),
      ));
      pos += 4 + len;
    }
    return out;
  }

  /// 解析 SST（共享字符串表），会把紧随其后的 CONTINUE 记录一并接上。
  static List<String> _parseSst(List<_Record> records, int sstIndex) {
    final segments = <Uint8List>[records[sstIndex].data];
    for (var i = sstIndex + 1; i < records.length; i++) {
      if (records[i].type == _continue) {
        segments.add(records[i].data);
      } else {
        break;
      }
    }

    final cursor = _SstCursor(segments);
    final total = cursor.readUint32(); // cstTotal
    final unique = cursor.readUint32(); // cstUnique
    final out = <String>[];
    final count = unique > 0 && unique < 0x7FFFFFFF ? unique : total;
    for (var i = 0; i < count; i++) {
      final s = cursor.readString();
      if (s == null) break;
      out.add(s);
    }
    return out;
  }

  /// 读取 BIFF8 `XLUnicodeString`（cch + grbit + 字符数据），返回文本与结束偏移。
  static ({String value, int next}) _readBiff8String(
      Uint8List data, int offset) {
    var o = offset;
    if (o + 3 > data.length) return (value: '', next: data.length);
    final cch = _u16(data, o);
    o += 2;
    final grbit = data[o];
    o += 1;

    final highByte = (grbit & 0x01) != 0;
    final extSt = (grbit & 0x04) != 0;
    final richSt = (grbit & 0x08) != 0;

    var cRun = 0;
    var cbExt = 0;
    if (richSt) {
      if (o + 2 > data.length) return (value: '', next: data.length);
      cRun = _u16(data, o);
      o += 2;
    }
    if (extSt) {
      if (o + 4 > data.length) return (value: '', next: data.length);
      cbExt = _u32(data, o);
      o += 4;
    }

    final sb = StringBuffer();
    final available = data.length - o;
    final need = highByte ? cch * 2 : cch;
    final take = need <= available ? cch : (highByte ? available ~/ 2 : available);
    for (var i = 0; i < take; i++) {
      if (highByte) {
        sb.writeCharCode(_u16(data, o));
        o += 2;
      } else {
        sb.writeCharCode(data[o]);
        o += 1;
      }
    }
    o += cRun * 4 + cbExt;
    if (o > data.length) o = data.length;
    return (value: sb.toString(), next: o);
  }

  // ══════════════════════════════════════════════════════
  //  工具函数
  // ══════════════════════════════════════════════════════

  /// RK 值解码：低位是「×100」与「整数」标志，否则高 32 位是 IEEE754 双精度的高位。
  static double _rkToDouble(int rk) {
    final isInt = (rk & 0x02) != 0;
    if (isInt) {
      final v = (rk >> 2) & 0x3FFFFFFF;
      final signed = (v & 0x20000000) != 0 ? v - 0x40000000 : v;
      return (rk & 0x01) != 0 ? signed / 100.0 : signed.toDouble();
    }
    final bd = ByteData(8);
    bd.setUint32(0, 0, Endian.little);
    bd.setUint32(4, rk & 0xFFFFFFFC, Endian.little);
    var v = bd.getFloat64(0, Endian.little);
    if ((rk & 0x01) != 0) v /= 100.0;
    return v;
  }

  /// 数值转文本：整数值不带小数点，避免出现「20.0 周」这类难看输出。
  static String _formatNumber(double v) {
    if (v.isNaN || v.isInfinite) return '';
    if (v == v.roundToDouble() && v.abs() < 1e15) {
      return v.toInt().toString();
    }
    return v.toString();
  }

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  static String _decodeUtf16(Uint8List b, int offset, int byteLength) {
    final sb = StringBuffer();
    for (var i = 0; i + 1 < byteLength; i += 2) {
      sb.writeCharCode(b[offset + i] | (b[offset + i + 1] << 8));
    }
    return sb.toString();
  }
}

class _Record {
  _Record({required this.type, required this.offset, required this.data});
  final int type;
  final int offset;
  final Uint8List data;
}

/// SST 读取游标：支持跨 `CONTINUE` 段的字符串续接。
///
/// BIFF8 规定：当一段字符串的**字符数据**跨过记录边界时，下一个 CONTINUE
/// 记录的首字节是一个新的 grbit（压缩/非压缩标志），不属于字符内容。
/// 本文件（教务系统导出）实测不含 CONTINUE，此逻辑用于兼容更长的表格。
class _SstCursor {
  _SstCursor(this.segments);

  final List<Uint8List> segments;
  int _si = 0;
  int _off = 0;

  bool _atSegmentEnd() => _si < segments.length && _off >= segments[_si].length;

  /// 前进到下一个非空段的开头
  bool _gotoNextSegment() {
    while (_si < segments.length && _off >= segments[_si].length) {
      _si++;
      _off = 0;
    }
    return _si < segments.length;
  }

  int _byte() {
    if (!_gotoNextSegment()) return 0;
    return segments[_si][_off++];
  }

  int readByte() => _byte();

  int readUint16() {
    final lo = _byte();
    final hi = _byte();
    return lo | (hi << 8);
  }

  int readUint32() {
    final lo = readUint16();
    final hi = readUint16();
    return lo | (hi << 16);
  }

  /// 读取一个 `XLUnicodeRichExtendedString`，失败返回 null。
  String? readString() {
    if (!_gotoNextSegment()) return null;
    if (segments[_si].length - _off < 3) return null;

    final cch = readUint16();
    var grbit = _byte();
    var highByte = (grbit & 0x01) != 0;
    final extSt = (grbit & 0x04) != 0;
    final richSt = (grbit & 0x08) != 0;

    var cRun = 0;
    var cbExt = 0;
    if (richSt) cRun = readUint16();
    if (extSt) cbExt = readUint32();

    final sb = StringBuffer();
    var left = cch;
    var stalled = 0;
    while (left > 0) {
      if (_atSegmentEnd()) {
        // 字符数据跨记录续接：新段首字节是 grbit
        if (!_gotoNextSegment()) break;
        grbit = _byte();
        highByte = (grbit & 0x01) != 0;
      }
      final seg = segments[_si];
      final avail = seg.length - _off;
      var take = left;
      if (highByte) {
        final byChars = avail ~/ 2;
        if (take > byChars) take = byChars;
        for (var i = 0; i < take; i++) {
          sb.writeCharCode(seg[_off] | (seg[_off + 1] << 8));
          _off += 2;
        }
      } else {
        if (take > avail) take = avail;
        for (var i = 0; i < take; i++) {
          sb.writeCharCode(seg[_off++]);
        }
      }
      if (take == 0) {
        if (++stalled > 4) break;
      } else {
        stalled = 0;
      }
      left -= take;
    }

    _skip(cRun * 4 + cbExt);
    return sb.toString();
  }

  /// 跳过若干原始字节（rich runs / 扩展数据），不消耗段首 grbit 标志。
  void _skip(int n) {
    var left = n;
    while (left > 0 && _si < segments.length) {
      final avail = segments[_si].length - _off;
      if (avail <= 0) {
        _si++;
        _off = 0;
        continue;
      }
      final take = left < avail ? left : avail;
      _off += take;
      left -= take;
    }
  }
}
