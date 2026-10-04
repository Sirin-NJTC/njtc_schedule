/// 节次时间配置 —— 内江师范学院标准作息时间表（用户可自定义）。
library;

/// 节次信息。
class Period {
  final int section; // 第几节（1起）
  final String label; // 显示标签，如 "第1节"
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  const Period({
    required this.section,
    required this.label,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
  });

  DateTime startToday(DateTime day) =>
      DateTime(day.year, day.month, day.day, startHour, startMinute);
  DateTime endToday(DateTime day) =>
      DateTime(day.year, day.month, day.day, endHour, endMinute);

  String get startText =>
      '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}';
  String get endText =>
      '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';

  /// 持久化用的紧凑写法，如 `08:00-08:45`（节次由下标决定，不存）。
  String encode() => '$startText-$endText';

  /// 从 [encode] 的写法还原；格式不对或时间越界时返回 null。
  static Period? decode(int section, String raw) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
    if (m == null) return null;
    final sh = int.parse(m.group(1)!);
    final sm = int.parse(m.group(2)!);
    final eh = int.parse(m.group(3)!);
    final em = int.parse(m.group(4)!);
    if (sh > 23 || eh > 23 || sm > 59 || em > 59) return null;
    return Period(
      section: section,
      label: '第$section节',
      startHour: sh,
      startMinute: sm,
      endHour: eh,
      endMinute: em,
    );
  }

  /// 只改开始/结束时间，节次与标签不变。
  Period withTime({
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
  }) =>
      Period(
        section: section,
        label: label,
        startHour: startHour,
        startMinute: startMinute,
        endHour: endHour,
        endMinute: endMinute,
      );
}

/// 内江师范学院常规作息（出厂默认值，用户可在「设置 → 节次时间」里改）。
const List<Period> defaultPeriods = [
  Period(section: 1, label: '第1节', startHour: 8, startMinute: 0, endHour: 8, endMinute: 45),
  Period(section: 2, label: '第2节', startHour: 8, startMinute: 55, endHour: 9, endMinute: 40),
  Period(section: 3, label: '第3节', startHour: 10, startMinute: 0, endHour: 10, endMinute: 45),
  Period(section: 4, label: '第4节', startHour: 10, startMinute: 55, endHour: 11, endMinute: 40),
  Period(section: 5, label: '第5节', startHour: 14, startMinute: 30, endHour: 15, endMinute: 15),
  Period(section: 6, label: '第6节', startHour: 15, startMinute: 25, endHour: 16, endMinute: 10),
  Period(section: 7, label: '第7节', startHour: 16, startMinute: 30, endHour: 17, endMinute: 15),
  Period(section: 8, label: '第8节', startHour: 17, startMinute: 25, endHour: 18, endMinute: 10),
  Period(section: 9, label: '第9节', startHour: 19, startMinute: 0, endHour: 19, endMinute: 45),
  Period(section: 10, label: '第10节', startHour: 19, startMinute: 55, endHour: 20, endMinute: 40),
  Period(section: 11, label: '第11节', startHour: 20, startMinute: 50, endHour: 21, endMinute: 35),
];

/// 当前生效的节次时间表。
///
/// 之所以做成**模块级可变状态**而不是塞进 `AppState` 再层层透传：
/// 节次时间全局只有这一份，课表网格、倒计时、提醒排布都要读它，
/// 用全局变量能让所有读取点保持「一个来源」，改动面最小。
/// 写入统一走 [setActivePeriods]，避免各处各自持有一份漂移。
List<Period> activePeriods = List<Period>.unmodifiable(defaultPeriods);

/// 把任意长度的节次表补齐成 [defaultPeriods] 的形状（缺的、非法的回落到默认值）。
List<Period> normalizePeriods(List<Period> list) {
  final out = <Period>[];
  for (final def in defaultPeriods) {
    Period chosen = def;
    for (final p in list) {
      if (p.section == def.section) {
        chosen = p;
        break;
      }
    }
    out.add(
      chosen.withTime(
        startHour: chosen.startHour.clamp(0, 23),
        startMinute: chosen.startMinute.clamp(0, 59),
        endHour: chosen.endHour.clamp(0, 23),
        endMinute: chosen.endMinute.clamp(0, 59),
      ),
    );
  }
  return out;
}

/// 设置当前生效的节次时间表（会自动补齐 / 校正非法值）。
void setActivePeriods(List<Period> list) {
  activePeriods = List<Period>.unmodifiable(normalizePeriods(list));
}

/// 恢复出厂作息。
void resetActivePeriods() => setActivePeriods(defaultPeriods);

/// 检查一份节次表里有没有「结束时间不晚于开始时间」的节次。
///
/// 返回第一处有问题的节次号；全部合法时返回 null。抽成纯函数是为了能单测，
/// 设置页只负责把结果显示成 SnackBar。
int? firstInvalidSection(List<Period> list) {
  for (final p in list) {
    final start = p.startHour * 60 + p.startMinute;
    final end = p.endHour * 60 + p.endMinute;
    if (end <= start) return p.section;
  }
  return null;
}

/// 当前节次表是否已被改过（和出厂默认不同）。
bool periodsCustomized() {
  for (var i = 0; i < defaultPeriods.length; i++) {
    final a = activePeriods[i];
    final b = defaultPeriods[i];
    if (a.startHour != b.startHour ||
        a.startMinute != b.startMinute ||
        a.endHour != b.endHour ||
        a.endMinute != b.endMinute) {
      return true;
    }
  }
  return false;
}

Period periodOfSection(int section) {
  for (final p in activePeriods) {
    if (p.section == section) return p;
  }
  return activePeriods.first;
}
