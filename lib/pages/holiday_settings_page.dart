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
    final ranges = cal.holidayRanges;
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
                  '${cal.holidays.length} 天 · ${ranges.length} 段',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '同一个节日的连续假期合并成一行；点一行可以改名字、起止日期和天数'
              '（放假时长自己定，学校临时调休也照这个改）。',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            if (ranges.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '还没有放假日',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              )
            else
              for (final r in ranges)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(r.name),
                  subtitle: Text(r.subtitle),
                  trailing: IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    onPressed: () => _removeRange(context, state, cal, r),
                  ),
                  onTap: () => _editRange(context, state, cal, r),
                ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _addRange(context, state, cal),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('添加假期'),
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

  // ------------------------------------------------------------ 放假区间

  /// 添加一段假期（默认一天，可以在编辑器里把时长调成任意天数）。
  Future<void> _addRange(
    BuildContext context,
    AppState state,
    HolidayCalendar cal,
  ) async {
    // 一律以**当前**日历为基准：build 时那份可能已经被启动静默联网更新换掉了，
    // 拿旧快照覆盖会把刚联网拿到的官方日历打回内置版 + 你这一处改动。
    final live = state.holidays;
    final edit = await _openRangeEditor(context, cal: live);
    if (edit == null || !context.mounted) return;
    final days = _spanDays(edit.start, edit.end);
    await _apply(
      context,
      state,
      live.withHolidayRange(edit.start, edit.end, name: edit.name),
      '已添加「${edit.name}」${_mdRangeText(edit.start, edit.end)}，共 $days 天',
    );
  }

  /// 点一行 → 改名字 / 改起止日期 / 改时长 / 删掉整段。
  Future<void> _editRange(
    BuildContext context,
    AppState state,
    HolidayCalendar cal,
    HolidayRange range,
  ) async {
    final live = state.holidays;
    final edit = await _openRangeEditor(context, cal: live, editing: range);
    if (edit == null || !context.mounted) return;

    if (edit.delete) {
      final borrowed = range.borrowedCount;
      final ok = await _confirm(
        context,
        '删掉「${range.name}」（${range.dateText}，${range.countText}）？'
            '${borrowed == 0 ? '' : '其中 $borrowed 天是接管来的，会还给${range.borrowedNames.join('、')}。'}',
      );
      if (ok != true || !context.mounted) return;
      await _apply(
        context,
        state,
        live.withoutHolidayRange(range),
        '已删除「${range.name}」',
      );
      return;
    }

    final days = _spanDays(edit.start, edit.end);
    final kept = epochDayOf(edit.start) == epochDayOf(range.start) &&
        epochDayOf(edit.end) == epochDayOf(range.end) &&
        edit.name == range.name;
    if (kept) {
      // 原样保存 = 什么都没干。这里必须直接返回：别去重写存档（会把内置的
      // 「国庆节假期」改名、顺手删掉这段里的补班日），更别把 source 盖上
      // 「手动调整过」——那会让联网更新从此再也不覆盖这份日历。
      _toast(context, '没有改动');
      return;
    }
    await _apply(
      context,
      state,
      live.withHolidayRange(
        edit.start,
        edit.end,
        name: edit.name,
        replacing: range.days.map((d) => d.date),
      ),
      '「${edit.name}」现在是 ${_mdRangeText(edit.start, edit.end)}，共 $days 天',
    );
  }

  Future<void> _removeRange(
    BuildContext context,
    AppState state,
    HolidayCalendar cal,
    HolidayRange range,
  ) async {
    final live = state.holidays;
    final borrowed = range.borrowedCount;
    final ok = await _confirm(
      context,
      '删掉「${range.name}」（${range.dateText}，${range.countText}）？'
          '${borrowed == 0 ? '' : '其中 $borrowed 天是接管来的，会还给${range.borrowedNames.join('、')}。'}',
    );
    if (ok != true || !context.mounted) return;
    await _apply(
      context,
      state,
      live.withoutHolidayRange(range),
      '已删除「${range.name}」',
    );
  }

  Future<_RangeEdit?> _openRangeEditor(
    BuildContext context, {
    required HolidayCalendar cal,
    HolidayRange? editing,
  }) {
    return showModalBottomSheet<_RangeEdit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RangeEditorSheet(calendar: cal, editing: editing),
    );
  }

  Future<void> _addMakeup(
    BuildContext context,
    AppState state,
    HolidayCalendar cal,
  ) async {
    final live = state.holidays;
    final date = await _pickDate(context);
    if (date == null || !context.mounted) return;
    final holidayName = live.holidayName(date);
    if (holidayName != null) {
      // 同一天既放假又补班会打架：原生排程里放假优先，补班会被静默忽略，
      // 而桌面小组件又会照补班画课 —— 干脆拦在门口，让用户先去改放假安排。
      _toast(
        context,
        '${date.month}月${date.day}日在「$holidayName」假期里，'
        '先去放假日删掉这天，再加补班',
      );
      return;
    }
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
      ...live.makeups.where((m) => !_sameDay([m.date], date)),
      MakeupDay(date, weekday, note ?? ''),
    ];
    await _apply(
      context,
      state,
      live.copyWith(makeups: makeups),
      '已添加补班日',
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
      for (final m in state.holidays.makeups)
        if (_sameDay([m.date], target.date)) MakeupDay(m.date, weekday, m.note) else m,
    ];
    await _apply(context, state, state.holidays.copyWith(makeups: makeups), '已修改');
  }

  Future<void> _removeMakeup(
    BuildContext context,
    AppState state,
    HolidayCalendar cal,
    MakeupDay target,
  ) async {
    final ok = await _confirm(context, '删除 ${_ymdText(target.date)} 的补班安排？');
    if (ok != true || !context.mounted) return;
    final makeups = state.holidays.makeups
        .where((m) => !_sameDay([m.date], target.date))
        .toList();
    await _apply(context, state, state.holidays.copyWith(makeups: makeups), '已删除');
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
      initialDate: _inPickerRange(now, _pickerFirst, _pickerLast),
      firstDate: _pickerFirst,
      lastDate: _pickerLast,
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

/// 假期区间编辑器的返回值：保存时带名称与起止日期，删除时 [delete] 为 true。
class _RangeEdit {
  const _RangeEdit({
    required this.name,
    required this.start,
    required this.end,
    this.delete = false,
  });

  final String name;
  final DateTime start;
  final DateTime end;
  final bool delete;
}

/// 「一段假期」的编辑器：名称 + 开始 + 结束 + 天数加减。
///
/// 用底部弹层而不是对话框，是因为日期选择器还要叠在上面，弹层不会被挤变形。
class _RangeEditorSheet extends StatefulWidget {
  const _RangeEditorSheet({required this.calendar, this.editing});

  /// 当前日历（用来实时提示「会接管哪一段」「会删掉几条补班」）。
  final HolidayCalendar calendar;

  /// 正在编辑的那一段；为 null 表示新增。
  final HolidayRange? editing;

  @override
  State<_RangeEditorSheet> createState() => _RangeEditorSheetState();
}

class _RangeEditorSheetState extends State<_RangeEditorSheet> {
  late final TextEditingController _name;
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    final today = DateTime.now();
    _start = editing?.start ?? DateTime(today.year, today.month, today.day);
    _end = editing?.end ?? _start;
    _name = TextEditingController(text: editing?.name ?? '法定节假日');
    // 存档里万一躺着一段超过上限的（手改 / 老数据），先拉回合法区间，
    // 否则「时长」会显示成 200 天、「延长一天」还按 200 天算。
    _clamp();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  int get _dayCount => _spanDays(_start, _end);

  bool _covers(DateTime d) {
    final e = epochDayOf(d);
    return e >= epochDayOf(_start) && e <= epochDayOf(_end);
  }

  /// 新范围压到的补班日（保存后会删掉这些补班安排）。
  List<MakeupDay> get _hitMakeups =>
      [for (final m in widget.calendar.makeups) if (_covers(m.date)) m];

  /// 新范围接管的其它假期段。
  List<HolidayRange> get _hitRanges {
    final days = <int>{
      for (var e = epochDayOf(_start); e <= epochDayOf(_end); e++) e,
    };
    return widget.calendar.rangesOverlapping(days, excluding: widget.editing);
  }

  /// 把结束日期拉回合法区间。
  ///
  /// [keepLength] 非空时按「保持这么长」算 —— 改**开始**日期时用它：
  /// 否则用户把开始选到结束之后，整段会被悄悄压成 1 天（v1.3.0 修掉的老毛病）。
  void _clamp({int? keepLength}) {
    final from = epochDayOf(_start);
    var len = keepLength ?? (epochDayOf(_end) - from + 1);
    if (len < 1) len = 1;
    if (len > maxHolidayRangeDays) len = maxHolidayRangeDays;
    _end = dateOfEpochDay(from + len - 1);
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _inPickerRange(_start, _pickerFirst, _pickerLast),
      firstDate: _pickerFirst,
      lastDate: _pickerLast,
      helpText: '假期开始',
    );
    if (picked == null) return;
    setState(() {
      final len = _dayCount; // 挪开始日期时总天数不动
      _start = DateTime(picked.year, picked.month, picked.day);
      _clamp(keepLength: len);
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _end.isBefore(_start) ? _start : _end,
      firstDate: _start,
      // 日历一律按「天」算（epochDay），别用本地 Duration 加减
      lastDate: dateOfEpochDay(epochDayOf(_start) + maxHolidayRangeDays - 1),
      helpText: '假期结束',
    );
    if (picked == null) return;
    setState(() {
      _end = DateTime(picked.year, picked.month, picked.day);
      _clamp();
    });
  }

  /// 时长 ±1 天（就是「结束日期」往前/往后挪一天）。
  void _bump(int delta) {
    final from = epochDayOf(_start);
    final len = (_dayCount + delta).clamp(1, maxHolidayRangeDays);
    setState(() => _end = dateOfEpochDay(from + len - 1));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing != null;
    final hitRanges = _hitRanges;
    final hitMakeups = _hitMakeups;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              editing ? '调整假期' : '添加假期',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '节日名称',
                hintText: '如 国庆节 / 校运会',
              ),
            ),
            const SizedBox(height: 4),
            _buildDateRow('开始', _start, _pickStart),
            _buildDateRow('结束', _end, _pickEnd),
            Row(
              children: [
                Text(
                  '时长：$_dayCount 天',
                  style: const TextStyle(fontSize: 14),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '缩短一天',
                  onPressed: _dayCount > 1 ? () => _bump(-1) : null,
                  icon: const Icon(Icons.remove_circle_outline, size: 22),
                ),
                IconButton(
                  tooltip: '延长一天',
                  onPressed:
                      _dayCount < maxHolidayRangeDays ? () => _bump(1) : null,
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                ),
              ],
            ),
            if (hitRanges.isNotEmpty)
              _buildWarn(
                '与「${hitRanges.map((r) => r.name).join('、')}」重叠的那几天'
                '会归到这一行（以后缩短或删掉这一段，会自动还给'
                '${hitRanges.map((r) => r.name).join('、')}）',
              ),
            if (hitMakeups.isNotEmpty)
              _buildWarn(
                '这段里 ${hitMakeups.length} 天排了补班，保存后会删掉那些补班安排'
                '（放假优先）',
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (editing)
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _RangeEdit(
                        name: _name.text.trim(),
                        start: _start,
                        end: _end,
                        delete: true,
                      ),
                    ),
                    child: const Text(
                      '删除这一段',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(
                    context,
                    _RangeEdit(
                      name: _name.text.trim().isEmpty
                          ? '法定节假日'
                          : _name.text.trim(),
                      start: _start,
                      end: _end,
                    ),
                  ),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRow(String label, DateTime date, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: Text('${_ymdText(date)}  ${_weekText(date)}'),
      trailing: const Icon(Icons.edit_calendar_outlined, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildWarn(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 14, color: Colors.orange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

bool _sameDay(Iterable<DateTime> days, DateTime target) =>
    days.any((d) =>
        d.year == target.year && d.month == target.month && d.day == target.day);

String _ymdText(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 日期选择器允许的范围（挑节日 / 挑补班日都用这一套）。
final DateTime _pickerFirst = DateTime(2020);
final DateTime _pickerLast = DateTime(2035);

/// 把日期收进选择器范围内 —— 存档里可能躺着 2035 年以后的假期，
/// 直接当 `initialDate` 喂给 `showDatePicker` 会触发断言。
DateTime _inPickerRange(DateTime d, DateTime lo, DateTime hi) {
  final e = epochDayOf(d);
  if (e < epochDayOf(lo)) return lo;
  if (e > epochDayOf(hi)) return hi;
  return DateTime(d.year, d.month, d.day);
}

/// 一段假期有几天（含首尾）。
int _spanDays(DateTime start, DateTime end) {
  final span = epochDayOf(end) - epochDayOf(start);
  return (span < 0 ? -span : span) + 1;
}

/// `10月1日 – 10月7日`（跨年时两边都带年份）；同一天只写一个。
String _mdRangeText(DateTime start, DateTime end) {
  final a = start.isAfter(end) ? end : start;
  final b = start.isAfter(end) ? start : end;
  final crossYear = a.year != b.year;
  final aText = crossYear ? _ymdText(a) : '${a.month}月${a.day}日';
  if (epochDayOf(a) == epochDayOf(b)) return aText;
  final bText = crossYear ? _ymdText(b) : '${b.month}月${b.day}日';
  return '$aText – $bText';
}

String _weekText(DateTime d) => '周${MakeupDay.weekdayLabels[d.weekday - 1]}';

/// 「10月5日 15:20」这样的更新时间。
String _timeText(DateTime d) =>
    '${d.month}月${d.day}日 '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
