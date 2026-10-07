/// 原生 OCR 桥的端到端验证（**必须在 Android 设备/模拟器上跑**）。
///
/// ```
/// flutter test integration_test/ocr_e2e_test.dart -d <设备>
/// ```
///
/// 它盯的是 `flutter test` 覆盖不到的那一层：tesseract4android AAR 有没有打进包、
/// `assets/tessdata` 有没有复制到 `filesDir`、引擎能不能 init、PdfRenderer 能不能渲染。
///
/// * 图片那条**自带输入**：用 Flutter 自己把两行课表画成 PNG 再喂给 OCR，
///   所以不需要任何夹具，也不受分区存储限制。
/// * PDF 那条用 `test/fixtures/ocr_sample.pdf`（`tool/make_ocr_fixture.py` 生成，
///   在 `pubspec.yaml` 里作为 asset 打进包）。**为什么不 adb push**：
///   `flutter test integration_test/...` 跑之前会卸载重装 App，
///   推到 `/sdcard/...` 的夹具活不到测试开始（§9.22）。下面的目录搜索只是给
///   「手工把 App 装好、直接跑测试」这种情况留的后路。
///
/// 这条用例会把 App 卸载重装（integration_test 的常规行为），
/// **别拿装了真实课表的手机跑**，用模拟器；真机上只手工点一遍。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:njtc_schedule/services/document_parser.dart';
import 'package:njtc_schedule/services/ocr_service.dart';

/// 夹具放哪儿都行，这里按「最容易 adb push 且应用读得到」的顺序试。
const List<String> searchDirs = [
  '/storage/emulated/0/Android/data/cn.edu.njtc.njtc_schedule/files',
  '/sdcard/Android/data/cn.edu.njtc.njtc_schedule/files',
  '/sdcard/Download',
  '/storage/emulated/0/Download',
];

/// 夹具：优先读打进包里的 asset（`flutter test` 会重装 App，只有这个一定在），
/// 读不到再退到设备共享目录（手工装好 App 直接跑测试时可能用得上）。
Future<Uint8List?> loadFixture(String name) async {
  try {
    final data = await rootBundle.load('test/fixtures/$name');
    return data.buffer.asUint8List();
  } catch (_) {
    // 落下去试试共享目录
  }
  for (final dir in searchDirs) {
    final file = File('$dir/$name');
    try {
      if (await file.exists()) return await file.readAsBytes();
    } on FileSystemException {
      // 分区存储不给读就继续换下一个目录
      continue;
    }
  }
  return null;
}

/// 现场画一张「课表两行字」的 PNG（白底黑字，2 倍图，OCR 更稳）。
Future<Uint8List> renderSampleImage() async {
  const lines = [
    '星期一 高等数学 明德楼A103 (3-4节)7-18周',
    '星期二 Python程序设计 格致楼205 (5-6节)7-18周',
  ];
  const fontSize = 40.0;
  const scale = 2.0;
  const pad = 40.0;
  const lineGap = 1.7;

  final painters = [
    for (final line in lines)
      TextPainter(
        text: TextSpan(
          text: line,
          style: const TextStyle(
            fontSize: fontSize,
            color: Colors.black,
            decoration: TextDecoration.none,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
  ];

  final width = painters.map((p) => p.width).reduce((a, b) => a > b ? a : b) +
      pad * 2;
  final height = pad * 2 + fontSize * lineGap * painters.length;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(scale);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = Colors.white,
  );
  var y = pad;
  for (final p in painters) {
    p.paint(canvas, Offset(pad, y));
    y += fontSize * lineGap;
  }
  final image = await recorder
      .endRecording()
      .toImage((width * scale).round(), (height * scale).round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('info：语言模型确实随包带到了设备上', (tester) async {
    expect(OcrService.supported, isTrue, reason: '这条只能在 Android 上跑');

    final info = await OcrService.info();
    // ignore: avoid_print
    print('OCR info → $info');

    final files = (info['files'] as Map?) ?? const {};
    final langs = info['languages'] as String? ?? '';
    expect(info['tessdataDir'], isNotNull);
    expect(langs, contains('chi_sim'), reason: '默认要带中文模型');
    expect(
      files.keys.any((k) => '$k'.contains('chi_sim')),
      isTrue,
      reason: 'assets/tessdata 里的 chi_sim 应该已经在 filesDir 里：$files',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('图片 OCR：认出课表中文，并能直接解析成课程', (tester) async {
    final bytes = await renderSampleImage();
    final r = await OcrService.recognizeImage(bytes);
    // ignore: avoid_print
    print('OCR 图片 → 置信度 ${r.confidence}% ${r.width}x${r.height}\n${r.text}');

    expect(r.text.contains('高等数学'), isTrue, reason: '识别结果：${r.text}');
    expect(r.text.contains('星期一'), isTrue, reason: '识别结果：${r.text}');
    // 置信度要真拿到：曾经因为 `clear()` 取晚了而恒为 0（见 BUILD_NOTES §9.22.4）
    expect(r.confidence, greaterThan(0), reason: '置信度应当是识别出来的真实值');

    // 跑过一次之后，语言模型应该已经复制到 filesDir 了（`installed` 由 false 变 true）
    final info = await OcrService.info();
    final files = (info['files'] as Map?)?.cast<String, dynamic>();
    final chiSim = (files?['chi_sim.traineddata'] as Map?)?.cast<String, dynamic>();
    expect(chiSim?['installed'], isTrue, reason: 'tessdata 应已落盘：$files');

    final tt = DocumentParser.parse(r.text);
    expect(tt.courses, isNotEmpty, reason: 'OCR 出来的文字要能走通解析：${r.text}');
    expect(tt.courses.any((c) => c.dayOfWeek == 1), isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('PDF OCR：PdfRenderer 渲染 + 逐页识别', (tester) async {
    final bytes = await loadFixture('ocr_sample.pdf');
    if (bytes == null) {
      // ignore: avoid_print
      print('跳过 PDF 用例：没找到 ocr_sample.pdf'
          '（跑 tool/make_ocr_fixture.py 生成，再 adb push 到 ${searchDirs.first}）');
      return;
    }

    final r = await OcrService.recognizePdf(bytes);
    // ignore: avoid_print
    print('OCR PDF → 共 ${r.pages} 页，识别 ${r.recognizedPages} 页\n${r.text}');

    expect(r.pages, greaterThanOrEqualTo(1));
    expect(r.recognizedPages, greaterThanOrEqualTo(1));
    expect(r.text.contains('Python'), isTrue, reason: '识别结果：${r.text}');
    expect(r.text.contains('星期二'), isTrue, reason: '识别结果：${r.text}');
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('拿一堆不是图片的字节去识别：给中文报错而不是崩', (tester) async {
    await expectLater(
      OcrService.recognizeImage(Uint8List.fromList(List.filled(512, 0x41))),
      throwsA(isA<OcrException>()),
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
