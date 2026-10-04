import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `RemoteViews` 只认白名单里的控件类（平台里那些带 `@RemoteView` 注解的类）。
///
/// 用裸 `android.view.View` 当颜色条，宿主 inflate 时会直接抛
/// `InflateException: Class not allowed to be inflated android.view.View`
/// —— 整块小组件都画不出来，用户看到的是一张白卡。
/// v1.1.6 ~ v1.1.8 真机上的「小组件渲染失败」就是这个原因，
/// 所以这里把它变成一条会失败的测试，而不是一句注释。
///
/// 另：`android:previewLayout` / `previewImage` 也要跟着这份布局走，
/// 预览同样是宿主 inflate 的，用了 `View` 一样白。
void main() {
  /// RemoteViews 允许的控件（只列我们可能用到的那些）。
  const allowed = <String>{
    'LinearLayout',
    'FrameLayout',
    'RelativeLayout',
    'GridLayout',
    'TableLayout',
    'TableRow',
    'TextView',
    'ImageView',
    'ImageButton',
    'Button',
    'ProgressBar',
    'Chronometer',
    'Space',
    'ViewFlipper',
    'ViewStub',
    'ListView',
    'GridView',
    'StackView',
    'AdapterViewFlipper',
  };

  final layoutDir = Directory('android/app/src/main/res/layout');

  test('res/layout 存在（否则测试要在项目根目录跑）', () {
    expect(layoutDir.existsSync(), isTrue,
        reason: '找不到 ${layoutDir.path}；请用 `flutter test`（工作目录=项目根）跑');
  });

  test('小组件布局只用 RemoteViews 白名单里的控件', () {
    final files = layoutDir
        .listSync()
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.startsWith('widget_'))
        .where((f) => f.path.endsWith('.xml'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    expect(files, isNotEmpty, reason: '一个 widget_*.xml 都没找到');

    final problems = <String>[];
    final tagRe = RegExp(r'<\s*([A-Za-z][A-Za-z0-9_.]*)');
    final viewRe = RegExp(r'<\s*(?:android\.)?view\.View[\s/>]');

    for (final f in files) {
      final name = f.uri.pathSegments.last;
      final text = f.readAsStringSync();

      if (viewRe.hasMatch(text)) {
        problems.add('$name 里出现了裸 <View>：RemoteViews 不允许，'
            '宿主的 RemoteViews 白名单里没有 android.view.View（换成 ImageView / FrameLayout）。');
      }

      for (final m in tagRe.allMatches(text)) {
        final tag = m.group(1)!;
        // 跳过 `<?xml ...?>` 与注释里的东西由调用方保证；这里只认元素名。
        if (tag.startsWith('!') || tag.startsWith('?')) continue;
        final base = tag.split('.').last;
        if (!allowed.contains(base)) {
          problems.add('$name 用了 RemoteViews 不认识的控件 <$tag>');
        }
      }
    }

    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('小组件布局里不再有裸 View 的 id（bar_N 必须是白名单控件）', () {
    final f = File('android/app/src/main/res/layout/widget_today.xml');
    final text = f.readAsStringSync();
    // bar_1..bar_5 是颜色条，历史上写成 <View>，现在是 <ImageView>。
    for (var i = 1; i <= 5; i++) {
      expect(text.contains('@+id/bar_$i'), isTrue, reason: 'bar_$i 不见了？');
      final idx = text.indexOf('@+id/bar_$i');
      final before = text.substring(0, idx);
      final open = before.lastIndexOf('<');
      expect(text.substring(open, open + 10).toLowerCase(), contains('imageview'),
          reason: 'bar_$i 的标签不是 ImageView —— 又写回 <View> 了？');
    }
  });
}
