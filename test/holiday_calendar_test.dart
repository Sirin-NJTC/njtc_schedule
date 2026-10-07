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

  group('节日归一与合并显示', () {
    test('festivalKeyOf 去掉「假期」后缀，春节那几天归到春节', () {
      expect(festivalKeyOf('国庆节假期'), '国庆节');
      expect(festivalKeyOf('中秋节假期'), '中秋节');
      expect(festivalKeyOf('元旦'), '元旦');
      expect(festivalKeyOf('劳动节放假'), '劳动节');
      expect(festivalKeyOf('除夕'), '春节');
      expect(festivalKeyOf('初一'), '春节');
      expect(festivalKeyOf('初十'), '春节');
      expect(festivalKeyOf('校运会'), '校运会');
      // 名字本身就叫「假期」时不能归一成空字符串
      expect(festivalKeyOf('假期'), '假期');
      expect(festivalKeyOf(' 国庆节 '), '国庆节');
    });

    test('dateOfEpochDay 与 epochDayOf 互为逆运算', () {
      final d = DateTime(2026, 10, 7);
      expect(dateOfEpochDay(epochDayOf(d)), d);
      expect(dateOfEpochDay(0), DateTime(1970, 1, 1));
    });

    test('内置日历合并成 3 段：中秋 / 国庆 / 元旦', () {
      final ranges = HolidayCalendar.builtin().holidayRanges;
      expect(ranges.map((r) => r.name).toList(), ['中秋节', '国庆节', '元旦']);
      expect(ranges.map((r) => r.dayCount).toList(), [3, 7, 3]);
      expect(ranges[1].subtitle, '10月1日（周四） – 10月7日（周三） · 共 7 天');
      expect(ranges[0].subtitle, '9月25日（周五） – 9月27日（周日） · 共 3 天');
      expect(ranges[1].start, DateTime(2026, 10, 1));
      expect(ranges[1].end, DateTime(2026, 10, 7));
      expect(ranges[1].isSingleDay, isFalse);
    });

    test('同一天只有一天时 subtitle 不带区间', () {
      final cal = HolidayCalendar(
        holidays: [HolidayDay(DateTime(2026, 10, 1), '国庆节')],
      );
      final r = cal.holidayRanges.single;
      expect(r.isSingleDay, isTrue);
      expect(r.subtitle, '10月1日（周四） · 共 1 天');
    });

    test('名字一样但日期断开 → 显示成两段', () {
      final cal = HolidayCalendar(holidays: [
        HolidayDay(DateTime(2026, 10, 1), '国庆节'),
        HolidayDay(DateTime(2026, 10, 2), '国庆节'),
        // 中间空了一天
        HolidayDay(DateTime(2026, 10, 4), '国庆节'),
      ]);
      final ranges = cal.holidayRanges;
      expect(ranges.length, 2);
      expect(ranges[0].dayCount, 2);
      expect(ranges[1].dayCount, 1);
    });

    test('不同节日紧挨着也不会被并成一段', () {
      final cal = HolidayCalendar(holidays: [
        HolidayDay(DateTime(2026, 9, 30), '中秋节'),
        HolidayDay(DateTime(2026, 10, 1), '国庆节'),
      ]);
      final ranges = cal.holidayRanges;
      expect(ranges.length, 2);
      expect(ranges.map((r) => r.name).toList(), ['中秋节', '国庆节']);
    });

    test('春节的除夕 / 初一 / 初二合并成一段「春节」', () {
      final cal = HolidayCalendar(holidays: [
        HolidayDay(DateTime(2026, 2, 16), '除夕'),
        HolidayDay(DateTime(2026, 2, 17), '初一'),
        HolidayDay(DateTime(2026, 2, 18), '初二'),
      ]);
      final r = cal.holidayRanges.single;
      expect(r.name, '春节');
      expect(r.dayCount, 3);
    });

    test('同一天出现两条时 sorted 去重，只留先来的那条', () {
      final cal = HolidayCalendar(holidays: [
        HolidayDay(DateTime(2026, 10, 1), '国庆节'),
        HolidayDay(DateTime(2026, 10, 1), '国庆节假期'),
      ]).sorted();
      expect(cal.holidays.length, 1);
      expect(cal.holidays.single.name, '国庆节');
      expect(cal.holidayRanges.length, 1);
      expect(cal.holidayEpochDays.length, 1);
    });

    test('补班日同样去重', () {
      final cal = HolidayCalendar(makeups: [
        MakeupDay(DateTime(2026, 10, 10), 3, '补周三'),
        MakeupDay(DateTime(2026, 10, 10), 4, '补周四'),
      ]).sorted();
      expect(cal.makeups.length, 1);
      expect(cal.makeups.single.weekday, 3);
    });
  });

  group('假期时长自主调整', () {
    test('延长两天：国庆 7 天 → 9 天，总天数跟着涨', () {
      final base = HolidayCalendar.builtin();
      final next = base.withHolidayRange(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 9),
        name: '国庆节',
        replacing: base.holidayRanges[1].days.map((d) => d.date),
      );
      expect(next.holidays.length, 15);
      final ranges = next.holidayRanges;
      expect(ranges.length, 3);
      expect(ranges[1].name, '国庆节');
      expect(ranges[1].dayCount, 9);
      expect(ranges[1].end, DateTime(2026, 10, 9));
      expect(next.isHoliday(DateTime(2026, 10, 9)), isTrue);
    });

    test('缩短：国庆 7 天 → 3 天，被切掉的那几天不再放假', () {
      final base = HolidayCalendar.builtin();
      final next = base.withHolidayRange(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 3),
        name: '国庆节',
        replacing: base.holidayRanges[1].days.map((d) => d.date),
      );
      expect(next.holidays.length, 9);
      expect(next.isHoliday(DateTime(2026, 10, 3)), isTrue);
      expect(next.isHoliday(DateTime(2026, 10, 4)), isFalse);
      expect(next.holidayRanges[1].dayCount, 3);
    });

    test('起止日期写反了也按正序处理', () {
      final next = const HolidayCalendar().withHolidayRange(
        DateTime(2026, 10, 7),
        DateTime(2026, 10, 1),
        name: '国庆节',
      );
      expect(next.holidays.length, 7);
      expect(next.holidays.first.date, DateTime(2026, 10, 1));
      expect(next.holidays.last.date, DateTime(2026, 10, 7));
    });

    test('新范围接管重叠的别的假期（同一天只留一条）', () {
      final base = HolidayCalendar.builtin();
      final next = base.withHolidayRange(
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 6),
        name: '校运会',
      );
      expect(next.holidays.length, 13, reason: '总天数不变，只是换了名字');
      final ranges = next.holidayRanges;
      expect(ranges.map((r) => r.name).toList(),
          ['中秋节', '国庆节', '校运会', '国庆节', '元旦']);
      expect(ranges[2].dayCount, 2);
      expect(next.holidayName(DateTime(2026, 10, 5)), '校运会');
    });

    test('新范围压到补班日 → 补班安排被删掉（放假优先）', () {
      final base = HolidayCalendar.builtin().copyWith(makeups: [
        MakeupDay(DateTime(2026, 10, 8), 4, '联网：国庆节后补班'),
        MakeupDay(DateTime(2026, 10, 10), 3, '联网：国庆节后补班'),
      ]);
      expect(base.makeups.length, 2);
      final next = base.withHolidayRange(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 8),
        name: '国庆节',
        replacing: base.holidayRanges[1].days.map((d) => d.date),
      );
      expect(next.makeups.length, 1, reason: '只删掉 10-08 那条');
      expect(next.makeups.single.date, DateTime(2026, 10, 10));
      expect(next.isHoliday(DateTime(2026, 10, 8)), isTrue);
      expect(next.weekdayOverride(DateTime(2026, 10, 8)), isNull);
    });

    test('天数上限：手滑选十年也只写 120 天', () {
      final next = const HolidayCalendar().withHolidayRange(
        DateTime(2026, 1, 1),
        DateTime(2035, 1, 1),
        name: '超长假期',
      );
      expect(next.holidays.length, maxHolidayRangeDays);
      expect(next.holidays.first.date, DateTime(2026, 1, 1));
      expect(
        next.holidays.last.date,
        dateOfEpochDay(epochDayOf(DateTime(2026, 1, 1)) + maxHolidayRangeDays - 1),
      );
    });

    test('名字留空时叫「法定节假日」', () {
      final next = const HolidayCalendar().withHolidayRange(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 1),
        name: '   ',
      );
      expect(next.holidays.single.name, '法定节假日');
    });

    test('withoutHolidayRange 删掉整段，别的段不动', () {
      final base = HolidayCalendar.builtin();
      final next = base.withoutHolidayRange(base.holidayRanges[1]);
      expect(next.holidays.length, 6);
      expect(next.holidayRanges.map((r) => r.name).toList(), ['中秋节', '元旦']);
      expect(next.isHoliday(DateTime(2026, 10, 1)), isFalse);
    });

    test('rangesOverlapping 能指出接管了哪几段（排除自己）', () {
      final base = HolidayCalendar.builtin();
      final target = base.holidayRanges[1];
      final days = {
        for (var e = epochDayOf(DateTime(2026, 10, 6));
            e <= epochDayOf(DateTime(2026, 10, 8));
            e++)
          e,
      };
      final hit = base.rangesOverlapping(days, excluding: target);
      expect(hit, isEmpty, reason: '自己那段不算被接管');

      final hitOthers = base.rangesOverlapping({
        for (var e = epochDayOf(DateTime(2026, 9, 26));
            e <= epochDayOf(DateTime(2026, 9, 30));
            e++)
          e,
      });
      expect(hitOthers.map((r) => r.name).toList(), ['中秋节']);
    });
  });

  // 复查（v1.3.0 对抗式检查）发现的 F1：延长假期吃掉别的节日之后，
  // 再缩短 / 删除时那一天不能就这么没了 —— 要还给原来的节日。
  group('接管与归还', () {
    HolidayCalendar extendMidAutumnToOct1() {
      final base = HolidayCalendar.builtin();
      return base.withHolidayRange(
        DateTime(2026, 9, 25),
        DateTime(2026, 10, 1),
        name: '中秋节',
        replacing: base.holidayRanges[0].days.map((d) => d.date),
      );
    }

    test('延长吃掉别的节日 → 那天记下原主', () {
      final ext = extendMidAutumnToOct1();
      expect(ext.holidays.length, 16, reason: '中秋多吃了 9-28~10-01 四天');
      expect(ext.holidayName(DateTime(2026, 10, 1)), '中秋节');
      final day = ext.holidays.firstWhere(
        (h) => epochDayOf(h.date) == epochDayOf(DateTime(2026, 10, 1)),
      );
      expect(day.originName, '国庆节');
      expect(ext.holidayRanges[0].borrowedCount, 1);
      expect(ext.holidayRanges[0].borrowedNames, ['国庆节']);
    });

    test('再缩回去 → 10-01 还给国庆，天数回到 13', () {
      final ext = extendMidAutumnToOct1();
      final back = ext.withHolidayRange(
        DateTime(2026, 9, 25),
        DateTime(2026, 9, 27),
        name: '中秋节',
        replacing: ext.holidayRanges[0].days.map((d) => d.date),
      );
      expect(back.holidays.length, 13);
      expect(back.holidayName(DateTime(2026, 10, 1)), '国庆节');
      expect(back.holidayRanges.map((r) => r.name).toList(),
          ['中秋节', '国庆节', '元旦']);
      expect(back.holidayRanges[1].dayCount, 7, reason: '国庆又是完整七天');
    });

    test('删掉接管过的那一段 → 那天也还给国庆', () {
      final ext = extendMidAutumnToOct1();
      final next = ext.withoutHolidayRange(ext.holidayRanges[0]);
      expect(next.holidays.length, 10, reason: '国庆 7 天 + 元旦 3 天');
      expect(next.holidayName(DateTime(2026, 10, 1)), '国庆节');
      expect(next.holidayRanges.map((r) => r.name).toList(), ['国庆节', '元旦']);
    });

    test('同一节日的不同写法不算接管，缩短就直接没掉', () {
      final base = HolidayCalendar.builtin();
      final saved = base.withHolidayRange(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 7),
        name: '国庆节',
        replacing: base.holidayRanges[1].days.map((d) => d.date),
      );
      expect(saved.holidays.every((h) => h.originName == null), isTrue,
          reason: '「国庆节假期」只是同一节日的另一种写法');

      final short = saved.withHolidayRange(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 3),
        name: '国庆节',
        replacing: saved.holidayRanges[1].days.map((d) => d.date),
      );
      expect(short.holidays.length, 9);
      expect(short.isHoliday(DateTime(2026, 10, 4)), isFalse);
    });

    test('被接管两次也只记最早那个主人', () {
      final base = HolidayCalendar.builtin();
      final mid = base.withHolidayRange(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 1),
        name: '校运会',
      );
      final again = mid.withHolidayRange(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 1),
        name: '校庆',
        replacing: [DateTime(2026, 10, 1)],
      );
      final day = again.holidays.firstWhere(
        (h) => epochDayOf(h.date) == epochDayOf(DateTime(2026, 10, 1)),
      );
      expect(day.name, '校庆');
      expect(day.originName, '国庆节');

      final back = again.withoutHolidayRange(again.holidayRanges[1]);
      expect(back.holidayName(DateTime(2026, 10, 1)), '国庆节');
    });

    test('接管记录进存档还能读回来；老存档照样读', () {
      final day = HolidayDay(DateTime(2026, 10, 1), '中秋节', originName: '国庆节');
      expect(day.toWire(), '^国庆节|2026-10-01|中秋节');
      final back = HolidayDay.parse(day.toWire())!;
      expect(back.name, '中秋节');
      expect(back.originName, '国庆节');

      final old = HolidayDay.parse('2026-10-01|国庆节')!;
      expect(old.name, '国庆节');
      expect(old.originName, isNull);

      // 名字里带竖线的老行照样读得对（新格式没抢走这个能力）
      final bar = HolidayDay(DateTime(2026, 10, 1), 'A|B');
      expect(bar.toWire(), '2026-10-01|A|B');
      expect(HolidayDay.parse(bar.toWire())!.name, 'A|B');
    });

    test('名字空白的存量数据在列表里显示成「法定节假日」', () {
      final cal = HolidayCalendar(
        holidays: [HolidayDay(DateTime(2026, 10, 1), '  ')],
      );
      expect(cal.holidayRanges.single.name, '法定节假日');
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

    test('接管记录也能存进存档再读回来（重启后仍能还回去）', () async {
      SharedPreferences.setMockInitialValues({});
      final base = HolidayCalendar.builtin();
      await HolidayStore.save(base.withHolidayRange(
        DateTime(2026, 9, 25),
        DateTime(2026, 10, 1),
        name: '中秋节',
        replacing: base.holidayRanges[0].days.map((d) => d.date),
      ));

      final back = await HolidayStore.load();
      final day = back.holidays.firstWhere(
        (h) => epochDayOf(h.date) == epochDayOf(DateTime(2026, 10, 1)),
      );
      expect(day.name, '中秋节');
      expect(day.originName, '国庆节');
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
