package cn.edu.njtc.njtc_schedule.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import cn.edu.njtc.njtc_schedule.MainActivity
import cn.edu.njtc.njtc_schedule.R

/**
 * 桌面小组件：**今日课程**。
 *
 * 形态是「静态行」而不是 `RemoteViewsService` 列表 —— 一天最多也就五六门课，
 * 静态行少一层 Service 生命周期，刷新时机完全由我们自己控制，也更省电。
 *
 * 刷新时机：
 * - 系统让它更新（`onUpdate`，含 `updatePeriodMillis` 的周期刷新）；
 * - 日期/时间/时区变了（跨零点要换成「今天」的课）；
 * - App 侧改完课表，通过 [WidgetBridge] 主动喊一声；
 * - 开机 / 应用升级后。
 */
class TodayWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) render(context, appWidgetManager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_REFRESH,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> refreshAll(context)
        }
    }

    companion object {
        private const val TAG = "NjtcWidget"

        /** App 侧改完课表后喊的那个 action。 */
        const val ACTION_REFRESH = "cn.edu.njtc.njtc_schedule.WIDGET_REFRESH"

        /** 每行最多 5 行，布局里 id 固定，这里按顺序列出来。 */
        private val ROW_IDS = intArrayOf(
            R.id.row_1, R.id.row_2, R.id.row_3, R.id.row_4, R.id.row_5,
        )
        private val BAR_IDS = intArrayOf(
            R.id.bar_1, R.id.bar_2, R.id.bar_3, R.id.bar_4, R.id.bar_5,
        )
        private val NAME_IDS = intArrayOf(
            R.id.name_1, R.id.name_2, R.id.name_3, R.id.name_4, R.id.name_5,
        )
        private val LOC_IDS = intArrayOf(
            R.id.loc_1, R.id.loc_2, R.id.loc_3, R.id.loc_4, R.id.loc_5,
        )
        private val TIME_IDS = intArrayOf(
            R.id.time_1, R.id.time_2, R.id.time_3, R.id.time_4, R.id.time_5,
        )

        /** 刷新桌面上所有本小组件。 */
        fun refreshAll(context: Context) {
            val app = context.applicationContext
            val manager = AppWidgetManager.getInstance(app) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(app, TodayWidgetProvider::class.java))
            if (ids == null || ids.isEmpty()) {
                Log.i(TAG, "没有放置小组件，跳过刷新")
                return
            }
            Log.i(TAG, "刷新小组件 ${ids.size} 个")
            for (id in ids) render(app, manager, id)
        }

        private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
            val snapshot = try {
                WidgetData.build(context)
            } catch (e: Exception) {
                Log.w(TAG, "取数据失败：${e.message}")
                return
            }

            val views = RemoteViews(context.packageName, R.layout.widget_today)
            views.setTextViewText(R.id.widget_date, snapshot.dateText)
            views.setTextViewText(R.id.widget_week, snapshot.weekText)
            views.setTextViewText(R.id.widget_footer, snapshot.footer)

            for (i in ROW_IDS.indices) {
                if (i < snapshot.rows.size) {
                    val row = snapshot.rows[i]
                    views.setViewVisibility(ROW_IDS[i], View.VISIBLE)
                    views.setTextViewText(NAME_IDS[i], row.name)
                    views.setTextViewText(LOC_IDS[i], row.location)
                    views.setTextViewText(TIME_IDS[i], row.time)
                    views.setInt(BAR_IDS[i], "setBackgroundColor", row.color)
                } else {
                    views.setViewVisibility(ROW_IDS[i], View.GONE)
                }
            }
            views.setViewVisibility(
                R.id.widget_empty,
                if (snapshot.rows.isEmpty()) View.VISIBLE else View.GONE,
            )

            val open = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pi = PendingIntent.getActivity(
                context,
                0,
                open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pi)

            manager.updateAppWidget(widgetId, views)
        }
    }
}
