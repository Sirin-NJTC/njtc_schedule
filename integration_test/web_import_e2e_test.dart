/// 真机 / 模拟器上的「网页登录导入」端到端验证：
/// Dart `JwxtService` → MethodChannel → 原生 WebView 真正加载页面 →
/// 注入 JS 抓 HTML → 写文件回传 → Dart 解析成 `Timetable`。
///
/// 用一个**本地 HTTP 服务**喂真实的「正方教务」课表页，避免依赖校园网与账号：
/// ```bash
/// python -m http.server 8080 --directory test/fixtures
/// flutter test integration_test/web_import_e2e_test.dart -d <device-id>
/// ```
/// 模拟器里宿主机的 `127.0.0.1` 是 `10.0.2.2`。
///
/// 用例传 `autoRead: true`，所以原生侧探测到课表页后会自己点「读取课表」，
/// 不需要人工点击 —— 正常入口永远是用户手动点。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:njtc_schedule/services/jwxt_service.dart';

const String kFixtureUrl = 'http://10.0.2.2:8137/zf_xskb_list.html';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('网页登录导入：真实 WebView 抓取 → 解析成课表', (tester) async {
    expect(
      JwxtService.supported,
      isTrue,
      reason: '该用例必须在 Android 真机或模拟器上运行',
    );

    debugPrint('[E2E-WEB] 打开 $kFixtureUrl');
    final result = await JwxtService.importFromWeb(
      url: kFixtureUrl,
      autoRead: true,
    );

    debugPrint('[E2E-WEB] status=${result.status} message=${result.message}');
    debugPrint('[E2E-WEB] pageUrl=${result.pageUrl} title=${result.pageTitle}');
    debugPrint('[E2E-WEB] rawText 长度=${result.rawText.length}');
    if (result.timetable != null) {
      final tt = result.timetable!;
      debugPrint('[E2E-WEB] 课表：${tt.name} / 学期=${tt.semester} / '
          '专业=${tt.major} / 周数=${tt.totalWeeks} / 起始=${tt.startDate} / '
          '课程数=${tt.courses.length}');
      for (final c in tt.courses.take(12)) {
        debugPrint('          ${c.name} | ${c.teacher} | ${c.location} | '
            '周${c.dayOfWeek} 第${c.startSection}-${c.endSection}节 '
            '${c.startWeek}-${c.endWeek}周');
      }
    }

    expect(result.ok, isTrue, reason: result.message);
    final tt = result.timetable;
    expect(tt, isNotNull, reason: '抓到课表页后必须能解析出课表');
    expect(result.pageUrl, contains('zf_xskb_list.html'));
    expect(result.pageTitle, isNotEmpty);
    expect(result.rawText, contains('示例课程甲'));

    expect(tt!.courses, isNotEmpty);
    expect(tt.courses.length, greaterThanOrEqualTo(8));
    // 页面里的元信息（学期 / 专业）应当被一并读出来
    expect(tt.semester, contains('2026-2027'));
    expect(tt.major, contains('示例工程'));

    final course = tt.courses.firstWhere((c) => c.name.contains('示例课程甲'));
    expect(course.teacher, '示例老师A');
    expect(course.location, isNotEmpty);
    expect(course.startWeek, greaterThanOrEqualTo(1));
    expect(course.endWeek, greaterThan(course.startWeek));
    expect(course.dayOfWeek, inInclusiveRange(1, 7));
    expect(course.startSection, greaterThanOrEqualTo(1));
    // 上次成功的地址会被原生侧记住，供下次直接复用
    expect(await JwxtService.lastUrl(), contains('zf_xskb_list.html'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
