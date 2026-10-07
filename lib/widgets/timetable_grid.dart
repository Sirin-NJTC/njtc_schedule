/// 课程表网格视图 —— 周/节次网格展示。
///
/// 版式：左侧节次轴（带上课时间）+ 周一~周日七列。
///
/// 几个容易踩的点，这里都处理了：
/// - 课程块按「跨了几节」撑高，不再是「第一节画卡片、后面画色块」；
/// - 同一格有多门**冲突**课时自动并排、均分列宽，不再互相覆盖丢课；
/// - 节次总数取 `activePeriods` 与课程实际最大节次的较大值（第 11 节也能显示）；
/// - 展示的正好是本周时，今天那一列高亮并画出「当前时间」横线；
/// - 首次进入自动横向滚到今天所在列（手机上七列放不下）。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/holiday_calendar.dart';
import '../models/period.dart';
import '../models/semester.dart';
import '../models/timetable.dart';
import '../theme.dart';
import 'course_card.dart';
import 'minute_ticker.dart';

/// 课程表网格（周一到周日 × 节次）。
class TimetableGrid extends StatefulWidget {
  final Timetable timetable;
  final int currentWeek;
  final void Function(Course course)? onCourseTap;

  /// 是否画周六 / 周日两列（设置 → 课表显示 → 显示周六/周日）。
  final bool showWeekend;

  /// 是否把「不在当前周」的课程也画出来（半透明），默认只画本周要上的课。
  final bool showInactiveCourses;

  /// 法定节假日 / 调休补班日日历。
  ///
  /// 放假那天的课程按「不上」处理（半透明，与「非本周课程」同款视觉）；
  /// 补班日（如「周六补周三的课」）显示被补星期的课程，表头加「补」角标。
  /// 默认空日历 = 旧行为，方便不关心节假别的调用方与既有测试。
  final HolidayCalendar holidays;

  const TimetableGrid({
    super.key,
    required this.timetable,
    required this.currentWeek,
    this.onCourseTap,
    this.showWeekend = true,
    this.showInactiveCourses = false,
    this.holidays = const HolidayCalendar(),
  });

  @override
  State<TimetableGrid> createState() => _TimetableGridState();
}

class _TimetableGridState extends State<TimetableGrid> {
  /// 一周七列；实际画几列看 [TimetableGrid.showWeekend]。
  static const int days = 7;
  static const double dayWidth = 118;
  static const double axisWidth = 54;
  static const double sectionHeight = 74;

  /// 实际要画的列数：关掉周末就只画周一到周五。
  int get _visibleDays => widget.showWeekend ? days : 5;

  /// 上午 / 下午 / 晚上的分界节次（在这些节次上方画一条淡分隔线）。
  static const List<int> _sessionStarts = [1, 5, 9];

  final ScrollController _hCtrl = ScrollController();
  bool _autoScrolled = false;

  @override
  void dispose() {
    _hCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TimetableGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timetable.id != widget.timetable.id) _autoScrolled = false;
  }

  /// 需要展示的节次总数：标准作息表节数，或课程实际用到的最大节次。
  ///
  /// 这里刻意**不做缓存**：`Timetable` 是可变对象，`updateTimetable(tt)` 传进来的
  /// 往往是同一个实例，靠 `identityHashCode` + 课程条数做指纹会在「改了某门课的
  /// 时间但课程数不变」时漏掉失效，结果课表改了网格不刷新 —— 得不偿失。
  /// 何况 [MinuteTicker] 只重建它自己那棵子树，并不会带动整张网格 rebuild，
  /// 全量重排本来就只在切周 / 改课表 / 切显示开关时发生。
  int get _sectionCount {
    var maxSection = activePeriods.length;
    for (final c in widget.timetable.courses) {
      if (c.endSection > maxSection) maxSection = c.endSection;
    }
    return maxSection;
  }

  /// 展示的正好是本周时返回今天所在列（0-6），否则 null。
  int? get _todayColumn {
    final start = widget.timetable.startDate;
    if (start == null) return null;
    final now = DateTime.now();
    // 学期还没开始，画面上就没有「今天」可言
    if (epochDayOf(now) < epochDayOf(start)) return null;
    // 周次判断统一走 weekOfSemester：这里原先另抄了一份 difference().inDays，
    // 和 AppState 那份写法不同，startDate 带时间分量时两边会算出不同的周
    if (weekOfSemester(
          startDate: start,
          day: now,
          totalWeeks: widget.timetable.totalWeeks,
        ) !=
        widget.currentWeek) {
      return null;
    }
    final col = now.weekday - 1;
    // 周末那两列被用户关掉时，今天不在画面上（否则会往看不见的列上滚）
    return col < _visibleDays ? col : null;
  }

  /// [now] 时刻在网格中的 y 坐标（不在上课时段就贴到相邻边界）。
  ///
  /// [now] 由 [MinuteTicker] 递进来；不自己读 `DateTime.now()`，
  /// 否则红线画出来就再也不动了。
  double? _nowLineY(DateTime now) {
    final mins = now.hour * 60 + now.minute;
    for (final p in activePeriods) {
      final start = p.startHour * 60 + p.startMinute;
      final end = p.endHour * 60 + p.endMinute;
      if (mins >= start && mins <= end) {
        final f = (mins - start) / math.max(1, end - start);
        return (p.section - 1) * sectionHeight + f * sectionHeight;
      }
    }
    for (final p in activePeriods) {
      final start = p.startHour * 60 + p.startMinute;
      if (mins < start) return (p.section - 1) * sectionHeight;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sectionCount;
    final placed = _layout();
    final today = _todayColumn;

    _scheduleAutoScroll(today);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _hCtrl,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderRow(today),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionAxis(sections),
                  for (var d = 0; d < _visibleDays; d++)
                    _buildDayColumn(
                      d,
                      sections,
                      placed[d],
                      isToday: today == d,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 首次布局完成后把今天那一列滚到视野中间（只在有今天时做）。
  void _scheduleAutoScroll(int? today) {
    if (_autoScrolled || today == null || today < 2) return;
    _autoScrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hCtrl.hasClients) return;
      final viewport = _hCtrl.position.viewportDimension;
      final target = today * dayWidth + dayWidth / 2 - viewport / 2;
      final max = _hCtrl.position.maxScrollExtent;
      _hCtrl.jumpTo(target.clamp(0.0, max));
    });
  }

  // ============================ 布局计算 ============================

  /// 一列的节假日元信息（由该列的日期对照 [widget.holidays] 算出）。
  ///
  /// [effectiveDow] 是这列**实际按星期几的课表上**：补班日取日历指定的星期，
  /// 其余取列本身的星期。放假日本身的课全按「不上」处理（[holiday] = true）。
  static const List<String> _dowLabels = ['一', '二', '三', '四', '五', '六', '日'];

  _DayMeta _dayMeta(int d) {
    final start = widget.timetable.startDate;
    if (start == null) {
      return _DayMeta(effectiveDow: d + 1, holiday: false, makeupDow: null);
    }
    final epochDay = epochDayOf(start) + (widget.currentWeek - 1) * 7 + d;
    final holiday = widget.holidays.holidayEpochDays.contains(epochDay);
    final makeup = holiday ? null : widget.holidays.makeupEpochDays[epochDay];
    return _DayMeta(
      effectiveDow: makeup ?? d + 1,
      holiday: holiday,
      makeupDow: makeup,
    );
  }

  /// 把当前周的课程排进「天 × 位置」；同一天内时间重叠的课程并排。
  ///
  /// 返回的列表固定按 7 天索引（下标 = dayOfWeek-1），画几列由调用方决定 ——
  /// 这样关掉周末时不需要动任何下标换算。
  ///
  /// 每列的「今天到底上哪些课」由 [_dayMeta] 决定：
  /// 放假日 → 本列原有的课全算「不上」（半透明，受 showInactiveCourses 控制）；
  /// 补班日 → 画**被补星期**的课（正常不透明），列本身的课算「不上」。
  List<List<_Placed>> _layout() {
    final result = List.generate(days, (_) => <_Placed>[]);
    for (var d = 0; d < days; d++) {
      final meta = _dayMeta(d);
      final nativeDow = d + 1;
      final list = widget.timetable.courses
          .where((c) {
            // 放进本列的课：要么是有效星期（含补班）的课，要么是列本身的课
            if (c.dayOfWeek != meta.effectiveDow && c.dayOfWeek != nativeDow) {
              return false;
            }
            // 「这列真要上」的课，或用户开了「显示非本周课程」
            final active = !meta.holiday &&
                c.dayOfWeek == meta.effectiveDow &&
                c.isActiveOnWeek(widget.currentWeek);
            return active || widget.showInactiveCourses;
          })
          .toList()
        ..sort((a, b) {
          final s = a.startSection.compareTo(b.startSection);
          if (s != 0) return s;
          return a.endSection.compareTo(b.endSection);
        });
      if (list.isEmpty) continue;

      var i = 0;
      while (i < list.length) {
        // 1. 把时间上连通（重叠或首尾相接）的课程切成一个「簇」
        final cluster = <Course>[list[i]];
        var clusterEnd = list[i].endSection;
        var j = i + 1;
        while (j < list.length && list[j].startSection <= clusterEnd) {
          cluster.add(list[j]);
          clusterEnd = math.max(clusterEnd, list[j].endSection);
          j++;
        }

        // 2. 簇内按最早可用泳道排布
        final laneEnds = <int>[];
        final laneOf = <Course, int>{};
        for (final c in cluster) {
          var lane = -1;
          for (var k = 0; k < laneEnds.length; k++) {
            if (laneEnds[k] < c.startSection) {
              lane = k;
              break;
            }
          }
          if (lane < 0) {
            lane = laneEnds.length;
            laneEnds.add(c.endSection);
          } else {
            laneEnds[lane] = c.endSection;
          }
          laneOf[c] = lane;
        }

        final laneWidth = dayWidth / laneEnds.length;
        for (final c in cluster) {
          result[d].add(
            _Placed(
              course: c,
              top: (c.startSection - 1) * sectionHeight,
              height: (c.endSection - c.startSection + 1) * sectionHeight,
              left: laneOf[c]! * laneWidth,
              width: laneWidth,
              conflict: laneEnds.length > 1,
              // 「这列真要上」= 不是放假日、是有效星期（含补班）的课、且本周上。
              // 其余（放假日的课、补班日列本身的课、非本周）都画淡一点
              active: !meta.holiday &&
                  c.dayOfWeek == meta.effectiveDow &&
                  c.isActiveOnWeek(widget.currentWeek),
            ),
          );
        }
        i = j;
      }
    }
    return result;
  }

  // ============================ 视图 ============================

  Widget _buildHeaderRow(int? today) {
    return Row(
      children: [
        const SizedBox(width: axisWidth),
        for (var d = 0; d < _visibleDays; d++)
          Container(
            width: dayWidth,
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: today == d
                  ? AppTheme.primary
                  : AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: _headerContent(d, today == d),
          ),
      ],
    );
  }

  /// 表头一格的内容：正常就是周几；放假日/补班日在下面加一行小字说明。
  Widget _headerContent(int d, bool isToday) {
    final meta = _dayMeta(d);
    final main = isToday ? '今天' : '周${_dowLabels[d]}';
    final style = TextStyle(
      fontWeight: FontWeight.bold,
      color: isToday ? Colors.white : _headerTextColor(d),
    );
    if (!meta.holiday && meta.makeupDow == null) {
      return Text(main, style: style);
    }
    final sub = meta.holiday
        ? '放假'
        : '补周${_dowLabels[meta.makeupDow! - 1]}';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(main, style: style),
        const SizedBox(height: 1),
        Text(
          sub,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: isToday ? Colors.white70 : AppTheme.primary,
          ),
        ),
      ],
    );
  }

  /// 非今天列的表头文字颜色（周末用强调色，与旧行为一致）。
  Color _headerTextColor(int d) => d >= 5 ? AppTheme.accent : AppTheme.textPrimary;

  Widget _buildSectionAxis(int sections) {
    return SizedBox(
      width: axisWidth,
      child: Column(
        children: [
          for (var s = 1; s <= sections; s++)
            _buildAxisTile(s, showSessionStart: _sessionStarts.contains(s)),
        ],
      ),
    );
  }

  Widget _buildAxisTile(int section, {required bool showSessionStart}) {
    Period? period;
    for (final p in activePeriods) {
      if (p.section == section) {
        period = p;
        break;
      }
    }
    return SizedBox(
      width: axisWidth,
      height: sectionHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showSessionStart)
            const SizedBox(
              height: 2,
              width: 26,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFFE5E7EB)),
              ),
            ),
          Text(
            '第$section节',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          if (period != null) ...[
            const SizedBox(height: 2),
            Text(
              period.startText,
              style: const TextStyle(fontSize: 9.5, color: Color(0xFF9CA3AF)),
            ),
            Text(
              period.endText,
              style: const TextStyle(fontSize: 9.5, color: Color(0xFF9CA3AF)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDayColumn(
    int day,
    int sections,
    List<_Placed> placed, {
    required bool isToday,
  }) {
    return SizedBox(
      width: dayWidth,
      height: sections * sectionHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 空网格底
          for (var s = 0; s < sections; s++)
            Positioned(
              top: s * sectionHeight,
              left: 2,
              right: 2,
              height: sectionHeight,
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isToday
                      ? AppTheme.primary.withValues(alpha: 0.05)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isToday
                        ? AppTheme.primary.withValues(alpha: 0.16)
                        : Colors.grey.shade200,
                  ),
                ),
              ),
            ),
          // 上午/下午/晚上分界
          for (final s in _sessionStarts)
            if (s > 1 && s <= sections)
              Positioned(
                top: (s - 1) * sectionHeight - 1,
                left: 0,
                right: 0,
                height: 1,
                child: Container(color: const Color(0xFFE5E7EB)),
              ),
          // 课程块
          for (final p in placed)
            Positioned(
              top: p.top,
              left: p.left,
              width: p.width,
              height: p.height,
              // fit: expand 不能省 —— 默认的 StackFit.loose 会把「宽高都是 0..span」
              // 的松约束传给 CourseCard，卡片于是按内容自适应（实测只有 42~61px 高），
              // 连堂课看起来就只占了一小节（用户 2026-10-04 反馈的那个 bug）。
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 非本周课程（周次没到 / 单双周不对）半透明，一眼能看出「这周不上」
                  Opacity(
                    opacity: p.active ? 1.0 : 0.35,
                    child: CourseCard(
                      course: p.course,
                      color: AppTheme.colorForCourse(p.course.name),
                      onTap: widget.onCourseTap == null
                          ? null
                          : () => widget.onCourseTap!(p.course),
                    ),
                  ),
                  if (p.course.oddEven != 0)
                    Positioned(
                      right: 4,
                      top: 3,
                      child: CourseBadge(
                        text: p.course.oddEven == 1 ? '单' : '双',
                        color: AppTheme.colorForCourse(p.course.name),
                      ),
                    ),
                ],
              ),
            ),
          // 当前时间线：每分钟自己往下挪，不再画一次就定住。
          //
          // 用 `Positioned.fill` + `Transform.translate` 而不是直接改 `Positioned`
          // 的 top —— Stack 只认**直接**的 Positioned 子节点，中间隔一层
          // MinuteTicker 它就不当定位元素了，会整块跑到左上角去。
          if (isToday)
            Positioned.fill(
              child: IgnorePointer(
                child: MinuteTicker(
                  builder: (_, now) {
                    final y = _nowLineY(now);
                    if (y == null) return const SizedBox.shrink();
                    return Transform.translate(
                      offset: Offset(
                        0,
                        y.clamp(0.0, sections * sectionHeight - 2),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 1.5,
                              color: const Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 一个已排好位置的课程块。
class _Placed {
  const _Placed({
    required this.course,
    required this.top,
    required this.height,
    required this.left,
    required this.width,
    required this.conflict,
    this.active = true,
  });

  final Course course;
  final double top;
  final double height;
  final double left;
  final double width;

  /// 同一格是否还有其他冲突课程（并排显示）。
  final bool conflict;

  /// 该课在当前周是否真的上（false = 只在「显示非本周课程」时画出来）。
  final bool active;
}

/// 一列的节假日元信息。
class _DayMeta {
  const _DayMeta({
    required this.effectiveDow,
    required this.holiday,
    required this.makeupDow,
  });

  /// 这列实际按星期几的课表上（补班日 = 日历指定的星期，其余 = 列本身）。
  final int effectiveDow;

  /// 这列是否放假日（本身的课全按「不上」处理）。
  final bool holiday;

  /// 这列是补班日时「按周几上课」；非补班日为 null。
  final int? makeupDow;
}
