/// 节次时间自定义的测试：模型 / 存储 / AppState / 设置页入口。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/app_state.dart';
import 'package:njtc_schedule/models/period.dart';
import 'package:njtc_schedule/pages/period_settings_page.dart';
import 'package:njtc_schedule/pages/settings_page.dart';
import 'package:njtc_schedule/storage/period_store.dart';
import 'package:njtc_schedule/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 每个用例前把全局节次表复位，避免用例之间互相污染。
  setUp(resetActivePeriods);

  group('Period 编解码', () {
    test('encode / decode 往返一致', () {
      const p = Period(
        section: 3,
        label: '第3节',
        startHour: 10,
        startMinute: 0,
        endHour: 10,
        endMinute: 45,
      );
      expect(p.encode(), '10:00-10:45');

      final back = Period.decode(3, '10:00-10:45');
      expect(back, isNotNull);
      expect(back!.section, 3);
      expect(back.label, '第3节');
      expect(back.startHour, 10);
      expect(back.startMinute, 0);
      expect(back.endHour, 10);
      expect(back.endMinute, 45);
    });

    test('格式不对或时间越界时返回 null', () {
      // 一位数的小时也认（教务导出里 `8:00` 和 `08:00` 都常见）
      final lenient = Period.decode(1, '8:00-8:45');
      expect(lenient, isNotNull);
      expect(lenient!.startHour, 8);
      expect(lenient.encode(), '08:00-08:45', reason: '回写时补前导 0');

      expect(Period.decode(1, '08:00~08:45'), isNull); // 分隔符不对
      expect(Period.decode(1, 'abc'), isNull);
      expect(Period.decode(1, '24:00-25:00'), isNull); // 时越界
      expect(Period.decode(1, '08:60-09:00'), isNull); // 分越界
      expect(Period.decode(1, '08:00-08:45-08:50'), isNull); // 多了一段
      expect(Period.decode(1, ' 08:00-08:45 '), isNotNull); // 两侧空格容忍
    });

    test('withTime 只换时间，保留节次与标签', () {
      final p = defaultPeriods[4]; // 第5节 14:20-15:05
      final q = p.withTime(
        startHour: 14,
        startMinute: 0,
        endHour: 14,
        endMinute: 45,
      );
      expect(q.section, 5);
      expect(q.label, '第5节');
      expect(q.encode(), '14:00-14:45');
      expect(p.encode(), '14:20-15:05', reason: '原对象不应被改动');
    });
  });

  group('normalizePeriods / activePeriods', () {
    test('长度不足时按节次补齐默认值', () {
      final list = normalizePeriods([
        const Period(
          section: 1,
          label: '第1节',
          startHour: 9,
          startMinute: 10,
          endHour: 9,
          endMinute: 55,
        ),
      ]);
      expect(list.length, defaultPeriods.length);
      expect(list.first.encode(), '09:10-09:55'); // 传进来的那条生效
      expect(list[1].encode(), defaultPeriods[1].encode()); // 其余回落默认
    });

    test('越界时间被夹到合法范围', () {
      final list = normalizePeriods([
        const Period(
          section: 2,
          label: '第2节',
          startHour: 30,
          startMinute: 99,
          endHour: 40,
          endMinute: 70,
        ),
      ]);
      expect(list[1].startHour, 23);
      expect(list[1].startMinute, 59);
      expect(list[1].endHour, 23);
      expect(list[1].endMinute, 59);
    });

    test('setActivePeriods 后 periodOfSection 读到新时间', () {
      expect(periodOfSection(1).encode(), '08:20-09:05');
      setActivePeriods([
        const Period(
          section: 1,
          label: '第1节',
          startHour: 8,
          startMinute: 30,
          endHour: 9,
          endMinute: 15,
        ),
      ]);
      expect(periodOfSection(1).encode(), '08:30-09:15');
      expect(periodOfSection(2).encode(), defaultPeriods[1].encode());
    });

    test('periodsCustomized 能识别改没改过', () {
      expect(periodsCustomized(), isFalse);
      setActivePeriods(defaultPeriods);
      expect(periodsCustomized(), isFalse);

      final changed = List<Period>.from(defaultPeriods);
      changed[0] = changed[0].withTime(
        startHour: 7,
        startMinute: 50,
        endHour: 8,
        endMinute: 35,
      );
      setActivePeriods(changed);
      expect(periodsCustomized(), isTrue);
    });

    test('firstInvalidSection 找出结束早于开始的节次', () {
      expect(firstInvalidSection(defaultPeriods), isNull);

      final bad = List<Period>.from(defaultPeriods);
      bad[2] = bad[2].withTime(
        startHour: 10,
        startMinute: 0,
        endHour: 9,
        endMinute: 0,
      );
      expect(firstInvalidSection(bad), 3);

      final same = List<Period>.from(defaultPeriods);
      same[0] = same[0].withTime(
        startHour: 8,
        startMinute: 0,
        endHour: 8,
        endMinute: 0, // 起止相同也算非法
      );
      expect(firstInvalidSection(same), 1);
    });
  });

  group('PeriodStore 读写', () {
    test('没存过时 load 返回 null', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await PeriodStore.load(), isNull);
    });

    test('save / load 往返一致（下标即节次-1）', () async {
      SharedPreferences.setMockInitialValues({});
      final custom = List<Period>.from(defaultPeriods);
      custom[0] = custom[0].withTime(
        startHour: 8,
        startMinute: 30,
        endHour: 9,
        endMinute: 15,
      );
      custom[8] = custom[8].withTime(
        startHour: 18,
        startMinute: 30,
        endHour: 19,
        endMinute: 15,
      );
      await PeriodStore.save(custom);

      final loaded = await PeriodStore.load();
      expect(loaded, isNotNull);
      expect(loaded!.length, defaultPeriods.length);
      expect(loaded[0].encode(), '08:30-09:15');
      expect(loaded[8].encode(), '18:30-19:15');
      expect(loaded[8].section, 9, reason: '第 9 节应落在下标 8');
      expect(loaded[1].encode(), defaultPeriods[1].encode());
    });

    test('存坏的数据时回落到默认（返回 null）', () async {
      SharedPreferences.setMockInitialValues({
        'njtc_periods': <String>['乱码', 'not-a-time'],
      });
      expect(await PeriodStore.load(), isNull);
    });

    test('老版本存的「旧出厂默认」会被新作息顶掉', () async {
      // 模拟老用户：打开过节次时间页并原样保存，存档里躺的是 08:00 那套旧作息，
      // 且没有版本号（视为 v1）。升级后这份存档不该继续挡着新作息 ——
      // 否则课程提醒会一直按已经作废的时间响。
      SharedPreferences.setMockInitialValues({
        'njtc_periods': legacyDefaultPeriods.map((e) => e.encode()).toList(),
      });
      expect(
        await PeriodStore.load(),
        isNull,
        reason: '和旧出厂默认一字不差 = 用户没真调过，应让位给新作息',
      );
    });

    test('用户自己调过的老存档不会被顶掉', () async {
      final custom = List<Period>.from(legacyDefaultPeriods);
      custom[0] = custom[0].withTime(
        startHour: 7,
        startMinute: 30,
        endHour: 8,
        endMinute: 15,
      );
      SharedPreferences.setMockInitialValues({
        'njtc_periods': custom.map((e) => e.encode()).toList(),
      });
      final loaded = await PeriodStore.load();
      expect(loaded, isNotNull, reason: '改过的时间必须保留，不能被升级冲掉');
      expect(loaded!.first.encode(), '07:30-08:15');
    });

    test('新版本存下来的时间原样返回', () async {
      SharedPreferences.setMockInitialValues({});
      final custom = List<Period>.from(defaultPeriods);
      custom[0] = custom[0].withTime(
        startHour: 8,
        startMinute: 0,
        endHour: 8,
        endMinute: 45,
      );
      await PeriodStore.save(custom); // save 会写下当前版本号
      final loaded = await PeriodStore.load();
      expect(loaded, isNotNull);
      expect(loaded!.first.encode(), '08:00-08:45', reason: '新版本下用户自己定的时间照旧');
    });

    test('clear 之后 load 回到 null', () async {
      SharedPreferences.setMockInitialValues({});
      await PeriodStore.save(defaultPeriods);
      expect(await PeriodStore.load(), isNotNull);
      await PeriodStore.clear();
      expect(await PeriodStore.load(), isNull);
    });
  });

  group('AppState 节次时间', () {
    test('init 会读回已保存的自定义节次', () async {
      SharedPreferences.setMockInitialValues({});
      final custom = List<Period>.from(defaultPeriods);
      custom[0] = custom[0].withTime(
        startHour: 7,
        startMinute: 45,
        endHour: 8,
        endMinute: 30,
      );
      await PeriodStore.save(custom);

      final state = AppState();
      await state.init();
      expect(state.periods.first.encode(), '07:45-08:30');
      expect(state.hasCustomPeriods, isTrue);
    });

    test('没有存过时用默认作息', () async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState();
      await state.init();
      expect(state.periods.first.encode(), defaultPeriods.first.encode());
      expect(state.hasCustomPeriods, isFalse);
    });

    test('updatePeriods 落盘，resetPeriods 清掉', () async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState();
      await state.init();

      final custom = List<Period>.from(defaultPeriods);
      custom[2] = custom[2].withTime(
        startHour: 10,
        startMinute: 10,
        endHour: 10,
        endMinute: 55,
      );
      await state.updatePeriods(custom);
      expect(state.periods[2].encode(), '10:10-10:55');
      expect(state.hasCustomPeriods, isTrue);

      // 换一个实例重新 init，验证确实落盘了
      final again = AppState();
      await again.init();
      expect(again.periods[2].encode(), '10:10-10:55');

      await state.resetPeriods();
      expect(state.hasCustomPeriods, isFalse);
      expect(state.periods[2].encode(), defaultPeriods[2].encode());
      expect(await PeriodStore.load(), isNull);
    });
  });

  group('设置页 → 节次时间', () {
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
          // 测试机默认 locale 是 en_US，这里显式钉成中文，
          // 才能验证 showTimePicker 的按钮是「取消 / 确定」而不是 Cancel / OK
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          home: const SettingsPage(),
          routes: {'/periods': (_) => const PeriodSettingsPage()},
        ),
      ));
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('设置页有「节次时间」入口，点进去能看到 11 节', (tester) async {
      await pumpSettings(tester);

      expect(find.text('节次时间'), findsOneWidget);
      expect(find.textContaining('学校默认作息'), findsOneWidget);

      await tester.tap(find.text('节次时间'));
      await tester.pumpAndSettle();

      expect(find.byType(PeriodSettingsPage), findsOneWidget);
      for (var i = 1; i <= 11; i++) {
        expect(find.text('第$i节'), findsOneWidget);
      }
      expect(find.text('08:20'), findsOneWidget);
      expect(find.text('21:35'), findsOneWidget);
      expect(find.text('45 分'), findsWidgets);
    });

    testWidgets('点开始时间会弹出时间选择器', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('节次时间'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('08:20'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(find.text('第1节 开始时间'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget, reason: '中文环境应是「取消」');

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('08:20'), findsOneWidget, reason: '取消后时间不变');
    });

    testWidgets('保存默认作息的节次表不会报错', (tester) async {
      final state = await pumpSettings(tester);
      await tester.tap(find.text('节次时间'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, '保存'));
      await tester.pumpAndSettle();

      expect(state.hasCustomPeriods, isFalse);
      expect(find.byType(PeriodSettingsPage), findsNothing, reason: '保存后返回');
    });

    testWidgets('「恢复默认」把草稿填回学校作息', (tester) async {
      final state = await pumpSettings(tester);
      await state.updatePeriods([
        const Period(
          section: 1,
          label: '第1节',
          startHour: 9,
          startMinute: 30,
          endHour: 10,
          endMinute: 15,
        ),
      ]);
      await tester.pumpAndSettle();

      await tester.tap(find.text('节次时间'));
      await tester.pumpAndSettle();
      // 入口卡片此时应显示已自定义
      expect(find.text('09:30'), findsOneWidget);

      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();
      expect(find.text('09:30'), findsNothing);
      expect(find.text('08:20'), findsOneWidget);
    });
  });
}
