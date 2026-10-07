/// 正方教务系统课表**网页（HTML）**解析器 —— 供「网页登录导入」使用。
///
/// 正方课表页的单元格结构与导出的 `.xls` 文件**不同**：
///
/// - `.xls`：一格内是一段以 `/` 分隔的文本，顺序为
///   `课程名/(1-2节)7-18周/ 地点/教师/(学期)-教学班/教学班组成`
/// - HTML ：一格内含 `kbcontent` 区块，字段之间靠 `<br>` 换行，
///   并靠子元素的 `title` 属性标注字段名，同一格多门课用 `<hr>` 分隔：
///   ```html
///   <td rowspan="2">
///     <div class="kbcontent">示例课程甲<br>
///       <font title="教师">示例老师A</font><br>
///       <font title="周次(节次)">7-18周(1-2节)</font><br>
///       <font title="地点">格致楼216</font><br>
///       <font title="教学班">(2026-2027-1)-ZB1040282-07</font><br>
///       <font title="教学班组成">演示26.8</font>
///     </div>
///   </td>
///   ```
///
/// 本解析器的做法是：把 HTML 单元格**归一化回 `.xls` 的 `/` 分隔格式**，
/// 再交给 [TimetableParser.parseCell] 处理。这样节次/周次/单双周/课程代码
/// 等时间解析逻辑只有**一套**（已被真实导出的 `.xls` 逐字段验证过），
/// 不会出现两套正则各自演化、行为不一致的问题。
///
/// 表格结构解析要点：
/// - 逐 `<td>/<th>` 计算 `rowspan`/`colspan` 占位矩阵，**每个物理单元格只处理一次**
///   （正方一个大节常由两行 `<tr>` 组成、课程格 `rowspan=2`，若按行展开会重复出课）。
/// - 表头行动态定位（找含「星期X」的行），据此建立「列 → 星期几」映射，
///   因此不依赖固定的列偏移。
/// - 节次信息优先由单元格自带的「周次(节次)」字段给出；缺失时才用
///   同一行左侧「节次」列的文本推算出时段下标，作为兜底。
library;

import '../models/course.dart';
import '../models/timetable.dart';
import 'timetable_parser.dart';

/// 正方课表网页解析器。
class ZfHtmlParser {
  ZfHtmlParser._();

  // ---------- 时间描述相关正则（仅用于把 HTML 字段归一化成 .xls 文本） ----------
  static final RegExp _reSecRange = RegExp(r'(\d+)\s*[-－—~至]\s*(\d+)\s*节');
  static final RegExp _reSecSingle = RegExp(r'(\d+)\s*节');
  static final RegExp _reWeekRange = RegExp(r'(\d+)\s*[-－—~至]\s*(\d+)\s*周');
  static final RegExp _reWeekList = RegExp(r'((?:\d+\s*[,，、]\s*)+\d+)\s*周');
  static final RegExp _reWeekSingle = RegExp(r'(\d+)\s*周');
  static final RegExp _reAnyTime =
      RegExp(r'\d+\s*[-－—~至]\s*\d+\s*[节周]|\d+\s*[节周]');
  static final RegExp _reDays = RegExp(r'星期\s*([一二三四五六日天])');
  static final RegExp _reTag = RegExp(r'<[^>]*>', dotAll: true);

  /// 页面里是否像课表（用于快速判断当前页该不该尝试解析）。
  static bool looksLikeTimetable(String html) =>
      html.contains('kbcontent') ||
      html.contains('kbtable') ||
      _reDays.hasMatch(html);

  // ============================ 对外入口 ============================

  /// 从整页 HTML 中解析课程；解析不到返回空列表。
  static List<Course> parseCourses(String html) {
    if (html.trim().isEmpty) return const <Course>[];
    _Table? best;
    var bestScore = 0;
    for (final raw in _extractTables(html)) {
      final table = _parseTable(raw);
      final score = _score(table);
      if (score > bestScore) {
        bestScore = score;
        best = table;
      }
    }
    if (best == null || bestScore == 0) return const <Course>[];
    return _coursesFrom(best);
  }

  /// 解析整页 HTML 为 [Timetable]；没有课程时返回 null。
  static Timetable? parseTimetable(String html, {String name = ''}) {
    final courses = parseCourses(html);
    if (courses.isEmpty) return null;
    final meta = extractMeta(_plainText(html));
    return Timetable(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      semester: meta.semester,
      major: meta.major,
      totalWeeks: meta.totalWeeks,
      startDate: meta.startDate,
      courses: courses,
    );
  }

  /// 把正方 jwglxt 课表接口（`xskbcx_cxXskbcxIndex.html?doType=query&gnmkdm=N2151`）
  /// 返回的 `kbList` 行转成 [Course]。
  ///
  /// 接口字段（各校版本略有差异，同义键都认）：
  /// `kcmc` 课程名 / `xm` 教师 / `cdmc` 场地 / `xqj` 星期(1-7) /
  /// `jcs` 节次（`1-2` 或 `3`）/ `zcd` 周次（`1-16周`、`1-15周(单)`、`1,3,5-9周`）。
  ///
  /// 实现上刻意**不重写**节次/周次/单双周的解析，而是拼成 `.xls` 方言的单元格文本
  /// （`课程/(x-y节)n-m周(单)/地点/教师`）交给 [TimetableParser.parseCell]：
  /// 这样「节次、周次区间、单双周、连堂」的语义全工程只维护一份。
  static List<Course> coursesFromJwglxtJson(List<dynamic> rows) {
    final out = <Course>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final name = _pickJsonField(raw, _jsonNameKeys);
      if (name.isEmpty) continue;
      final day = int.tryParse(_pickJsonField(raw, _jsonDayKeys));
      if (day == null || day < 1 || day > 7) continue;
      final section = _jsonSectionSpec(raw);
      if (section.isEmpty) continue;
      final weeks = _jsonWeekSpecs(raw);
      if (weeks.isEmpty) continue;
      final teacher = _pickJsonField(raw, _jsonTeacherKeys);
      final location = _pickJsonField(raw, _jsonPlaceKeys);
      for (final week in weeks) {
        out.addAll(
          TimetableParser.parseCell(
            '$name/($section节)$week/$location/$teacher',
            dayOfWeek: day,
          ),
        );
      }
    }
    // 同一门课被接口重复返回时去重，并保持「按星期、按节次」的稳定顺序。
    final seen = <String>{};
    final unique = <Course>[];
    for (final c in out) {
      final key = '${c.name}|${c.teacher}|${c.location}|${c.dayOfWeek}|'
          '${c.startSection}-${c.endSection}|${c.startWeek}-${c.endWeek}|'
          '${c.oddEven}';
      if (seen.add(key)) unique.add(c);
    }
    unique.sort((a, b) {
      final d = a.dayOfWeek.compareTo(b.dayOfWeek);
      if (d != 0) return d;
      return a.startSection.compareTo(b.startSection);
    });
    return unique;
  }

  static const List<String> _jsonNameKeys = ['kcmc', 'kcm', 'courseName'];
  static const List<String> _jsonTeacherKeys = ['xm', 'jsxm', 'jsmc', 'teacher'];
  static const List<String> _jsonPlaceKeys = [
    'cdmc',
    'jxcdmc',
    'jasmc',
    'classroom',
    'room',
  ];
  static const List<String> _jsonDayKeys = ['xqj', 'xq', 'skxq', 'day', 'weekday'];
  static const List<String> _jsonSectionKeys = ['jcs', 'jc', 'sksj'];
  static const List<String> _jsonWeekKeys = ['zcd', 'zc', 'skzc', 'weeks'];

  static String _pickJsonField(Map<dynamic, dynamic> row, List<String> keys) {
    for (final k in keys) {
      final v = row[k];
      if (v == null) continue;
      final s = v is List ? v.join(',') : '$v';
      final t = s.trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  /// `jcs` 可能是 `1-2` / `1-2节` / `第1-2节` / `1`；
  /// 拿不到时用 `ksjc`+`jsjc`（或 `cxjc` 节数）算。
  static String _jsonSectionSpec(Map<dynamic, dynamic> row) {
    final raw = _pickJsonField(row, _jsonSectionKeys);
    final m = RegExp(r'(\d+)\s*[-－—~至,，]\s*(\d+)').firstMatch(raw);
    if (m != null) return '${m.group(1)}-${m.group(2)}';
    final single = RegExp(r'\d+').firstMatch(raw);
    if (single != null) return single.group(0)!;

    final start = int.tryParse(_pickJsonField(row, const ['ksjc', 'skjc', 'startSection']));
    if (start == null) return '';
    final end = int.tryParse(_pickJsonField(row, const ['jsjc', 'endSection']));
    if (end != null) return end > start ? '$start-$end' : '$start';
    final count = int.tryParse(_pickJsonField(row, const ['cxjc', 'sectionCount']));
    if (count != null && count > 1) return '$start-${start + count - 1}';
    return '$start';
  }

  /// `zcd` 可能是 `1-16周` / `1-15周(单)` / `1,3,5-9周` / `第1-16周`；
  /// 逗号分隔的离散周次**逐段产出**，不补空隙（补了会凭空多出没课的周）。
  static List<String> _jsonWeekSpecs(Map<dynamic, dynamic> row) {
    var s = _pickJsonField(row, _jsonWeekKeys);
    if (s.isEmpty) return const <String>[];
    s = s
        .replaceAll(RegExp(r'[，、；;]'), ',')
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll('周数', '')
        .replaceAll('第', '')
        .replaceAll(RegExp(r'\s+'), '');
    final out = <String>[];
    for (final part in s.split(',')) {
      if (part.isEmpty) continue;
      final m = RegExp(r'(\d+)\s*[-－—~至]?\s*(\d+)?').firstMatch(part);
      if (m == null) continue;
      final a = m.group(1)!;
      final b = m.group(2);
      final odd = part.contains('单')
          ? '(单)'
          : part.contains('双')
              ? '(双)'
              : '';
      out.add('$a${b == null ? '' : '-$b'}周$odd');
    }
    return out;
  }

  /// 从 `xnm`（学年，如 `2026`）与 `xqm`（学期码：`3`=第一学期 / `12`=第二学期 /
  /// `16`=第三学期）拼出与网页一致的学期名。认不出返回空串。
  static String semesterFromCodes(String xnm, String xqm) {
    final year = int.tryParse(xnm);
    if (year == null) return '';
    final term = switch (xqm) {
      '3' => '1',
      '12' => '2',
      '16' => '3',
      _ => '',
    };
    if (term.isEmpty) return '';
    return '$year-${year + 1}年第$term学期';
  }

  /// 把页面里最像课表的那张表还原成**纯文本二维数组**。
  ///
  /// 用于「不是正方 `kbcontent` 结构、但格内已经是 `/` 分隔文本」的教务系统页面：
  /// 交给 `TimetableParser.parseGrid` 即可复用同一套「列 → 星期、行 → 节次」推断逻辑。
  /// `rowspan` 单元格只填**起始行**，避免同一门课在展开时被解析两次。
  static List<List<String>> textGrid(String html) {
    if (html.trim().isEmpty) return const <List<String>>[];
    _Table? best;
    var bestScore = 0;
    for (final raw in _extractTables(html)) {
      final table = _parseTable(raw);
      final score = _score(table);
      if (score > bestScore) {
        bestScore = score;
        best = table;
      }
    }
    if (best == null || bestScore == 0) return const <List<String>>[];
    final rows = <List<String>>[];
    for (final cell in best.cells) {
      while (rows.length <= cell.row) {
        rows.add(List<String>.filled(best.maxCol, ''));
      }
      if (cell.col >= 0 && cell.col < best.maxCol) {
        rows[cell.row][cell.col] = _plainText(cell.html);
      }
    }
    return rows;
  }

  /// 从页面纯文本里抽取学期 / 专业 / 总周数 / 起始日期。
  ///
  /// 例如「本学期2026-08-31正式上课至2027-01-17结束，共20周.」。
  static ({String semester, String major, int totalWeeks, DateTime? startDate})
      extractMeta(String text) {
    var semester = '';
    final sem = RegExp(r'\d{4}\s*[-－]\s*\d{4}\s*学?年?\s*第?\s*[一二1-2]\s*学?期')
        .firstMatch(text);
    if (sem != null) {
      // 归一到与 `.xls` 页脚一致的写法：网页上多为「2026-2027学年第1学期」，
      // 而导出的表格里是「2026-2027年第1学期」，统一去掉「学」字避免两处不一致。
      semester =
          sem.group(0)!.replaceAll(RegExp(r'\s+'), '').replaceAll('学年', '年');
    }

    var major = '';
    // 网页上多数是「专业：示例工程」，但有些页面把「专业」和值放在相邻单元格里，
    // 经 `_plainText` 拼成「专业 示例工程」，所以冒号是可选的；
    // 若「专业」后面跟的其实是别的标签（如「课程表」），则不算专业名。
    final mj = RegExp(r'专业\s*[：:]?\s*([^\s，,。;；、/]+)').firstMatch(text);
    if (mj != null) {
      final v = mj.group(1)!.trim();
      if (v.isNotEmpty && !v.contains('课') && !v.contains('表')) major = v;
    }

    var totalWeeks = 0;
    final tw = RegExp(r'共\s*(\d+)\s*周').firstMatch(text);
    if (tw != null) totalWeeks = int.tryParse(tw.group(1)!) ?? 0;

    DateTime? startDate;
    final sd = RegExp(
      r'(\d{4})\s*[-年/.]\s*(\d{1,2})\s*[-月/.]\s*(\d{1,2})\s*日?\s*(?:正式)?(?:上课|开学|行课|开课)',
    ).firstMatch(text);
    if (sd != null) {
      final y = int.tryParse(sd.group(1)!);
      final m = int.tryParse(sd.group(2)!);
      final d = int.tryParse(sd.group(3)!);
      if (y != null && m != null && d != null) startDate = DateTime(y, m, d);
    }
    return (
      semester: semester,
      major: major,
      totalWeeks: totalWeeks,
      startDate: startDate,
    );
  }

  // ============================ 表格结构 ============================

  /// 取出页面里所有 `<table>` 的内部 HTML（嵌套表也会各自成为候选）。
  ///
  /// 每张表都会被当成一个独立候选：课表本身可能是嵌在布局表里的内层表，
  /// 若只取最外层就会解析错。最终由 [parseCourses] 按「像课程格的单元格数」打分择优。
  static List<String> _extractTables(String html) {
    final result = <String>[];
    final nestedRe = RegExp(r'<table\b', caseSensitive: false);
    final starts = nestedRe.allMatches(html).toList();
    for (final m in starts) {
      if (result.length > 120) break; // 防御：异常页面不至于拖垮解析
      final inner = _tableInner(html, m.start);
      if (inner == null) continue;
      if (nestedRe.hasMatch(inner.inner)) {
        final unfolded = _dropNestedTables(inner.inner);
        if (unfolded.trim().isNotEmpty) result.add(unfolded);
      } else if (inner.inner.trim().isNotEmpty) {
        result.add(inner.inner);
      }
    }
    return result;
  }

  /// 返回 [startIdx] 处 `<table>` 的内部 HTML 与「表格结束」下标。
  static ({String inner, int end})? _tableInner(String html, int startIdx) {
    final lower = html.toLowerCase();
    var depth = 0;
    var i = startIdx;
    var innerStart = -1;
    while (i < lower.length) {
      final lt = lower.indexOf('<', i);
      if (lt < 0) break;
      if (lower.startsWith('<table', lt)) {
        depth++;
        if (depth == 1) {
          final gt = lower.indexOf('>', lt);
          if (gt < 0) return null;
          innerStart = gt + 1;
        }
        i = lt + 6;
        continue;
      }
      if (lower.startsWith('</table', lt)) {
        depth--;
        final gt = lower.indexOf('>', lt);
        final next = gt < 0 ? lower.length : gt + 1;
        if (depth <= 0 && innerStart >= 0) {
          return (inner: html.substring(innerStart, lt), end: next);
        }
        i = next;
        continue;
      }
      i = lt + 1;
    }
    return null;
  }

  /// 反复删除嵌套的 `<table>...</table>`，直到没有嵌套。
  static String _dropNestedTables(String s) {
    final re = RegExp(r'<table\b[\s\S]*?</table\s*>', caseSensitive: false);
    var out = s;
    for (var i = 0; i < 12; i++) {
      final next = out.replaceAll(re, '');
      if (next == out) break;
      out = next;
    }
    return out;
  }

  static List<String> _rowHtmls(String tableInner) {
    final re = RegExp(r'<tr\b[^>]*>([\s\S]*?)</tr\s*>', caseSensitive: false);
    return [
      for (final m in re.allMatches(tableInner)) m.group(1) ?? '',
    ];
  }

  static List<_RawCell> _cellHtmls(String rowHtml) {
    final re = RegExp(r'<(td|th)\b([^>]*)>([\s\S]*?)</\1\s*>', caseSensitive: false);
    return [
      for (final m in re.allMatches(rowHtml))
        _RawCell(attrs: m.group(2) ?? '', inner: m.group(3) ?? ''),
    ];
  }

  static int _attrInt(String attrs, String name) {
    final m = RegExp('$name\\s*=\\s*["\']?\\s*(\\d+)', caseSensitive: false)
        .firstMatch(attrs);
    final v = m == null ? null : int.tryParse(m.group(1)!);
    return (v == null || v < 1) ? 1 : v;
  }

  /// 解析一张表的单元格矩阵（`rowspan`/`colspan` 感知）。
  static _Table _parseTable(String tableHtml) {
    final rows = _rowHtmls(tableHtml);
    final cells = <_Cell>[];
    final grid = <List<int?>>[];

    void ensure(int r, int c) {
      while (grid.length <= r) {
        grid.add(<int?>[]);
      }
      while (grid[r].length <= c) {
        grid[r].add(null);
      }
    }

    for (var r = 0; r < rows.length; r++) {
      var c = 0;
      for (final raw in _cellHtmls(rows[r])) {
        ensure(r, c);
        while (grid[r][c] != null) {
          c++;
          ensure(r, c);
        }
        final rowSpan = _attrInt(raw.attrs, 'rowspan');
        final colSpan = _attrInt(raw.attrs, 'colspan');
        final idx = cells.length;
        cells.add(_Cell(r, c, rowSpan, colSpan, raw.inner));
        for (var i = 0; i < rowSpan; i++) {
          for (var j = 0; j < colSpan; j++) {
            ensure(r + i, c + j);
            grid[r + i][c + j] = idx;
          }
        }
        c += colSpan;
      }
    }

    var maxCol = 0;
    for (final row in grid) {
      if (row.length > maxCol) maxCol = row.length;
    }
    return _Table(cells: cells, grid: grid, maxCol: maxCol);
  }

  // ============================ 课程抽取 ============================

  static int _score(_Table t) {
    var score = 0;
    for (final cell in t.cells) {
      if (_looksLikeCourseCell(cell.html)) score++;
    }
    return score;
  }

  static bool _looksLikeCourseCell(String html) {
    if (html.contains('kbcontent')) return true;
    final text = _plainText(html);
    if (text.isEmpty) return false;
    if (!_reAnyTime.hasMatch(text)) return false;
    // 表头/说明单元格一般不含「周 + 节」的组合
    return text.contains('周') || text.contains('节');
  }

  static List<Course> _coursesFrom(_Table t) {
    // 1. 定位表头行与「列 → 星期几」映射
    var headerRow = -1;
    var firstDayCol = -1;
    final dayByCol = <int, int>{};
    const dayNames = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '日': 7,
      '天': 7,
    };
    for (final cell in t.cells) {
      final m = _reDays.firstMatch(_plainText(cell.html));
      if (m == null) continue;
      final day = dayNames[m.group(1)!];
      if (day == null) continue;
      if (headerRow < 0 || cell.row < headerRow) headerRow = cell.row;
      for (var j = 0; j < cell.colSpan; j++) {
        dayByCol[cell.col + j] = day;
      }
      if (firstDayCol < 0 || cell.col < firstDayCol) firstDayCol = cell.col;
    }
    if (headerRow < 0 || firstDayCol < 0) return const <Course>[];

    // 2. 逐物理单元格抽课（每个 td 只处理一次，天然避免 rowspan 重复）
    final courses = <Course>[];
    for (final cell in t.cells) {
      if (cell.row <= headerRow) continue;
      final day = dayByCol[cell.col];
      if (day == null) continue;
      if (!_looksLikeCourseCell(cell.html)) continue;
      final slotIndex = _slotIndexOf(t, cell.row, firstDayCol);
      for (final normalized in _normalizeCell(cell.html)) {
        courses.addAll(
          TimetableParser.parseCell(
            normalized,
            dayOfWeek: day,
            slotIndex: slotIndex,
          ),
        );
      }
    }

    // 3. 兜底去重（同一门课被同一格重复写出时）
    final seen = <String>{};
    final unique = <Course>[];
    for (final c in courses) {
      final key = '${c.name}|${c.teacher}|${c.location}|${c.dayOfWeek}|'
          '${c.startSection}-${c.endSection}|${c.startWeek}-${c.endWeek}|'
          '${c.oddEven}|${c.courseCode}';
      if (seen.add(key)) unique.add(c);
    }
    unique.sort((a, b) {
      final d = a.dayOfWeek.compareTo(b.dayOfWeek);
      if (d != 0) return d;
      return a.startSection.compareTo(b.startSection);
    });
    return unique;
  }

  /// 用同一行左侧「节次」列的文本推算时段下标（0-4），失败返回 -1。
  static int _slotIndexOf(_Table t, int row, int firstDayCol) {
    if (row < 0 || row >= t.grid.length) return -1;
    final gridRow = t.grid[row];
    for (var c = 0; c < firstDayCol && c < gridRow.length; c++) {
      final idx = gridRow[c];
      if (idx == null) continue;
      final text = _plainText(t.cells[idx].html);
      final m = _reSecRange.firstMatch(text);
      final single = _reSecSingle.firstMatch(text);
      final first = m != null
          ? int.tryParse(m.group(1)!)
          : (single != null ? int.tryParse(single.group(1)!) : null);
      if (first == null) continue;
      final slot = TimetableParser.slotStartSections.indexOf(first);
      if (slot >= 0) return slot;
    }
    return -1;
  }

  /// 把一个课程单元格归一化成 `.xls` 风格的 `课程/时间/地点/教师/教学班/组成`。
  static List<String> _normalizeCell(String html) {
    final out = <String>[];
    // 同格多门课的分隔符有两种写法：多数正方版本用 `<hr>`，
    // 另有一批版本直接在 HTML 里写一行连续短横线（抓回来/innerText 里看到的就是 `-----`）。
    final blocks = html.split(
      RegExp(r'<hr\b[^>]*>|-{5,}', caseSensitive: false),
    );
    for (final block in blocks) {
      final line = _normalizeBlock(block);
      if (line != null && line.isNotEmpty) out.add(line);
    }
    return out;
  }

  static String? _normalizeBlock(String html) {
    // 1. 收集带 title 属性的字段（正方用 title 标注字段名）
    final titled = <String, String>{};
    final titleRe = RegExp(
      r'''<(\w+)\b([^>]*title\s*=\s*(?:"([^"]*)"|'([^']*)')[^>]*)>([\s\S]*?)</\1\s*>''',
      caseSensitive: false,
    );
    for (final m in titleRe.allMatches(html)) {
      final title = (m.group(3) ?? m.group(4) ?? '').trim();
      if (title.isEmpty) continue;
      final value = _plainText(m.group(5) ?? '');
      if (value.isEmpty) continue;
      titled.putIfAbsent(title, () => value);
    }

    // 没有任何 title 标注字段时，这一格本身就是 `.xls` 风格的斜杠文本
    // （`课程名/(1-2节)7-18周/地点/教师/教学班/组成`）——直接原样交给
    // `TimetableParser.parseCell`，否则按 title 字段重建会把地点/教师等丢掉。
    if (titled.isEmpty) {
      for (final line in _plainLines(html)) {
        if (line.contains('/') && _reAnyTime.hasMatch(line)) return line;
      }
    }

    List<String> pick(bool Function(String key) test) => [
          for (final e in titled.entries)
            if (test(e.key)) e.value,
        ];

    final weekSpec = pick((k) => k.contains('周') || k.contains('节') || k.contains('时间')).join(' ');
    final teacher = pick((k) => k.contains('教师') || k.contains('老师')).join(' ');
    final location =
        pick((k) => k.contains('地点') || k.contains('教室') || k.contains('场地')).join('；');
    final classNo = pick((k) => k.contains('教学班') && !k.contains('组成')).join('；');
    final classOrg = pick((k) => k.contains('组成') || k.contains('班级')).join('；');
    final named = pick((k) =>
        k.contains('课程') && !k.contains('代码') && !k.contains('编号') && !k.contains('号'));

    final lines = _plainLines(html);

    // 2. 时间描述：优先 title 字段，其次任意一行里带「周/节」的文本
    var timeRaw = weekSpec;
    if (timeRaw.trim().isEmpty) {
      for (final line in lines) {
        if (_reAnyTime.hasMatch(line)) {
          timeRaw = line;
          break;
        }
      }
    }
    final timeSpec = _composeTimeSpec(timeRaw);
    if (timeSpec.isEmpty) return null;

    // 3. 课程名：优先 title="课程"，否则取第一行非「教师/时间/地点」的行
    var name = named.isNotEmpty ? named.first : '';
    if (name.isEmpty) {
      // 有些教务系统的课程格本身就是 `.xls` 风格的斜杠文本
      // （`课程名/(1-2节)7-18周/地点/教师/教学班/组成`），
      // 这种情况下课程名就在第一个斜杠之前，而整行都带时间描述，
      // 直接走下面的「跳过含时间描述的行」会一路跳过变成「未知课程」。
      for (final line in lines) {
        if (!line.contains('/')) continue;
        final head = line.split('/').first.trim();
        if (head.isEmpty || _reAnyTime.hasMatch(head)) continue;
        name = head;
        break;
      }
    }
    if (name.isEmpty) {
      for (final line in lines) {
        if (_reAnyTime.hasMatch(line)) continue;
        if (line.isNotEmpty &&
            line == teacher.trim()) {
          continue;
        }
        if (line.isNotEmpty && line == location.trim()) continue;
        name = line;
        break;
      }
    }
    if (name.isEmpty) name = '未知课程';

    // 4. 课程代码：从教学班字段里提取（如 (2026-2027-1)-ZB1040282-07 → ZB1040282-07）
    final code = _extractCode(classNo);

    final parts = <String>[
      name,
      timeSpec,
      location,
      teacher,
      code.isNotEmpty ? code : classNo,
      classOrg,
    ];
    return parts
        .map((e) => e.replaceAll(RegExp(r'[/\r\n]+'), ' ').trim())
        .join('/');
  }

  /// 把「7-18周(1-2节)」「(1-2节)7-18周(单)」「1,3,5周」等写法归一成
  /// `(1-2节)7-18周(单)` 这种 `.xls` 风格的时间描述；完全无法识别时返回空串。
  static String _composeTimeSpec(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';

    int? secStart, secEnd, wkStart, wkEnd;
    final sm = _reSecRange.firstMatch(s);
    if (sm != null) {
      secStart = int.tryParse(sm.group(1)!);
      secEnd = int.tryParse(sm.group(2)!);
    } else {
      final ss = _reSecSingle.firstMatch(s);
      if (ss != null) {
        secStart = int.tryParse(ss.group(1)!);
        secEnd = secStart;
      }
    }

    final wm = _reWeekRange.firstMatch(s);
    if (wm != null) {
      wkStart = int.tryParse(wm.group(1)!);
      wkEnd = int.tryParse(wm.group(2)!);
    } else {
      final wl = _reWeekList.firstMatch(s);
      if (wl != null) {
        final nums = RegExp(r'\d+')
            .allMatches(wl.group(1)!)
            .map((m) => int.parse(m.group(0)!))
            .toList()
          ..sort();
        if (nums.isNotEmpty) {
          wkStart = nums.first;
          wkEnd = nums.last;
        }
      } else {
        final ws = _reWeekSingle.firstMatch(s);
        if (ws != null) {
          wkStart = int.tryParse(ws.group(1)!);
          wkEnd = wkStart;
        }
      }
    }

    if (secStart == null && wkStart == null) return '';

    final oddEven = s.contains('单') ? 1 : (s.contains('双') ? 2 : 0);
    final buf = StringBuffer();
    if (secStart != null && secEnd != null) {
      buf.write('($secStart-$secEnd节)');
    }
    if (wkStart != null && wkEnd != null) {
      buf.write('$wkStart-$wkEnd周');
      if (oddEven == 1) buf.write('(单)');
      if (oddEven == 2) buf.write('(双)');
    } else {
      buf.write('1-20周');
    }
    return buf.toString();
  }

  static String _extractCode(String raw) {
    final m = RegExp(r'([A-Z]{1,4}\d{6,8}-\d{1,2})').firstMatch(raw.toUpperCase());
    return m?.group(1) ?? '';
  }

  // ============================ 文本工具 ============================

  static List<String> _plainLines(String html) => _plainText0(html)
      .split(RegExp(r'[\r\n]+'))
      .map((e) => e.replaceAll(RegExp(r'[ \t\u00a0\u3000]+'), ' ').trim())
      .where((e) => e.isNotEmpty)
      .toList();

  static String _plainText(String html) => _plainLines(html).join(' ');

  static String _plainText0(String html) {
    var s = html;
    s = s.replaceAll(
      RegExp(r'<(script|style)\b[\s\S]*?</\1\s*>', caseSensitive: false),
      '',
    );
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(
      RegExp(r'</(div|p|li|h[1-6]|tr|td)\s*>', caseSensitive: false),
      '\n',
    );
    s = s.replaceAll(_reTag, '');
    return _decodeEntities(s);
  }

  static String _decodeEntities(String s) {
    var out = s;
    out = out.replaceAll(RegExp(r'&nbsp;?', caseSensitive: false), ' ');
    out = out.replaceAll(RegExp(r'&amp;', caseSensitive: false), '&');
    out = out.replaceAll(RegExp(r'&lt;', caseSensitive: false), '<');
    out = out.replaceAll(RegExp(r'&gt;', caseSensitive: false), '>');
    out = out.replaceAll(RegExp(r'&quot;', caseSensitive: false), '"');
    out = out.replaceAll('&#39;', "'");
    out = out.replaceAll('&apos;', "'");
    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    return out;
  }
}

/// 原始单元格（属性 + 内部 HTML）。
class _RawCell {
  const _RawCell({required this.attrs, required this.inner});
  final String attrs;
  final String inner;
}

/// 一个物理单元格。
class _Cell {
  const _Cell(this.row, this.col, this.rowSpan, this.colSpan, this.html);
  final int row;
  final int col;
  final int rowSpan;
  final int colSpan;
  final String html;
}

/// 一张待解析的表（已建好多格占位矩阵）。
class _Table {
  const _Table({
    required this.cells,
    required this.grid,
    required this.maxCol,
  });

  final List<_Cell> cells;

  /// 占位矩阵：`grid[row][col]` = `cells` 下标；null 表示该格位空闲。
  final List<List<int?>> grid;

  /// 最大列数。
  final int maxCol;
}
