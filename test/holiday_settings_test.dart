/// 设置页的两个显示开关 + 「法定节假日」页的交互测试。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/app_state.dart';
import 'package:njtc_schedule/models/holiday_calendar.dart';
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
  ///
  /// [calendar] 用来先把日历换成指定的一份（比如带补班日的），
  /// 省得在测试里点一堆日期选择器。
  Future<AppState> pumpHolidayPage(
    WidgetTester tester, {
    HolidayCalendar? calendar,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.init();
    if (calendar != null) {
      await state.updateHolidays(calendar);
    }

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
    testWidgets('列出合并后的假期段、补班日为空、开关默认开着', (tester) async {
      final state = await pumpHolidayPage(tester);

      expect(find.text('放假日'), findsOneWidget);
      expect(find.text('13 天 · 3 段'), findsOneWidget);
      expect(find.text('还没有补班日'), findsOneWidget);

      // 同一个节日的连续假期合并成一行：中秋 / 国庆 / 元旦
      expect(find.text('中秋节'), findsOneWidget);
      expect(find.text('国庆节'), findsOneWidget);
      expect(find.text('元旦'), findsOneWidget);
      expect(
        find.text('10月1日（周四） – 10月7日（周三） · 共 7 天'),
        findsOneWidget,
      );
      expect(
        find.text('9月25日（周五） – 9月27日（周日） · 共 3 天'),
        findsOneWidget,
      );
      // 逐个日期一行已经是过去式了
      expect(find.text('2026-10-01  周四'), findsNothing);

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

    testWidgets('删掉第一段：确认后整段消失并存盘', (tester) async {
      final state = await pumpHolidayPage(tester);
      expect(state.holidays.holidays.length, 13);

      // 第一段是中秋（3 天），删除时整段一起走
      await tester.tap(find.byTooltip('删除').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('删掉「中秋节」'), findsOneWidget);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(state.holidays.holidays.length, 10);
      expect(find.text('10 天 · 2 段'), findsOneWidget);
      expect(find.text('中秋节'), findsNothing);
      expect((await HolidayStore.load()).holidays.length, 10);
    });

    testWidgets('取消删除时什么都不会变', (tester) async {
      final state = await pumpHolidayPage(tester);

      await tester.tap(find.byTooltip('删除').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(state.holidays.holidays.length, 13);
    });

    testWidgets('「恢复内置」把删掉的整段加回来', (tester) async {
      final state = await pumpHolidayPage(tester);

      await tester.tap(find.byTooltip('删除').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(state.holidays.holidays.length, 10);

      await tester.tap(find.text('恢复内置'));
      await tester.pumpAndSettle();
      // 恢复是会覆盖用户改动的，所以也要二次确认（按钮写「恢复」而不是「删除」）
      expect(find.textContaining('恢复成内置'), findsOneWidget);
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();

      expect(state.holidays.holidays.length, 13);
      expect(find.text('13 天 · 3 段'), findsOneWidget);
    });
  });

  group('法定节假日页 → 假期时长自主调整', () {
    /// 打开某一行的区间编辑器。
    Future<void> openEditor(WidgetTester tester, String name) async {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(find.text('调整假期'), findsOneWidget);
    }

    testWidgets('点一行能打开编辑器，延长两天后这行变成 9 天', (tester) async {
      final state = await pumpHolidayPage(tester);
      await openEditor(tester, '国庆节');

      expect(find.text('时长：7 天'), findsOneWidget);

      await tester.tap(find.byTooltip('延长一天'));
      await tester.pumpAndSettle();
      expect(find.text('时长：8 天'), findsOneWidget);
      await tester.tap(find.byTooltip('延长一天'));
      await tester.pumpAndSettle();
      expect(find.text('时长：9 天'), findsOneWidget);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(state.holidays.holidays.length, 15);
      expect(
        find.text('10月1日（周四） – 10月9日（周五） · 共 9 天'),
        findsOneWidget,
      );
      expect(find.textContaining('现在是 10月1日 – 10月9日，共 9 天'), findsOneWidget);
      expect(state.holidayMeta.source, HolidayStore.sourceManual);
    });

    testWidgets('缩短一天：国庆 7 天 → 6 天，多出来的那天不再放假', (tester) async {
      final state = await pumpHolidayPage(tester);
      await openEditor(tester, '国庆节');

      await tester.tap(find.byTooltip('缩短一天'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(state.holidays.holidays.length, 12);
      expect(state.holidays.isHoliday(DateTime(2026, 10, 7)), isFalse);
      expect(find.text('12 天 · 3 段'), findsOneWidget);
    });

    testWidgets('时长最短只能到 1 天', (tester) async {
      await pumpHolidayPage(tester);
      await openEditor(tester, '元旦');

      expect(find.text('时长：3 天'), findsOneWidget);
      await tester.tap(find.byTooltip('缩短一天'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('缩短一天'));
      await tester.pumpAndSettle();
      expect(find.text('时长：1 天'), findsOneWidget);

      // 到 1 天时「缩短一天」按钮被禁用
      final buttons = tester
          .widgetList<IconButton>(find.byType(IconButton))
          .where((b) => b.tooltip == '缩短一天');
      expect(buttons.single.onPressed, isNull);
    });

    testWidgets('原样保存会提示「没有改动」', (tester) async {
      final state = await pumpHolidayPage(tester);
      await openEditor(tester, '国庆节');

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 测试环境下提醒排不上，SnackBar 后面会跟一句说明，所以用 textContaining
      expect(find.textContaining('没有改动'), findsOneWidget);
      expect(state.holidays.holidays.length, 13);
    });

    testWidgets('改名字：同一段假期换个名字显示', (tester) async {
      final state = await pumpHolidayPage(tester);
      await openEditor(tester, '中秋节');

      await tester.enterText(find.byType(TextField), '中秋 + 校庆');
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(state.holidays.holidays.length, 13);
      expect(find.text('中秋 + 校庆'), findsOneWidget);
      expect(find.text('中秋节'), findsNothing);
    });

    testWidgets('「删除这一段」先二次确认，再整段拿走', (tester) async {
      final state = await pumpHolidayPage(tester);

      await openEditor(tester, '国庆节');
      await tester.tap(find.text('删除这一段'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('删掉「国庆节」（10月1日（周四） – 10月7日（周三）'),
        findsOneWidget,
      );
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(state.holidays.holidays.length, 6);
      expect(find.text('6 天 · 2 段'), findsOneWidget);
      expect(find.text('国庆节'), findsNothing);
    });

    testWidgets('把中秋往后延到 10 月 1 日：那天改归中秋，国庆只剩 6 天', (tester) async {
      final state = await pumpHolidayPage(tester);

      await openEditor(tester, '中秋节');
      // 09-25 ~ 09-27，往后延 4 天就吃到国庆第一天
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('延长一天'));
        await tester.pumpAndSettle();
      }
      expect(find.text('时长：7 天'), findsOneWidget);
      expect(find.textContaining('与「国庆节」重叠'), findsOneWidget);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 中秋多出 4 天、国庆少 1 天，10-01 只是换了主人
      expect(state.holidays.holidays.length, 16);
      expect(find.text('16 天 · 3 段'), findsOneWidget);
      expect(state.holidays.holidayName(DateTime(2026, 10, 1)), '中秋节');
      expect(state.holidays.holidayRanges[1].name, '国庆节');
      expect(state.holidays.holidayRanges[1].dayCount, 6);
      expect(
        find.text('9月25日（周五） – 10月1日（周四） · 共 7 天'),
        findsOneWidget,
      );
      expect(
        find.text('10月2日（周五） – 10月7日（周三） · 共 6 天'),
        findsOneWidget,
      );
      expect(state.holidays.holidayRanges.length, 3);
    });

    testWidgets('编辑器会提示将删掉几条补班安排', (tester) async {
      final base = HolidayCalendar.builtin().copyWith(makeups: [
        MakeupDay(DateTime(2026, 10, 8), 4, '联网：国庆节后补班'),
      ]);
      final state = await pumpHolidayPage(tester, calendar: base);
      expect(state.holidays.makeups.length, 1);

      await openEditor(tester, '国庆节');
      // 结束日期 10-07 → 10-08，正好压到补班那天
      await tester.tap(find.byTooltip('延长一天'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('这段里 1 天排了补班'),
        findsOneWidget,
      );

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(state.holidays.holidays.length, 14);
      expect(state.holidays.makeups, isEmpty);
      expect(find.text('还没有补班日'), findsOneWidget);
    });

    testWidgets('「添加假期」默认一天，保存后多出一段', (tester) async {
      final state = await pumpHolidayPage(tester);
      final before = state.holidays.holidayRanges.length;

      await tester.tap(find.text('添加假期'));
      await tester.pumpAndSettle();
      expect(find.text('时长：1 天'), findsOneWidget);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(state.holidays.holidayRanges.length, before + 1);
      expect(find.text('法定节假日'), findsOneWidget);
    });

    // 复查 F2：原样保存曾经照样把存档重写一遍，还把 source 盖上「手动调整过」，
    // 导致联网更新从此再也不覆盖这份日历。
    testWidgets('原样保存不动存档、也不标「手动调整过」', (tester) async {
      final state = await pumpHolidayPage(tester);
      expect(state.holidayMeta.source, HolidayStore.sourceBuiltin);

      await openEditor(tester, '国庆节');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.textContaining('没有改动'), findsOneWidget);
      expect(state.holidayMeta.source, HolidayStore.sourceBuiltin,
          reason: '不能变成「手动调整过」，否则联网更新再也覆盖不了这份日历');
      final stored = await HolidayStore.load();
      final oct2 = stored.holidays.firstWhere(
        (h) => epochDayOf(h.date) == epochDayOf(DateTime(2026, 10, 2)),
      );
      expect(oct2.name, '国庆节假期', reason: '存档里的名字不该被归一化写回');
    });

    // 复查 F3：把「开始」选到「结束」之后，整段曾被悄悄压成 1 天。
    testWidgets('改「开始」日期会保持时长，不会压成 1 天', (tester) async {
      final state = await pumpHolidayPage(tester);
      await openEditor(tester, '国庆节');
      expect(find.text('时长：7 天'), findsOneWidget);

      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.text('时长：7 天'), findsOneWidget);
      expect(find.text('2026-10-26  周一'), findsOneWidget,
          reason: '开始挪到 10-20，结束跟着挪到 10-26');
      expect(state.holidays.holidays.length, 13, reason: '还没保存');
    });

    // 复查 F1：延长吃掉国庆第一天之后再删掉中秋，10-01 要还给国庆。
    testWidgets('删掉接管过的那一段：确认框说明会还给国庆，数据也真的还了', (tester) async {
      final state = await pumpHolidayPage(tester);

      await openEditor(tester, '中秋节');
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('延长一天'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(state.holidays.holidays.length, 16);
      expect(state.holidays.holidayName(DateTime(2026, 10, 1)), '中秋节');

      await tester.tap(find.byTooltip('删除').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('其中 1 天是接管来的，会还给国庆节'),
        findsOneWidget,
      );

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(state.holidays.holidays.length, 10);
      expect(find.text('10 天 · 2 段'), findsOneWidget);
      expect(state.holidays.holidayName(DateTime(2026, 10, 1)), '国庆节');
      expect(state.holidays.holidayRanges[0].dayCount, 7,
          reason: '国庆又是完整七天');
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
      expect(state.holidays.holidays.length, 10);
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
