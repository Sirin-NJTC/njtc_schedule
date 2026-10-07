/// 手动添加 / 编辑课程页 —— 不依赖导入，自己填一门课。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/course.dart';
import '../models/period.dart';
import '../models/timetable.dart';
import '../theme.dart';

/// 打开课程编辑器，返回 `true` 表示保存过（新增或修改）。
///
/// 还没有任何课表时会**先自动建一份「我的课表」**：这样无论有没有导入成功，
/// 「手动添加课程」这个入口永远可用 —— 导入失败或数据不全时它就是兜底手段。
Future<bool?> openCourseEditor(BuildContext context, {Course? original}) async {
  final app = context.read<AppState>();
  if (app.active == null) {
    await app.addTimetable(
      Timetable(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: '我的课表',
        totalWeeks: 20,
      ),
    );
  }
  if (!context.mounted) return null;
  return Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => CourseEditPage(original: original)),
  );
}

/// 手动添加（`original == null`）或编辑一门课程。
class CourseEditPage extends StatefulWidget {
  /// 要编辑的课程；为 null 表示新增。
  final Course? original;

  const CourseEditPage({super.key, this.original});

  @override
  State<CourseEditPage> createState() => _CourseEditPageState();
}

class _CourseEditPageState extends State<CourseEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _teacher;
  late final TextEditingController _location;

  late int _day;
  late int _startSection;
  late int _endSection;
  late int _startWeek;
  late int _endWeek;
  late int _oddEven;

  bool _saving = false;

  bool get _isEdit => widget.original != null;

  @override
  void initState() {
    super.initState();
    final c = widget.original;
    _name = TextEditingController(text: c?.name ?? '');
    _teacher = TextEditingController(text: c?.teacher ?? '');
    _location = TextEditingController(text: c?.location ?? '');
    _day = c?.dayOfWeek ?? 1;
    _startSection = c?.startSection ?? 1;
    _endSection = c?.endSection ?? 2;
    _startWeek = c?.startWeek ?? 1;
    _endWeek = c?.endWeek ?? (context.read<AppState>().active?.totalWeeks ?? 20);
    _oddEven = c?.oddEven ?? 0;
  }

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _location.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 保存：新增则追加，编辑则**按对象身份替换**（[Course] 是不可变对象）。
  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('请先填写课程名称');
      return;
    }
    if (_startSection > _endSection) {
      _snack('开始节次不能晚于结束节次');
      return;
    }
    if (_startWeek > _endWeek) {
      _snack('开始周次不能晚于结束周次');
      return;
    }

    final app = context.read<AppState>();
    final tt = app.active;
    if (tt == null) {
      _snack('还没有课表，请先创建一份');
      return;
    }

    final course = Course(
      name: name,
      teacher: _teacher.text.trim(),
      location: _location.text.trim(),
      dayOfWeek: _day,
      startSection: _startSection,
      endSection: _endSection,
      startWeek: _startWeek,
      endWeek: _endWeek,
      oddEven: _oddEven,
      courseCode: widget.original?.courseCode ?? '',
      className: widget.original?.className ?? '',
    );

    setState(() => _saving = true);
    if (_isEdit) {
      final idx = tt.courses.indexOf(widget.original!);
      if (idx >= 0) {
        tt.courses[idx] = course;
      } else {
        tt.courses.add(course);
      }
    } else {
      tt.courses.add(course);
    }
    // updateTimetable 会落盘并按新课程重排提醒闹钟。
    await app.updateTimetable(tt);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除课程'),
        content: Text('确定删除「${widget.original!.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除',
                style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final app = context.read<AppState>();
    final tt = app.active;
    if (tt == null) return;
    tt.courses.remove(widget.original);
    await app.updateTimetable(tt);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  static const List<String> _dayNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final totalWeeks = context.watch<AppState>().active?.totalWeeks ?? 20;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑课程' : '添加课程'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: '删除课程',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFEF4444)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        children: [
          _card('课程信息', [
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '课程名称 *',
                hintText: '如 示例课程戊',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _teacher,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '教师',
                      hintText: '如 示例老师B',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _location,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: '地点',
                      hintText: '如 明德楼A103',
                    ),
                  ),
                ),
              ],
            ),
          ]),
          _card('上课时间', [
            _label('星期'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var d = 1; d <= 7; d++)
                  _chip('周${_dayNames[d - 1]}', _day == d,
                      () => setState(() => _day = d)),
              ],
            ),
            const SizedBox(height: 16),
            _label('节次'),
            Row(
              children: [
                Expanded(
                  child: _dropdown<int>(
                    value: _startSection,
                    items: activePeriods
                        .map((p) => DropdownMenuItem(
                              value: p.section,
                              child: Text('第${p.section}节 ${p.startText}',
                                  style: const TextStyle(fontSize: 14)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _startSection = v;
                        if (_endSection < v) _endSection = v;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dropdown<int>(
                    value: _endSection,
                    items: activePeriods
                        .map((p) => DropdownMenuItem(
                              value: p.section,
                              child: Text('第${p.section}节 ${p.endText}',
                                  style: const TextStyle(fontSize: 14)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _endSection = v;
                        if (_startSection > v) _startSection = v;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _label('周次'),
            Row(
              children: [
                Expanded(child: _weekDropdown('开始', _startWeek, totalWeeks, (v) {
                  setState(() {
                    _startWeek = v;
                    if (_endWeek < v) _endWeek = v;
                  });
                })),
                const SizedBox(width: 12),
                Expanded(child: _weekDropdown('结束', _endWeek, totalWeeks, (v) {
                  setState(() {
                    _endWeek = v;
                    if (_startWeek > v) _startWeek = v;
                  });
                })),
              ],
            ),
            const SizedBox(height: 16),
            _label('单双周'),
            Wrap(
              spacing: 8,
              children: [
                _chip('每周', _oddEven == 0, () => setState(() => _oddEven = 0)),
                _chip('单周', _oddEven == 1, () => setState(() => _oddEven = 1)),
                _chip('双周', _oddEven == 2, () => setState(() => _oddEven = 2)),
              ],
            ),
          ]),
          const SizedBox(height: 22),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(_isEdit ? '保存修改' : '添加课程'),
          ),
          const SizedBox(height: 12),
          const Text(
            '提示：同一门课如果一周上多次（不同天或不同节次），分几次添加即可；'
            '保存后课程提醒会自动重排。',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
      );

  Widget _chip(String text, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.12)
              : AppTheme.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.55)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 14, color: AppTheme.primary),
              const SizedBox(width: 4),
            ],
            Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? AppTheme.primary : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _weekDropdown(
    String hint,
    int value,
    int totalWeeks,
    ValueChanged<int> onChanged,
  ) {
    final max = totalWeeks < 1 ? 20 : totalWeeks;
    return _dropdown<int>(
      value: value.clamp(1, max),
      items: [
        for (var w = 1; w <= max; w++)
          DropdownMenuItem(
            value: w,
            child: Text('$hint 第$w周', style: const TextStyle(fontSize: 14)),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
