package cn.edu.njtc.njtc_schedule.reminder

import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone

/**
 * 一个节次的上下课时间。
 *
 * @param startMin 该节开始时刻，从当日 00:00 起算的分钟数（如 08:00 -> 480）
 * @param endMin   该节结束时刻，同样以分钟计
 */
data class PeriodSlot(val section: Int, val startMin: Int, val endMin: Int)

/**
 * 一个节次落在哪个时段。
 *
 * 分段与 Dart 侧 `lib/models/period.dart` 的作息表一致：
 * 上午 1-4 节、下午 5-8 节、晚上 9-11 节。
 * 课表里的「上下午晚第一节」就是各时段里当天实际最早的那节课。
 */
enum class Session(val label: String, val startSection: Int, val endSection: Int) {
    MORNING("上午", 1, 4),
    AFTERNOON("下午", 5, 8),
    EVENING("晚上", 9, 11);

    companion object {
        fun of(section: Int): Session = when {
            section <= MORNING.endSection -> MORNING
            section <= AFTERNOON.endSection -> AFTERNOON
            else -> EVENING
        }
    }
}

/** 一条「提前 N 分钟」提醒的作用范围。 */
enum class LeadScope {
    /** 只在上午/下午/晚上第一节课前提醒，且提醒内容是**该时段全部课程**的预告。 */
    SESSION_PREVIEW,

    /** 只在上午/下午/晚上第一节课前提醒，内容是单节课提醒。 */
    SESSION_FIRST,

    /** 当天每一节课都提醒。 */
    ALL;

    companion object {
        fun from(raw: String?): LeadScope = when (raw) {
            "sessionPreview" -> SESSION_PREVIEW
            "sessionFirst" -> SESSION_FIRST
            else -> ALL
        }
    }
}

/** 一门课程的一堂课，字段与 Dart 侧 `lib/models/course.dart` 的 `Course` 一一对应。 */
data class ReminderCourse(
    val name: String,
    val location: String,
    val teacher: String,
    val dayOfWeek: Int,
    val startSection: Int,
    val endSection: Int,
    val startWeek: Int,
    val endWeek: Int,
    val oddEven: Int,
    val colorIndex: Int,
) {
    /** 该课在指定周是否上课（与 Dart 侧 `Course.isActiveOnWeek` 完全一致的语义）。 */
    fun isActiveOnWeek(week: Int): Boolean {
        if (week < startWeek || week > endWeek) return false
        if (oddEven == 1 && week % 2 == 0) return false // 单周：偶数周不上
        if (oddEven == 2 && week % 2 == 1) return false // 双周：奇数周不上
        return true
    }
}

/** 提醒偏好。 */
data class ReminderPrefs(
    /** 总开关 */
    val enabled: Boolean,
    /** 提前多少分钟提醒（降序，如 [30, 15, 5]） */
    val leadMinutes: List<Int>,
    /**
     * 与 [leadMinutes] **一一对应且顺序一致**的作用范围。
     *
     * 由 Dart 侧下发（见 `lib/services/reminder_service.dart` 的 `buildPlanPayload`）：
     * 30 分钟 → 时段预告、15 分钟 → 仅时段首课、5 分钟 → 每一节课。
     */
    val leadScopes: List<LeadScope>,
    /** 是否发送「下课前预告下一节课」 */
    val endReminder: Boolean,
    /** 「下课前 N 分钟」的 N，默认 5。 */
    val endPreviewMinutes: Int,
    /** 是否使用 vivo 原子通知（原子岛）承载「下课前预告」 */
    val vivoAtomic: Boolean,
) {
    fun scopeAt(index: Int): LeadScope = leadScopes.getOrNull(index) ?: LeadScope.ALL
    fun leadAt(index: Int): Int = leadMinutes.getOrNull(index) ?: 0
}

/**
 * 完整提醒计划 —— 由 Flutter 侧计算并下发，原生侧据此自行推算未来 N 天的全部提醒。
 *
 * 之所以把「课程规则」而不是「具体提醒时刻」交给原生，是为了让提醒能自持续：
 * 系统闹钟在「每日巡检闹钟」或开机广播里被重新排布，无需用户再次打开 App。
 */
data class ReminderPlan(
    /** 学期第 1 周周一所在日期（epochDay，1970-01-01 为 0） */
    val semesterStartEpochDay: Long,
    val totalWeeks: Int,
    val periods: Map<Int, PeriodSlot>,
    val courses: List<ReminderCourse>,
    val prefs: ReminderPrefs,
) {
    companion object {
        fun fromJson(json: JSONObject): ReminderPlan {
            val periods = mutableMapOf<Int, PeriodSlot>()
            val periodsJson = json.optJSONArray("periods") ?: JSONArray()
            for (i in 0 until periodsJson.length()) {
                val o = periodsJson.getJSONObject(i)
                val section = o.getInt("section")
                periods[section] = PeriodSlot(
                    section = section,
                    startMin = o.getInt("startMin"),
                    endMin = o.getInt("endMin"),
                )
            }

            val courses = mutableListOf<ReminderCourse>()
            val coursesJson = json.optJSONArray("courses") ?: JSONArray()
            for (i in 0 until coursesJson.length()) {
                val o = coursesJson.getJSONObject(i)
                courses.add(
                    ReminderCourse(
                        name = o.optString("name"),
                        location = o.optString("location"),
                        teacher = o.optString("teacher"),
                        dayOfWeek = o.optInt("dayOfWeek", 1),
                        startSection = o.optInt("startSection", 1),
                        endSection = o.optInt("endSection", 2),
                        startWeek = o.optInt("startWeek", 1),
                        endWeek = o.optInt("endWeek", 20),
                        oddEven = o.optInt("oddEven", 0),
                        colorIndex = o.optInt("colorIndex", 0),
                    )
                )
            }

            val leadsJson = json.optJSONArray("leadMinutes") ?: JSONArray()
            val scopesJson = json.optJSONArray("leadScopes") ?: JSONArray()
            // 分钟数与作用范围必须成对排序，否则下标错位会导致「哪条提醒只对时段首课生效」判断错乱
            val pairs = mutableListOf<Pair<Int, LeadScope>>()
            for (i in 0 until leadsJson.length()) {
                pairs.add(leadsJson.getInt(i) to LeadScope.from(scopesJson.optString(i, null)))
            }
            if (pairs.isEmpty()) pairs.add(15 to LeadScope.SESSION_FIRST)
            pairs.sortByDescending { it.first }

            return ReminderPlan(
                semesterStartEpochDay = json.optLong("semesterStartEpochDay", 0L),
                totalWeeks = json.optInt("totalWeeks", 20),
                periods = periods,
                courses = courses,
                prefs = ReminderPrefs(
                    enabled = json.optBoolean("enabled", true),
                    leadMinutes = pairs.map { it.first },
                    leadScopes = pairs.map { it.second },
                    endReminder = json.optBoolean("endReminder", true),
                    endPreviewMinutes = json.optInt("endPreviewMinutes", 5),
                    vivoAtomic = json.optBoolean("vivoAtomic", true),
                ),
            )
        }
    }
}

/**
 * 计算得到的一条具体闹钟。
 *
 * @property type 提醒类型：
 *   - `0 .. leadMinutes.size-1` —— 对应 leadMinutes 下标的「即将上课」提醒
 *   - [TYPE_END] —— 「下课前 N 分钟预告下一节课」
 * @property nextCourseIndex [type] 为 [TYPE_END] 时指向下一节课在 plan.courses 中的下标，否则 -1
 * @property sessionPreview 该条是否为「时段预告」（内容列出整个上午/下午/晚上的课程）
 */
data class ReminderInstance(
    /** 稳定的请求码：等于该条在本次计划中的下标，取消时按上次的下标列表逐个取消 */
    val requestCode: Int,
    val triggerAtMillis: Long,
    val courseIndex: Int,
    /** 该提醒所属日期（epochDay），用于日志与去重 */
    val dateEpochDay: Long,
    val type: Int,
    val nextCourseIndex: Int = -1,
    val sessionPreview: Boolean = false,
) {
    companion object {
        const val TYPE_END = 3
    }
}

/** epochDay <-> 本地零点时刻 的换算工具（避开 java.time，兼容 minSdk 24）。 */
object DayMath {
    const val MILLIS_PER_DAY = 86_400_000L
    private val utc: TimeZone = TimeZone.getTimeZone("UTC")

    /** epochDay -> 本地时区当天 00:00 的毫秒时间戳。 */
    fun epochDayToLocalMidnight(epochDay: Long, zone: TimeZone = TimeZone.getDefault()): Long {
        val u = Calendar.getInstance(utc)
        u.clear()
        u.timeInMillis = epochDay * MILLIS_PER_DAY
        val local = Calendar.getInstance(zone)
        local.clear()
        local.set(
            u.get(Calendar.YEAR),
            u.get(Calendar.MONTH),
            u.get(Calendar.DAY_OF_MONTH),
            0, 0, 0,
        )
        local.set(Calendar.MILLISECOND, 0)
        return local.timeInMillis
    }

    /** 本地时区的某个毫秒时间戳 -> 它所属日期的 epochDay。 */
    fun localMillisToEpochDay(millis: Long, zone: TimeZone = TimeZone.getDefault()): Long {
        val local = Calendar.getInstance(zone)
        local.timeInMillis = millis
        val u = Calendar.getInstance(utc)
        u.clear()
        u.set(
            local.get(Calendar.YEAR),
            local.get(Calendar.MONTH),
            local.get(Calendar.DAY_OF_MONTH),
            0, 0, 0,
        )
        u.set(Calendar.MILLISECOND, 0)
        return Math.floorDiv(u.timeInMillis, MILLIS_PER_DAY)
    }

    /** 在给定日期零点的基础上加若干天并设定到指定时分，返回毫秒时间戳（DST 安全）。 */
    fun atLocalTime(
        dayMidnightMillis: Long,
        hourOfDay: Int,
        minute: Int,
        zone: TimeZone = TimeZone.getDefault(),
    ): Long {
        val c = Calendar.getInstance(zone)
        c.timeInMillis = dayMidnightMillis
        c.set(Calendar.HOUR_OF_DAY, hourOfDay)
        c.set(Calendar.MINUTE, minute)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        return c.timeInMillis
    }

    /** 在给定日期零点的基础上整日平移，返回新的零点毫秒时间戳（DST 安全）。 */
    fun plusDays(dayMidnightMillis: Long, days: Int, zone: TimeZone = TimeZone.getDefault()): Long {
        val c = Calendar.getInstance(zone)
        c.timeInMillis = dayMidnightMillis
        c.add(Calendar.DAY_OF_YEAR, days)
        c.set(Calendar.HOUR_OF_DAY, 0)
        c.set(Calendar.MINUTE, 0)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        return c.timeInMillis
    }

    /** Calendar.DAY_OF_WEEK(1=周日..7=周六) -> ISO 星期(1=周一..7=周日)。 */
    fun isoDayOfWeek(dayMidnightMillis: Long, zone: TimeZone = TimeZone.getDefault()): Int {
        val c = Calendar.getInstance(zone)
        c.timeInMillis = dayMidnightMillis
        val dow = c.get(Calendar.DAY_OF_WEEK)
        return if (dow == Calendar.SUNDAY) 7 else dow - 1
    }
}
