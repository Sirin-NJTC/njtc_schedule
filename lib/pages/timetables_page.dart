/// 课表管理页 —— 多课表切换、重命名、删除。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/timetable.dart';
import '../theme.dart';

/// 多课表管理页面。
class TimetablesPage extends StatelessWidget {
  const TimetablesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final list = state.timetables;

    return Scaffold(
      appBar: AppBar(title: const Text('课表管理')),
      body: list.isEmpty
          ? const Center(child: Text('暂无课表，请先导入'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final tt = list[index];
                final isActive = state.active?.id == tt.id;
                return _TimetableTile(
                  timetable: tt,
                  isActive: isActive,
                  onTap: () => state.setActive(tt.id),
                  onRename: () => _rename(context, state, tt),
                  onDelete: () => _delete(context, state, tt),
                );
              },
            ),
    );
  }

  void _rename(BuildContext context, AppState state, Timetable tt) {
    final controller = TextEditingController(text: tt.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名课表'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '课表名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              state.renameTimetable(tt.id, controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _delete(BuildContext context, AppState state, Timetable tt) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除课表'),
        content: Text('确定删除「${tt.name}」吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              state.removeTimetable(tt.id);
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _TimetableTile extends StatelessWidget {
  final Timetable timetable;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _TimetableTile({
    required this.timetable,
    required this.isActive,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isActive
            ? const BorderSide(color: AppTheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.calendar_month, color: AppTheme.primary),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                timetable.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '当前',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
          ],
        ),
        subtitle: Text(
          [
            timetable.semester,
            '${timetable.courses.length} 门课',
          ].where((e) => e.isNotEmpty).join(' · '),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'rename',
              child: Text('重命名'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
          onSelected: (v) {
            if (v == 'rename') {
              onRename();
            } else if (v == 'delete') {
              onDelete();
            }
          },
        ),
      ),
    );
  }
}
