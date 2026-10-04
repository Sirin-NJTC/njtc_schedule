package cn.edu.njtc.njtc_schedule.reminder

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import cn.edu.njtc.njtc_schedule.MainActivity
import java.util.Calendar

/** 一次排布的结果，回传 Flutter 用于「下次提醒」等展示。 */
data class ScheduleResult(
    val scheduled: Int,
    val horizonDays: Int,
    val nextTriggerAtMillis: Long,
    val exact: Boolean,
    val note: String,
)

/**
 * 课程提醒调度引擎。
 *
 * 设计要点：
 * 1. Flutter 只下发「课程规则」（哪门课、星期几、第几节、周次区间、单双周、作息时间表），
 *    具体的提醒时刻全部由本类自行推算，因此提醒不依赖 App 是否被打开过。
 * 2. 采用滑动窗口：每次只排布未来 [HORIZON_DAYS] 天的闹钟，并额外挂一个「每日巡检闹钟」
 *    （次日 00:05），由它在每天把窗口往后推，从而做到自持续。
 * 3. 开机 / 应用升级后由 BootReceiver 从 PlanStore 重建全部闹钟。
 * 4. 提醒闹钟优先用 setAlarmClock（系统当作用户闹钟，Doze / 省电都不推迟），
 *    失败退回 setExactAndAllowWhileIdle，再退回 setAndAllowWhileIdle（不抛异常、不丢提醒）。
 */
object ReminderScheduler {
    private const val TAG = "NjtcReminder"

    /** 滑动窗口长度（天）。14 天 ≈ 160~240 个闹钟，远低于系统 500 个精确闹钟的上限。 */
    const val HORIZON_DAYS = 14

    /** 单次排布的闹钟数量上限，防御性保护。 */
    private const val MAX_ALARMS = 240

    /** 每日巡检闹钟的请求码（与提醒请求码不冲突：提醒码是 0..MAX_ALARMS-1）。 */
    const val DRIVER_REQUEST_CODE = 900001

    /** 距离现在不足 2 秒的提醒直接丢弃，避免刚排完就立刻弹一个过期的通知。 */
    private const val MIN_LEAD_MILLIS = 2_000L

    /**
     * 是否用 `setAlarmClock` 排提醒（更抗 Doze / 厂商省电，代价是状态栏常驻闹钟图标）。
     * 改成 false 即回到 `setExactAndAllowWhileIdle`。
     */
    private const val USE_ALARM_CLOCK = true

    /** `setAlarmClock` 的「展示用意图」请求码，与提醒码、巡检码都不冲突。 */
    private const val ALARM_SHOW_REQUEST_CODE = 900002

    const val ACTION_REMINDER = "cn.edu.njtc.njtc_schedule.action.COURSE_REMINDER"
    const val ACTION_DAILY_DRIVER = "cn.edu.njtc.njtc_schedule.action.DAILY_DRIVER"

    const val EXTRA_COURSE_INDEX = "course_index"
    const val EXTRA_NEXT_COURSE_INDEX = "next_course_index"
    const val EXTRA_TYPE = "type"
    const val EXTRA_SESSION_PREVIEW = "session_preview"
    const val EXTRA_LEAD_MINUTES = "lead_minutes"
    const val EXTRA_DATE_EPOCH_DAY = "date_epoch_day"

    private const val PI_FLAGS =
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    // ---------------------------------------------------------------- 对外入口

    /** 保存计划并立即重新排布全部闹钟。 */
    fun sync(ctx: Context, json: org.json.JSONObject): ScheduleResult {
        PlanStore.savePlan(ctx, json)
        PlanStore.saveLastSync(ctx, System.currentTimeMillis())
        return reschedule(ctx)
    }

    /** 从已保存的计划重建全部闹钟。 */
    fun reschedule(ctx: Context): ScheduleResult {
        val plan = PlanStore.loadPlan(ctx)
            ?: return ScheduleResult(0, HORIZON_DAYS, 0L, false, "尚未设置课程提醒计划")

        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        cancelScheduled(ctx, am)

        if (!plan.prefs.enabled) {
            armDailyDriver(ctx, am)
            PlanStore.saveCodes(ctx, emptyList())
            return ScheduleResult(0, HORIZON_DAYS, 0L, false, "课程提醒已关闭")
        }
        if (plan.courses.isEmpty()) {
            armDailyDriver(ctx, am)
            PlanStore.saveCodes(ctx, emptyList())
            return ScheduleResult(0, HORIZON_DAYS, 0L, false, "当前课表没有课程")
        }

        val now = System.currentTimeMillis()
        val all = computeInstances(plan, now)
        val used = if (all.size > MAX_ALARMS) all.subList(0, MAX_ALARMS) else all

        var exact = true
        for (inst in used) {
            exact = setAlarm(ctx, am, inst) && exact
        }
        PlanStore.saveCodes(ctx, used.map { it.requestCode })
        armDailyDriver(ctx, am)

        val next = used.minOfOrNull { it.triggerAtMillis } ?: 0L
        Log.i(
            TAG,
            "排布完成：共 ${used.size} 个提醒闹钟（推导 ${all.size} 个，上限 $MAX_ALARMS），" +
                "窗口 $HORIZON_DAYS 天，精确闹钟=$exact，最近一次=${fmt(next)}",
        )
        for (inst in used.take(12)) {
            val c = plan.courses.getOrNull(inst.courseIndex) ?: continue
            Log.i(
                TAG,
                "  #${inst.requestCode} ${fmt(inst.triggerAtMillis)} " +
                    "${describeType(inst, plan)} ${c.name} @${c.location}",
            )
        }
        if (used.size > 12) Log.i(TAG, "  ...（其余 ${used.size - 12} 条略）")

        return ScheduleResult(
            scheduled = used.size,
            horizonDays = HORIZON_DAYS,
            nextTriggerAtMillis = next,
            exact = exact,
            note = if (all.size > MAX_ALARMS) "提醒较多，仅排布最近 $MAX_ALARMS 条" else "",
        )
    }

    /** 取消全部闹钟与每日巡检，并清空计划。 */
    fun cancelAll(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        cancelScheduled(ctx, am)
        am.cancel(driverPendingIntent(ctx))
        PlanStore.saveCodes(ctx, emptyList())
    }

    // ---------------------------------------------------------------- 计划推导

    /**
     * 推导 [now, now + HORIZON_DAYS) 区间内的全部提醒时刻。
     *
     * 周次口径与 Dart 侧 `AppState._autoDetectWeek` 保持一致：`(天数差 ~/ 7) + 1`。
     *
     * 提醒规则（按用户要求实现）：
     * 1. 提前 30 分钟 —— **只在**当天上午/下午/晚上的第一节课前触发，且内容是**该时段全部课程**
     *    的预告（把该时段要用的书一次带齐）。
     * 2. 提前 15 分钟 —— 同样**只在**时段第一节课前触发，内容是单节课提醒。
     * 3. 提前 5 分钟 —— 当天**每一节课**都提醒，不区分是否时段首课。
     * 4. 下课前 N 分钟（默认 5）—— 预告**下一节课**；若下一节与当前是「连堂」
     *    （同名、同地点且节次紧接），或当天已经没有下一节课，则**不发**。
     */
    fun computeInstances(plan: ReminderPlan, now: Long): List<ReminderInstance> {
        val tz = java.util.TimeZone.getDefault()
        val todayMidnight = DayMath.epochDayToLocalMidnight(
            DayMath.localMillisToEpochDay(now, tz), tz,
        )
        val startMidnight = DayMath.epochDayToLocalMidnight(plan.semesterStartEpochDay, tz)
        val daysSinceStart = Math.round(
            (todayMidnight - startMidnight).toDouble() / DayMath.MILLIS_PER_DAY.toDouble(),
        ).toInt()

        val out = ArrayList<ReminderInstance>()

        for (offset in 0 until HORIZON_DAYS) {
            val dayMidnight = DayMath.plusDays(todayMidnight, offset, tz)
            val week = Math.floorDiv(daysSinceStart + offset, 7) + 1
            if (week < 1 || week > plan.totalWeeks) continue
            val isoDow = DayMath.isoDayOfWeek(dayMidnight, tz)
            val epochDay = DayMath.localMillisToEpochDay(dayMidnight, tz)

            // 法定节假日：整天不排提醒（「节假日不提醒」开关关掉时日历不生效）。
            if (plan.skipHolidays && plan.holidays.contains(epochDay)) continue
            // 调休补班：这天按「补的是周几」的课表上课（如周六补周三的课）。
            // 它与上面的开关无关 —— 补班修正的是「今天到底上周几的课」，不是放不放假。
            val classDow = plan.makeups[epochDay] ?: isoDow

            // 当天该周实际要上的课，按节次排序 —— 「下一节课」「时段首课」都基于这份列表
            val dayCourses = plan.courses.withIndex()
                .filter { (_, c) -> c.dayOfWeek == classDow && c.isActiveOnWeek(week) }
                .sortedWith(
                    compareBy({ it.value.startSection }, { it.value.endSection }, { it.value.name }),
                )
            if (dayCourses.isEmpty()) continue

            // 上午 / 下午 / 晚上各自当天最早的那节课
            val sessionFirst = HashSet<Int>()
            for (session in Session.entries) {
                dayCourses
                    .firstOrNull { Session.of(it.value.startSection) == session }
                    ?.let { sessionFirst.add(it.index) }
            }

            for ((pos, entry) in dayCourses.withIndex()) {
                val ci = entry.index
                val course = entry.value
                val startSlot = plan.periods[course.startSection] ?: continue
                val endSlot = plan.periods[course.endSection] ?: startSlot

                for (li in plan.prefs.leadMinutes.indices) {
                    val lead = plan.prefs.leadAt(li)
                    val scope = plan.prefs.scopeAt(li)
                    val sessionOnly = scope != LeadScope.ALL
                    if (sessionOnly && ci !in sessionFirst) continue

                    val minuteOfDay = startSlot.startMin - lead
                    val trigger = DayMath.atLocalTime(
                        dayMidnight, Math.floorDiv(minuteOfDay, 60), Math.floorMod(minuteOfDay, 60), tz,
                    )
                    if (trigger > now + MIN_LEAD_MILLIS) {
                        out.add(
                            ReminderInstance(
                                requestCode = 0, // 稍后统一编号
                                triggerAtMillis = trigger,
                                courseIndex = ci,
                                dateEpochDay = epochDay,
                                type = li,
                                sessionPreview = scope == LeadScope.SESSION_PREVIEW,
                            )
                        )
                    }
                }

                if (plan.prefs.endReminder) {
                    val next = dayCourses.getOrNull(pos + 1)?.value
                    // 连堂判定：下一节就是同一门课、同一地点，中间不用换书换教室 → 无需预告
                    val chained = next != null &&
                        next.startSection == course.endSection + 1 &&
                        next.name == course.name &&
                        next.location == course.location
                    if (next != null && !chained) {
                        val minuteOfDay = endSlot.endMin - plan.prefs.endPreviewMinutes
                        val trigger = DayMath.atLocalTime(
                            dayMidnight,
                            Math.floorDiv(minuteOfDay, 60),
                            Math.floorMod(minuteOfDay, 60),
                            tz,
                        )
                        if (trigger > now + MIN_LEAD_MILLIS) {
                            out.add(
                                ReminderInstance(
                                    requestCode = 0,
                                    triggerAtMillis = trigger,
                                    courseIndex = ci,
                                    dateEpochDay = epochDay,
                                    type = ReminderInstance.TYPE_END,
                                    nextCourseIndex = dayCourses[pos + 1].index,
                                )
                            )
                        }
                    }
                }
            }
        }

        out.sortBy { it.triggerAtMillis }
        // 按时间顺序统一编号：请求码即下标，取消时按上次保存的下标列表逐个取消
        return out.mapIndexed { idx, inst -> inst.copy(requestCode = idx) }
    }

    /** 取某天某时段的全部课程（供「时段预告」文案使用），按节次排序。 */
    fun coursesInSession(
        plan: ReminderPlan,
        dayOfWeek: Int,
        week: Int,
        session: Session,
    ): List<ReminderCourse> = plan.courses
        .filter {
            it.dayOfWeek == dayOfWeek &&
                it.isActiveOnWeek(week) &&
                Session.of(it.startSection) == session
        }
        .sortedWith(compareBy({ it.startSection }, { it.endSection }, { it.name }))

    // ---------------------------------------------------------------- 闹钟读写

    private fun setAlarm(
        ctx: Context,
        am: AlarmManager,
        inst: ReminderInstance,
    ): Boolean {
        val pi = reminderPendingIntent(ctx, inst)
        val canExact = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.canScheduleExactAlarms()
        } else {
            true
        }
        if (!canExact) {
            // 没有精确闹钟权限：只能退到「允许待机期间触发」的非精确闹钟。
            return try {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, inst.triggerAtMillis, pi)
                false
            } catch (e: SecurityException) {
                Log.w(TAG, "闹钟排布被拒绝：${e.message}")
                false
            }
        }

        // 优先用 setAlarmClock：系统把它当作「用户自己的闹钟」，
        // Doze 深度休眠与厂商省电策略都不会推迟它；而 setExactAndAllowWhileIdle
        // 在 Doze 下会被合批到维护窗口，隔夜之后的早八提醒可能晚到几十分钟。
        // 代价是状态栏会常驻一个闹钟小图标（系统对「用户闹钟」的标记）。
        // 想换回旧行为只需把 USE_ALARM_CLOCK 改成 false。
        if (USE_ALARM_CLOCK) {
            try {
                am.setAlarmClock(
                    AlarmManager.AlarmClockInfo(inst.triggerAtMillis, alarmShowIntent(ctx)),
                    pi,
                )
                return true
            } catch (e: SecurityException) {
                Log.w(TAG, "setAlarmClock 被拒绝，退回精确闹钟：${e.message}")
            } catch (e: RuntimeException) {
                Log.w(TAG, "setAlarmClock 失败，退回精确闹钟：${e.message}")
            }
        }

        return try {
            am.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP, inst.triggerAtMillis, pi,
            )
            true
        } catch (e: SecurityException) {
            Log.w(TAG, "精确闹钟被拒绝，降级为 setAndAllowWhileIdle：${e.message}")
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, inst.triggerAtMillis, pi)
            false
        }
    }

    private fun cancelScheduled(ctx: Context, am: AlarmManager) {
        for (code in PlanStore.loadCodes(ctx)) {
            val intent = Intent(ctx, ReminderReceiver::class.java).apply {
                action = ACTION_REMINDER
                data = Uri.parse("njtc://reminder/$code")
            }
            val pi = PendingIntent.getBroadcast(ctx, code, intent, PI_FLAGS)
            am.cancel(pi)
            pi.cancel()
        }
    }

    /** 每日 00:05 的巡检闹钟：把滑动窗口整体后移，实现提醒自持续。 */
    private fun armDailyDriver(ctx: Context, am: AlarmManager) {
        val tz = java.util.TimeZone.getDefault()
        val now = System.currentTimeMillis()
        val todayMidnight = DayMath.epochDayToLocalMidnight(
            DayMath.localMillisToEpochDay(now, tz), tz,
        )
        var trigger = DayMath.atLocalTime(todayMidnight, 0, 5, tz)
        if (trigger <= now) {
            trigger = DayMath.atLocalTime(DayMath.plusDays(todayMidnight, 1, tz), 0, 5, tz)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, driverPendingIntent(ctx))
            } else {
                am.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP, trigger, driverPendingIntent(ctx),
                )
            }
        } catch (e: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, driverPendingIntent(ctx))
        }
        Log.i(TAG, "每日巡检闹钟已设在 ${fmt(trigger)}")
    }

    private fun reminderPendingIntent(ctx: Context, inst: ReminderInstance): PendingIntent {
        val intent = Intent(ctx, ReminderReceiver::class.java).apply {
            action = ACTION_REMINDER
            data = Uri.parse("njtc://reminder/${inst.requestCode}")
            putExtra(EXTRA_COURSE_INDEX, inst.courseIndex)
            putExtra(EXTRA_NEXT_COURSE_INDEX, inst.nextCourseIndex)
            putExtra(EXTRA_TYPE, inst.type)
            putExtra(EXTRA_SESSION_PREVIEW, inst.sessionPreview)
            putExtra(EXTRA_DATE_EPOCH_DAY, inst.dateEpochDay)
        }
        return PendingIntent.getBroadcast(ctx, inst.requestCode, intent, PI_FLAGS)
    }

    private fun driverPendingIntent(ctx: Context): PendingIntent {
        val intent = Intent(ctx, ReminderReceiver::class.java).apply {
            action = ACTION_DAILY_DRIVER
            data = Uri.parse("njtc://daily-driver")
        }
        return PendingIntent.getBroadcast(ctx, DRIVER_REQUEST_CODE, intent, PI_FLAGS)
    }

    /**
     * `setAlarmClock` 需要的「展示用意图」——系统把这条闹钟展示成「用户闹钟」时，
     * 用户点它应当打开本应用（而不是别的界面）。
     */
    private fun alarmShowIntent(ctx: Context): PendingIntent {
        val intent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(ctx, ALARM_SHOW_REQUEST_CODE, intent, PI_FLAGS)
    }

    // ---------------------------------------------------------------- 展示辅助

    private fun describeType(inst: ReminderInstance, plan: ReminderPlan): String {
        if (inst.type == ReminderInstance.TYPE_END) {
            return "下课前 ${plan.prefs.endPreviewMinutes} 分钟预告"
        }
        val scope = plan.prefs.scopeAt(inst.type)
        val lead = plan.prefs.leadAt(inst.type)
        return when (scope) {
            LeadScope.SESSION_PREVIEW -> "上课前 $lead 分钟（时段首课 · 整段预告）"
            LeadScope.SESSION_FIRST -> "上课前 $lead 分钟（仅时段首课）"
            LeadScope.ALL -> "上课前 $lead 分钟（每一节课）"
        }
    }

    private fun fmt(millis: Long): String = formatTime(millis)

    /** 把毫秒时间戳格式化为「2026-10-05(周一) 09:45」，供日志与 Flutter 侧预览复用。 */
    fun formatTime(millis: Long): String {
        if (millis <= 0L) return "-"
        val tz = java.util.TimeZone.getDefault()
        val c = Calendar.getInstance(tz)
        c.timeInMillis = millis
        val weekNames = arrayOf("周日", "周一", "周二", "周三", "周四", "周五", "周六")
        return String.format(
            "%04d-%02d-%02d(%s) %02d:%02d",
            c.get(Calendar.YEAR),
            c.get(Calendar.MONTH) + 1,
            c.get(Calendar.DAY_OF_MONTH),
            weekNames[c.get(Calendar.DAY_OF_WEEK) - 1],
            c.get(Calendar.HOUR_OF_DAY),
            c.get(Calendar.MINUTE),
        )
    }

    /** 生成「距现在最近的前 [limit] 条提醒」的可读列表，用于 App 内预览与联调排查。 */
    fun preview(ctx: Context, limit: Int): List<Map<String, Any?>> {
        val plan = PlanStore.loadPlan(ctx) ?: return emptyList()
        val now = System.currentTimeMillis()
        val out = ArrayList<Map<String, Any?>>()
        for (inst in computeInstances(plan, now)) {
            if (out.size >= limit) break
            val c = plan.courses.getOrNull(inst.courseIndex) ?: continue
            val isEnd = inst.type == ReminderInstance.TYPE_END
            val next = if (isEnd) plan.courses.getOrNull(inst.nextCourseIndex) else null
            out.add(
                mapOf(
                    "triggerAt" to inst.triggerAtMillis,
                    "timeText" to formatTime(inst.triggerAtMillis),
                    "courseName" to if (next != null) "下节课：${next.name}" else c.name,
                    "location" to (next?.location ?: c.location),
                    "isEnd" to isEnd,
                    "kind" to when {
                        isEnd -> "endPreview"
                        inst.sessionPreview -> "sessionPreview"
                        else -> "lead"
                    },
                    "label" to if (inst.sessionPreview) {
                        val session = Session.of(c.startSection)
                        "${session.label}课程预告（提前 ${plan.prefs.leadAt(inst.type)} 分钟）"
                    } else {
                        describeType(inst, plan)
                    },
                )
            )
        }
        return out
    }
}
