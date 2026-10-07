/// 分钟级时钟 —— 驱动倒计时、当前时间线这类「随时间自己走」的展示。
///
/// 为什么需要它：课表网格与首页的倒计时原先都在 `build()` 里读一次
/// `DateTime.now()` 就完事，界面上没有任何东西随时间推进。App 开着两小时，
/// 倒计时仍显示开屏那一刻的读数、当前时间红线也停在原位。
///
/// 刻意做成 **builder + 局部 setState** 而不是让首页整体计时重建：
/// 那样每分钟都会把整张课表网格连同布局算法重跑一遍。
/// 把它放在最小的子树上（倒计时那一块、时间线那一条），代价就只有一个小 Text。
///
/// ⚠️ `flutter test` 下必须关掉定时器 —— `Timer.periodic` 会让
/// `pumpAndSettle()` 永远等不到静止。这里沿用项目里 `HolidaySyncService`
/// 的既有约定：读 `FLUTTER_TEST` 环境变量。
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

/// 每分钟重建一次 [builder]，把「现在」作为第二个参数递进去。
class MinuteTicker extends StatefulWidget {
  const MinuteTicker({
    super.key,
    required this.builder,
    this.enabled = true,
  });

  /// 用 `(context, now)` 造出子树；`now` 每分钟刷新一次。
  final Widget Function(BuildContext context, DateTime now) builder;

  /// 显式关掉计时（一般不需要，测试环境会自动识别）。
  final bool enabled;

  /// 测试环境不跑定时器，避免 `pumpAndSettle()` 被周期性重建拖到超时。
  ///
  /// 与 `HolidaySyncService.autoSyncEnabled` 用的是同一个环境变量，保持一致。
  static bool get tickingAllowed =>
      Platform.environment['FLUTTER_TEST'] != 'true';

  @override
  State<MinuteTicker> createState() => _MinuteTickerState();
}

class _MinuteTickerState extends State<MinuteTicker> with WidgetsBindingObserver {
  Timer? _timer;
  late DateTime _now;
  bool _observing = false;

  bool get _live => widget.enabled && MinuteTicker.tickingAllowed;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    if (_live) {
      // 对齐到下一个整分，免得刚进页面就差几十秒、第一跳看起来很突兀
      _timer = Timer(Duration(seconds: 60 - _now.second), _startPeriodic);
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
  }

  void _startPeriodic() {
    if (!mounted) return;
    _tick();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _now = DateTime.now());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台切回来立刻校准一次：后台期间定时器可能被系统挂起
    if (state == AppLifecycleState.resumed) _tick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}
