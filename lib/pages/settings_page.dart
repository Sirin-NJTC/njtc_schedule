/// 设置页 —— 学期起始日期、总周数、关于。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/reminder_prefs.dart';
import '../models/timetable.dart';
import '../services/reminder_service.dart';
import '../services/widget_service.dart';
import '../theme.dart';

/// 设置页面。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tt = state.active;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (tt != null) _buildTimetableSettings(context, state, tt),
          const SizedBox(height: 16),
          const _DisplaySettings(),
          const SizedBox(height: 16),
          const _ReminderEntry(),
          const SizedBox(height: 12),
          const _PeriodEntry(),
          const SizedBox(height: 12),
          const _HolidayEntry(),
          const SizedBox(height: 12),
          const _WidgetEntry(),
          const SizedBox(height: 24),
          const _AboutSection(),
        ],
      ),
    );
  }

  Widget _buildTimetableSettings(
      BuildContext context, AppState state, Timetable tt) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '当前课表设置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('学期起始日期'),
              subtitle: Text(
                tt.startDate == null
                    ? '未设置（按第1周显示）'
                    : '${tt.startDate!.year}-${tt.startDate!.month.toString().padLeft(2, '0')}-${tt.startDate!.day.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickStartDate(context, state, tt),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('总周数'),
              subtitle: Text('${tt.totalWeeks} 周'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickTotalWeeks(context, state, tt),
            ),
            const Divider(),
            const Text(
              '设置学期起始日期后，应用会自动计算当前是第几周，用于课堂倒计时和周次展示。',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStartDate(
      BuildContext context, AppState state, Timetable tt) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: tt.startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      await state.setStartDate(tt.id, picked);
    }
  }

  Future<void> _pickTotalWeeks(
      BuildContext context, AppState state, Timetable tt) async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        final controller =
            TextEditingController(text: tt.totalWeeks.toString());
        return AlertDialog(
          title: const Text('设置总周数'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '总周数'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                final v = int.tryParse(controller.text.trim());
                if (v != null && v > 0 && v <= 30) {
                  Navigator.pop(context, v);
                }
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (result != null) {
      tt.totalWeeks = result;
      await state.updateTimetable(tt);
    }
  }
}

/// 课表显示开关：周六 / 周日两列、非本周课程是否也画出来。
///
/// 这两个开关只影响**画成什么样**：不动课表数据，也不影响课程提醒
/// （提醒只按课程自己的周次排）。
class _DisplaySettings extends StatelessWidget {
  const _DisplaySettings();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final prefs = state.displayPrefs;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '课表显示',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('显示周六 / 周日'),
              subtitle: const Text(
                '关掉后课表只画周一到周五，每一列更宽、更好点',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              value: prefs.showWeekend,
              onChanged: (v) =>
                  state.updateDisplayPrefs(prefs.copyWith(showWeekend: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('显示非本周课程'),
              subtitle: const Text(
                '把「本学期有、但本周不上」的课半透明画出来（默认只画本周要上的课）',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              value: prefs.showInactiveCourses,
              onChanged: (v) => state.updateDisplayPrefs(
                prefs.copyWith(showInactiveCourses: v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「法定节假日」入口行。
class _HolidayEntry extends StatelessWidget {
  const _HolidayEntry();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cal = state.holidays;
    final skip = state.reminderPrefs.skipHolidays;
    final on = skip && !cal.isEmpty;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (on ? AppTheme.primary : AppTheme.textSecondary)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.event_available_rounded,
            size: 20,
            color: on ? AppTheme.primary : AppTheme.textSecondary,
          ),
        ),
        title: const Text(
          '法定节假日',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            skip ? '${cal.summaryText} · 放假不提醒' : '${cal.summaryText} · 提醒忽略节假日',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pushNamed('/holidays'),
      ),
    );
  }
}

class _ReminderEntry extends StatelessWidget {
  const _ReminderEntry();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final prefs = state.reminderPrefs;
    final status = state.reminderStatus;
    final supported = state.remindersSupported;
    final on = supported && prefs.enabled;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (on ? AppTheme.primary : AppTheme.textSecondary)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.notifications_active_rounded,
            size: 20,
            color: on ? AppTheme.primary : AppTheme.textSecondary,
          ),
        ),
        title: const Text(
          '课程提醒',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(_subtitle(supported, prefs, status)),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pushNamed('/reminders'),
      ),
    );
  }

  String _subtitle(
    bool supported,
    ReminderPrefs prefs,
    ReminderDeviceStatus? status,
  ) {
    if (!supported) return '当前平台不支持（仅 Android 版可用）';
    if (!prefs.enabled) return '已关闭 · 点击开启课程提醒';
    final leads = prefs.sortedLeads;
    final parts = <String>[
      if (leads.isNotEmpty) '提前 ${leads.join(' / ')} 分钟',
      if (prefs.endReminder) '下节课预告',
      if (prefs.vivoAtomic && (status?.isVivo ?? false)) '原子岛',
    ];
    final base = parts.isEmpty ? '已开启，但没有选择任何提醒时机' : parts.join(' · ');
    final count = status?.scheduledCount ?? 0;
    return count > 0 ? '$base · 已排布 $count 个' : base;
  }
}

/// 「节次时间」入口行。
class _PeriodEntry extends StatelessWidget {
  const _PeriodEntry();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final ps = state.periods;
    final customized = state.hasCustomPeriods;
    final base =
        '第1节 ${ps.first.startText} · 第${ps.last.section}节 ${ps.last.endText}';

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (customized ? AppTheme.primary : AppTheme.textSecondary)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.schedule_rounded,
            size: 20,
            color: customized ? AppTheme.primary : AppTheme.textSecondary,
          ),
        ),
        title: const Text(
          '节次时间',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(customized ? '已自定义 · $base' : '学校默认作息 · $base'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pushNamed('/periods'),
      ),
    );
  }
}

/// 桌面小组件入口：说清楚怎么把「今日课程」放到桌面，并顺手同步一次数据。
class _WidgetEntry extends StatelessWidget {
  const _WidgetEntry();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.widgets_rounded,
            size: 20,
            color: AppTheme.primary,
          ),
        ),
        title: const Text(
          '桌面小组件',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('在桌面直接看「今天上什么课」'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showWidgetHelp(context),
      ),
    );
  }

  void _showWidgetHelp(BuildContext context) {
    final state = context.read<AppState>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '把「今日课程」放到桌面',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text(
              '1. 回到手机桌面，长按空白处 → 「桌面挂件 / 小组件」\n'
              '2. 找到「内师课程表」，把「今日课程」拖到桌面上\n'
              '3. 小组件会显示今天的课、上课时间和教室',
              style: TextStyle(fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 8),
            const Text(
              '课表或作息改动后小组件会自动刷新；'
              '换了课表没更新的话，点下面的按钮手动同步一次。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await WidgetService.sync(timetable: state.active, holidays: state.holidays);
                  if (!sheet.mounted) return;
                  Navigator.of(sheet).pop();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已同步到桌面小组件')),
                  );
                },
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: const Text('立即同步'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();
  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '关于',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              // 版本号需与 pubspec.yaml 的 `version:` 保持一致（前者显示、后者决定 APK 文件名与 versionCode）。
              '内江师范学院课程表 v1.1.14\n'
              '支持从教务系统导入课程表（网页登录抓取 / 导出文件 / 粘贴文本），'
              '自动识别周次、节次、单双周，提供周次切换、课堂倒计时、多课表管理等实用功能，'
              '也可以手动添加、编辑、删除单门课程（导入缺了教师或教室时可直接补）；'
              '每节课的上下课时间可以按学校实际作息自己改。'
              '并可按上课前的时机提醒：上午·下午·晚上第一节前 30 分钟会预告该时段全部课程，'
              '每一节课前 5 分钟提醒，下课前 5 分钟预告下一节课（连堂不提醒）。\n\n'
              '桌面小组件「今日课程」可以直接放在桌面上看今天上什么课。\n\n'
              '在 vivo / iQOO 手机上，「下节课预告」还可投递到原子通知与原子岛；'
              '未开通原子通知准入时会自动降级为普通通知。\n\n'
              '数据仅保存在本地设备，不会上传到任何服务器。',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
