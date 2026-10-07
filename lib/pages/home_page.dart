/// 首页 —— 课程表主视图，含周次切换、倒计时、课表切换。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/semester.dart';
import '../models/timetable.dart';
import '../theme.dart';
import '../widgets/course_detail.dart';
import '../widgets/minute_ticker.dart';
import '../widgets/timetable_grid.dart';
import 'course_edit_page.dart';

/// 首页主视图。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tt = state.active;

    return Scaffold(
      body: SafeArea(
        child: tt == null
            ? const _EmptyState()
            : Column(
                children: [
                  _buildHeader(context, state, tt),
                  Expanded(
                    child: TimetableGrid(
                      timetable: tt,
                      currentWeek: state.currentWeek,
                      showWeekend: state.displayPrefs.showWeekend,
                      showInactiveCourses:
                          state.displayPrefs.showInactiveCourses,
                      holidays: state.holidays,
                      onCourseTap: (c) => showCourseDetail(context, c),
                    ),
                  ),
                  _buildBottomBar(context, state),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppState state, Timetable tt) {
    // 算一次复用，别在同一帧里连算三遍
    final realWeek = _realWeek(tt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tt.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (tt.semester.isNotEmpty || tt.major.isNotEmpty)
                      Text(
                        [tt.semester, tt.major].where((e) => e.isNotEmpty).join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              // 倒计时不能只在 build 时算一次 —— 用 MinuteTicker 让它每分钟自己走。
              // 故意把 ticker 收在这一小块上，别让它带着整张网格一起重建。
              MinuteTicker(builder: (_, now) => _buildCountdown(state, tt, now)),
              const SizedBox(width: 4),
              _buildAddButton(context),
              const SizedBox(width: 4),
              _buildReminderButton(context, state),
            ],
          ),
          const SizedBox(height: 12),
          // 周次切换条：左右箭头翻页，中间点开周次选择器
          Row(
            children: [
              IconButton(
                onPressed: state.currentWeek > 1 ? state.prevWeek : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => _showWeekPicker(context, state, tt),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '第 ${state.currentWeek} 周',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.expand_more,
                            size: 18, color: AppTheme.primary),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed:
                    state.currentWeek < tt.totalWeeks ? state.nextWeek : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          // 看的不是本周时，给一个一键回到本周的入口
          if (realWeek != null && realWeek != state.currentWeek)
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: () => state.setCurrentWeek(realWeek),
                icon: const Icon(Icons.today_rounded, size: 16),
                label: Text('回到本周 · 第 $realWeek 周',
                    style: const TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          if (tt.startDate == null) ...[
            const SizedBox(height: 2),
            InkWell(
              onTap: () => Navigator.pushNamed(context, '/settings'),
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 14, color: Color(0xFFD97706)),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '未设置学期起始日期，「第几周」与课程提醒可能不准 · 点此设置',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFFD97706)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 右上角「手动添加课程」入口：不依赖导入，随时可以自己加一门课。
  Widget _buildAddButton(BuildContext context) {
    return Tooltip(
      message: '手动添加课程',
      child: InkWell(
        onTap: () => openCourseEditor(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.add_rounded,
            size: 20,
            color: AppTheme.primary,
          ),
        ),
      ),
    );
  }

  /// 右上角的课程提醒入口：开启时为实心主色，未开启为灰色描边。
  Widget _buildReminderButton(BuildContext context, AppState state) {
    final supported = state.remindersSupported;
    final on = supported && state.reminderPrefs.enabled;
    final color = on ? AppTheme.primary : AppTheme.textSecondary;
    return Tooltip(
      message: !supported
          ? '课程提醒（仅 Android 版可用）'
          : on
              ? '课程提醒已开启'
              : '课程提醒未开启',
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, '/reminders'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            on
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            size: 20,
            color: color,
          ),
        ),
      ),
    );
  }

  /// 「今天」真正处在第几周（没有学期起始日期时返回 null）。
  ///
  /// 算法统一走 [weekOfSemester]。这里原先另抄了一份（还抄得和 `AppState`
  /// 那份不一样），结果「回到本周」跳的周和网格高亮的今天可能不是同一周。
  /// 只用于显示，不改变全局状态。
  int? _realWeek(Timetable tt) => currentWeekOf(tt.startDate, tt.totalWeeks);

  static String _monthDay(DateTime d) => '${d.month}/${d.day}';

  /// 周次选择器：列出全部周次，标出本周与当前查看的周。
  void _showWeekPicker(BuildContext context, AppState state, Timetable tt) {
    final total = tt.totalWeeks;
    final real = _realWeek(tt);
    final start = tt.startDate;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Row(
                children: [
                  const Icon(Icons.calendar_view_week_rounded,
                      size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  const Text(
                    '选择周次',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '共 $total 周',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Flexible(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                shrinkWrap: true,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.35,
                ),
                itemCount: total,
                itemBuilder: (_, index) {
                  final week = index + 1;
                  final selected = week == state.currentWeek;
                  final isReal = week == real;
                  final fg = selected ? Colors.white : AppTheme.textPrimary;
                  return InkWell(
                    onTap: () {
                      state.setCurrentWeek(week);
                      Navigator.pop(sheetContext);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.primary
                            : isReal
                                ? AppTheme.primary.withValues(alpha: 0.08)
                                : AppTheme.background,
                        borderRadius: BorderRadius.circular(12),
                        border: isReal && !selected
                            ? Border.all(
                                color: AppTheme.primary.withValues(alpha: 0.45))
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '第 $week 周',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: fg,
                            ),
                          ),
                          if (start != null)
                            Text(
                              // 走 epochDay 反推，不用 add(Duration) —— 夏令时地区
                              // 会把 23/25 小时的一天算进去
                              _monthDay(startOfWeek(startDate: start, week: week)!),
                              style: TextStyle(
                                fontSize: 10,
                                color: selected
                                    ? Colors.white70
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          if (isReal)
                            Text(
                              '本周',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : AppTheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 距离下一节课的倒计时。
  ///
  /// [now] 由 [MinuteTicker] 每分钟递进来 —— 这里刻意不自己读 `DateTime.now()`，
  /// 否则算一次就冻住了。
  ///
  /// 查找交给 [nextClassOccurrence]：它会跨天找（今天的课上完了就找明天的）、
  /// 跳过放假日、并认得补班日。早先这里只扫今天，且拿「正在查看的周」过滤，
  /// 用户翻到别的周时今天真实的课反而被藏掉。
  Widget _buildCountdown(AppState state, Timetable tt, DateTime now) {
    final next = nextClassOccurrence(
      courses: tt.courses,
      holidays: state.holidays,
      startDate: tt.startDate,
      totalWeeks: tt.totalWeeks,
      periods: state.periods,
      from: now,
    );
    if (next == null) return const SizedBox.shrink();

    final Widget mainText;
    if (next.isToday) {
      final diff = next.startsAt.difference(now);
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      mainText = Text(
        hours > 0 ? '$hours小时$minutes分' : '$minutes分钟',
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppTheme.primary,
        ),
      );
    } else {
      // 今天的课上完了：告诉用户下一节课在什么时候，而不是什么都不显示
      mainText = Text(
        '${_dayLabel(now, next.startsAt)} ${_hm(next.startsAt)}',
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: AppTheme.primary,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            next.isToday ? '即将上课' : '下一节课',
            style: const TextStyle(fontSize: 11, color: AppTheme.primary),
          ),
          mainText,
          Text(
            next.course.name,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// 未来某天怎么称呼：明天 / 后天 / 周几。
  static String _dayLabel(DateTime now, DateTime target) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(target.year, target.month, target.day);
    final gap = day.difference(today).inDays;
    if (gap == 1) return '明天';
    if (gap == 2) return '后天';
    return '周${['一', '二', '三', '四', '五', '六', '日'][target.weekday - 1]}';
  }

  Widget _buildBottomBar(BuildContext context, AppState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _navItem(context, Icons.grid_view, '课表', () {}),
          _navItem(context, Icons.download, '导入',
              () => Navigator.pushNamed(context, '/import')),
          _navItem(context, Icons.swap_horiz, '切换',
              () => Navigator.pushNamed(context, '/timetables')),
          _navItem(context, Icons.settings, '设置',
              () => Navigator.pushNamed(context, '/settings')),
        ],
      ),
    );
  }

  Widget _navItem(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.textSecondary),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_month, size: 96, color: Colors.grey.shade300),
          const SizedBox(height: 20),
          const Text(
            '还没有课程表',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '从教务系统导入你的课程表吧',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/import'),
            icon: const Icon(Icons.download),
            label: const Text('导入课表'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => openCourseEditor(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('手动添加课程'),
          ),
          const SizedBox(height: 8),
          const Text(
            '不想用导入？也可以自己一门一门加',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
