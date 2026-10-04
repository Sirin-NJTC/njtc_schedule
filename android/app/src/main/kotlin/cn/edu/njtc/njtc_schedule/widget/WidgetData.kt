package cn.edu.njtc.njtc_schedule.widget

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

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

    /** 出场作息，和 Dart 侧 `defaultPeriods` 保持一致（没同步过时用它兜底）。 */
    private val DEFAULT_PERIODS: Map<Int, Pair<String, String>> = mapOf(
        1 to ("08:00" to "08:45"),
        2 to ("08:55" to "09:40"),
        3 to ("10:00" to "10:45"),
        4 to ("10:55" to "11:40"),
        5 to ("14:30" to "15:15"),
        6 to ("15:25" to "16:10"),
        7 to ("16:30" to "17:15"),
        8 to ("17:25" to "18:10"),
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
        val dow = dayOfWeek(now)

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

        val footer = when {
            todays.isEmpty() && week < 0 -> "今天没课（还没设置学期起始日期）"
            todays.isEmpty() -> "今天没课，好好休息"
            todays.size > MAX_ROWS -> "还有 ${todays.size - MAX_ROWS} 门 · 点开看全部"
            else -> "共 ${todays.size} 门 · 点开看全部"
        }
        return Snapshot(dateText, weekText, rows, footer)
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
