/// 设置页的两个显示开关 + 「法定节假日」页的交互测试。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/app_state.dart';
import 'package:njtc_schedule/pages/holiday_settings_page.dart';
import 'package:njtc_schedule/pages/settings_page.dart';
import 'package:njtc_schedule/services/holiday_sync_service.dart';
import 'package:njtc_schedule/storage/holiday_store.dart';
import 'package:njtc_schedule/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> pumpSettings(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.init();

    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        home: const SettingsPage(),
        routes: {'/holidays': (_) => const HolidaySettingsPage()},
      ),
    ));
    await tester.pumpAndSettle();
    return state;
  }

  group('设置页 → 课表显示', () {
    testWidgets('两个开关都在，默认显示周末、只显示本周课程', (tester) async {
      final state = await pumpSettings(tester);

      expect(find.text('课表显示'), findsOneWidget);
      expect(find.text('显示周六 / 周日'), findsOneWidget);
      expect(find.text('显示非本周课程'), findsOneWidget);

      final switches = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      // 第一个是周末开关（true），第二个是非本周课程（false）
      expect(switches.first.value, isTrue);
      expect(switches.elementAt(1).value, isFalse);
      expect(state.displayPrefs.showWeekend, isTrue);
      expect(state.displayPrefs.showInactiveCourses, isFalse);
    });

    testWidgets('关掉周末开关会立刻存进 AppState', (tester) async {
      final state = await pumpSettings(tester);

      await tester.tap(find.text('显示周六 / 周日'));
      await tester.pumpAndSettle();

      expect(state.displayPrefs.showWeekend, isFalse);
      expect(state.displayPrefs.showInactiveCourses, isFalse);
      // 界面上的开关也要跟着变
      final switches = tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(switches.first.value, isFalse);
    });

    testWidgets('打开「显示非本周课程」不影响周末开关', (tester) async {
      final state = await pumpSettings(tester);

      await tester.tap(find.text('显示非本周课程'));
      await tester.pumpAndSettle();

      expect(state.displayPrefs.showInactiveCourses, isTrue);
      expect(state.displayPrefs.showWeekend, isTrue);
    });
  });

  group('设置页 → 法定节假日入口', () {
    testWidgets('入口显示当前日历摘要，点进去是节假日页', (tester) async {
      await pumpSettings(tester);

      expect(find.text('法定节假日'), findsOneWidget);
      expect(find.textContaining('放假 13 天'), findsOneWidget);
      expect(find.textContaining('放假不提醒'), findsOneWidget);

      await tester.tap(find.text('法定节假日'));
      await tester.pumpAndSettle();

      expect(find.byType(HolidaySettingsPage), findsOneWidget);
      expect(find.text('节假日关闭通知'), findsOneWidget);
    });
  });

  /// 直接把节假日设置页当首页撑起来（顶部没有 SettingsPage，省一次导航）。
  Future<AppState> pumpHolidayPage(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.init();

    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        home: const HolidaySettingsPage(),
      ),
    ));
    await tester.pumpAndSettle();
    return state;
  }

  group('法定节假日页', () {
    testWidgets('列出内置放假日、补班日为空、开关默认开着', (tester) async {
      final state = await pumpHolidayPage(tester);

      expect(find.text('放假日'), findsOneWidget);
      expect(find.text('13 天'), findsOneWidget);
      expect(find.text('还没有补班日'), findsOneWidget);

      // 国庆第一天那一行
      expect(find.text('2026-10-01  周四'), findsOneWidget);
      expect(find.text('国庆节'), findsOneWidget);

      final switchTile = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(switchTile.value, isTrue);
      expect(state.reminderPrefs.skipHolidays, isTrue);
    });

    testWidgets('关掉「放假当天不提醒」会写进提醒偏好', (tester) async {
      final state = await pumpHolidayPage(tester);

      await tester.tap(find.text('放假当天不提醒'));
      await tester.pumpAndSettle();

      expect(state.reminderPrefs.skipHolidays, isFalse);
      final switchTile = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(switchTile.value, isFalse);
    });

    testWidgets('删掉一天：确认后列表少一天并存盘', (tester) async {
      final state = await pumpHolidayPage(tester);
      expect(state.holidays.holidays.length, 13);

      await tester.tap(find.byTooltip('删除').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('？'), findsOneWidget);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(state.holidays.holidays.length, 12);
      expect(find.text('12 天'), findsOneWidget);
      expect((await HolidayStore.load()).holidays.length, 12);
    });

    testWidgets('取消删除时什么都不会变', (tester) async {
      final state = await pumpHolidayPage(tester);

      await tester.tap(find.byTooltip('删除').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(state.holidays.holidays.length, 13);
    });

    testWidgets('「恢复内置」把删掉的那天加回来', (tester) async {
      final state = await pumpHolidayPage(tester);

      await tester.tap(find.byTooltip('删除').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(state.holidays.holidays.length, 12);

      await tester.tap(find.text('恢复内置'));
      await tester.pumpAndSettle();
      // 恢复是会覆盖用户改动的，所以也要二次确认（按钮写「恢复」而不是「删除」）
      expect(find.textContaining('恢复成内置'), findsOneWidget);
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();

      expect(state.holidays.holidays.length, 13);
      expect(find.text('13 天'), findsOneWidget);
    });
  });

  group('节假日页 → 联网更新', () {
    final json2026 = File('test/fixtures/holiday_2026.json').readAsStringSync();
    final json2027 = File('test/fixtures/holiday_2027.json').readAsStringSync();

    tearDown(() => HolidaySyncService.getOverride = null);

    testWidgets('卡片上写着数据来源与天数（默认是内置估算值）', (tester) async {
      await pumpHolidayPage(tester);

      expect(find.text('联网更新'), findsOneWidget);
      expect(find.text('立即联网更新'), findsOneWidget);
      expect(
        find.text('内置估算值，建议联网更新 · 放假 13 天 · 补班 0 天'),
        findsOneWidget,
      );
    });

    testWidgets('点「立即联网更新」后换成官方数据并记下来源与时间', (tester) async {
      HolidaySyncService.getOverride =
          (uri) async => uri.path.endsWith('/2026') ? json2026 : json2027;
      final state = await pumpHolidayPage(tester);

      await tester.tap(find.text('立即联网更新'));
      await tester.pumpAndSettle();

      // 2026 年换成官方 33 天 + 6 天补班；内置里 2027 年那 3 天留着
      expect(state.holidays.holidays.length, 36);
      expect(state.holidays.makeups.length, 6);
      expect(state.holidayMeta.source, HolidayStore.sourceNet);
      expect(state.holidayMeta.updatedAt, isNotNull);
      expect(
        find.textContaining('来自联网更新（'),
        findsOneWidget,
      );
      expect(
        find.textContaining('放假 36 天 · 补班 6 天'),
        findsWidgets, // 卡片副标题与 SnackBar 各一处
      );
      expect(
        find.textContaining('已联网更新（2026 年）'),
        findsOneWidget,
      );
    });

    testWidgets('联网失败：日历原样不动，SnackBar 说明原因', (tester) async {
      HolidaySyncService.getOverride =
          (uri) async => throw const SocketException('没有网络');
      final state = await pumpHolidayPage(tester);

      await tester.tap(find.text('立即联网更新'));
      await tester.pumpAndSettle();

      expect(state.holidays.holidays.length, 13);
      expect(state.holidayMeta.source, HolidayStore.sourceBuiltin);
      expect(find.textContaining('联网更新失败'), findsOneWidget);
      expect(find.textContaining('日历保持原样'), findsOneWidget);
    });

    testWidgets('手动改过之后再联网：先问一句要不要覆盖', (tester) async {
      HolidaySyncService.getOverride =
          (uri) async => uri.path.endsWith('/2026') ? json2026 : json2027;
      final state = await pumpHolidayPage(tester);

      // 手动删一天 → 来源变成 manual
      await tester.tap(find.byTooltip('删除').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(state.holidayMeta.source, HolidayStore.sourceManual);

      await tester.tap(find.text('立即联网更新'));
      await tester.pumpAndSettle();
      // 卡片说明里也有「整年替换」，所以这里只断言出现过
      expect(find.textContaining('整年替换'), findsWidgets);

      // 选「取消」→ 什么都没更新
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(state.holidays.holidays.length, 12);
      expect(state.holidayMeta.source, HolidayStore.sourceManual);

      // 再来一次，这回点「继续」
      await tester.tap(find.text('立即联网更新'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(state.holidays.holidays.length, 36);
      expect(state.holidayMeta.source, HolidayStore.sourceNet);
    });
  });
}
