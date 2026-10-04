/// 课表显示偏好（显示周六日 / 显示非本周课程）：模型 / 存储 / AppState。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/app_state.dart';
import 'package:njtc_schedule/models/display_prefs.dart';
import 'package:njtc_schedule/storage/display_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DisplayPrefs', () {
    test('默认显示周末、只显示本周课程', () {
      final p = DisplayPrefs();
      expect(p.showWeekend, isTrue);
      expect(p.showInactiveCourses, isFalse);
      expect(p.summaryText, '显示周六日 · 只显示本周课程');
    });

    test('summaryText 跟着两个开关变', () {
      expect(
        DisplayPrefs(showWeekend: false).summaryText,
        '只看周一到周五 · 只显示本周课程',
      );
      expect(
        DisplayPrefs(showInactiveCourses: true).summaryText,
        '显示周六日 · 显示非本周课程',
      );
      expect(
        DisplayPrefs(showWeekend: false, showInactiveCourses: true).summaryText,
        '只看周一到周五 · 显示非本周课程',
      );
    });

    test('copyWith 能显式关掉，也能只改一个', () {
      final p = DisplayPrefs();
      // 关键：显式传 false 不能被 ?? 吃掉
      expect(p.copyWith(showWeekend: false).showWeekend, isFalse);
      expect(p.copyWith(showWeekend: false).showInactiveCourses, isFalse);
      final q = p.copyWith(showInactiveCourses: true);
      expect(q.showInactiveCourses, isTrue);
      expect(q.showWeekend, isTrue);
    });

    test('toString 带上两个字段', () {
      final s = DisplayPrefs().toString();
      expect(s, contains('showWeekend: true'));
      expect(s, contains('showInactiveCourses: false'));
    });
  });

  group('DisplayStore', () {
    test('没存过时是默认值', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await DisplayStore.load();
      expect(p.showWeekend, isTrue);
      expect(p.showInactiveCourses, isFalse);
    });

    test('存了再读一致（两个开关都改）', () async {
      SharedPreferences.setMockInitialValues({});
      await DisplayStore.save(
        DisplayPrefs(showWeekend: false, showInactiveCourses: true),
      );
      final back = await DisplayStore.load();
      expect(back.showWeekend, isFalse);
      expect(back.showInactiveCourses, isTrue);
    });

    test('只存了周末开关时，另一个回到默认', () async {
      SharedPreferences.setMockInitialValues({
        'njtc_display_show_weekend': false,
      });
      final back = await DisplayStore.load();
      expect(back.showWeekend, isFalse);
      expect(back.showInactiveCourses, isFalse);
    });
  });

  group('AppState 显示偏好', () {
    test('init 后是默认值，updateDisplayPrefs 会存盘并通知', () async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState();
      await state.init();
      expect(state.displayPrefs.showWeekend, isTrue);

      var notified = 0;
      state.addListener(() => notified++);

      await state.updateDisplayPrefs(
        state.displayPrefs.copyWith(showWeekend: false),
      );

      expect(notified, 1, reason: '只通知一次，别重复刷界面');
      expect(state.displayPrefs.showWeekend, isFalse);

      // 落盘了：换一个实例重新读也是关掉的
      final again = AppState();
      await again.init();
      expect(again.displayPrefs.showWeekend, isFalse);
      expect(await DisplayStore.load(), isNotNull);
      final stored = await DisplayStore.load();
      expect(stored.showWeekend, isFalse);
    });

    test('两个开关互不影响', () async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState();
      await state.init();

      await state.updateDisplayPrefs(
        state.displayPrefs.copyWith(showInactiveCourses: true),
      );
      expect(state.displayPrefs.showInactiveCourses, isTrue);
      expect(state.displayPrefs.showWeekend, isTrue, reason: '周末开关不该被顺手改掉');
    });
  });
}
