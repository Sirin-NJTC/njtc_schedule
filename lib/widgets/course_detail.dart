/// 课程详情弹窗 —— 显示课程完整信息。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/course.dart';
import '../pages/course_edit_page.dart';
import '../theme.dart';

/// 显示课程详情。
Future<void> showCourseDetail(BuildContext context, Course course) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // 把外层的 context 传进弹窗：弹窗自己 pop 之后它的 context 已失效，
    // 而「编辑」需要 pop 完弹窗再 push 编辑页。
    builder: (_) => _CourseDetailSheet(course: course, hostContext: context),
  );
}

class _CourseDetailSheet extends StatelessWidget {
  final Course course;

  /// 弹出这个弹窗的那个页面 context，用于 pop / push / 读 AppState。
  final BuildContext hostContext;

  const _CourseDetailSheet({required this.course, required this.hostContext});

  /// 编辑：先关掉详情弹窗，再打开编辑页。
  Future<void> _edit() async {
    Navigator.pop(hostContext);
    await openCourseEditor(hostContext, original: course);
  }

  /// 删除：二次确认后从当前课表移除并落盘（会顺带重排提醒）。
  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: hostContext,
      builder: (ctx) => AlertDialog(
        title: const Text('删除课程'),
        content: Text('确定删除「${course.name}」吗？'),
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
    if (ok != true || !hostContext.mounted) return;
    final app = hostContext.read<AppState>();
    final tt = app.active;
    if (tt == null) return;
    tt.courses.remove(course);
    await app.updateTimetable(tt);
    if (hostContext.mounted) Navigator.pop(hostContext);
  }

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.colorForCourse(course.name);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.75)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              course.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _infoRow(Icons.schedule, '时间', '周${['一', '二', '三', '四', '五', '六', '日'][course.dayOfWeek - 1]} 第${course.sectionText}'),
          _infoRow(Icons.event_note, '周次', course.weekText),
          _infoRow(Icons.place, '地点', course.location.isNotEmpty ? course.location : '未填写'),
          _infoRow(Icons.person, '教师', course.teacher.isNotEmpty ? course.teacher : '未填写'),
          if (course.courseCode.isNotEmpty)
            _infoRow(Icons.code, '课程代码', course.courseCode),
          if (course.className.isNotEmpty)
            _infoRow(Icons.group, '教学班', course.className),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('编辑'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('删除'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
