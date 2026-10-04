/// 节次时间设置页 —— 自定义每一节的开始 / 结束时间。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/period.dart';
import '../theme.dart';

/// 节次时间设置页。
///
/// 页面上编辑的是一份「草稿」(`_list`)，点「保存」才写回 `AppState`；
/// 这样用户改到一半返回不会把作息弄乱。
class PeriodSettingsPage extends StatefulWidget {
  const PeriodSettingsPage({super.key});

  @override
  State<PeriodSettingsPage> createState() => _PeriodSettingsPageState();
}

class _PeriodSettingsPageState extends State<PeriodSettingsPage> {
  late List<Period> _list;

  @override
  void initState() {
    super.initState();
    _list = List<Period>.from(context.read<AppState>().periods);
  }

  Future<void> _pickTime(int index, bool isStart) async {
    final p = _list[index];
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart
          ? TimeOfDay(hour: p.startHour, minute: p.startMinute)
          : TimeOfDay(hour: p.endHour, minute: p.endMinute),
      helpText: '第${p.section}节 ${isStart ? '开始' : '结束'}时间',
      // 手机上 24 小时制更贴合课表习惯（08:00 / 14:30 这种写法）
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;

    setState(() {
      _list[index] = isStart
          ? p.withTime(
              startHour: picked.hour,
              startMinute: picked.minute,
              endHour: p.endHour,
              endMinute: p.endMinute,
            )
          : p.withTime(
              startHour: p.startHour,
              startMinute: p.startMinute,
              endHour: picked.hour,
              endMinute: picked.minute,
            );
    });
  }

  /// 把时间换成「当天第几分钟」，方便比较先后。
  int _minutesOf(int hour, int minute) => hour * 60 + minute;

  Future<void> _save() async {
    final bad = firstInvalidSection(_list);
    if (bad != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('第$bad 节的结束时间要晚于开始时间')),
      );
      return;
    }

    await context.read<AppState>().updatePeriods(_list);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存，课程提醒已按新时间重新排布')),
    );
    Navigator.of(context).pop();
  }

  void _restoreDefaults() {
    setState(() {
      _list = List<Period>.from(defaultPeriods);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已填回学校默认作息，记得点下面的保存')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('节次时间'),
        actions: [
          TextButton(
            onPressed: _restoreDefaults,
            child: const Text('恢复默认'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _buildHint(),
          const SizedBox(height: 14),
          _buildPeriodCard(),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '保存',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHint() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.primary),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '课表里显示的节次时间、首页倒计时、以及课程提醒的触发时刻，'
              '都是按这里的时间算的。改完保存后提醒会自动重排。',
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _list.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _buildRow(i),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(int index) {
    final p = _list[index];
    final minutes = _minutesOf(p.endHour, p.endMinute) -
        _minutesOf(p.startHour, p.startMinute);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              p.label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                _timeButton(
                  text: p.startText,
                  onTap: () => _pickTime(index, true),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('~', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                _timeButton(
                  text: p.endText,
                  onTap: () => _pickTime(index, false),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              '$minutes 分',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeButton({required String text, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }
}
