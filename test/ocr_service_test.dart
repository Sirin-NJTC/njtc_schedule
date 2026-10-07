/// OCR 原生桥的 Dart 侧：参数怎么递过去、原生错误怎么变成给用户看的中文。
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/services/ocr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  /// 把通道换成「假原生」：记录调用，返回给定结果。
  void mock(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(OcrService.channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    calls.clear();
    // 单元测试跑在 Windows 上，平台判断得先打开才能走到通道
    OcrService.supportedOverride = true;
  });

  tearDown(() {
    OcrService.supportedOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(OcrService.channel, null);
  });

  test('recognizeImage：字节 + 语言 + 版面模式递过去，文字与置信度带回来', () async {
    mock((call) async => <Object?, Object?>{
          'text': '星期一 高等数学 明德楼A103',
          'confidence': 87.4,
          'width': 1200,
          'height': 900,
        });

    final r = await OcrService.recognizeImage(Uint8List.fromList([1, 2, 3]));

    expect(r.text, '星期一 高等数学 明德楼A103');
    expect(r.confidence, 87, reason: '原生给 double 也要能收（取整）');
    expect(r.width, 1200);
    expect(r.height, 900);

    expect(calls.single.method, 'recognizeImage');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['bytes'], Uint8List.fromList([1, 2, 3]));
    expect(args['langs'], 'chi_sim+eng');
    expect(args['psm'], 6);
  });

  test('recognizeImage 可以指定语言与版面模式', () async {
    mock((call) async => <Object?, Object?>{'text': ''});
    final r = await OcrService.recognizeImage(
      Uint8List.fromList([9]),
      langs: 'chi_sim',
      psm: 4,
    );
    expect(r.text, '');
    expect(r.confidence, 0, reason: '原生没给置信度时按 0 处理，不能崩');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['langs'], 'chi_sim');
    expect(args['psm'], 4);
  });

  test('recognizePdf：页数、截断标记都带回来', () async {
    mock((call) async => <Object?, Object?>{
          'text': '星期一 大学英语',
          'pages': 12,
          'recognizedPages': 8,
          'truncated': true,
        });

    final r = await OcrService.recognizePdf(Uint8List.fromList([1]));

    expect(r.text, contains('大学英语'));
    expect(r.pages, 12);
    expect(r.recognizedPages, 8);
    expect(r.truncated, isTrue);
    expect(calls.single.method, 'recognizePdf');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['maxPages'], 8);
  });

  test('原生报错 → OcrException，message 原样给用户看', () async {
    mock((call) async => throw PlatformException(
          code: 'ocr_failed',
          message: 'OCR 引擎初始化失败：语言模型 chi_sim 没能加载',
        ));

    await expectLater(
      OcrService.recognizeImage(Uint8List.fromList([1])),
      throwsA(isA<OcrException>().having(
        (e) => e.message,
        'message',
        contains('语言模型 chi_sim'),
      )),
    );
  });

  test('原生没实现这个方法 → 提示「组件没装进安装包」', () async {
    mock((call) async => throw MissingPluginException('no impl'));

    await expectLater(
      OcrService.recognizeImage(Uint8List.fromList([1])),
      throwsA(isA<OcrException>().having(
        (e) => e.message,
        'message',
        contains('OCR 组件没有装进这个安装包'),
      )),
    );
  });

  test('info：诊断信息透传', () async {
    mock((call) async => <Object?, Object?>{
          'tessdataDir': '/data/user/0/xx/files/tessdata',
          'models': ['chi_sim 13077423 B', 'eng 4113088 B'],
          'langs': 'chi_sim+eng',
        });

    final info = await OcrService.info();
    expect(info['langs'], 'chi_sim+eng');
    expect(info['models'], contains('chi_sim 13077423 B'));
    expect(calls.single.method, 'info');
  });

  test('不支持的平台直接给中文提示，不去打通道', () async {
    OcrService.supportedOverride = false;
    mock((call) async => <Object?, Object?>{});

    await expectLater(
      OcrService.recognizeImage(Uint8List.fromList([1])),
      throwsA(isA<OcrException>().having(
        (e) => e.message,
        'message',
        contains('请在 Android 手机上使用'),
      )),
    );
    expect(await OcrService.info(), isEmpty);
    expect(calls, isEmpty);
  });
}
