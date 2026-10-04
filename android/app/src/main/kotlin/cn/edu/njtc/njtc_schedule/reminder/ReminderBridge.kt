package cn.edu.njtc.njtc_schedule.reminder

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Flutter <-> 原生 的课程提醒桥。
 *
 * 通道名：`cn.edu.njtc.njtc_schedule/reminder`
 *
 * | 方法 | 入参 | 返回 |
 * | --- | --- | --- |
 * | `status` | — | 设备/权限/已排布闹钟数 |
 * | `sync` | `plan`(JSON 字符串) | 排布结果 |
 * | `cancelAll` | — | null |
 * | `preview` | `limit`(int) | 最近若干条提醒 |
 * | `testNow` | `isEnd`(bool), `courseName`(String?) | 实际使用的通道 |
 * | `requestNotificationPermission` | — | 调用后是否已授权 |
 * | `openNotificationSettings` / `openExactAlarmSettings` /
 *   `openBatteryOptimizationSettings` / `openAutoStartSettings` | — | 跳转结果 |
 */
class ReminderBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL).also {
        it.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "status" -> result.success(statusMap())

                "sync" -> {
                    val raw = call.argument<String>("plan")
                    if (raw.isNullOrBlank()) {
                        result.error("bad_args", "缺少 plan 参数", null)
                        return
                    }
                    val r = ReminderScheduler.sync(activity, JSONObject(raw))
                    result.success(scheduleResultMap(r))
                }

                "cancelAll" -> {
                    ReminderScheduler.cancelAll(activity)
                    PlanStore.clear(activity)
                    result.success(null)
                }

                "preview" -> {
                    val limit = call.argument<Int>("limit") ?: 8
                    result.success(ReminderScheduler.preview(activity, limit.coerceIn(1, 50)))
                }

                "testNow" -> {
                    val isEnd = call.argument<Boolean>("isEnd") ?: false
                    val sessionPreview = call.argument<Boolean>("sessionPreview") ?: false
                    val courseName = call.argument<String>("courseName")
                    result.success(sendTest(isEnd, sessionPreview, courseName))
                }

                "requestNotificationPermission" -> {
                    result.success(requestNotificationPermission())
                }

                "openNotificationSettings" -> {
                    VivoHelper.openNotificationSettings(activity)
                    result.success(null)
                }

                "openExactAlarmSettings" -> {
                    VivoHelper.openExactAlarmSettings(activity)
                    result.success(null)
                }

                "openBatteryOptimizationSettings" -> {
                    VivoHelper.openBatteryOptimizationSettings(activity)
                    result.success(null)
                }

                "openAutoStartSettings" -> {
                    result.success(VivoHelper.openAutoStartSettings(activity))
                }

                "dispose" -> {
                    channel.setMethodCallHandler(null)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            Log.e(TAG, "处理 ${call.method} 失败：${t.message}", t)
            result.error("reminder_error", t.message ?: t.toString(), null)
        }
    }

    // ------------------------------------------------------------ 各方法实现

    private fun statusMap(): Map<String, Any?> {
        val base = HashMap<String, Any?>(VivoHelper.deviceSummary(activity))
        base["platform"] = "android"
        base["hasPlan"] = PlanStore.hasPlan(activity)
        base["scheduledCount"] = PlanStore.loadCodes(activity).size
        base["lastSyncAt"] = PlanStore.lastSync(activity)
        base["postNotificationGranted"] = hasNotificationPermission()
        base["alwaysShowAtomicHint"] = VIVO_APPLY_HINT
        return base
    }

    private fun scheduleResultMap(r: ScheduleResult): Map<String, Any?> = mapOf(
        "scheduled" to r.scheduled,
        "horizonDays" to r.horizonDays,
        "nextTriggerAt" to r.nextTriggerAtMillis,
        "nextTriggerText" to ReminderScheduler.formatTime(r.nextTriggerAtMillis),
        "exact" to r.exact,
        "note" to r.note,
    )

    private fun hasNotificationPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

    private fun requestNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !hasNotificationPermission()) {
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQ_POST_NOTIFICATIONS,
            )
            // 授权是异步的，UI 侧拿到 false 后通过 status() 复查
            return false
        }
        return true
    }

    /**
     * 立刻发一条提醒，方便用户在真机上验证通知 / 原子岛是否正常。
     *
     * 三种形态分别对应：单节课提醒 / 时段预告 / 下节课预告。
     * 有计划时用课表里的真实课程（含今天对应的周次），没有计划时用内置演示文案。
     */
    private fun sendTest(
        isEnd: Boolean,
        sessionPreview: Boolean,
        courseName: String?,
    ): Map<String, Any?> {
        val plan = PlanStore.loadPlan(activity)
        val tz = java.util.TimeZone.getDefault()
        val todayEpochDay = DayMath.localMillisToEpochDay(System.currentTimeMillis(), tz)
        val course = plan?.courses?.firstOrNull { courseName == null || it.name == courseName }

        val content: ReminderContent = if (plan != null && course != null) {
            when {
                isEnd -> {
                    val week = if (plan.semesterStartEpochDay > 0L) {
                        Math.floorDiv(todayEpochDay - plan.semesterStartEpochDay, 7L).toInt() + 1
                    } else {
                        1
                    }
                    val dayCourses = plan.courses
                        .filter { it.dayOfWeek == course.dayOfWeek && it.isActiveOnWeek(week) }
                        .sortedWith(compareBy({ it.startSection }, { it.endSection }, { it.name }))
                    val pos = dayCourses.indexOfFirst { it == course }
                    val next = if (pos >= 0) dayCourses.getOrNull(pos + 1) else dayCourses.lastOrNull()
                    NotificationFactory.buildContent(
                        plan = plan,
                        course = course,
                        type = ReminderInstance.TYPE_END,
                        dateEpochDay = todayEpochDay,
                        nextCourse = next,
                    )
                }

                sessionPreview -> NotificationFactory.buildContent(
                    plan = plan,
                    course = course,
                    type = 0,
                    dateEpochDay = todayEpochDay,
                    sessionPreview = true,
                )

                else -> NotificationFactory.buildContent(
                    plan = plan,
                    course = course,
                    type = 0,
                    dateEpochDay = todayEpochDay,
                )
            }
        } else {
            val accent = NotificationFactory.colorFor(0)
            when {
                sessionPreview -> ReminderContent(
                    title = "还有 30 分钟上课 · 上午共 3 门课",
                    content = "08:00 人工智能导论 @明德楼B216\n" +
                        "10:00 高等数学Ⅰ（上） @明德楼A103\n" +
                        "10:55 大学英语Ⅰ @明德楼B105",
                    subText = "记得带齐上午要用的全部教材",
                    capsuleText = "上午 3 门课",
                    islandLeftText = "上午 3 门课",
                    islandRightText = "还有 30 分钟",
                    isEnd = false,
                    accentColor = accent,
                    notificationId = 9903,
                )

                isEnd -> ReminderContent(
                    title = "「高等数学Ⅰ（上）」10:45 下课",
                    content = "下节课：大学物理V（上） · 10:55 · 明德楼B105",
                    subText = "下节课预告 · 第5-6节",
                    capsuleText = "大学物理… 10:55",
                    islandLeftText = "大学物理V（上）",
                    islandRightText = "10:55 上课",
                    isEnd = true,
                    accentColor = accent,
                    notificationId = 9901,
                )

                else -> ReminderContent(
                    title = "第3-4节 · 高等数学Ⅰ（上）",
                    content = "10:00 上课 · 明德楼A103 · 曾玉祥",
                    subText = "还有 15 分钟",
                    capsuleText = "15 分钟后 高等数学…",
                    islandLeftText = "高等数学Ⅰ（上）",
                    islandRightText = "还有 15 分钟",
                    isEnd = false,
                    accentColor = accent,
                    notificationId = 9902,
                )
            }
        }

        val useAtomic = isEnd && (plan?.prefs?.vivoAtomic ?: true)
        val mode = NotificationFactory.show(
            ctx = activity,
            content = content,
            useAtomic = useAtomic,
            triggerAtMillis = 0L,
        )
        return mapOf(
            "mode" to mode,
            "title" to content.title,
            "content" to content.content,
            "isVivo" to VivoHelper.isVivo(),
            "isIslandCapable" to VivoHelper.isIslandCapable(),
        )
    }

    companion object {
        private const val TAG = "NjtcReminderBridge"
        const val CHANNEL = "cn.edu.njtc.njtc_schedule/reminder"
        private const val REQ_POST_NOTIFICATIONS = 20741

        /** vivo 原子通知准入提示（原文来自官方 doc/894）。 */
        const val VIVO_APPLY_HINT =
            "原子通知需先向 oosyztz@vivo.com 申请准入；未开通时系统会忽略 superx 字段，" +
                "按普通通知展示（notification.superx.showNotify 默认 true）。"
    }
}
