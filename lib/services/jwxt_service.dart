/// 教务系统「网页登录导入」服务。
///
/// 与旧版的根本区别：不再试图在后台用 HTTP 复刻登录流程。
/// 内江师范学院教务系统走「智慧内师」统一身份认证，登录带**滑块验证码**，
/// 纯代码模拟既不稳定也容易触发风控；而且**校内校外都能直连，不需要 VPN**。
///
/// 现在的做法（与主流课程表 App 一致）：
/// 1. 在应用内弹出真正的 WebView（原生 `WebImportActivity`），用户像在浏览器里一样
///    输账号密码、过验证码，登录态由 WebView 的 Cookie 自己维护；
/// 2. 用户进入「课表查询」页面后点「读取课表」，原生侧注入 JS 把当前页的
///    表格 HTML 与整页文本抓回来；
/// 3. Dart 侧按「正方网页结构 → 通用 HTML 表格 → 纯文本」三级兜底解析。
///
/// 解析入口 [parsePayload] 与抓取解耦，因此可以直接喂 HTML 做单元测试
/// （见 `test/zf_html_parser_test.dart`）。
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../models/course.dart';
import '../models/timetable.dart';
import 'timetable_parser.dart';
import 'zf_html_parser.dart';

/// 教务系统常用入口。
class JwxtConfig {
  JwxtConfig._();

  /// 智慧内师**融合门户**（公网可开的那个地址）。
  ///
  /// `pass.njtc.edu.cn`（校园网内的门户地址）**只在校园网 DNS 里有记录**，
  /// 校外手机上 WebView 报 `net::ERR_NAME_NOT_RESOLVED`（2026-10-04 真机实测）。
  /// 同一个门户在公网主机 `tpass.njtc.edu.cn` 上也能开到：那里返回一个 meta
  /// refresh 跳到 `/app.php/portal_v4`，会走统一身份认证，登录后就是门户首页。
  /// 所以网页导入的默认入口用这个，用户登录后自己在门户里点进「课表查询」。
  static const String portalUrl = 'https://tpass.njtc.edu.cn/app.php/portal_v4';

  /// 学校统一身份认证（CAS）——公网可达。
  ///
  /// 直接用 [casUrl] + service 参数就成了「直达课表查询页」的深链，
  /// 网页导入右上角菜单里的「打开课表查询页」走的就是它。
  static const String casUrl = 'https://tpass.njtc.edu.cn';

  /// 校园网内的门户地址（校外解析不了，只作记录，不要在代码里使用）。
  static const String campusPortalUrl =
      'https://pass.njtc.edu.cn/frontend/center_portal_njtc/home/index.html';

  /// 正方教务系统入口。
  static const String jwxtBase = 'https://jwxt.njtc.edu.cn';

  /// 正方学生课表查询页（未登录时会自动跳到登录页）。
  static const String timetableUrl =
      'https://jwxt.njtc.edu.cn/jsxsd/xskb/xskb_list.do';
}

/// 网页导入的结局。
enum WebImportStatus {
  /// 成功解析出课程。
  ok,

  /// 用户关掉了网页登录窗口。
  cancelled,

  /// 打开了网页，但没能解析出课表（或平台不支持）。
  failed,
}

/// 网页导入结果。
class WebImportResult {
  const WebImportResult({
    required this.status,
    required this.message,
    this.timetable,
    this.pageUrl = '',
    this.pageTitle = '',
    this.rawText = '',
  });

  final WebImportStatus status;
  final String message;
  final Timetable? timetable;

  /// 抓取时所在页面的地址。
  final String pageUrl;

  /// 抓取时页面的标题。
  final String pageTitle;

  /// 抓到的页面纯文本 —— 解析失败时可以让用户改用「粘贴文本」导入，
  /// 不至于白跑一趟登录。
  final String rawText;

  bool get ok => status == WebImportStatus.ok;
  bool get cancelled => status == WebImportStatus.cancelled;
}

/// 教务系统网页导入服务（全部为静态方法，无需实例）。
class JwxtService {
  JwxtService._();

  static const String channelName = 'cn.edu.njtc.njtc_schedule/webimport';
  static const MethodChannel _channel = MethodChannel(channelName);

  /// 网页登录导入只在 Android 上可用（依赖原生 WebView 页面）。
  ///
  /// 用 `dart:io` 的 `Platform` 而不是 `defaultTargetPlatform`：
  /// 后者在 `flutter test` 里也会报 android，会让测试误判。
  static bool get supported => Platform.isAndroid;

  /// 上次成功抓到课表的页面地址（由原生侧记住），没有则返回 null。
  static Future<String?> lastUrl() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('lastUrl');
    } catch (_) {
      return null;
    }
  }

  /// 打开网页登录窗口，用户登录并进入课表页后点「读取课表」即可导入。
  ///
  /// [url] 为空时原生侧会使用上次成功的页面地址，首次则打开智慧内师门户。
  ///
  /// [autoRead] 仅供自动化测试：探测到课表页后不等用户点击，直接抓取并返回。
  static Future<WebImportResult> importFromWeb({
    String? url,
    bool autoRead = false,
  }) async {
    if (!supported) {
      return const WebImportResult(
        status: WebImportStatus.failed,
        message: '网页登录导入仅在 Android 版可用',
      );
    }

    Map<Object?, Object?>? raw;
    try {
      raw = await _channel.invokeMapMethod<Object?, Object?>(
        'open',
        <String, dynamic>{
          if (url != null && url.trim().isNotEmpty) 'url': url.trim(),
          if (autoRead) 'autoRead': true,
        },
      );
    } on PlatformException catch (e) {
      return WebImportResult(
        status: WebImportStatus.failed,
        message: e.message ?? '无法打开网页登录窗口',
      );
    } catch (e) {
      return WebImportResult(
        status: WebImportStatus.failed,
        message: '无法打开网页登录窗口：$e',
      );
    }

    if (raw == null) {
      return const WebImportResult(
        status: WebImportStatus.cancelled,
        message: '已取消',
      );
    }
    if (raw['ok'] != true) {
      if (raw['cancelled'] == true) {
        return const WebImportResult(
          status: WebImportStatus.cancelled,
          message: '已取消',
        );
      }
      return WebImportResult(
        status: WebImportStatus.failed,
        message: '${raw['message'] ?? '没有拿到页面内容'}',
      );
    }

    final payloadText = '${raw['payload'] ?? ''}';
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(payloadText) as Map<String, dynamic>;
    } catch (e) {
      return const WebImportResult(
        status: WebImportStatus.failed,
        message: '抓取结果格式异常，请重试',
      );
    }
    return parsePayload(payload);
  }

  /// 把原生抓到的页面内容解析成课表（与抓取解耦，便于单元测试）。
  ///
  /// 三级兜底：
  /// 1. 正方课表页结构（`kbcontent` + `title` 标注字段）；
  /// 2. 通用 HTML 表格（单元格里是 `/` 分隔文本的教务系统）；
  /// 3. 整页纯文本（`TimetableParser.parseFreeText`）。
  static WebImportResult parsePayload(
    Map<String, dynamic> payload, {
    String name = '',
  }) {
    final pageUrl = '${payload['url'] ?? ''}';
    final pageTitle = '${payload['title'] ?? ''}';
    final tableHtml = '${payload['tableHtml'] ?? ''}';
    final text = '${payload['text'] ?? ''}';
    final metaText = '$pageTitle\n$text';

    // ── 路径 0：正方 jwglxt 课表 JSON 接口 ──
    // 注入脚本抓不到 DOM 表格时，会由**原生侧**（不是 JS，JS 里一律不同步发请求）
    // POST 一次真正的数据接口 `xskbcx_cxXsKb.html?doType=query&gnmkdm=N2151`，
    // 把 `kbList` 带回来：它给的是**整学期**的原始字段（`jcs` / `zcd` / `xqj`），
    // 比抠渲染后的 DOM 稳，也不受「页面上一次只画一周」的限制。
    final jsonRows = payload['jsonRows'];
    final diag = payload['diag'];
    // ignore: avoid_print
    print('NjtcImport: 载荷 表格HTML=${tableHtml.length} 文本=${text.length} '
        'jsonRows=${jsonRows is List ? jsonRows.length : 0} '
        '课程格=${payload['kbFilled'] ?? 0} '
        '页面标题=$pageTitle 接口端点=${payload['jsonEndpoint'] ?? ''} 诊断=$diag');
    if (jsonRows is List && jsonRows.isNotEmpty) {
      final courses = ZfHtmlParser.coursesFromJwglxtJson(jsonRows);
      if (courses.isNotEmpty) {
        _logParse('教务接口 jsonRows', courses);
        final pageMeta = ZfHtmlParser.extractMeta(metaText);
        final maxWeek = courses.fold<int>(
          0,
          (m, c) => c.endWeek > m ? c.endWeek : m,
        );
        final fromCodes = ZfHtmlParser.semesterFromCodes(
          '${payload['xnm'] ?? ''}',
          '${payload['xqm'] ?? ''}',
        );
        return WebImportResult(
          status: WebImportStatus.ok,
          message: '已从教务接口识别 ${courses.length} 门课',
          timetable: _buildTimetable(courses, (
            semester: pageMeta.semester.isNotEmpty
                ? pageMeta.semester
                : fromCodes,
            major: pageMeta.major,
            totalWeeks: pageMeta.totalWeeks > 0 ? pageMeta.totalWeeks : maxWeek,
            startDate: pageMeta.startDate,
          ), name),
          pageUrl: pageUrl,
          pageTitle: pageTitle,
          rawText: text,
        );
      }
    }

    // ── 路径 1：正方课表页 ──
    // 只有当至少解析出一个真实课程名时才采信：解析器在结构完全对不上时会
    // 退化成「未知课程」，那种结果不如交给下面的表格/文本兜底。
    final zfCourses = ZfHtmlParser.parseCourses(tableHtml);
    if (zfCourses.isNotEmpty && zfCourses.any((c) => c.name != '未知课程')) {
      _logParse('正方课表页 DOM', zfCourses);
      final meta = ZfHtmlParser.extractMeta(metaText);
      return WebImportResult(
        status: WebImportStatus.ok,
        message: '已识别 ${zfCourses.length} 门课',
        timetable: _buildTimetable(zfCourses, meta, name),
        pageUrl: pageUrl,
        pageTitle: pageTitle,
        rawText: text,
      );
    }

    // ── 路径 2：通用 HTML 表格（格内是 `/` 分隔文本）──
    if (tableHtml.isNotEmpty) {
      final grid = ZfHtmlParser.textGrid(tableHtml);
      if (grid.isNotEmpty) {
        final tt = TimetableParser.parseGrid(grid, name: name);
        if (tt.courses.isNotEmpty) {
          _logParse('通用网页表格', tt.courses);
          return WebImportResult(
            status: WebImportStatus.ok,
            message: '已从网页表格识别 ${tt.courses.length} 门课',
            timetable: tt,
            pageUrl: pageUrl,
            pageTitle: pageTitle,
            rawText: text,
          );
        }
      }
    }

    // ── 路径 3：整页纯文本 ──
    if (text.trim().isNotEmpty) {
      final tt = TimetableParser.parseFreeText(text, name: name);
      if (tt.courses.isNotEmpty) {
        _logParse('整页文字', tt.courses);
        return WebImportResult(
          status: WebImportStatus.ok,
          message: '已从页面文字识别 ${tt.courses.length} 门课',
          timetable: tt,
          pageUrl: pageUrl,
          pageTitle: pageTitle,
          rawText: text,
        );
      }
    }

    return WebImportResult(
      status: WebImportStatus.failed,
      message: '当前页面没有识别到课表。'
          '请在融合门户里点进「课表查询 / 我的课表」，看到课表后'
          '再点右上角「读取课表」。',
      pageUrl: pageUrl,
      pageTitle: pageTitle,
      rawText: text,
    );
  }

  /// 导入诊断日志。
  ///
  /// 只打**数量**，不打课程名与教师名 —— 用户回传日志时这些字段会被平台做隐私过滤，
  /// 而「有几门课带了教师/地点」这种计数既不含个人信息，又能一眼定位
  /// 「导入后没有老师 / 没有教室」到底是**没抓到**还是**抓到了但没显示**。
  static void _logParse(String source, List<Course> courses) {
    final teacher = courses.where((c) => c.teacher.trim().isNotEmpty).length;
    final place = courses.where((c) => c.location.trim().isNotEmpty).length;
    // ignore: avoid_print
    print('NjtcImport: 解析来源=$source 课程=${courses.length} '
        '有教师=$teacher 有地点=$place');
  }

  static Timetable _buildTimetable(
    List<Course> courses,
    ({String semester, String major, int totalWeeks, DateTime? startDate}) meta,
    String name,
  ) {
    final auto = <String>[
      if (meta.semester.isNotEmpty) meta.semester,
      if (meta.major.isNotEmpty) meta.major,
      '课表',
    ].join(' ');
    return Timetable(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.isEmpty ? auto : name,
      semester: meta.semester,
      major: meta.major,
      totalWeeks: meta.totalWeeks > 0 ? meta.totalWeeks : 20,
      startDate: meta.startDate,
      courses: courses,
    );
  }
}
