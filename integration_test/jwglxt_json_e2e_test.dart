/// 「正方 jwglxt 课表 JSON 接口」路径的端到端验证。
///
/// 与 `web_import_e2e_test.dart`（走渲染后的 DOM）互补：这里验证的是
/// **优先路径** —— 注入脚本在课表页里顺手 POST 一发
/// `xskbcx_cxXskbcxIndex.html?doType=query&gnmkdm=N2151`，把 `kbList`
/// 原始字段回传给 Dart 解析。它给的是整学期数据，比抠 DOM 稳，
/// 也不受「页面上一次只画一周」的限制。
///
/// 固件服务见 `tool/jwglxt_fixture_server.py`：
/// ```bash
/// python tool/jwglxt_fixture_server.py 8138
/// flutter test integration_test/jwglxt_json_e2e_test.dart -d <device-id>
/// ```
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:njtc_schedule/services/jwxt_service.dart';

/// 模拟器里宿主机的 `127.0.0.1` 是 `10.0.2.2`。
const String kJsonFixtureUrl =
    'http://10.0.2.2:8138/jwglxt/kbcx/xskbcx_cxXskbcxIndex.html';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('正方 jwglxt JSON 接口：注入脚本 POST 接口 → Dart 解析成课表',
      (tester) async {
    expect(
      JwxtService.supported,
      isTrue,
      reason: '该用例必须在 Android 真机或模拟器上运行',
    );

    debugPrint('[E2E-JSON] 打开 $kJsonFixtureUrl');
    final result = await JwxtService.importFromWeb(
      url: kJsonFixtureUrl,
      autoRead: true,
    );

    debugPrint('[E2E-JSON] status=${result.status} message=${result.message}');
    debugPrint('[E2E-JSON] pageUrl=${result.pageUrl} title=${result.pageTitle}');
    if (result.timetable != null) {
      final tt = result.timetable!;
      debugPrint('[E2E-JSON] 课表：学期=${tt.semester} / 周数=${tt.totalWeeks} / '
          '课程数=${tt.courses.length}');
      for (final c in tt.courses) {
        debugPrint('           ${c.name} | ${c.teacher} | ${c.location} | '
            '周${c.dayOfWeek} 第${c.startSection}-${c.endSection}节 '
            '${c.startWeek}-${c.endWeek}周 单双周=${c.oddEven}');
      }
    }

    expect(result.ok, isTrue, reason: result.message);
    // 走的是接口路径，而不是 DOM 抠字
    expect(result.message, contains('教务接口'));

    final tt = result.timetable;
    expect(tt, isNotNull, reason: '接口返回的 kbList 必须能解析成课表');
    expect(tt!.courses.length, 6, reason: '4 行 kbList，其中离散周次那行拆成 3 段');

    // 学期由 xnm=2026 + xqm=3 推出来
    expect(tt.semester, '2026-2027年第1学期');
    // 页面上没有「共 N 周」，用 max(zcd)=18 反推
    expect(tt.totalWeeks, 18);

    final ai = tt.courses.firstWhere((c) => c.name.contains('示例课程甲'));
    expect(ai.teacher, '示例老师A');
    expect(ai.location, '格致楼216');
    expect(ai.dayOfWeek, 1);
    expect(ai.startSection, 1);
    expect(ai.endSection, 2);
    expect(ai.startWeek, 7);
    expect(ai.endWeek, 18);

    // 单双周
    final physics = tt.courses.firstWhere((c) => c.name.contains('示例课程庚'));
    expect(physics.oddEven, 1);
    expect(physics.dayOfWeek, 4);

    // 离散周次 1,3,5-9 必须逐段保留，不能补空隙
    final ethics =
        tt.courses.where((c) => c.name.contains('示例课程乙')).toList();
    expect(ethics.length, 3);
    expect(
      ethics.map((c) => '${c.startWeek}-${c.endWeek}').toList(),
      ['1-1', '3-3', '5-9'],
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
