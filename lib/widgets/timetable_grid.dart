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
import '../models/period.dart';
import '../models/timetable.dart';
import '../theme.dart';
import 'course_card.dart';

/// 课程表网格（周一到周日 × 节次）。
class TimetableGrid extends StatefulWidget {
  final Timetable timetable;
  final int currentWeek;
  final void Function(Course course)? onCourseTap;

  const TimetableGrid({
    super.key,
    required this.timetable,
    required this.currentWeek,
    this.onCourseTap,
  });

  @override
  State<TimetableGrid> createState() => _TimetableGridState();
}

class _TimetableGridState extends State<TimetableGrid> {
  static const int days = 7;
  static const double dayWidth = 118;
  static const double axisWidth = 54;
  static const double sectionHeight = 74;

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
    final startDay = DateTime(start.year, start.month, start.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(startDay).inDays;
    if (diff < 0) return null;
    if (diff ~/ 7 + 1 != widget.currentWeek) return null;
    return now.weekday - 1;
  }

  /// 当前时刻在网格中的 y 坐标（不在上课时段就贴到相邻边界）。
  double? _nowLineY() {
    final now = DateTime.now();
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
                  for (var d = 0; d < days; d++)
                    _buildDayColumn(
                      d,
                      sections,
                      placed[d],
                      isToday: today == d,
                      nowY: today == d ? _nowLineY() : null,
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

  /// 把当前周的课程排进「天 × 位置」；同一天内时间重叠的课程并排。
  List<List<_Placed>> _layout() {
    final result = List.generate(days, (_) => <_Placed>[]);
    for (var d = 0; d < days; d++) {
      final list = widget.timetable.courses
          .where((c) =>
              c.dayOfWeek == d + 1 && c.isActiveOnWeek(widget.currentWeek))
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
        for (var d = 0; d < days; d++)
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
            child: Text(
              d == today
                  ? '今天'
                  : '周${['一', '二', '三', '四', '五', '六', '日'][d]}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: today == d
                    ? Colors.white
                    : (d >= 5 ? AppTheme.accent : AppTheme.textPrimary),
              ),
            ),
          ),
      ],
    );
  }

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
    double? nowY,
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
              child: Stack(
                children: [
                  CourseCard(
                    course: p.course,
                    color: AppTheme.colorForCourse(p.course.name),
                    onTap: widget.onCourseTap == null
                        ? null
                        : () => widget.onCourseTap!(p.course),
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
          // 当前时间线
          if (nowY != null)
            Positioned(
              top: nowY.clamp(0.0, sections * sectionHeight - 2),
              left: 0,
              right: 0,
              child: IgnorePointer(
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
                      child: Container(height: 1.5, color: const Color(0xFFEF4444)),
                    ),
                  ],
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
  });

  final Course course;
  final double top;
  final double height;
  final double left;
  final double width;

  /// 同一格是否还有其他冲突课程（并排显示）。
  final bool conflict;
}
