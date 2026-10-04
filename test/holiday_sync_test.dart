/// 节假日**联网更新**的解析 / 推导 / 合并 测试。
///
/// 夹具是 2026-10 从 `https://timor.tech/api/holiday/year/2026` 抓下来的**真实
/// 返回体**（`test/fixtures/holiday_2026.json`），另有一份「还没公布」的年份
/// （`holiday_2027.json`，`{"code":0,"holiday":{}}`）。测试不打真网络。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/app_state.dart';
import 'package:njtc_schedule/models/holiday_calendar.dart';
import 'package:njtc_schedule/services/holiday_sync_service.dart';
import 'package:njtc_schedule/storage/holiday_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

/// 造一个「联网返回体」：只给 MM-DD / 日期 / 是否放假 / 名称。
String _body(Map<String, Object?> days) => jsonEncode(<String, Object?>{
      'code': 0,
      'holiday': days,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final json2026 = _fixture('holiday_2026.json');
  final json2027 = _fixture('holiday_2027.json');

  tearDown(() {
    HolidaySyncService.getOverride = null;
    HolidaySyncService.forceAutoSync = false;
  });

  group('parseYear：真实返回体', () {
    test('2026：33 天放假、6 天补班，名称都在', () {
      final data = HolidaySyncService.parseYear(json2026, 2026);
      expect(data.year, 2026);
      expect(data.holidays.length, 33);
      expect(data.makeups.length, 6);
      expect(data.isEmpty, isFalse);
      expect(data.holidays.every((h) => h.name.isNotEmpty), isTrue);

      final cal = HolidayCalendar(
        holidays: data.holidays,
        makeups: data.makeups,
      ).sorted();
      expect(cal.holidayName(DateTime(2026, 10, 1)), '国庆节');
      expect(cal.holidayName(DateTime(2026, 9, 25)), '中秋节');
      expect(cal.holidayName(DateTime(2026, 10, 8)), isNull);
      expect(cal.isHoliday(DateTime(2026, 10, 7)), isTrue);
      expect(cal.isHoliday(DateTime(2026, 9, 24)), isFalse);
    });

    test('补班日的「按周几上课」按惯例推导', () {
      final data = HolidaySyncService.parseYear(json2026, 2026);
      final byDay = <String, int>{
        for (final m in data.makeups)
          '${m.date.year}-${m.date.month}-${m.date.day}': m.weekday,
      };
      // 元旦 01-01(四)~01-03(六) 放假，01-04(日) 补班 → 假期内最后一个工作日是周五
      expect(byDay['2026-1-4'], DateTime.friday);
      // 春节 02-15(日)~02-23(一) 放假：02-14(六) 前补班 → 第一个工作日周一
      expect(byDay['2026-2-14'], DateTime.monday);
      // 02-28(六) 后补班 → 最后一个工作日是 02-23 周一
      expect(byDay['2026-2-28'], DateTime.monday);
      // 劳动节 05-01(五)~05-05(二)：05-09(六) 后补班 → 周二
      expect(byDay['2026-5-9'], DateTime.tuesday);
      // 中秋 09-25(五)~09-27(日)：09-20(日) 前补班 → 周五
      expect(byDay['2026-9-20'], DateTime.friday);
      // 国庆 10-01(四)~10-07(三)：10-10(六) 后补班 → 周三
      expect(byDay['2026-10-10'], DateTime.wednesday);
      expect(data.makeups.every((m) => m.note.startsWith('联网：')), isTrue);
    });

    test('还没公布的年份返回空数据而不是报错', () {
      final data = HolidaySyncService.parseYear(json2027, 2027);
      expect(data.year, 2027);
      expect(data.isEmpty, isTrue);
      expect(data.holidays, isEmpty);
      expect(data.makeups, isEmpty);
    });

    test('code != 0 抛 HolidaySyncException', () {
      expect(
        () => HolidaySyncService.parseYear('{"code":-1,"msg":"没了"}', 2026),
        throwsA(
          isA<HolidaySyncException>().having(
            (e) => e.message,
            'message',
            contains('code=-1'),
          ),
        ),
      );
    });

    test('不是 JSON 时抛 HolidaySyncException', () {
      expect(
        () => HolidaySyncService.parseYear('<html>502</html>', 2026),
        throwsA(isA<HolidaySyncException>()),
      );
    });

    test('只有 MM-DD 键、没有 date 字段时用请求的年份补上', () {
      final data = HolidaySyncService.parseYear(
        _body(<String, Object?>{
          '10-01': <String, Object?>{'holiday': true, 'name': '国庆节'},
        }),
        2026,
      );
      expect(data.holidays.single.date, DateTime(2026, 10, 1));
      expect(data.holidays.single.name, '国庆节');
    });

    test('同一天既放假又补班时只留放假（免得自相矛盾）', () {
      final data = HolidaySyncService.parseYear(
        _body(<String, Object?>{
          '10-01': <String, Object?>{'holiday': true, 'name': '国庆节'},
          '10-01b': <String, Object?>{
            'holiday': false,
            'name': '国庆节后补班',
            'after': true,
            'date': '2026-10-01',
          },
        }),
        2026,
      );
      expect(data.holidays.length, 1);
      expect(data.makeups, isEmpty);
    });
  });

  group('deriveMakeupWeekday', () {
    test('假期为空或找不到假期时返回 null', () {
      expect(
        HolidaySyncService.deriveMakeupWeekday(
          date: DateTime(2026, 10, 10),
          after: true,
          holidayEpochDays: <int>{},
        ),
        isNull,
      );
      expect(
        HolidaySyncService.deriveMakeupWeekday(
          date: DateTime(2026, 10, 10),
          after: true,
          holidayEpochDays: <int>{epochDayOf(DateTime(2026, 1, 1))},
        ),
        isNull,
      );
    });

    test('前补取假期内第一个工作日、后补取最后一个', () {
      final block = <int>{
        for (var d = 1; d <= 5; d++) epochDayOf(DateTime(2026, 5, d)),
      };
      // 假期 05-01(五)~05-05(二)，工作日是 05-01(五) 和 05-04(一)、05-05(二)
      expect(
        HolidaySyncService.deriveMakeupWeekday(
          date: DateTime(2026, 5, 9),
          after: true,
          holidayEpochDays: block,
        ),
        DateTime.tuesday,
      );
      expect(
        HolidaySyncService.deriveMakeupWeekday(
          date: DateTime(2026, 4, 30),
          after: false,
          holidayEpochDays: block,
        ),
        DateTime.friday,
      );
    });
  });

  group('merge / countDropped', () {
    test('联网覆盖到的年份整年替换，没覆盖的年份（含用户自己加的）留着', () {
      final base = HolidayCalendar(
        holidays: <HolidayDay>[
          HolidayDay(DateTime(2026, 10, 1), '国庆节'), // 会被替换
          HolidayDay(DateTime(2026, 12, 31), '校运会'), // 2026 年，联网没有 → 丢
          HolidayDay(DateTime(2027, 1, 1), '元旦'), // 2027 年没覆盖 → 留
        ],
      );
      final fetched = <HolidayYearData>[
        HolidaySyncService.parseYear(json2026, 2026),
        HolidaySyncService.parseYear(json2027, 2027),
      ];
      final merged = HolidaySyncService.merge(base, fetched);
      expect(merged.holidays.length, 33 + 1); // 2026 全换成官方的 33 天 + 2027 那条
      expect(
        merged.holidays.any((h) => h.date == DateTime(2027, 1, 1)),
        isTrue,
      );
      expect(
        merged.holidays.any((h) => h.name == '校运会'),
        isFalse,
      );
      expect(merged.makeups.length, 6);
      expect(
        HolidaySyncService.countDropped(base, fetched),
        1, // 只有 2026-12-31 那条会被冲掉
      );
    });

    test('同一天既在旧日历又在联网数据里时以联网为准', () {
      final base = HolidayCalendar(
        holidays: <HolidayDay>[
          HolidayDay(DateTime(2026, 10, 1), '自己起的名字'),
        ],
      );
      final merged = HolidaySyncService.merge(
        base,
        <HolidayYearData>[HolidaySyncService.parseYear(json2026, 2026)],
      );
      expect(merged.holidayName(DateTime(2026, 10, 1)), '国庆节');
    });
  });

  group('update：整条链路（HTTP 用 getOverride 打桩）', () {
    test('两年都拿到：ok，日历换成官方的，note 说明覆盖了哪几年', () async {
      final hits = <String>[];
      HolidaySyncService.getOverride = (uri) async {
        hits.add(uri.path);
        return uri.path.endsWith('/2026') ? json2026 : json2027;
      };
      final outcome = await HolidaySyncService.update(
        HolidayCalendar.builtin(),
        now: DateTime(2026, 10, 4),
      );
      expect(hits, <String>[
        '/api/holiday/year/2026',
        '/api/holiday/year/2027',
      ]);
      expect(outcome.ok, isTrue);
      expect(outcome.note, '2026 年');
      // 2026 年整年换成官方的 33 天；内置里 2027 年那 3 天还在（2027 没数据）
      expect(outcome.calendar.holidays.length, 36);
      expect(outcome.calendar.makeups.length, 6);
      // 内置里那条 2027-01-03 被保留了（2027 年接口还没数据）
      expect(
        outcome.calendar.holidays.any((h) => h.date == DateTime(2027, 1, 3)),
        isTrue,
      );
    });

    test('接口没公布任何一年：ok=false，日历原样返回', () async {
      HolidaySyncService.getOverride = (uri) async => json2027;
      final base = HolidayCalendar.builtin();
      final outcome = await HolidaySyncService.update(
        base,
        years: <int>[2027],
      );
      expect(outcome.ok, isFalse);
      expect(outcome.calendar.holidays.length, base.holidays.length);
      expect(outcome.note, contains('还没公布'));
    });

    test('网络不通：ok=false，错误写在 note 里，不抛异常', () async {
      HolidaySyncService.getOverride =
          (uri) async => throw const SocketException('没有网络');
      final base = HolidayCalendar.builtin();
      final outcome = await HolidaySyncService.update(base, years: <int>[2026]);
      expect(outcome.ok, isFalse);
      expect(outcome.note, contains('连不上接口'));
      expect(outcome.calendar.holidays.length, base.holidays.length);
    });

    test('接口返回 code!=0：ok=false', () async {
      HolidaySyncService.getOverride = (uri) async => '{"code":-1,"msg":"忙"}';
      final outcome = await HolidaySyncService
          .update(HolidayCalendar.builtin(), years: <int>[2026]);
      expect(outcome.ok, isFalse);
      expect(outcome.note, contains('code=-1'));
    });

    test('yearsFor：学期跨年，取今年与明年', () {
      expect(HolidaySyncService.yearsFor(DateTime(2026, 10, 4)), <int>[2026, 2027]);
      expect(HolidaySyncService.yearsFor(DateTime(2027, 3, 1)), <int>[2027, 2028]);
    });
  });

  group('AppState 启动时的静默同步', () {
    /// 起一个 AppState：先按参数预置日历与来源，再打开「允许自动同步」并打桩取数。
    Future<(AppState, List<Uri>)> boot({
      HolidayCalendar? stored,
      String? source,
      DateTime? updatedAt,
    }) async {
      SharedPreferences.setMockInitialValues({});
      if (stored != null) await HolidayStore.save(stored);
      if (source != null) {
        await HolidayStore.saveMeta(source: source, updatedAt: updatedAt);
      }
      final hits = <Uri>[];
      HolidaySyncService.forceAutoSync = true;
      HolidaySyncService.getOverride = (uri) async {
        hits.add(uri);
        return uri.path.endsWith('/2027') ? json2027 : json2026;
      };
      final state = AppState();
      await state.init();
      // init 里的静默同步是 unawaited 的，把微任务队列跑干净再断言
      await pumpEventQueue();
      return (state, hits);
    }

    test('从没同步过（内置估算值）：启动就静默换成官方的', () async {
      final (state, hits) = await boot();
      expect(hits, isNotEmpty);
      expect(state.holidays.holidays.length, 36); // 2026 官方 33 + 内置 2027 那 3 天
      expect(state.holidays.makeups.length, 6);
      expect(state.holidayMeta.source, HolidayStore.sourceNet);
      expect(state.holidayMeta.updatedAt, isNotNull);
      // 也要落盘，不然下次启动又白跑一遍
      expect((await HolidayStore.load()).holidays.length, 36);
      expect((await HolidayStore.loadMeta()).source, HolidayStore.sourceNet);
    });

    test('手动改过：启动**不**联网，用户那份日历原样留着', () async {
      final mine = HolidayCalendar(
        holidays: <HolidayDay>[
          HolidayDay(DateTime(2026, 12, 31), '校运会'),
        ],
      );
      final (state, hits) = await boot(
        stored: mine,
        source: HolidayStore.sourceManual,
        updatedAt: DateTime.now(),
      );
      expect(hits, isEmpty);
      expect(state.holidays.holidays.length, 1);
      expect(state.holidays.holidayName(DateTime(2026, 12, 31)), '校运会');
      expect(state.holidayMeta.source, HolidayStore.sourceManual);
    });

    test('刚联网更新过（30 天内）：启动不再打接口', () async {
      final (_, hits) = await boot(
        stored: HolidayCalendar(
          holidays: <HolidayDay>[HolidayDay(DateTime(2026, 10, 1), '国庆节')],
        ),
        source: HolidayStore.sourceNet,
        updatedAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      expect(hits, isEmpty);
    });

    test('联网更新超过 30 天：启动会自动再拉一次', () async {
      final (state, hits) = await boot(
        stored: HolidayCalendar(
          holidays: <HolidayDay>[HolidayDay(DateTime(2026, 10, 1), '国庆节')],
        ),
        source: HolidayStore.sourceNet,
        updatedAt: DateTime.now().subtract(const Duration(days: 40)),
      );
      expect(hits, isNotEmpty);
      // 存档里只有 2026 那一天，整年换成官方的 33 天
      expect(state.holidays.holidays.length, 33);
      expect(state.holidayMeta.source, HolidayStore.sourceNet);
    });

    test('测试环境默认不联网（autoSyncEnabled 为 false）', () {
      HolidaySyncService.forceAutoSync = false;
      expect(HolidaySyncService.autoSyncEnabled, isFalse);
      HolidaySyncService.forceAutoSync = true;
      expect(HolidaySyncService.autoSyncEnabled, isTrue);
    });
  });
}
