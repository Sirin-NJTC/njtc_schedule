/// 「反向代理部署」形态的端到端验证 —— 内江师范真实形态。
///
/// 前面两条 E2E 分别验证了：
///   * `web_import_e2e_test.dart`   —— 抠渲染后的 DOM（9 门课）
///   * `jwglxt_json_e2e_test.dart`  —— 常规部署 `/jwglxt/kbcx/xskbcx_cxXskbcxIndex.html`
///                                     推接口端点 → POST kbList（6 门课）
///
/// 但学校实际给的是**反向代理**地址：
/// `https://jxglpt-xxx.proxy.njtc.edu.cn/sso/driotlogin?url=kbcx%252Fxskbcx_cxXskbcxIndex.html%253Fgnmkdm%253DN2151`
/// 路径里**没有 `/kbcx/` 那一段**（老代码就是在这里 `return null`，于是永远
/// 拿不到接口数据、只能退化成抠 DOM，教师/地点整列都丢）。这条路的端点要从
/// `url=` 参数里**解两遍百分号编码**再拼出来 —— 之前只在 jsdom 里验过推导，
/// 真 WebView 上一次都没跑过，所以补这条。
///
/// 两个用例覆盖代理的两种落地方式：
///   1. `/sso/driotlogin`   —— 登录接口原地吐课表页，`url=` 参数还在（走解码分支）
///   2. `/sso/driotlogin_r` —— 302 跳到 `/kbcx/xskbcx_cxXskbcxIndex.html`
///                             （跳完参数没了，只能靠路径推，走 pathname 分支）
/// 两条路必须推出**同一个**数据接口 `/kbcx/xskbcx_cxXsKb.html`。
///
/// 固件服务见 `tool/jwglxt_fixture_server.py`（其中的 `/__posts`、`/__reset`
/// 是专给这个测试用的观察口：把服务端收到的 POST 路径读回来，证明「打的确实是
/// 推导出来的数据接口，而不是把 POST 发到页面地址上」）：
/// ```bash
/// python tool/jwglxt_fixture_server.py 8138
/// flutter test integration_test/jwglxt_proxy_e2e_test.dart -d <device-id>
/// ```
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:njtc_schedule/services/jwxt_service.dart';

/// 固件服务的地址：
///   * 模拟器：宿主机的 `127.0.0.1` 就是 `10.0.2.2`（默认值）
///   * **真机**：先 `adb reverse tcp:8138 tcp:8138`，再
///     `--dart-define=FIXTURE_HOST=http://127.0.0.1:8138`
const String kHost = String.fromEnvironment(
  'FIXTURE_HOST',
  defaultValue: 'http://10.0.2.2:8138',
);

/// 反向代理形态：真地址在 `url=` 里，且是**双层**百分号编码
/// （`%252F` 解一遍是 `%2F`，解两遍才是 `/`）。
const String kProxyDirectUrl = '$kHost/sso/driotlogin'
    '?url=kbcx%252Fxskbcx_cxXskbcxIndex.html%253Fgnmkdm%253DN2151';

/// 同一个代理，但登录完是 302 跳到真正的课表页。
const String kProxyRedirectUrl = '$kHost/sso/driotlogin_r';

/// 两种形态都应该推导出来的数据接口（正方约定：页面 `_cxXskbcxIndex.html`，
/// 数据接口 `_cxXsKb.html`）。
const String kExpectedDataEndpoint = '/kbcx/xskbcx_cxXsKb.html';

Future<void> _resetPosts() async {
  final r = await http.get(Uri.parse('$kHost/__reset'));
  expect(r.statusCode, 200, reason: '固件服务的 /__reset 必须可用');
}

Future<List<String>> _readPosts() async {
  final r = await http.get(Uri.parse('$kHost/__posts'));
  expect(r.statusCode, 200, reason: '固件服务的 /__posts 必须可用');
  final body = jsonDecode(r.body) as Map<String, dynamic>;
  return (body['posts'] as List).cast<String>();
}

/// 两条路共用的断言：接口路径生效、6 门课、且**服务端收到的第一个 POST
/// 就是推导出来的数据接口**。
Future<void> _expectInterfaceImport(String url) async {
  debugPrint('[E2E-PROXY] 打开 $url');
  final result = await JwxtService.importFromWeb(url: url, autoRead: true);

  debugPrint('[E2E-PROXY] status=${result.status} message=${result.message}');
  debugPrint('[E2E-PROXY] pageUrl=${result.pageUrl} title=${result.pageTitle}');
  final posts = await _readPosts();
  debugPrint('[E2E-PROXY] 固件服务收到的 POST 路径=$posts');

  expect(result.ok, isTrue, reason: result.message);
  // 必须走接口路径，而不是退化成抠 DOM（退化的话教师/地点会丢）
  expect(result.message, contains('教务接口'));

  // 端点推导正确：第一个尝试的就是数据接口，而不是页面地址
  expect(
    posts,
    isNotEmpty,
    reason: '接口路径必须真的发出 POST（空 = 又退化成只抠 DOM 了）',
  );
  expect(
    posts.first,
    kExpectedDataEndpoint,
    reason: '反向代理的接口端点必须从 url= 参数解两遍码推出来',
  );

  final tt = result.timetable;
  expect(tt, isNotNull, reason: '接口返回的 kbList 必须能解析成课表');
  expect(tt!.courses.length, 6, reason: '4 行 kbList，离散周次那行拆成 3 段');
  expect(tt.semester, '2026-2027年第1学期'); // xnm=2026 + xqm=3
  expect(tt.totalWeeks, 18); // 页面没写「共 N 周」，用 max(zcd) 反推

  final ai = tt.courses.firstWhere((c) => c.name.contains('人工智能导论'));
  expect(ai.teacher, '韩云');
  expect(ai.location, '明德楼B216');
  expect(ai.dayOfWeek, 1);
  expect(ai.startSection, 1);
  expect(ai.endSection, 2);
  expect(ai.startWeek, 7);
  expect(ai.endWeek, 18);

  final physics = tt.courses.firstWhere((c) => c.name.contains('大学物理'));
  expect(physics.oddEven, 1);
  expect(physics.dayOfWeek, 4);

  final ethics =
      tt.courses.where((c) => c.name.contains('思想道德与法治')).toList();
  expect(ethics.map((c) => '${c.startWeek}-${c.endWeek}').toList(),
      ['1-1', '3-3', '5-9']);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('反向代理（原地吐页面，url= 参数还在）：解两遍码推出接口端点 → 拿到整学期课',
      (tester) async {
    expect(JwxtService.supported, isTrue,
        reason: '该用例必须在 Android 真机或模拟器上运行');
    await _resetPosts();
    await _expectInterfaceImport(kProxyDirectUrl);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('反向代理（302 跳到课表页，url= 参数丢了）：靠路径推出同一个接口端点',
      (tester) async {
    expect(JwxtService.supported, isTrue,
        reason: '该用例必须在 Android 真机或模拟器上运行');
    await _resetPosts();
    await _expectInterfaceImport(kProxyRedirectUrl);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
