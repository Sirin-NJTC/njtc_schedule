/// 课程提醒设置页 —— 提醒时机、vivo 原子通知（原子岛）与权限引导。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/reminder_prefs.dart';
import '../services/reminder_service.dart';
import '../theme.dart';

/// 课程提醒设置页。
class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({super.key});

  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage> {
  List<ReminderPreviewItem> _preview = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadPreview());
  }

  Future<void> _reloadPreview() async {
    final items = await ReminderService.preview(limit: 8);
    if (!mounted) return;
    setState(() => _preview = items);
  }

  Future<void> _apply(Future<void> Function(AppState app) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(context.read<AppState>());
      await _reloadPreview();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final prefs = app.reminderPrefs;
    final status = app.reminderStatus;

    return Scaffold(
      appBar: AppBar(
        title: const Text('课程提醒'),
        actions: [
          IconButton(
            tooltip: '重新排布',
            onPressed: _busy
                ? null
                : () => _apply((a) async {
                      final r = await a.syncReminders();
                      _snack(r.note.isEmpty
                          ? '已排布 ${r.scheduled} 个提醒'
                          : '${r.note}（已排布 ${r.scheduled} 个）');
                    }),
            icon: const Icon(Icons.event_repeat_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!app.remindersSupported) _buildUnsupportedCard(),
          if (!app.remindersSupported) const SizedBox(height: 16),

          _buildMasterCard(app, prefs),
          const SizedBox(height: 16),

          if (prefs.enabled) ...[
            _buildLeadCard(prefs),
            const SizedBox(height: 16),
            _buildEndCard(prefs),
            const SizedBox(height: 16),
            _buildHolidayCard(app),
            const SizedBox(height: 16),
            if (status?.isVivo ?? false) ...[
              _buildVivoCard(app, prefs, status),
              const SizedBox(height: 16),
            ],
            _buildPermissionCard(app, status),
            const SizedBox(height: 16),
            _buildPreviewCard(app),
            const SizedBox(height: 16),
            _buildTestCard(app, status),
          ],

          const SizedBox(height: 8),
          _buildFootnote(status),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 各分区

  Widget _buildUnsupportedCard() {
    return _card(
      color: const Color(0xFFFFF7ED),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              '课程提醒依赖 Android 的本地闹钟与通知能力，'
              '当前平台不可用。请在 Android 手机上使用本功能。',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterCard(AppState app, ReminderPrefs prefs) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: prefs.enabled,
            onChanged: _busy
                ? null
                : (v) => _apply((a) async {
                      await a.updateReminderPrefs(prefs.copyWith(enabled: v));
                    }),
            title: const Text(
              '开启课程提醒',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              prefs.enabled ? prefs.summaryText : '关闭后不再发送任何提醒',
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
            ),
          ),
          const Divider(height: 8),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(Icons.autorenew_rounded,
                    size: 16, color: AppTheme.textSecondary),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '提醒由手机本地排布，无需联网；卸载重装前请重新开启一次。',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeadCard(ReminderPrefs prefs) {
    final leads = prefs.sortedLeads;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.alarm_rounded,
            title: '提前提醒',
            subtitle: '30 / 15 分钟只在上午·下午·晚上的第一节提醒，5 分钟对每一节课都提醒',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ReminderPrefs.leadOptions.map((min) {
              final selected = prefs.leadMinutes.contains(min);
              return FilterChip(
                label: Text('提前 $min 分钟'),
                selected: selected,
                onSelected: _busy
                    ? null
                    : (v) {
                        final next = {...prefs.leadMinutes};
                        if (v) {
                          next.add(min);
                        } else {
                          next.remove(min);
                        }
                        _apply((a) async {
                          await a.updateReminderPrefs(
                            prefs.copyWith(leadMinutes: next),
                          );
                        });
                      },
              );
            }).toList(),
          ),
          if (leads.isEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              '未选择任何提前提醒时间。',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ] else ...[
            const SizedBox(height: 14),
            ...leads.map((min) {
              final scope = prefs.scopeOf(min);
              final color = scope == LeadScope.all
                  ? AppTheme.primary
                  : AppTheme.secondary;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 5),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '提前 $min 分钟：${scope.description}',
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildEndCard(ReminderPrefs prefs) {
    return _card(
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: prefs.endReminder,
        onChanged: _busy
            ? null
            : (v) => _apply((a) async {
                  await a.updateReminderPrefs(prefs.copyWith(endReminder: v));
                }),
        title: const _SectionTitle(
          icon: Icons.timer_off_rounded,
          title: '下节课预告',
          subtitle: '下课前 5 分钟预告下一节课；连堂的课（同名同地点、节次紧接）不提醒',
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  /// 法定节假日：开关本身与日期清单都在「设置 → 法定节假日」里，这里只做入口 + 现状。
  ///
  /// 不在这里再放一个开关，是为了避免同一个偏好有两个看起来独立的开关
  /// （改一边、另一边看起来没变，用户会以为是 bug）。
  Widget _buildHolidayCard(AppState app) {
    final cal = app.holidays;
    final skip = app.reminderPrefs.skipHolidays;
    return _card(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          Icons.event_available_rounded,
          color: skip ? AppTheme.primary : AppTheme.textSecondary,
        ),
        title: const Text(
          '法定节假日',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            skip
                ? '放假当天不提醒 · ${cal.summaryText}（含调休补班日，可自行调整）'
                : '已关闭：放假当天照常提醒 · ${cal.summaryText}',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pushNamed('/holidays'),
      ),
    );
  }

  Widget _buildVivoCard(
    AppState app,
    ReminderPrefs prefs,
    ReminderDeviceStatus? status,
  ) {
    final island = status?.isIslandCapable ?? false;
    final rom = status?.romVersion ?? '';
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: prefs.vivoAtomic,
            onChanged: _busy
                ? null
                : (v) => _apply((a) async {
                      await a.updateReminderPrefs(prefs.copyWith(vivoAtomic: v));
                    }),
            title: const _SectionTitle(
              icon: Icons.pix_rounded,
              title: '原子通知 / 原子岛',
              subtitle: '把「下节课预告」投递到状态栏胶囊与原子岛',
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _badge(
                island ? '支持原子岛' : '仅状态栏胶囊',
                island ? AppTheme.accent : AppTheme.textSecondary,
              ),
              if (rom.isNotEmpty) _badge('OriginOS $rom', AppTheme.primary),
              if (status?.sceneEnabled == true)
                _badge('场景开关已开', AppTheme.accent),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: AppTheme.primary),
                    SizedBox(width: 6),
                    Text(
                      '关于原子岛',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  status?.applyHint.isNotEmpty == true
                      ? status!.applyHint
                      : '未开通 vivo 原子通知准入时，系统会忽略原子通知字段并自动降级为普通通知，'
                          '不会丢提醒。',
                  style: const TextStyle(
                      fontSize: 12, height: 1.5, color: AppTheme.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCard(AppState app, ReminderDeviceStatus? status) {
    final rows = <Widget>[];

    final notifOk = status?.notificationsEnabled ?? false;
    rows.add(_permissionTile(
      icon: Icons.notifications_active_rounded,
      title: '通知权限',
      ok: notifOk,
      okText: '已开启',
      badText: '未开启，提醒不会显示',
      onTap: notifOk
          ? () => ReminderService.openNotificationSettings()
          : () async {
              final granted = await ReminderService.requestNotificationPermission();
              await app.refreshReminderStatus();
              if (!granted) {
                await ReminderService.openNotificationSettings();
              }
            },
    ));

    final exactOk = status?.exactAlarmAllowed ?? true;
    rows.add(_permissionTile(
      icon: Icons.schedule_rounded,
      title: '精确闹钟',
      ok: exactOk,
      okText: '已允许',
      badText: '未允许，提醒可能延迟几分钟',
      onTap: exactOk ? null : () => ReminderService.openExactAlarmSettings(),
    ));

    final batteryOk = status?.ignoringBatteryOptimizations ?? false;
    rows.add(_permissionTile(
      icon: Icons.battery_saver_rounded,
      title: '电池优化',
      ok: batteryOk,
      okText: '已忽略优化',
      badText: '建议加入白名单，避免后台被清理',
      onTap: batteryOk
          ? null
          : () => ReminderService.openBatteryOptimizationSettings(),
    ));

    if (status?.isVivo ?? false) {
      rows.add(_permissionTile(
        icon: Icons.rocket_launch_rounded,
        title: '自启动 / 后台运行',
        ok: false,
        okText: '',
        badText: 'vivo 建议手动允许自启动与后台高耗电',
        actionText: '去设置',
        onTap: () async {
          final r = await ReminderService.openAutoStartSettings();
          if (!mounted) return;
          _snack(r.startsWith('fallback')
              ? '未找到自启动管理页，请在系统设置中手动允许'
              : '已打开 vivo 自启动管理页');
        },
      ));
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.verified_user_rounded,
            title: '权限检查',
            subtitle: '任一项未开启都可能让提醒不准时或看不到',
          ),
          const SizedBox(height: 4),
          ...rows,
          if (status != null) ...[
            const Divider(height: 20),
            Text(
              '设备：${status.deviceLabel} · Android ${status.androidRelease}'
              '${status.isVivo ? ' · OriginOS ${status.osVersion.isEmpty ? '—' : status.osVersion}' : ''}',
              style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _permissionTile({
    required IconData icon,
    required String title,
    required bool ok,
    required String okText,
    required String badText,
    String actionText = '开启',
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20, color: ok ? AppTheme.accent : AppTheme.textSecondary),
      title: Text(title, style: const TextStyle(fontSize: 14.5)),
      subtitle: Text(
        ok ? okText : badText,
        style: TextStyle(
          fontSize: 12,
          color: ok ? AppTheme.accent : const Color(0xFFD97706),
        ),
      ),
      trailing: ok || onTap == null
          ? Icon(ok ? Icons.check_circle_rounded : Icons.remove_circle_outline,
              size: 18, color: ok ? AppTheme.accent : AppTheme.textSecondary)
          : TextButton(onPressed: onTap, child: Text(actionText)),
      onTap: ok ? null : onTap,
    );
  }

  Widget _buildPreviewCard(AppState app) {
    final sync = app.lastSync;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.list_alt_rounded,
            title: '最近的提醒',
            subtitle: '按当前课表和所选时机推算（滚动 14 天）',
          ),
          const SizedBox(height: 8),
          if (_preview.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '暂时没有可排布的提醒。可能是：当前周次没有课、'
                '课表未设置学期起始日期，或提醒已关闭。',
                style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.5),
              ),
            )
          else
            ..._preview.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 32,
                      decoration: BoxDecoration(
                        color: switch (item.kind) {
                          'sessionPreview' => AppTheme.secondary,
                          'endPreview' => AppTheme.accent,
                          _ => AppTheme.primary,
                        },
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.timeText,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item.label} · ${item.courseName}'
                            '${item.location.isEmpty ? '' : ' · ${item.location}'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (sync != null) ...[
            const Divider(height: 20),
            Text(
              sync.ok
                  ? '已排布 ${sync.scheduled} 个提醒'
                      '${sync.horizonDays > 0 ? '（未来 ${sync.horizonDays} 天）' : ''}'
                      '${sync.exact ? ' · 使用精确闹钟' : ' · 未获精确闹钟权限，可能略有延迟'}'
                  : sync.note,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: sync.ok ? AppTheme.textSecondary : const Color(0xFFD97706),
              ),
            ),
            if (sync.ok && sync.nextTriggerText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '下一次：${sync.nextTriggerText}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildTestCard(AppState app, ReminderDeviceStatus? status) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.science_rounded,
            title: '立即验证',
            subtitle: '不用等到上课时间，马上发一条提醒看看效果',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _sendTest(
                    () => ReminderService.testNow(),
                    '上课提醒',
                  ),
                  icon: const Icon(Icons.notifications_none_rounded, size: 18),
                  label: const Text('上课提醒'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _sendTest(
                    () => ReminderService.testNow(sessionPreview: true),
                    '时段预告',
                  ),
                  icon: const Icon(Icons.menu_book_rounded, size: 18),
                  label: const Text('时段预告'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _sendTest(
                () => ReminderService.testNow(isEnd: true),
                '下节课预告',
              ),
              icon: const Icon(Icons.pix_rounded, size: 18),
              label: const Text('下节课预告（vivo 走原子岛）'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendTest(
    Future<String> Function() send,
    String label,
  ) async {
    final mode = await send();
    _snack('$label：$mode');
  }

  Widget _buildFootnote(ReminderDeviceStatus? status) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        status == null || !status.hasPlan
            ? '提示：提醒计划保存在手机本地，重启手机后会自动恢复。'
            : '提示：已排布 ${status.scheduledCount} 个提醒闹钟，重启手机后会自动恢复。',
        style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.5),
      ),
    );
  }

  // ------------------------------------------------------------ 小部件

  Widget _card({required Widget child, Color? color}) {
    return Card(
      color: color,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    this.subtitle,
    this.padding = EdgeInsets.zero,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
