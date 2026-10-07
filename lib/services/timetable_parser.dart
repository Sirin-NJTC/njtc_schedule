/// 课程表解析器 —— 解析教务系统导出的 XLS/XLSX 表格 或 手动粘贴的文本。
///
/// 支持两种格式：
/// 1. 正方教务系统标准课表（内江师范学院）：
///    表格结构：行0=学期/课表名/专业，行1=表头(节次| |周一到周日)，
///    行2-6=5个时段（上午一/二、下午三/四、晚上五）。
///    每格格式：`课程/(x-y节)n-m周[(单/双)]/ 地点/教师/(学期)-课程代码/教学班组成`
///    同格多门课用换行分隔。
/// 2. 用户手动粘贴的自由文本（尽力解析）。
///
/// 解析算法要点（已用真实课表数据 20/20 条完全正确验证）：
/// - 按 `/` 分割后 **动态定位含时间信息的字段**，而不是假定它在第 0 段。
///   真实数据是 `课程名/(1-2节)7-18周/...`，时间在 parts[1]；
///   但也存在 `课程名(1-2节)7-18周/...` 时间与课名同段的变体。
/// - 节次正则必须带「节」、周次正则必须带「周」，否则
///   `(1-2节)7-18周` 里的 `1-2` 会被误当成周次。
/// - 时间字段之后的字段顺序固定：地点 / 教师 / 教学班 / 教学班组成。
library;

import '../models/course.dart';
import '../models/timetable.dart';

/// 课程表解析器。
class TimetableParser {
  /// 标准 5 时段布局的节次起点（上午一/二、下午三/四、晚上五）。
  static const List<int> slotStartSections = [1, 3, 5, 7, 9];

  /// 判断某字段是否含时间信息（节次或周次）。
  static final RegExp _reHasTime = RegExp(r'\d+\s*[-－—~至]\s*\d+\s*[节周]|\d+\s*[节周]');

  /// 节次区间：`1-2节`。必须带「节」。
  static final RegExp _reSection = RegExp(r'(\d+)\s*[-－—~至]\s*(\d+)\s*节');

  /// 单节次：`第3节` / `3节`。
  static final RegExp _reSectionSingle = RegExp(r'(\d+)\s*节');

  /// 周次区间：`7-18周`。必须带「周」——这是避免把 `1-2节` 误读成周次的关键。
  static final RegExp _reWeek = RegExp(r'(\d+)\s*[-－—~至]\s*(\d+)\s*周');

  /// 单周：`7周`。
  static final RegExp _reWeekSingle = RegExp(r'(\d+)\s*周');

  /// 课程代码，如 `ZB1040282-07` / `GB0640014-10`。
  static final RegExp _reCode = RegExp(r'([A-Z]{1,4}\d{6,8}-\d{1,2})');

  /// 课名尾部粘连的地点，如 `格致楼309` / `第五教学楼A101` / `田径场04`。
  /// 只用于「没有单独地址列」时的兜底拆分（见 [parseCell] 第 6.1 步）。
  static final RegExp _reTrailingPlace = RegExp(
    r'[\u4e00-\u9fa5]{1,8}(?:楼|馆|场|区|苑|中心)\s*[A-Za-z]?\d{1,4}(?:[-—－]\d{1,4})?(?:室|教室)?$',
  );

  /// 同上，但可以出现在行内任意位置（整页文字兜底解析用）。
  static final RegExp _rePlaceAnywhere = RegExp(
    r'[\u4e00-\u9fa5]{1,8}(?:楼|馆|场|区|苑|中心)\s*[A-Za-z]?\d{1,4}(?:[-—－]\d{1,4})?(?:室|教室)?',
  );

  /// 解析一个单元格的内容，返回该格内的课程列表。
  ///
  /// 例如：
  /// `示例课程甲/(1-2节)7-18周/ 格致楼216/示例老师A/(2026-2027-1)-ZB1040282-07/演示26.8`
  /// 同一格可含多门课，用换行分隔。
  static List<Course> parseCell(
    String text, {
    required int dayOfWeek, // 1-7
    int slotIndex = -1, // 时段索引 0-4，节次缺失时用于补齐
  }) {
    final results = <Course>[];
    if (text.trim().isEmpty) return results;

    // 同格多门课用换行分隔（\n 或 \r\n）
    final blocks = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);

    for (final block in blocks) {
      final course = _parseBlock(block, dayOfWeek: dayOfWeek, slotIndex: slotIndex);
      if (course != null) results.add(course);
    }
    return results;
  }

  /// 解析单条课程块文本，失败返回 null。
  static Course? _parseBlock(
    String block, {
    required int dayOfWeek,
    int slotIndex = -1,
  }) {
    final s = block.trim();
    if (s.isEmpty) return null;

    final parts = s.split('/').map((e) => e.trim()).toList();

    // 1. 动态定位含时间信息的字段
    var timeIdx = -1;
    for (var i = 0; i < parts.length; i++) {
      if (_reHasTime.hasMatch(parts[i])) {
        timeIdx = i;
        break;
      }
    }
    if (timeIdx == -1) return null; // 无时间信息，无法定位

    // 2. 分离课程名与时间描述
    String courseName;
    String timeSpec;
    if (timeIdx == 0) {
      // 课程名与时间同段：`课程名(1-2节)7-18周`
      final m = RegExp(r'[(（]').firstMatch(parts[0]);
      if (m != null) {
        courseName = parts[0].substring(0, m.start).trim();
        timeSpec = parts[0].substring(m.start);
      } else {
        courseName = parts[0];
        timeSpec = '';
      }
    } else {
      courseName = parts.sublist(0, timeIdx).join('/').trim();
      timeSpec = parts[timeIdx];
    }
    if (courseName.isEmpty) courseName = '未知课程';

    // 3. 节次（必须带「节」）
    var startSection = 0, endSection = 0;
    final secMatch = _reSection.firstMatch(timeSpec);
    if (secMatch != null) {
      startSection = int.tryParse(secMatch.group(1)!) ?? 0;
      endSection = int.tryParse(secMatch.group(2)!) ?? 0;
    } else {
      final single = _reSectionSingle.firstMatch(timeSpec);
      if (single != null) {
        startSection = endSection = int.tryParse(single.group(1)!) ?? 0;
      }
    }
    // 节次缺失时用时段模板补齐
    if (startSection == 0 && slotIndex >= 0 && slotIndex < slotStartSections.length) {
      startSection = slotStartSections[slotIndex];
      endSection = startSection + 1;
    }

    // 4. 周次（必须带「周」）
    var startWeek = 0, endWeek = 0;
    final weekMatch = _reWeek.firstMatch(timeSpec);
    if (weekMatch != null) {
      startWeek = int.tryParse(weekMatch.group(1)!) ?? 0;
      endWeek = int.tryParse(weekMatch.group(2)!) ?? 0;
    } else {
      final single = _reWeekSingle.firstMatch(timeSpec);
      if (single != null) {
        startWeek = endWeek = int.tryParse(single.group(1)!) ?? 0;
      }
    }
    if (startWeek == 0) {
      startWeek = 1;
      endWeek = 20;
    }

    // 5. 单双周
    var oddEven = 0;
    if (timeSpec.contains('单')) {
      oddEven = 1;
    } else if (timeSpec.contains('双')) {
      oddEven = 2;
    }

    // 6. 时间字段之后的固定顺序：地点 / 教师 / 教学班 / 教学班组成
    final rest = parts.sublist(timeIdx + 1);
    var location = rest.isNotEmpty ? rest[0] : '';
    final teacher = rest.length > 1 ? rest[1] : '';
    final codeRaw = rest.length > 2 ? rest[2] : '';
    final className = rest.length > 3 ? rest[3] : '';

    // 6.1 兜底：有些页面把「课名 地点」挤在同一行（没有单独的地址列），
    // 于是地点被并进了课名 —— 从课名尾部把 `XX楼B309` 这类地点拆出来。
    // 真机上就是这样：提醒里出现「… 格致楼309 @」，地点字段其实是空的。
    var name = courseName;
    if (location.isEmpty) {
      final placeMatch = _reTrailingPlace.firstMatch(name);
      if (placeMatch != null) {
        final candidate = placeMatch.group(0)!.trim();
        final head = name.substring(0, placeMatch.start).trim();
        // 只有拆完还剩课名时才认，避免把「格致楼309」本身当成课程
        if (head.isNotEmpty) {
          name = head;
          location = candidate;
        }
      }
    }

    return Course(
      name: name,
      teacher: teacher,
      location: location,
      dayOfWeek: dayOfWeek,
      startSection: startSection,
      endSection: endSection,
      startWeek: startWeek,
      endWeek: endWeek,
      oddEven: oddEven,
      courseCode: _extractCode(codeRaw),
      className: className,
    );
  }

  /// 从教学班字段提取课程代码。
  /// `(2026-2027-1)-ZB1040282-07` → `ZB1040282-07`；无法识别则退回去括号原文。
  static String _extractCode(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final m = _reCode.firstMatch(s);
    if (m != null) return m.group(1)!;
    return s.replaceAll(RegExp(r'[()]'), '').trim();
  }

  /// 从教务系统导出的表格数据（二维 List）解析完整课表。
  ///
  /// [grid]: 二维单元格，grid[row][col]。
  static Timetable parseGrid(List<List<String>> grid, {String name = ''}) {
    final courses = <Course>[];
    final nRows = grid.length;

    // ── 动态定位表头行（含「星期X」的行）──
    var headerRow = -1;
    for (var r = 0; r < nRows; r++) {
      if (grid[r].any((c) => RegExp(r'星期[一二三四五六日天]').hasMatch(c))) {
        headerRow = r;
        break;
      }
    }

    // 表头列 → 星期几
    final colToDay = <int, int>{};
    if (headerRow >= 0) {
      const dayChars = '一二三四五六日';
      final hr = grid[headerRow];
      for (var c = 0; c < hr.length; c++) {
        final m = RegExp(r'星期([一二三四五六日天])').firstMatch(hr[c]);
        if (m != null) {
          final ch = m.group(1)!;
          colToDay[c] = ch == '天' ? 7 : dayChars.indexOf(ch) + 1;
        }
      }
    }
    // 兜底：col 2..8 → 周一..周日
    if (colToDay.isEmpty) {
      for (var c = 2; c <= 8; c++) {
        colToDay[c] = c - 1;
      }
    }

    // ── 提取学期 / 专业（表头行之前的行）──
    var semester = '', major = '';
    final infoEnd = headerRow > 0 ? headerRow : (nRows > 0 ? 1 : 0);
    for (var r = 0; r < infoEnd; r++) {
      for (final cell in grid[r]) {
        final t = cell.trim();
        if (semester.isEmpty && t.contains('学期')) semester = t;
        if (major.isEmpty && t.startsWith('专业')) {
          major = t.replaceFirst(RegExp(r'^专业[：:]\s*'), '').trim();
        }
      }
    }

    // ── 遍历数据行 ──
    final startRow = headerRow >= 0 ? headerRow + 1 : 2;
    var footerText = '';
    for (var r = startRow; r < nRows; r++) {
      final row = grid[r];
      if (row.isEmpty) continue;
      // 页脚：首列以「注」开头
      if (row[0].trim().startsWith('注')) {
        footerText = row.join(' ');
        break;
      }

      final slotIndex = r - startRow;
      for (final entry in colToDay.entries) {
        final c = entry.key;
        final dayOfWeek = entry.value;
        if (c >= row.length) continue;
        final cellText = row[c].trim();
        if (cellText.isEmpty) continue;

        courses.addAll(parseCell(
          cellText,
          dayOfWeek: dayOfWeek,
          slotIndex: slotIndex,
        ));
      }
    }

    // ── 从页脚提取学期起始日期与总周数 ──
    // 页脚样例：
    //   「注--内容顺序为：课程<>周次<>地点<>教师<>教学班<>教学班组成 ……
    //     本学期2026-08-31正式上课至2027-01-17结束，共20周. 打印时间：2026-08-31」
    // 这两项是「当前第几周」与「课程提醒按第几周生效」的依据，缺失会导致周次永远锁死第 1 周。
    DateTime? startDate;
    var parsedWeeks = 0;
    if (footerText.isNotEmpty) {
      final dm = RegExp(r'本学期\s*(\d{4})\s*[-－/.]\s*(\d{1,2})\s*[-－/.]\s*(\d{1,2})\s*正式上课')
          .firstMatch(footerText);
      if (dm != null) {
        final y = int.parse(dm.group(1)!);
        final mo = int.parse(dm.group(2)!);
        final d = int.parse(dm.group(3)!);
        if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
          startDate = DateTime(y, mo, d);
        }
      }
      final wm = RegExp(r'共\s*(\d{1,2})\s*周').firstMatch(footerText);
      if (wm != null) parsedWeeks = int.parse(wm.group(1)!);
    }

    return Timetable(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.isEmpty ? (semester.isEmpty ? '我的课表' : semester) : name,
      semester: semester,
      major: major,
      totalWeeks: parsedWeeks > 0 ? parsedWeeks : 20,
      startDate: startDate,
      courses: courses,
    );
  }

  /// 从 XLS/XLSX 文件读取的二维表格解析（null 单元格归一为空串）。
  static Timetable parseExcelGrid(List<List<String?>> grid, {String name = ''}) {
    final normalized =
        grid.map((row) => row.map((c) => c ?? '').toList()).toList();
    return parseGrid(normalized, name: name);
  }

  /// 解析手动粘贴的自由文本（尽力而为）。
  ///
  /// 优先尝试按「正方表格粘贴」处理（含制表符时视为表格行/列），
  /// 否则按逐行文本解析：`课程名 周x 第n-m节 周a-b 地点 教师`。
  static Timetable parseFreeText(String text, {String name = ''}) {
    // 含制表符 → 当作从 Excel 直接复制的表格
    if (text.contains('\t')) {
      final grid = text
          .split(RegExp(r'[\r\n]+'))
          .where((l) => l.trim().isNotEmpty)
          .map((l) => l.split('\t').map((c) => c.trim()).toList())
          .toList();
      if (grid.length >= 3) {
        final t = parseGrid(grid, name: name);
        if (t.courses.isNotEmpty) return t;
      }
    }

    final courses = <Course>[];
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final c = _parseFreeLine(line.trim());
      if (c != null) courses.add(c);
    }
    return Timetable(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.isEmpty ? '导入课表' : name,
      courses: courses,
    );
  }

  static Course? _parseFreeLine(String line) {
    if (line.isEmpty) return null;

    // 星期（「星期一」和「周一」都要认，教务导出里两种写法都常见）
    int? dayOfWeek;
    final dayMatch = RegExp(r'(?:星期|周)([一二三四五六日天1-7])').firstMatch(line);
    if (dayMatch != null) {
      final d = dayMatch.group(1)!;
      const map = {
        '一': 1, '二': 2, '三': 3, '四': 4,
        '五': 5, '六': 6, '日': 7, '天': 7,
      };
      dayOfWeek = map[d] ?? int.tryParse(d);
    }

    // 节次
    final secMatch = _reSection.firstMatch(line);
    final startSection = secMatch != null ? int.tryParse(secMatch.group(1)!) : null;
    final endSection = secMatch != null ? int.tryParse(secMatch.group(2)!) : null;

    // 周次
    final weekMatch = _reWeek.firstMatch(line);
    final startWeek =
        weekMatch != null ? (int.tryParse(weekMatch.group(1)!) ?? 1) : 1;
    final endWeek =
        weekMatch != null ? (int.tryParse(weekMatch.group(2)!) ?? 20) : 20;
    final oddEven = line.contains('单') ? 1 : (line.contains('双') ? 2 : 0);

    if (dayOfWeek == null || startSection == null || endSection == null) {
      return null;
    }

    // 课程名与地点：原来这里把教师/地点直接丢掉（`location: ''`），真机上就表现为
    // 「导入课程没有老师和教室」—— 所以整行里先把 `XX楼A101` 摘出来当地点，
    // 再去掉节次/周次/星期描述，剩下的才是课程名。
    final placeMatch = _rePlaceAnywhere.firstMatch(line);
    final location = placeMatch?.group(0)?.trim() ?? '';
    var head = line;
    if (location.isNotEmpty) head = head.replaceFirst(location, ' ');
    head = head
        .replaceAll(RegExp(r'\d+\s*[-－—~至]\s*\d+\s*[节周]'), ' ')
        .replaceAll(RegExp(r'\d+\s*[节周]'), ' ')
        .replaceAll(RegExp(r'[（(][^）)]*[）)]'), ' ')
        .replaceAll(RegExp(r'(?:星期|周)\s*[一二三四五六日天1-7]'), ' ');
    final courseName = head.replaceAll(RegExp(r'\s+'), ' ').trim();

    return Course(
      name: courseName.isEmpty ? '未知课程' : courseName,
      teacher: '',
      location: location,
      dayOfWeek: dayOfWeek,
      startSection: startSection,
      endSection: endSection,
      startWeek: startWeek,
      endWeek: endWeek,
      oddEven: oddEven,
    );
  }
}
