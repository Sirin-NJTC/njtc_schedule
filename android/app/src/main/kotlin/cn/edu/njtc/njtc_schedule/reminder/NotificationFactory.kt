package cn.edu.njtc.njtc_schedule.reminder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.util.Log
import cn.edu.njtc.njtc_schedule.MainActivity
import cn.edu.njtc.njtc_schedule.R

/** 一条提醒的展示文案与配色，便于先算出来再决定走普通通知还是原子通知。 */
data class ReminderContent(
    val title: String,
    val content: String,
    val subText: String,
    val capsuleText: String,
    val islandLeftText: String,
    val islandRightText: String,
    val isEnd: Boolean,
    val accentColor: Int,
    val notificationId: Int,
)

/**
 * 通知构建与发送。
 *
 * 两条通道：
 * - [CHANNEL_REMINDER] 上课前提醒（提前 N 分钟）
 * - [CHANNEL_END] 下节课预告 —— 在 vivo 设备上会额外挂载原子通知 / 原子岛字段
 */
object NotificationFactory {
    private const val TAG = "NjtcNotify"

    const val CHANNEL_REMINDER = "njtc_course_reminder"
    const val CHANNEL_END = "njtc_course_end"

    /** 与 `lib/theme.dart` 里 `AppTheme.courseColors` 保持完全一致的 8 色课程调色板。 */
    private val COURSE_COLORS = intArrayOf(
        0xFF6366F1.toInt(),
        0xFF8B5CF6.toInt(),
        0xFFEC4899.toInt(),
        0xFFF59E0B.toInt(),
        0xFF10B981.toInt(),
        0xFF06B6D4.toInt(),
        0xFF3B82F6.toInt(),
        0xFFEF4444.toInt(),
    )

    fun colorFor(index: Int): Int = COURSE_COLORS[((index % COURSE_COLORS.size) + COURSE_COLORS.size) % COURSE_COLORS.size]

    /** 创建两条通知通道（幂等）。 */
    fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (nm.getNotificationChannel(CHANNEL_REMINDER) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_REMINDER,
                    "上课提醒",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "上午/下午/晚上第一节前 30/15 分钟（30 分钟那条会预告整段课程），" +
                        "以及每一节课前 5 分钟"
                    enableVibration(true)
                }
            )
        }
        if (nm.getNotificationChannel(CHANNEL_END) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_END,
                    "下节课预告",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "下课前 5 分钟预告下一节课（连堂的课不提醒）；" +
                        "vivo 设备可显示为原子通知 / 原子岛"
                }
            )
        }
    }

    // ------------------------------------------------------------ 文案计算

    /**
     * 计算一条提醒的展示文案。
     *
     * 三种形态：
     * 1. [sessionPreview] —— 「时段预告」：列出整个上午/下午/晚上要上的全部课程。
     * 2. [type] == [ReminderInstance.TYPE_END] —— 「下课前 N 分钟预告下一节课」。
     * 3. 其余 —— 单节课的「上课前 N 分钟」提醒。
     *
     * @param dateEpochDay 该提醒所属日期，用于反推周次（时段预告要按周过滤课程）
     * @param nextCourse   「下节课」，仅 [ReminderInstance.TYPE_END] 用得到
     */
    fun buildContent(
        plan: ReminderPlan,
        course: ReminderCourse,
        type: Int,
        dateEpochDay: Long = 0L,
        nextCourse: ReminderCourse? = null,
        sessionPreview: Boolean = false,
    ): ReminderContent {
        val isEnd = type == ReminderInstance.TYPE_END
        val startSlot = plan.periods[course.startSection]
        val endSlot = plan.periods[course.endSection] ?: startSlot

        val sectionText = if (course.startSection == course.endSection) {
            "第${course.startSection}节"
        } else {
            "第${course.startSection}-${course.endSection}节"
        }
        val startText = startSlot?.let { hhmm(it.startMin) } ?: ""
        val place = course.location.ifBlank { "地点待定" }
        val accent = colorFor(course.colorIndex)

        if (sessionPreview) {
            val lead = plan.prefs.leadAt(type)
            return sessionPreviewContent(plan, course, dateEpochDay, lead, accent)
        }

        if (isEnd) {
            val next = nextCourse
            val nextSlot = next?.let { plan.periods[it.startSection] }
            val nextStart = nextSlot?.let { hhmm(it.startMin) } ?: ""
            val nextPlace = next?.location?.ifBlank { null } ?: "地点待定"
            val nextSection = next?.let {
                if (it.startSection == it.endSection) {
                    "第${it.startSection}节"
                } else {
                    "第${it.startSection}-${it.endSection}节"
                }
            } ?: ""
            val endText = endSlot?.let { hhmm(it.endMin) } ?: ""
            val nextName = next?.name ?: "下一节课"
            return ReminderContent(
                title = "「${course.name}」${endText} 下课",
                content = "下节课：$nextName · $nextStart · $nextPlace",
                subText = "下节课预告 · $nextSection",
                capsuleText = "${shortName(nextName)} $nextStart",
                islandLeftText = nextName,
                islandRightText = "$nextStart 上课",
                isEnd = true,
                accentColor = accent,
                notificationId = notifId(course, type),
            )
        }

        val lead = plan.prefs.leadAt(type)
        return ReminderContent(
            title = "${sectionText} · ${course.name}",
            content = "$startText 上课 · $place" + if (course.teacher.isNotBlank()) " · ${course.teacher}" else "",
            subText = "还有 $lead 分钟",
            capsuleText = "$lead 分钟后 ${shortName(course.name)}",
            islandLeftText = course.name,
            islandRightText = "还有 $lead 分钟",
            isEnd = false,
            accentColor = accent,
            notificationId = notifId(course, type),
        )
    }

    /** 「时段预告」文案：把该时段要上的课全部列出来，方便一次带齐教材。 */
    private fun sessionPreviewContent(
        plan: ReminderPlan,
        course: ReminderCourse,
        dateEpochDay: Long,
        lead: Int,
        accent: Int,
    ): ReminderContent {
        val session = Session.of(course.startSection)
        val week = if (plan.semesterStartEpochDay > 0L) {
            Math.floorDiv(dateEpochDay - plan.semesterStartEpochDay, 7L).toInt() + 1
        } else {
            1
        }
        val list = ReminderScheduler.coursesInSession(plan, course.dayOfWeek, week, session)
        val lines = list.map { c ->
            val t = plan.periods[c.startSection]?.let { hhmm(it.startMin) } ?: ""
            val p = c.location.ifBlank { "地点待定" }
            "$t ${c.name} @$p"
        }
        val body = if (lines.isEmpty()) {
            "$session.label · ${course.name} @${course.location.ifBlank { "地点待定" }}"
        } else {
            lines.joinToString("\n")
        }
        val count = maxOf(list.size, 1)
        return ReminderContent(
            title = "还有 $lead 分钟上课 · ${session.label}共 $count 门课",
            content = body,
            subText = "记得带齐${session.label}要用的全部教材",
            capsuleText = "${session.label} $count 门课",
            islandLeftText = "${session.label} $count 门课",
            islandRightText = "还有 $lead 分钟",
            isEnd = false,
            accentColor = accent,
            notificationId = notifId(course, ReminderInstance.TYPE_END + 1),
        )
    }

    /** 通知 id：同一门课的同一类提醒互相覆盖，避免通知栏堆叠。 */
    private fun notifId(course: ReminderCourse, type: Int): Int {
        val idx = course.name.hashCode() and 0x3FF
        return 1000 + idx * 8 + type
    }

    private fun shortName(name: String): String =
        if (name.length <= 6) name else name.substring(0, 6) + "…"

    private fun hhmm(minuteOfDay: Int): String {
        val h = Math.floorDiv(minuteOfDay, 60)
        val m = Math.floorMod(minuteOfDay, 60)
        return String.format("%02d:%02d", h, m)
    }

    // ------------------------------------------------------------ 发送

    /**
     * 发送一条提醒。
     *
     * @param useAtomic true 时挂载 vivo 原子通知（superx）字段；
     *                  原子通知失败的降级由系统按 `showNotify=true` 处理。
     * @return 实际使用的通道描述，用于日志与「试一下」回显
     */
    fun show(
        ctx: Context,
        content: ReminderContent,
        useAtomic: Boolean,
        triggerAtMillis: Long,
    ): String {
        ensureChannels(ctx)
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val clickIntent = clickPendingIntent(ctx, content.notificationId)
        val channel = if (content.isEnd) CHANNEL_END else CHANNEL_REMINDER

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(ctx, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx).also {
                @Suppress("DEPRECATION")
                it.setPriority(
                    if (content.isEnd) Notification.PRIORITY_DEFAULT else Notification.PRIORITY_HIGH
                )
            }
        }

        builder
            .setSmallIcon(R.drawable.ic_stat_course)
            .setContentTitle(content.title)
            .setContentText(content.content)
            .setColor(content.accentColor)
            .setColorized(false)
            .setContentIntent(clickIntent)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setWhen(if (triggerAtMillis > 0) triggerAtMillis else System.currentTimeMillis())

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
            builder.style = Notification.BigTextStyle().bigText(content.content)
        }

        val notification = builder.build()

        // 只要用户显式开启了原子通知就挂载 superx 字段：非 vivo 设备/未开通准入时
        // 系统会直接忽略这些 extra（官方 showNotify 默认 true → 降级为普通通知），
        // 因此挂载本身没有副作用，同时让字段可以在任意设备上用 dumpsys 验证。
        val atomic = useAtomic
        if (atomic) {
            VivoHelper.attachSuperx(
                ctx = ctx,
                notification = notification,
                title = content.title,
                content = content.content,
                subText = content.subText,
                capsuleText = content.capsuleText,
                islandLeftText = content.islandLeftText,
                islandRightText = content.islandRightText,
                accentColor = content.accentColor,
                clickIntent = clickIntent,
                template = VivoHelper.TEMPLATE_EMPHASIS,
            )
        }

        try {
            nm.notify(content.notificationId, notification)
        } catch (t: Throwable) {
            Log.e(TAG, "发送通知失败：${t.message}", t)
            return "failed:${t.message}"
        }

        val mode = if (atomic) {
            when {
                VivoHelper.isIslandCapable() -> "vivo 原子通知 + 原子岛"
                VivoHelper.isVivo() -> "vivo 原子通知（状态栏胶囊）"
                else -> "vivo 原子通知（当前非 vivo 设备，字段已挂载但会被系统忽略）"
            }
        } else {
            "普通通知"
        }
        Log.i(TAG, "已发送[$mode] id=${content.notificationId} ${content.title} | ${content.content}")
        return mode
    }

    /** 取消某门课的全部提醒通知（含时段预告，其 type 为 TYPE_END + 1）。 */
    fun cancel(ctx: Context, plan: ReminderPlan) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        for (c in plan.courses) {
            for (t in 0..(ReminderInstance.TYPE_END + 1)) {
                nm.cancel(notifId(c, t))
            }
        }
    }

    private fun clickPendingIntent(ctx: Context, notificationId: Int): PendingIntent {
        val intent = Intent(ctx, MainActivity::class.java).apply {
            action = "cn.edu.njtc.njtc_schedule.action.OPEN_FROM_REMINDER"
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        }
        return PendingIntent.getActivity(
            ctx,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** 保持与 theme.dart 一致的主色，供测试通知使用。 */
    val BRAND_PRIMARY: Int = 0xFF5B6BF0.toInt()
    val WHITE: Int = Color.WHITE
}
