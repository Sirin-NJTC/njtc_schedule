/// 法定节假日 / 调休补班日日历：模型 / 存储 / AppState。
///
/// 这里锁定的是「提醒排布要用的那几个数」：epochDay 的算法必须和原生
/// `DayMath` 一致（否则放假那天照样响），wire 文本必须能往返。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:njtc_schedule/app_state.dart';
import 'package:njtc_schedule/models/holiday_calendar.dart';
import 'package:njtc_schedule/storage/holiday_store.dart';
import 'package:njtc_schedule/storage/reminder_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('epochDayOf', () {
    test('1970-01-01 是 0，跨日 +1', () {
      expect(epochDayOf(DateTime(1970, 1, 1)), 0);
      expect(epochDayOf(DateTime(1970, 1, 2)), 1);
      expect(
        epochDayOf(DateTime(2026, 10, 4)) - epochDayOf(DateTime(2026, 10, 1)),
        3,
      );
    });

    test('只看年月日：同一天的时分秒不影响结果', () {
      expect(
        epochDayOf(DateTime(2026, 10, 4, 23, 59, 59)),
        epochDayOf(DateTime(2026, 10, 4, 0, 0, 1)),
      );
    });
  });

  group('HolidayDay / MakeupDay 编解码', () {
    test('wire 文本往返一致', () {
      final h = HolidayDay(DateTime(2026, 10, 1), '国庆节');
      expect(h.toWire(), '2026-10-01|国庆节');
      final back = HolidayDay.parse(h.toWire());
      expect(back, isNotNull);
      expect(back!.name, '国庆节');
      expect(back.date, DateTime(2026, 10, 1));

      final m = MakeupDay(DateTime(2026, 10, 10), 3, '补周三的课');
      expect(m.toWire(), '2026-10-10|3|补周三的课');
      final bm = MakeupDay.parse(m.toWire());
      expect(bm, isNotNull);
      expect(bm!.weekday, 3);
      expect(bm.weekdayText, '周三');
      expect(bm.note, '补周三的课');
    });

    test('名称里带竖线也不会被截断', () {
      final h = HolidayDay.parse('2026-10-01|国庆|中秋连休');
      expect(h, isNotNull);
      expect(h!.name, '国庆|中秋连休');
    });

    test('格式不对返回 null（宁可少一天也不崩）', () {
      expect(HolidayDay.parse('乱码'), isNull);
      expect(HolidayDay.parse('2026-13-01|不存在的月份'), isNull);
      expect(MakeupDay.parse('2026-10-10|9|周几越界'), isNull);
      expect(MakeupDay.parse('2026-10-10|abc|不是数字'), isNull);
      expect(MakeupDay.parse('没有竖线'), isNull);
    });

    test('备注可以为空', () {
      final m = MakeupDay.parse('2026-10-10|3');
      expect(m, isNotNull);
      expect(m!.note, '');
      expect(m.weekday, 3);
    });
  });

  group('HolidayCalendar 内置日历', () {
    test('内置 13 个放假日、0 个补班日', () {
      final cal = HolidayCalendar.builtin();
      expect(cal.holidays.length, 13);
      expect(cal.makeups, isEmpty);
      expect(cal.isEmpty, isFalse);
      expect(cal.summaryText, '放假 13 天 · 补班 0 天');
    });

    test('2026 国庆那几天都算放假，并且能报出名字', () {
      final cal = HolidayCalendar.builtin();
      for (var d = 1; d <= 7; d++) {
        final day = DateTime(2026, 10, d);
        expect(cal.isHoliday(day), isTrue, reason: '10 月 $d 日应放假');
      }
      expect(cal.holidayName(DateTime(2026, 10, 1)), '国庆节');
      expect(cal.holidayName(DateTime(2026, 10, 4)), '国庆节假期');
      expect(cal.holidayName(DateTime(2026, 10, 8)), isNull);
      expect(cal.isHoliday(DateTime(2026, 10, 8)), isFalse);
    });

    test('中秋 / 元旦也在内置里', () {
      final cal = HolidayCalendar.builtin();
      expect(cal.holidayName(DateTime(2026, 9, 25)), '中秋节');
      expect(cal.holidayName(DateTime(2027, 1, 1)), '元旦');
      expect(cal.isHoliday(DateTime(2027, 1, 3)), isTrue);
    });

    test('空日历的说明文字', () {
      const empty = HolidayCalendar();
      expect(empty.isEmpty, isTrue);
      expect(empty.summaryText, '未设置任何节假日');
    });
  });

  group('HolidayCalendar 查询与下发', () {
    test('weekdayOverride 只对补班日生效', () {
      final cal = HolidayCalendar(
        holidays: [HolidayDay(DateTime(2026, 10, 1), '国庆节')],
        makeups: [MakeupDay(DateTime(2026, 10, 10), 3, '补周三的课')],
      );
      expect(cal.weekdayOverride(DateTime(2026, 10, 10)), 3);
      expect(cal.weekdayOverride(DateTime(2026, 10, 11)), isNull);
      expect(cal.weekdayOverride(DateTime(2026, 10, 1)), isNull);
    });

    test('holidayEpochDays / makeupEpochDays 与 epochDayOf 对齐', () {
      final cal = HolidayCalendar(
        holidays: [HolidayDay(DateTime(2026, 10, 1), '国庆节')],
        makeups: [MakeupDay(DateTime(2026, 10, 10), 3, '')],
      );
      expect(cal.holidayEpochDays, {epochDayOf(DateTime(2026, 10, 1))});
      expect(
        cal.makeupEpochDays,
        {epochDayOf(DateTime(2026, 10, 10)): 3},
      );
    });

    test('makeupPayload 是原生侧认的字段名', () {
      final cal = HolidayCalendar(
        makeups: [MakeupDay(DateTime(2026, 10, 10), 3, '补周三的课')],
      );
      final payload = cal.makeupPayload();
      expect(payload.length, 1);
      expect(payload.first['epochDay'], epochDayOf(DateTime(2026, 10, 10)));
      expect(payload.first['weekday'], 3);
    });

    test('sorted 按日期升序，copyWith 也保持有序', () {
      final cal = HolidayCalendar(
        holidays: [
          HolidayDay(DateTime(2026, 10, 7), '晚'),
          HolidayDay(DateTime(2026, 10, 1), '早'),
        ],
        makeups: [
          MakeupDay(DateTime(2026, 10, 11), 4, '晚'),
          MakeupDay(DateTime(2026, 10, 10), 3, '早'),
        ],
      ).sorted();
      expect(cal.holidays.first.name, '早');
      expect(cal.holidays.last.name, '晚');
      expect(cal.makeups.first.note, '早');

      final more = cal.copyWith(
        holidays: [...cal.holidays, HolidayDay(DateTime(2026, 9, 25), '中秋')],
      );
      expect(more.holidays.first.date, DateTime(2026, 9, 25));
    });
  });

  group('HolidayStore', () {
    test('从未保存过 → 内置日历', () async {
      SharedPreferences.setMockInitialValues({});
      final cal = await HolidayStore.load();
      expect(cal.holidays.length, 13);
      expect(cal.summaryText, '放假 13 天 · 补班 0 天');
    });

    test('存了再读一致（含补班日与中文名称）', () async {
      SharedPreferences.setMockInitialValues({});
      await HolidayStore.save(HolidayCalendar(
        holidays: [HolidayDay(DateTime(2026, 10, 1), '国庆节')],
        makeups: [MakeupDay(DateTime(2026, 10, 10), 3, '补周三的课')],
      ));

      final back = await HolidayStore.load();
      expect(back.holidays.length, 1);
      expect(back.holidays.first.name, '国庆节');
      expect(back.makeups.length, 1);
      expect(back.makeups.first.weekday, 3);
      expect(back.makeups.first.note, '补周三的课');
    });

    test('用户把节假日全删光 → 读到的是「空」而不是内置那份', () async {
      SharedPreferences.setMockInitialValues({});
      await HolidayStore.save(const HolidayCalendar());

      final back = await HolidayStore.load();
      expect(back.isEmpty, isTrue, reason: '不能又冒出内置的 13 天');
      expect(back.summaryText, '未设置任何节假日');
    });

    test('clear 之后回到内置那份', () async {
      SharedPreferences.setMockInitialValues({});
      await HolidayStore.save(const HolidayCalendar());
      await HolidayStore.clear();

      final back = await HolidayStore.load();
      expect(back.holidays.length, 13);
    });

    test('存档里混进坏行时跳过坏行，不整体失败', () async {
      SharedPreferences.setMockInitialValues({
        'njtc_holidays': ['2026-10-01|国庆节', '这不是一行合法数据'],
        'njtc_holiday_makeups': ['2026-10-10|3|补周三'],
      });
      final back = await HolidayStore.load();
      expect(back.holidays.length, 1);
      expect(back.makeups.length, 1);
    });
  });

  group('AppState 节假日', () {
    test('init 后是内置日历，updateHolidays 会存盘', () async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState();
      await state.init();
      expect(state.holidays.holidays.length, 13);

      await state.updateHolidays(
        state.holidays.copyWith(
          makeups: [MakeupDay(DateTime(2026, 10, 10), 3, '补周三的课')],
        ),
      );

      expect(state.holidays.makeups.length, 1);
      final stored = await HolidayStore.load();
      expect(stored.makeups.length, 1);
      expect(stored.makeups.first.weekday, 3);
    });

    test('resetHolidays 回到内置那份', () async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState();
      await state.init();
      await state.updateHolidays(const HolidayCalendar());
      expect(state.holidays.isEmpty, isTrue);

      await state.resetHolidays();
      expect(state.holidays.holidays.length, 13);
      expect((await HolidayStore.load()).holidays.length, 13);
    });

    test('skipHolidays 默认开启，能关掉并存盘', () async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState();
      await state.init();
      expect(state.reminderPrefs.skipHolidays, isTrue);

      await state.updateReminderPrefs(
        state.reminderPrefs.copyWith(skipHolidays: false),
      );
      expect(state.reminderPrefs.skipHolidays, isFalse);
      expect((await ReminderStore.load()).skipHolidays, isFalse);
      expect(state.reminderPrefs.summaryText, isNot(contains('节假日不提醒')));
    });
  });
}
