/// 课表显示偏好（全局，跨课表共享）。
library;

/// 「课表怎么显示」的偏好。
///
/// 这两个开关只影响**画出来的样子**，不改课表数据，也不改提醒排布
/// （提醒只按课程自己的周次来）。
class DisplayPrefs {
  /// 是否显示周六 / 周日两列。
  ///
  /// 关掉之后课表只画周一到周五五列，手机窄屏下每列更宽、更好点。
  /// 注意：周末**确实有课**的课表别关，关了那两列就看不见了。
  bool showWeekend;

  /// 是否把「不在当前周」的课程也画出来（灰显）。
  ///
  /// 默认关闭：课表只画本周真正要上的课，和纸质课表的习惯一致。
  /// 打开后，本学期有、但本周不上（周次没到 / 单双周不对）的课会以
  /// 半透明灰块显示，方便一眼看出「这门课这周不上」。
  bool showInactiveCourses;

  DisplayPrefs({
    this.showWeekend = true,
    this.showInactiveCourses = false,
  });

  /// 供 UI 副标题用的一句话总结。
  String get summaryText {
    final days = showWeekend ? '显示周六日' : '只看周一到周五';
    final inactive = showInactiveCourses ? '显示非本周课程' : '只显示本周课程';
    return '$days · $inactive';
  }

  DisplayPrefs copyWith({
    bool? showWeekend,
    bool? showInactiveCourses,
  }) {
    return DisplayPrefs(
      showWeekend: showWeekend ?? this.showWeekend,
      showInactiveCourses: showInactiveCourses ?? this.showInactiveCourses,
    );
  }

  @override
  String toString() => 'DisplayPrefs(showWeekend: $showWeekend, '
      'showInactiveCourses: $showInactiveCourses)';
}
