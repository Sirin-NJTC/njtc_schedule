package cn.edu.njtc.njtc_schedule.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import android.widget.RemoteViews
import android.widget.TextView
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
 * - 刚被放到桌面（`onEnabled`）—— 之前少了这一条，添加后要等 App 启动才见内容；
 * - 日期/时间/时区变了（跨零点要换成「今天」的课）；
 * - App 侧改完课表，通过 [WidgetBridge] 主动喊一声；
 * - 开机 / 应用升级后。
 *
 * 画界面这件事集中在 [buildViews] 里，`render` 与 [probeRendered] 都走它 ——
 * [probeRendered] 会把布局真的 inflate 一遍再读回文字，这样「桌面上到底该显示什么」
 * 可以在真机上取证，而不用靠猜（见 `integration_test/widget_render_e2e_test.dart`）。
 */
class TodayWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        Log.i(TAG, "onUpdate ids=${appWidgetIds.joinToString()}")
        for (id in appWidgetIds) render(context, appWidgetManager, id)
    }

    /** 第一个本小组件被放到桌面时调用：立刻画一次，别等到用户下次打开 App。 */
    override fun onEnabled(context: Context) {
        Log.i(TAG, "onEnabled：第一个小组件被添加，先画一次")
        refreshAll(context)
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
            Log.i(TAG, "刷新小组件 ${ids.size} 个 ids=${ids.joinToString()}")
            for (id in ids) render(app, manager, id)
        }

        private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
            manager.updateAppWidget(widgetId, buildViews(context, widgetId))
        }

        /**
         * 画一张小组件界面。
         *
         * 注意：**任何情况下都要返回一张能看的卡**。取数据万一抛异常，也画一张写着原因的
         * 兜底卡；早期版本这里是 `catch { return }`，一旦取数失败宿主就永远停在占位/旧内容，
         * 用户看到的就是一块白板，连错在哪都看不出来。
         */
        fun buildViews(context: Context, widgetId: Int = -1): RemoteViews {
            val snapshot = try {
                WidgetData.build(context)
            } catch (e: Exception) {
                Log.w(TAG, "取数据失败：${e.message}")
                return fallbackViews(context, "课表数据读不出来，打开 App 重试")
            }

            Log.i(
                TAG,
                "渲染#$widgetId ${snapshot.dateText} ${snapshot.weekText} " +
                    "行数=${snapshot.rows.size} 页脚=${snapshot.footer}" +
                    snapshot.rows.joinToString(separator = "") {
                        " | ${it.time} ${it.name}@${it.location}"
                    },
            )

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

            attachOpenApp(context, views)
            return views
        }

        /** 取数失败时的兜底卡：白板上至少写清「怎么了、怎么办」。 */
        private fun fallbackViews(context: Context, text: String): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_today)
            views.setTextViewText(R.id.widget_date, "今日课程")
            views.setTextViewText(R.id.widget_week, "")
            views.setTextViewText(R.id.widget_empty, text)
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            for (id in ROW_IDS) views.setViewVisibility(id, View.GONE)
            views.setTextViewText(R.id.widget_footer, "打开 App 同步课表")
            attachOpenApp(context, views)
            return views
        }

        private fun attachOpenApp(context: Context, views: RemoteViews) {
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
        }

        /**
         * 把小组件真的 inflate 一遍，读回它**实际会显示的文字**。
         *
         * 这是给「桌面上看到的和 App 里说的不一致」这类问题取证用的：不用把手机解锁、
         * 不用靠截图猜，直接在真机上问一句「你现在会画成什么样」。
         * 顺带也是集成测试的断言依据。
         */
        fun probeRendered(context: Context): Map<String, Any> {
            val root = buildViews(context, -1).apply(context, FrameLayout(context))
            fun text(id: Int): String =
                (root.findViewById<TextView>(id))?.text?.toString() ?: ""
            fun visible(id: Int): Boolean =
                root.findViewById<View>(id)?.visibility == View.VISIBLE

            val rows = mutableListOf<String>()
            for (i in ROW_IDS.indices) {
                if (!visible(ROW_IDS[i])) continue
                rows += "${text(TIME_IDS[i])} ${text(NAME_IDS[i])}@${text(LOC_IDS[i])}"
            }

            return hashMapOf(
                "date" to text(R.id.widget_date),
                "week" to text(R.id.widget_week),
                "empty" to text(R.id.widget_empty),
                "emptyVisible" to visible(R.id.widget_empty),
                "footer" to text(R.id.widget_footer),
                "rows" to rows,
            )
        }
    }
}
