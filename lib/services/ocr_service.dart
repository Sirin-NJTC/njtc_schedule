/// 离线 OCR / PDF 识别 —— 原生桥 `cn.edu.njtc.njtc_schedule/ocr` 的 Dart 侧封装。
///
/// 为什么要自己写原生桥而不是用现成插件：见 `BUILD_NOTES.md` §9.22（pdfrx 那条路会把
/// Dart native assets / build hooks 引进构建链，Windows 上还要开发者模式，CI 很脆）。
/// 现在这套：OCR 用 JitPack 上的 Tesseract4Android（模型随 APK 走，离线、不需要
/// Google 服务，国产 ROM 也能用），PDF 用 Android 自带的 `PdfRenderer` 渲染成位图再 OCR，
/// 文字版和扫描版走同一条路，APK 只多出语言模型的体积。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// OCR 失败。`message` 是给用户看的原文（原生侧写的都是中文）。
class OcrException implements Exception {
  const OcrException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一张图片的识别结果。
class OcrImageResult {
  const OcrImageResult({
    required this.text,
    required this.confidence,
    required this.width,
    required this.height,
  });

  /// 识别出来的文字（保留词间空格，便于按列还原表格）。
  final String text;

  /// Tesseract 的平均置信度（0~100），过低时界面会提示用户核对。
  final int confidence;

  /// 实际送去识别的位图尺寸（原生侧可能降采样或放大过）。
  final int width;
  final int height;
}

/// 一份 PDF 的识别结果。
class OcrPdfResult {
  const OcrPdfResult({
    required this.text,
    required this.pages,
    required this.recognizedPages,
    required this.truncated,
  });

  final String text;

  /// PDF 总页数。
  final int pages;

  /// 本次真正识别了多少页（受 `maxPages` 限制）。
  final int recognizedPages;

  /// 是否因为页数上限被截断。
  final bool truncated;
}

/// OCR / PDF 识别的入口。
class OcrService {
  OcrService._();

  /// 原生桥通道名（测试里 mock 这个通道即可）。
  static const MethodChannel channel =
      MethodChannel('cn.edu.njtc.njtc_schedule/ocr');

  static const String channelName = 'cn.edu.njtc.njtc_schedule/ocr';

  /// 默认语言：中文简体 + 英文（楼栋号、`B213`、`Python` 这些拉丁字符）。
  static const String defaultLangs = 'chi_sim+eng';

  /// 版面模式 6 = 当作一整块文本（课表截图基本就是这个形态）。
  static const int defaultPsm = 6;

  /// 只有 Android 有这套原生桥。
  ///
  /// 单元测试跑在 Windows 上（`Platform.isAndroid` 恒 false），用
  /// [supportedOverride] 强行打开，才能把通道收发也测到。
  @visibleForTesting
  static bool? supportedOverride;

  static bool get supported => supportedOverride ?? (!kIsWeb && Platform.isAndroid);

  /// 识别一张图片（相册 / 拍照 / 截图）。
  static Future<OcrImageResult> recognizeImage(
    Uint8List bytes, {
    String langs = defaultLangs,
    int psm = defaultPsm,
  }) async {
    final map = await _invoke('recognizeImage', {
      'bytes': bytes,
      'langs': langs,
      'psm': psm,
    });
    return OcrImageResult(
      text: (map['text'] as String?) ?? '',
      confidence: (map['confidence'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
    );
  }

  /// 识别一份 PDF（文字版、扫描版都走渲染成图再 OCR）。
  static Future<OcrPdfResult> recognizePdf(
    Uint8List bytes, {
    String langs = defaultLangs,
    int psm = defaultPsm,
    int maxPages = 8,
  }) async {
    final map = await _invoke('recognizePdf', {
      'bytes': bytes,
      'langs': langs,
      'psm': psm,
      'maxPages': maxPages,
    });
    return OcrPdfResult(
      text: (map['text'] as String?) ?? '',
      pages: (map['pages'] as num?)?.toInt() ?? 0,
      recognizedPages: (map['recognizedPages'] as num?)?.toInt() ?? 0,
      truncated: (map['truncated'] as bool?) ?? false,
    );
  }

  /// 诊断信息：语言模型是否随包发出、是否已复制到 filesDir。真机排查用。
  static Future<Map<Object?, Object?>> info() async {
    if (!supported) return const {};
    final map = await channel.invokeMethod<Map<Object?, Object?>>('info');
    return map ?? const {};
  }

  static Future<Map<Object?, Object?>> _invoke(
    String method,
    Map<String, Object?> args,
  ) async {
    if (!supported) {
      throw const OcrException('这个平台不支持离线识别，请在 Android 手机上使用。');
    }
    try {
      final map = await channel.invokeMethod<Map<Object?, Object?>>(method, args);
      return map ?? const {};
    } on PlatformException catch (e) {
      throw OcrException(e.message ?? '识别失败（${e.code}）');
    } on MissingPluginException {
      throw const OcrException('OCR 组件没有装进这个安装包（请用完整版 APK 重新安装）。');
    }
  }
}
