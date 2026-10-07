/// 课表全览 —— 把一整周画在一张放大的画布上，双指缩放、拖动看细节。
///
/// 和首页那张网格是同一个 [TimetableGrid]，只是换了更大的列宽/行高并打开
/// `zoomable`（不再套内部滚动，交给 InteractiveViewer 缩放拖拽），所以两边的
/// 排版规则、放假/补班/单双周/非本周的半透明表现完全一致，不会各说各话。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/course_detail.dart';
import '../widgets/timetable_grid.dart';

/// 课表全览页（当前这一周，放大展示）。
class WeekOverviewPage extends StatefulWidget {
  const WeekOverviewPage({super.key});

  @override
  State<WeekOverviewPage> createState() => _WeekOverviewPageState();
}

class _WeekOverviewPageState extends State<WeekOverviewPage> {
  /// 自己翻到第几周；null = 跟着首页的当前周走。
  int? _week;

  /// 变一下就让网格整棵重建 —— 换个 key 是复位缩放的省事办法
  /// （TransformationController 在网格内部，外面拿不到）。
  int _resetToken = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tt = state.active;

    if (tt == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('课表全览')),
        body: const Center(child: Text('还没有课程表')),
      );
    }

    final total = tt.totalWeeks < 1 ? 1 : tt.totalWeeks;
    final week = (_week ?? state.currentWeek).clamp(1, total);

    return Scaffold(
      appBar: AppBar(
        title: const Text('课表全览'),
        actions: [
          if (week != state.currentWeek)
            TextButton(
              onPressed: () => setState(() => _week = state.currentWeek),
              child: const Text('回到本周'),
            ),
          IconButton(
            tooltip: '复位缩放',
            onPressed: () => setState(() => _resetToken++),
            icon: const Icon(Icons.center_focus_strong_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildWeekBar(state, week, total),
            const Divider(height: 1),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey('week-overview-$_resetToken'),
                child: TimetableGrid(
                  timetable: tt,
                  currentWeek: week,
                  showWeekend: state.displayPrefs.showWeekend,
                  showInactiveCourses: state.displayPrefs.showInactiveCourses,
                  holidays: state.holidays,
                  // 首页是 118 × 74；全览页放大到 176 × 112，再靠双指缩放看细节。
                  dayWidth: 176,
                  sectionHeight: 112,
                  zoomable: true,
                  onCourseTap: (c) => showCourseDetail(context, c),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 周次切换条：左右箭头翻周，中间点开周次选择器。
  Widget _buildWeekBar(AppState state, int week, int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: '上一周',
            onPressed: week > 1 ? () => setState(() => _week = week - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _pickWeek(week, total),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '第 $week 周',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                        if (week == state.currentWeek) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '本周',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 2),
                        const Icon(Icons.expand_more,
                            size: 18, color: AppTheme.primary),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '整周一页 · 双指缩放 · 拖动看细节',
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '下一周',
            onPressed: week < total ? () => setState(() => _week = week + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  /// 周次选择器（底部弹出的网格，跟首页同一个手感）。
  Future<void> _pickWeek(int week, int total) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '选择周次',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              height: 260,
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.5,
                ),
                itemCount: total,
                itemBuilder: (_, i) {
                  final w = i + 1;
                  final selected = w == week;
                  return InkWell(
                    onTap: () => Navigator.pop(ctx, w),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '第$w周',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : AppTheme.primary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _week = picked);
  }
}

/// 供首页调用的入口（`tt` 为空时首页本来就不会显示这个按钮）。
Future<void> showWeekOverview(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const WeekOverviewPage()),
  );
}
