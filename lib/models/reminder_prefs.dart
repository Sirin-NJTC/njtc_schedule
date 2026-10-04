/// 课程提醒偏好设置。
library;

/// 一条「提前 N 分钟」提醒的作用范围。
///
/// 用户的规则是：
/// - 提前 30 分钟：只在上午 / 下午 / 晚上**第一节课**前提醒，且提醒内容是
///   **该时段全部课程**的预告（一次把该时段要用的书都带齐）；
/// - 提前 15 分钟：同样只在时段第一节课前提醒，内容是单节课提醒；
/// - 提前 5 分钟：当天**每一节课**都提醒。
///
/// 判定放在 Dart 侧（偏好本来就住在这里），原生侧只按 [wire] 值执行，
/// 这样策略可以脱离 Android 做单元测试。
enum LeadScope {
  /// 仅时段首课 + 整段课程预告。
  sessionPreview,

  /// 仅时段首课 + 单节课提醒。
  sessionFirst,

  /// 每一节课都提醒。
  all;

  /// 下发给原生侧的字符串（须与 `Models.kt` 的 `LeadScope.from` 一致）。
  String get wire => name;

  /// 由提前分钟数推出作用范围。
  static LeadScope forLead(int minutes) {
    if (minutes >= 30) return LeadScope.sessionPreview;
    if (minutes >= 10) return LeadScope.sessionFirst;
    return LeadScope.all;
  }

  /// 该作用范围是否只对「时段第一节课」生效。
  bool get sessionFirstOnly => this != LeadScope.all;

  String get description => switch (this) {
        LeadScope.sessionPreview => '上午/下午/晚上第一节前，预告该时段全部课程',
        LeadScope.sessionFirst => '只在上午/下午/晚上第一节前提醒',
        LeadScope.all => '当天每一节课都提醒',
      };
}

/// 提醒偏好（全局，跨课表共享）。
class ReminderPrefs {
  /// 总开关。
  bool enabled;

  /// 提前提醒的分钟数集合，取值只来自 [leadOptions]。
  Set<int> leadMinutes;

  /// 是否在下课前预告下一节课。
  ///
  /// 触发点是「下课时间往前 [endPreviewMinutes] 分钟」，且**只对不连堂的课**生效：
  /// 下一节若是同一门课、同一地点且节次紧接（连堂），说明不用换书换教室，就不提醒。
  bool endReminder;

  /// 「下课前 N 分钟」的 N。
  int endPreviewMinutes;

  /// 是否把「下节课预告」投递到 vivo 原子通知 / 原子岛。
  ///
  /// 仅 vivo / iQOO 设备有意义；非 vivo 设备上该开关不影响普通通知投递。
  /// 未通过 vivo 准入时系统会忽略原子通知字段并自动降级为普通通知，
  /// 因此默认开启是安全的。
  bool vivoAtomic;

  /// 法定节假日 / 调休补班日是否生效。
  ///
  /// 开启时：放假那天**不排任何课程提醒**；调休补班日（如「周六补周三的课」）
  /// 按对应周几的课表排提醒 —— 具体日期由「设置 → 法定节假日」里那份可编辑的
  /// 日历决定（见 `lib/models/holiday_calendar.dart`）。
  bool skipHolidays;

  ReminderPrefs({
    this.enabled = true,
    Set<int>? leadMinutes,
    this.endReminder = true,
    this.endPreviewMinutes = 5,
    this.vivoAtomic = true,
    this.skipHolidays = true,
  }) : leadMinutes = leadMinutes == null
            ? {...defaultLeadMinutes}
            : leadMinutes.where(leadOptions.contains).toSet();

  /// 可选的提前提醒分钟数（用户已确认 30 / 15 / 5 全选）。
  static const List<int> leadOptions = [30, 15, 5];

  /// 默认提前提醒分钟数。
  static const Set<int> defaultLeadMinutes = {30, 15, 5};

  /// 「下课前预告」的默认提前量（分钟）。
  static const int defaultEndPreviewMinutes = 5;

  /// 降序排列的提前分钟数（如 `[30, 15, 5]`），供原生侧排布闹钟。
  List<int> get sortedLeads {
    final list = leadMinutes.where(leadOptions.contains).toList()
      ..sort((a, b) => b.compareTo(a));
    return list;
  }

  /// 与 [sortedLeads] 一一对应且顺序一致的作用范围列表。
  List<LeadScope> get sortedScopes =>
      sortedLeads.map(LeadScope.forLead).toList();

  /// 某个提前分钟数对应的作用范围。
  LeadScope scopeOf(int minutes) => LeadScope.forLead(minutes);

  /// 开启后是否至少有一个提醒会真正触发。
  bool get hasAnyTrigger => enabled && (endReminder || sortedLeads.isNotEmpty);

  /// 提醒时间的可读描述，如「提前 30 / 15 / 5 分钟 · 下节课预告」。
  String get summaryText {
    if (!enabled) return '已关闭';
    final parts = <String>[];
    if (sortedLeads.isNotEmpty) {
      parts.add('提前 ${sortedLeads.join(' / ')} 分钟');
    }
    if (endReminder) parts.add('下课前 $endPreviewMinutes 分钟预告');
    if (skipHolidays) parts.add('节假日不提醒');
    if (parts.isEmpty) return '未选择任何提醒';
    return parts.join(' · ');
  }

  ReminderPrefs copyWith({
    bool? enabled,
    Set<int>? leadMinutes,
    bool? endReminder,
    int? endPreviewMinutes,
    bool? vivoAtomic,
    bool? skipHolidays,
  }) {
    return ReminderPrefs(
      enabled: enabled ?? this.enabled,
      leadMinutes: leadMinutes ?? {...this.leadMinutes},
      endReminder: endReminder ?? this.endReminder,
      endPreviewMinutes: endPreviewMinutes ?? this.endPreviewMinutes,
      vivoAtomic: vivoAtomic ?? this.vivoAtomic,
      skipHolidays: skipHolidays ?? this.skipHolidays,
    );
  }

  @override
  String toString() =>
      'ReminderPrefs(enabled: $enabled, leads: $sortedLeads, '
      'end: $endReminder, endPreview: $endPreviewMinutes, '
      'vivoAtomic: $vivoAtomic, skipHolidays: $skipHolidays)';
}
