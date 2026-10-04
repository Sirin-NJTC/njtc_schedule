/// 法定节假日 / 调休补班日设置页。
///
/// 为什么需要它：法定节假日不上课，但课表里的课是按**周几**排的 ——
/// 放假那天的课不会自动消失，于是提醒会照响。这里给出一份可自行增删改的
/// 日历：放假那天不排提醒，调休补班那天按「补的是周几」的课表排提醒。
///
/// 日期来源：内置那份是按公开日历整理的**估算值**，可以点「联网更新」拉官方
/// 公布的数据；**学校的具体调休安排以学校通知为准**，所以这里的一切都可以改。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/holiday_calendar.dart';
import '../storage/holiday_store.dart';
import '../theme.dart';

/// 节假日设置页。
class HolidaySettingsPage extends StatefulWidget {
  const HolidaySettingsPage({super.key});

  @override
  State<HolidaySettingsPage> createState() => _HolidaySettingsPageState();
}

class _HolidaySettingsPageState extends State<HolidaySettingsPage> {
  /// 正在联网更新（按钮转圈 + 防重复点）。
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cal = state.holidays;
    final skip = state.reminderPrefs.skipHolidays;

    return Scaffold(
      appBar: AppBar(title: const Text('法定节假日')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSyncCard(context, state, cal),
          const SizedBox(height: 16),
          _buildSwitchCard(context, state, skip, cal),
          const SizedBox(height: 16),
          _buildMakeupCard(context, state, cal),
          const SizedBox(height: 16),
          _buildHolidayCard(context, state, cal),
          const SizedBox(height: 16),
          _buildFooter(context, state),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 联网更新

  Widget _buildSyncCard(
    BuildContext context,
    AppState state,
    HolidayCalendar cal,
  ) {
    final meta = state.holidayMeta;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '联网更新',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${_sourceText(meta)} · ${cal.summaryText}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            const Text(
              '放假与调休安排以公开的节假日数据为准，联网更新会按年份整年替换'
              '（接口还没公布的年份保持不动）。补班日「按周几上课」接口不给，'
              '这里按惯例推导，请按学校通知核对。',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _syncing ? null : () => _syncFromNetwork(context, state),
                icon: _syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync_outlined, size: 18),
                label: Text(_syncing ? '正在联网更新…' : '立即联网更新'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sourceText(HolidayMeta meta) {
    switch (meta.source) {
      case HolidayStore.sourceNet:
        final at = meta.updatedAt;
        return at == null ? '来自联网更新' : '来自联网更新（${_timeText(at)}）';
      case HolidayStore.sourceManual:
        return '手动调整过，未联网核对';
      default:
        return '内置估算值，建议联网更新';
    }
  }

  /// 联网更新：有手动改过的条目时先问一句（联网会整年替换）。
  Future<void> _syncFromNetwork(BuildContext context, AppState state) async {
    if (state.holidayMeta.source == HolidayStore.sourceManual) {
      final ok = await _confirm(
        context,
        '联网更新会按年份整年替换现在的日历，你手动加/改过的条目可能被覆盖。继续？',
        confirmText: '继续',
      );
      if (ok != true || !context.mounted) return;
    }
    setState(() => _syncing = true);
    final outcome = await state.syncHolidaysFromNetwork();
    if (!context.mounted) return;
    setState(() => _syncing = false);
    _toast(
      context,
      outcome.ok
          ? '已联网更新（${outcome.note}）：${outcome.calendar.summaryText}'
          : '联网更新失败：${outcome.note}（日历保持原样）',
    );
  }

  // ------------------------------------------------------------ 开关

  Widget _buildSwitchCard(
    BuildContext context,
    AppState state,
    bool skip,
    HolidayCalendar cal,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '节假日关闭通知',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('放假当天不提醒'),
              subtitle: const Text(
                '开启后，下面列出的放假日整天不弹课程提醒；'
                '调休补班日照常按「补的那天」提醒',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              value: skip,
              onChanged: (v) => state.updateReminderPrefs(
                state.reminderPrefs.copyWith(skipHolidays: v),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 补班日

  Widget _buildMakeupCard(
    BuildContext context,
    AppState state,
    HolidayCalendar cal,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '调休补班日',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${cal.makeups.length} 天',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '某天补课就加一条，比如「10 月 10 日（周六）补周三的课」。'
              '不补课就别加 —— 加错了会多提醒。',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            if (cal.makeups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '还没有补班日',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              )
            else
              for (final m in cal.makeups)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${_ymdText(m.date)}  ${_weekText(m.date)}'),
                  subtitle: Text(
                    [m.weekdayText, if (m.note.isNotEmpty) m.note].join(' · '),
                  ),
                  trailing: IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    onPressed: () => _removeMakeup(context, state, cal, m),
                  ),
                  onTap: () => _editMakeup(context, state, cal, m),
                ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _addMakeup(context, state, cal),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('添加补班日'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 放假日

  Widget _buildHolidayCard(
    BuildContext context,
    AppState state,
    HolidayCalendar cal,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '放假日',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${cal.holidays.length} 天',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '放假当天不上课，所以不需要提醒。点一行可以改名字。',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            if (cal.holidays.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '还没有放假日',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              )
            else
              for (final h in cal.holidays)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${_ymdText(h.date)}  ${_weekText(h.date)}'),
                  subtitle: Text(h.name),
                  trailing: IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    onPressed: () => _removeHoliday(context, state, cal, h),
                  ),
                  onTap: () => _editHoliday(context, state, cal, h),
                ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _addHoliday(context, state, cal),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('添加放假日'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _reset(context, state),
                  child: const Text('恢复内置'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, AppState state) {
    final prefs = state.reminderPrefs;
    return Text(
      '改完会立刻重排提醒（当前：${prefs.summaryText}）。'
      '联网更新拿到的是国家公布的放假安排，学校临时调休仍需以学校通知为准。',
      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
    );
  }

  // ------------------------------------------------------------ 动作

  Future<void> _addHoliday(
    BuildContext context,
    AppState state,
    HolidayCalendar cal,
  ) async {
    final date = await _pickDate(context);
    if (date == null || !context.mounted) return;
    final name = await _askText(
      context,
      title: '假日名称',
      hint: '如 国庆节 / 校运会',
      initial: '法定节假日',
    );
    if (name == null || !context.mounted) return;

    if (_sameDay(cal.makeups.map((m) => m.date), date)) {
      // 同一天不能既放假又补课（放假优先，补班会被忽略），所以这里直接冲突提示
      _toast(context, '这一天已经是补班日，请先删掉那条补班安排');
      return;
    }
    final holidays = [
      ...cal.holidays.where((h) => !_sameDay([h.date], date)),
      HolidayDay(date, name.isEmpty ? '法定节假日' : name),
    ];
    await _apply(context, state, cal.copyWith(holidays: holidays), '已添加 ${_ymdText(date)}');
  }

  Future<void> _editHoliday(
    BuildContext context,
    AppState state,
    HolidayCalendar cal,
    HolidayDay target,
  ) async {
    final name = await _askText(
      context,
      title: '假日名称',
      hint: '如 国庆节',
      initial: target.name,
    );
    if (name == null || !context.mounted) return;
    final holidays = [
      for (final h in cal.holidays)
        if (_sameDay([h.date], target.date)) HolidayDay(h.date, name) else h,
    ];
    await _apply(context, state, cal.copyWith(holidays: holidays), '已修改');
  }

  Future<void> _removeHoliday(
    BuildContext context,
    AppState state,
    HolidayCalendar cal,
    HolidayDay target,
  ) async {
    final ok = await _confirm(context, '删除 ${_ymdText(target.date)}（${target.name}）？');
    if (ok != true || !context.mounted) return;
    final holidays =
        cal.holidays.where((h) => !_sameDay([h.date], target.date)).toList();
    await _apply(context, state, cal.copyWith(holidays: holidays), '已删除');
  }

  Future<void> _addMakeup(
    BuildContext context,
    AppState state,
    HolidayCalendar cal,
  ) async {
    final date = await _pickDate(context);
    if (date == null || !context.mounted) return;
    final weekday = await _askWeekday(context, initial: date.weekday);
    if (weekday == null || !context.mounted) return;
    final note = await _askText(
      context,
      title: '备注（可留空）',
      hint: '补周三的课',
      initial: '',
    );
    if (!context.mounted) return;

    final makeups = [
      ...cal.makeups.where((m) => !_sameDay([m.date], date)),
      MakeupDay(date, weekday, note ?? ''),
    ];
    // 补班日 + 放假日同日会互相打架（放假优先），所以加补班时把同日的放假删掉
    final holidays =
        cal.holidays.where((h) => !_sameDay([h.date], date)).toList();
    final dropped = cal.holidays.length != holidays.length;
    await _apply(
      context,
      state,
      cal.copyWith(makeups: makeups, holidays: holidays),
      dropped ? '已添加补班日，并移除了同日放假日' : '已添加补班日',
    );
  }

  Future<void> _editMakeup(
    BuildContext context,
    AppState state,
    HolidayCalendar cal,
    MakeupDay target,
  ) async {
    final weekday = await _askWeekday(context, initial: target.weekday);
    if (weekday == null || !context.mounted) return;
    final makeups = [
      for (final m in cal.makeups)
        if (_sameDay([m.date], target.date)) MakeupDay(m.date, weekday, m.note) else m,
    ];
    await _apply(context, state, cal.copyWith(makeups: makeups), '已修改');
  }

  Future<void> _removeMakeup(
    BuildContext context,
    AppState state,
    HolidayCalendar cal,
    MakeupDay target,
  ) async {
    final ok = await _confirm(context, '删除 ${_ymdText(target.date)} 的补班安排？');
    if (ok != true || !context.mounted) return;
    final makeups =
        cal.makeups.where((m) => !_sameDay([m.date], target.date)).toList();
    await _apply(context, state, cal.copyWith(makeups: makeups), '已删除');
  }

  Future<void> _reset(BuildContext context, AppState state) async {
    final ok = await _confirm(
      context,
      '恢复成内置的那份节假日日历？你后来加的都会没。',
      confirmText: '恢复',
    );
    if (ok != true || !context.mounted) return;
    final result = await state.resetHolidays();
    if (!context.mounted) return;
    _toast(context, result.note);
  }

  /// 存盘 + 重排提醒 + 一句反馈。重排失败也要说清楚，否则用户以为没生效。
  Future<void> _apply(
    BuildContext context,
    AppState state,
    HolidayCalendar next,
    String okText,
  ) async {
    final result = await state.updateHolidays(next);
    if (!context.mounted) return;
    _toast(context, result.ok ? okText : '$okText，但提醒没排上：${result.note}');
  }

  // ------------------------------------------------------------ 小工具

  Future<DateTime?> _pickDate(BuildContext context) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: '选择日期',
    );
  }

  Future<int?> _askWeekday(BuildContext context, {required int initial}) {
    return showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('这天按周几的课表上课？'),
        children: [
          for (var w = 1; w <= 7; w++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, w),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      '周${MakeupDay.weekdayLabels[w - 1]}',
                      style: TextStyle(
                        fontWeight:
                            w == initial ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (w == initial) ...[
                      const SizedBox(width: 8),
                      const Text(
                        '（当前）',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<String?> _askText(
    BuildContext context, {
    required String title,
    required String hint,
    required String initial,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 二次确认。默认按钮是「删除」，做恢复 / 清空时记得传 [confirmText]。
  Future<bool?> _confirm(
    BuildContext context,
    String message, {
    String confirmText = '删除',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }
}

bool _sameDay(Iterable<DateTime> days, DateTime target) =>
    days.any((d) =>
        d.year == target.year && d.month == target.month && d.day == target.day);

String _ymdText(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _weekText(DateTime d) => '周${MakeupDay.weekdayLabels[d.weekday - 1]}';

/// 「10月5日 15:20」这样的更新时间。
String _timeText(DateTime d) =>
    '${d.month}月${d.day}日 '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
