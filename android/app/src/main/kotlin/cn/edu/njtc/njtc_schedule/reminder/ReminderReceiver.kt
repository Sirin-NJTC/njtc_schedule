package cn.edu.njtc.njtc_schedule.reminder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 提醒闹钟的落地点，同时兼顾「每日巡检闹钟」。
 *
 * 全部逻辑都在原生侧完成，不需要 Flutter 引擎存活 —— 这是提醒能在 App 被划掉、
 * 甚至从未打开的情况下依然准时到达的原因。
 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ReminderScheduler.ACTION_DAILY_DRIVER -> {
                Log.i(TAG, "每日巡检闹钟触发：重新排布提醒窗口")
                try {
                    ReminderScheduler.reschedule(context)
                } catch (t: Throwable) {
                    Log.e(TAG, "每日巡检重排失败：${t.message}", t)
                }
            }

            ReminderScheduler.ACTION_REMINDER -> {
                val plan = PlanStore.loadPlan(context)
                if (plan == null) {
                    Log.w(TAG, "收到提醒闹钟但没有已保存的计划，忽略")
                    return
                }
                val index = intent.getIntExtra(ReminderScheduler.EXTRA_COURSE_INDEX, -1)
                val nextIndex = intent.getIntExtra(ReminderScheduler.EXTRA_NEXT_COURSE_INDEX, -1)
                val type = intent.getIntExtra(ReminderScheduler.EXTRA_TYPE, 0)
                val sessionPreview =
                    intent.getBooleanExtra(ReminderScheduler.EXTRA_SESSION_PREVIEW, false)
                val epochDay =
                    intent.getLongExtra(ReminderScheduler.EXTRA_DATE_EPOCH_DAY, 0L)
                val course = plan.courses.getOrNull(index)
                if (course == null) {
                    Log.w(TAG, "提醒闹钟指向的课程不存在（index=$index），忽略")
                    return
                }
                val content = NotificationFactory.buildContent(
                    plan = plan,
                    course = course,
                    type = type,
                    dateEpochDay = epochDay,
                    nextCourse = plan.courses.getOrNull(nextIndex),
                    sessionPreview = sessionPreview,
                )
                // 原子通知只承载「下节课预告」（用户选定），上课前提醒一律走普通通知
                val useAtomic = plan.prefs.vivoAtomic && content.isEnd
                NotificationFactory.show(
                    ctx = context,
                    content = content,
                    useAtomic = useAtomic,
                    triggerAtMillis = System.currentTimeMillis(),
                )
            }
        }
    }

    companion object {
        private const val TAG = "NjtcReminderRx"
    }
}
