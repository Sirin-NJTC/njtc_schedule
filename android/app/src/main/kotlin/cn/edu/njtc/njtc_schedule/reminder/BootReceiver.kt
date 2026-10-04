package cn.edu.njtc.njtc_schedule.reminder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 开机 / 应用升级后重建全部提醒闹钟。
 *
 * 系统在重启时会清空 AlarmManager 里的全部闹钟，因此必须在这里从 [PlanStore]
 * 重新推导并排布 —— 这也是提醒不依赖用户再次打开 App 的关键一环。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action !in TRIGGERS) return
        Log.i(TAG, "收到 $action，重建课程提醒闹钟")
        try {
            NotificationFactory.ensureChannels(context)
            val result = ReminderScheduler.reschedule(context)
            Log.i(TAG, "重建完成：${result.scheduled} 个闹钟，${result.note}")
        } catch (t: Throwable) {
            Log.e(TAG, "重建闹钟失败：${t.message}", t)
        }
    }

    companion object {
        private const val TAG = "NjtcBoot"
        private val TRIGGERS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
            "android.intent.action.REBOOT",
        )
    }
}
