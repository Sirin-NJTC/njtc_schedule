package cn.edu.njtc.njtc_schedule.widget

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.HashMap
import java.util.HashSet
import java.util.Locale
import java.util.TimeZone

/**
 * 把 Dart 侧推过来的课表 JSON 折算成「今天要画的那几行」。
 *
 * 这里刻意**不依赖 Flutter**：小组件可能在 App 进程没起来时被系统唤醒，
 * 全靠 [NjtcWidgetStore] 里那份 JSON。
 */
internal object WidgetData {

    /** 一行 = 今天的一门课。 */
    data class Row(
        val time: String,
        val name: String,
        val location: String,
        val color: Int,
    )

    /** 一次渲染要用到的全部内容。 */
    data class Snapshot(
        val dateText: String,
        val weekText: String,
        val rows: List<Row>,
        val footer: String,
    )

    /** 最多画几行；超出的折成 footer 里的一句「还有 N 门」。 */
    private const val MAX_ROWS = 5

    /** 和 `lib/theme.dart` 的 `AppTheme.courseColors` 一一对应。 */
    private val COURSE_COLORS = intArrayOf(
        0xFF6366F1.toInt(), // 靛蓝
        0xFF8B5CF6.toInt(), // 紫
        0xFFEC4899.toInt(), // 粉
        0xFFF59E0B.toInt(), // 琥珀
        0xFF10B981.toInt(), // 绿
        0xFF06B6D4.toInt(), // 青
        0xFF3B82F6.toInt(), // 蓝
        0xFFEF4444.toInt(), // 红
    )

    /**
     * 出场作息，和 Dart 侧 `defaultPeriods` 保持一致（没同步过时用它兜底）。
     *
     * 依据《内江师范学院关于执行全年统一作息时间的通知》（2026-04-29 发布，
     * 自 2026-05-06 起执行）：上午 1-4 节 08:20 起、下午 5-8 节 14:20 起，
     * 晚上 9-11 节不变。改这里时请同步 `lib/models/period.dart` 与 `preview.html`。
     */
    private val DEFAULT_PERIODS: Map<Int, Pair<String, String>> = mapOf(
        1 to ("08:20" to "09:05"),
        2 to ("09:15" to "10:00"),
        3 to ("10:20" to "11:05"),
        4 to ("11:15" to "12:00"),
        5 to ("14:20" to "15:05"),
        6 to ("15:15" to "16:00"),
        7 to ("16:20" to "17:05"),
        8 to ("17:15" to "18:00"),
        9 to ("19:00" to "19:45"),
        10 to ("19:55" to "20:40"),
        11 to ("20:50" to "21:35"),
    )

    private val WEEKDAY_NAMES = arrayOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")

    fun build(context: Context, now: Calendar = Calendar.getInstance()): Snapshot {
        val dateText = "${now.get(Calendar.MONTH) + 1}月${now.get(Calendar.DAY_OF_MONTH)}日 " +
            WEEKDAY_NAMES[dayOfWeek(now) - 1]

        val raw = NjtcWidgetStore.timetable(context)
        if (raw.isNullOrBlank()) {
            val note = if (NjtcWidgetStore.hasTimetable(context)) {
                "还没有课表 · 点开 App 导入"
            } else {
                "打开 App 同步一次课表"
            }
            return Snapshot(dateText, "", emptyList(), note)
        }

        val tt = try {
            JSONObject(raw)
        } catch (e: Exception) {
            return Snapshot(dateText, "", emptyList(), "课表数据读不出来，打开 App 重试")
        }

        val totalWeeks = tt.optInt("totalWeeks", 20).coerceAtLeast(1)
        val start = parseDate(tt.optString("startDate"))
        val week = if (start == null) -1 else weekNumber(start, now, totalWeeks)
        val weekText = if (week < 0) "未设置起始日期" else "第${week}周"

        val periods = loadPeriods(context)
        val holidayIdx = parseHolidays(NjtcWidgetStore.holidays(context))
        val today = todayEpochDay(now)

        // 调休补班：这天按「周几」上课（覆盖真实星期几）；否则用真实星期几。
        val makeupDow = holidayIdx.makeups[today]
        val dow = makeupDow ?: dayOfWeek(now)

        // 放假日（且不是补班日）→ 直接放假，不画课。
        val holidayName = if (makeupDow == null) holidayIdx.names[today] else null
        if (holidayName != null) {
            return Snapshot(dateText, weekText, emptyList(), "今天放假 · $holidayName")
        }

        val todays = ArrayList<JSONObject>()
        val courses = tt.optJSONArray("courses") ?: JSONArray()
        for (i in 0 until courses.length()) {
            val c = courses.optJSONObject(i) ?: continue
            if (c.optInt("dayOfWeek", 1) != dow) continue
            if (week >= 0 && !activeOnWeek(c, week)) continue
            todays.add(c)
        }
        todays.sortBy { it.optInt("startSection", 1) }

        val rows = todays.take(MAX_ROWS).map { c ->
            val name = c.optString("name")
            val startSection = c.optInt("startSection", 1)
            val endSection = c.optInt("endSection", startSection)
            Row(
                time = timeText(periods, startSection, endSection),
                name = name,
                location = c.optString("location"),
                color = colorForCourse(name),
            )
        }

        // 补班日：在说明里点明「补周几」，免得看到一堆课却以为是周末。
        val makeupNote = if (makeupDow != null) "补${WEEKDAY_NAMES[makeupDow - 1]} · " else ""
        val footer = when {
            todays.isEmpty() && week < 0 -> "今天没课（还没设置学期起始日期）"
            todays.isEmpty() && makeupDow != null -> "今天没课（补班日）"
            todays.isEmpty() -> "今天没课，好好休息"
            todays.size > MAX_ROWS -> "${makeupNote}还有 ${todays.size - MAX_ROWS} 门 · 点开看全部"
            else -> "${makeupNote}共 ${todays.size} 门 · 点开看全部"
        }
        return Snapshot(dateText, weekText, rows, footer)
    }

    // ------------------------------------------------------------ 节假日

    /**
     * 解析好的节假日索引：放假日不画课、补班日按指定周几画。
     *
     * 数据结构对齐 Dart 侧 `HolidayCalendar` 下发的 JSON：
     * `{"h":[{"e":epochDay,"n":"名称"}, …], "m":[{"e":epochDay,"w":周几,"n":"备注"}, …]}`。
     */
    private data class HolidayIndex(
        val days: Set<Long>,
        val names: Map<Long, String>,
        val makeups: Map<Long, Int>,
    ) {
        companion object {
            val EMPTY = HolidayIndex(emptySet(), emptyMap(), emptyMap())
        }
    }

    private fun parseHolidays(raw: String?): HolidayIndex {
        if (raw.isNullOrBlank()) return HolidayIndex.EMPTY
        return try {
            val root = JSONObject(raw)
            val days = HashSet<Long>()
            val names = HashMap<Long, String>()
            val hArr = root.optJSONArray("h") ?: JSONArray()
            for (i in 0 until hArr.length()) {
                val o = hArr.optJSONObject(i) ?: continue
                val e = o.optLong("e", -1L)
                if (e < 0) continue
                days.add(e)
                val n = o.optString("n")
                if (n.isNotBlank()) names[e] = n
            }
            val makeups = HashMap<Long, Int>()
            val mArr = root.optJSONArray("m") ?: JSONArray()
            for (i in 0 until mArr.length()) {
                val o = mArr.optJSONObject(i) ?: continue
                val e = o.optLong("e", -1L)
                val w = o.optInt("w", 0)
                if (e < 0 || w < 1 || w > 7) continue
                makeups[e] = w
            }
            HolidayIndex(days, names, makeups)
        } catch (e: Exception) {
            HolidayIndex.EMPTY
        }
    }

    /**
     * 今天的 epochDay（UTC 天数），和 Dart 的 `epochDayOf` 完全一致：
     * 取本地年月日当 UTC 零点，再除以 86400000。
     */
    private fun todayEpochDay(now: Calendar): Long {
        val y = now.get(Calendar.YEAR)
        val m = now.get(Calendar.MONTH) + 1
        val d = now.get(Calendar.DAY_OF_MONTH)
        val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
        utc.clear()
        utc.set(y, m - 1, d, 0, 0, 0)
        utc.set(Calendar.MILLISECOND, 0)
        return utc.timeInMillis / 86_400_000L
    }

    // ------------------------------------------------------------ 细节

    /** 周一=1 … 周日=7（Calendar 里周日=1，先平移再取模）。 */
    private fun dayOfWeek(now: Calendar): Int =
        ((now.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1

    /** 和 Dart 的 `AppState._autoDetectWeek` 同一套算法：`diff ~/ 7 + 1` 再夹到 [1, totalWeeks]。 */
    private fun weekNumber(start: Calendar, now: Calendar, totalWeeks: Int): Int {
        val ms = now.timeInMillis - start.timeInMillis
        val days = Math.floorDiv(ms, 86_400_000L)
        val week = (days / 7).toInt() + 1
        return week.coerceIn(1, totalWeeks)
    }

    /** 对应 Dart 的 `Course.isActiveOnWeek`。 */
    private fun activeOnWeek(c: JSONObject, week: Int): Boolean {
        val startWeek = c.optInt("startWeek", 1)
        val endWeek = c.optInt("endWeek", 20)
        if (week < startWeek || week > endWeek) return false
        return when (c.optInt("oddEven", 0)) {
            1 -> week % 2 == 1 // 单周
            2 -> week % 2 == 0 // 双周
            else -> true
        }
    }

    private fun timeText(
        periods: Map<Int, Pair<String, String>>,
        startSection: Int,
        endSection: Int,
    ): String {
        val a = periods[startSection]?.first
        val b = periods[endSection]?.second ?: periods[startSection]?.second
        return if (a != null && b != null) "$a-$b" else "第${startSection}节"
    }

    /** 课程名稳定取色，算法与 Dart 的 `AppTheme.colorForCourse` 完全一致。 */
    private fun colorForCourse(name: String): Int {
        if (name.isEmpty()) return COURSE_COLORS[0]
        var hash = 0
        for (ch in name) hash += ch.code // Dart 的 codeUnits 就是 UTF-16 码元
        return COURSE_COLORS[((hash % COURSE_COLORS.size) + COURSE_COLORS.size) % COURSE_COLORS.size]
    }

    private fun loadPeriods(context: Context): Map<Int, Pair<String, String>> {
        val raw = NjtcWidgetStore.periods(context) ?: return DEFAULT_PERIODS
        return try {
            val arr = JSONArray(raw)
            val out = HashMap<Int, Pair<String, String>>()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val section = o.optInt("s", i + 1)
                val a = o.optString("a")
                val b = o.optString("b")
                if (a.isNotBlank() && b.isNotBlank()) out[section] = a to b
            }
            if (out.isEmpty()) DEFAULT_PERIODS else out
        } catch (e: Exception) {
            DEFAULT_PERIODS
        }
    }

    /** 只取 `yyyy-MM-dd` 那一段，解析成当天 0 点。 */
    private fun parseDate(raw: String?): Calendar? {
        if (raw.isNullOrBlank() || raw.length < 10) return null
        return try {
            val d = SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(raw.substring(0, 10))
                ?: return null
            Calendar.getInstance().apply {
                time = d
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
        } catch (e: Exception) {
            null
        }
    }
}
