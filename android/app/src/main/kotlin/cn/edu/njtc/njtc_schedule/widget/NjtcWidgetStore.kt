package cn.edu.njtc.njtc_schedule.widget

import android.content.Context
import android.content.SharedPreferences

/**
 * 桌面小组件自己的存档。
 *
 * 为什么不直接读 Flutter 的 `FlutterSharedPreferences`：那边是**异步落盘**的，
 * Dart 侧刚 `setString` 完就发刷新广播时，原生这里另开一个 SharedPreferences 实例
 * 有可能读到旧值。所以改由 Flutter 侧通过 [WidgetBridge] 把 JSON 主动推过来，
 * 存进本文件，小组件只认这一份；两边职责清楚，也不会互相踩。
 */
internal object NjtcWidgetStore {

    private const val PREFS = "njtc_widget"
    private const val KEY_TIMETABLE = "timetable"
    private const val KEY_PERIODS = "periods"
    private const val KEY_HAS_TIMETABLE = "has_timetable"
    private const val KEY_UPDATED_AT = "updated_at"

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** 保存 Flutter 侧推过来的课表与节次时间（传 null 表示清掉）。 */
    fun save(
        context: Context,
        hasTimetable: Boolean,
        timetable: String?,
        periods: String?,
    ) {
        val editor = prefs(context).edit()
        editor.putBoolean(KEY_HAS_TIMETABLE, hasTimetable)
        if (timetable == null) editor.remove(KEY_TIMETABLE) else editor.putString(KEY_TIMETABLE, timetable)
        if (periods == null) editor.remove(KEY_PERIODS) else editor.putString(KEY_PERIODS, periods)
        editor.putLong(KEY_UPDATED_AT, System.currentTimeMillis())
        editor.apply()
    }

    /**
     * 同步过、且那次同步时是有课表的。
     *
     * 用来区分「刚装好还没同步」和「同步过了但一门课都没有」——
     * 前者提示「打开 App 同步一次」，后者直接说「还没有课表」。
     */
    fun hasTimetable(context: Context): Boolean =
        prefs(context).getBoolean(KEY_HAS_TIMETABLE, false)

    /** 课表的 JSON 原文（就是 Dart 侧 `Timetable.toJsonString()` 的结果）。 */
    fun timetable(context: Context): String? = prefs(context).getString(KEY_TIMETABLE, null)

    /** 节次时间的 JSON 数组，形如 `[{"s":1,"a":"08:00","b":"08:45"}, …]`。 */
    fun periods(context: Context): String? = prefs(context).getString(KEY_PERIODS, null)

    /** 上次同步时间（毫秒），给小组件上的「未同步」提示用。 */
    fun updatedAt(context: Context): Long = prefs(context).getLong(KEY_UPDATED_AT, 0L)
}
