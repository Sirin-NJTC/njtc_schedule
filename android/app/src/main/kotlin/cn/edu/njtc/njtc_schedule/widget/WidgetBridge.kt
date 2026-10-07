package cn.edu.njtc.njtc_schedule.widget

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 桌面小组件的 Dart ↔ 原生桥。
 *
 * Dart 侧每次课表/节次时间变化都会把整份 JSON 推过来（`update`），
 * 原生存进 [NjtcWidgetStore] 后立刻重画小组件；另有 `refresh` 只重画不换数据，
 * 以及 `probe` 回读「小组件实际会显示的文字」用于诊断与集成测试。
 *
 * 走桥而不是让原生去读 Flutter 的 `SharedPreferences`：那边是异步落盘的，
 * 刚写完就读有可能读到旧值（两边各持一个实例，谁也保证不了顺序）。
 */
class WidgetBridge(private val context: Context, messenger: BinaryMessenger) {

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val hasTimetable = call.argument<Boolean>("hasTimetable") ?: false
                    val timetable = call.argument<String>("timetable")
                    val periods = call.argument<String>("periods")
                    val holidays = call.argument<String>("holidays")
                    NjtcWidgetStore.save(
                        context.applicationContext,
                        hasTimetable,
                        timetable,
                        periods,
                        holidays,
                    )
                    TodayWidgetProvider.refreshAll(context.applicationContext)
                    Log.i(TAG, "已同步小组件数据 hasTimetable=$hasTimetable " +
                        "timetable=${timetable?.length ?: 0}B periods=${periods?.length ?: 0}B " +
                        "holidays=${holidays?.length ?: 0}B")
                    result.success(true)
                }
                "refresh" -> {
                    TodayWidgetProvider.refreshAll(context.applicationContext)
                    result.success(true)
                }
                // 诊断用：把小组件现在**实际会画出来的文字**回给 Dart 侧。
                // 桌面上显示不对时，不用解锁手机截图，直接在真机上问一句就够了。
                "probe" -> {
                    val rendered = TodayWidgetProvider.probeRendered(context.applicationContext)
                    Log.i(TAG, "渲染探针 $rendered")
                    result.success(rendered)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val TAG = "NjtcWidget"
        const val CHANNEL = "cn.edu.njtc.njtc_schedule/widget"
    }
}
