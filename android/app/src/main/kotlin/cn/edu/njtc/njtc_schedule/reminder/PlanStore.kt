package cn.edu.njtc.njtc_schedule.reminder

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * 提醒计划的本地持久化。
 *
 * 存在 SharedPreferences 里而不是内存中，是为了让「开机广播」和「每日巡检闹钟」
 * 在没有 Flutter/Dart 侧参与的情况下也能重建全部闹钟。
 */
object PlanStore {
    private const val PREFS = "njtc_reminder_plan"
    private const val KEY_PLAN = "plan_json"
    private const val KEY_CODES = "scheduled_codes"
    private const val KEY_LAST_SYNC = "last_sync_at"

    private fun prefs(ctx: Context) =
        ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun savePlan(ctx: Context, json: JSONObject) {
        prefs(ctx).edit().putString(KEY_PLAN, json.toString()).apply()
    }

    fun loadPlan(ctx: Context): ReminderPlan? {
        val raw = prefs(ctx).getString(KEY_PLAN, null) ?: return null
        return try {
            ReminderPlan.fromJson(JSONObject(raw))
        } catch (e: Exception) {
            null
        }
    }

    fun hasPlan(ctx: Context): Boolean = prefs(ctx).contains(KEY_PLAN)

    fun saveCodes(ctx: Context, codes: List<Int>) {
        val arr = JSONArray()
        for (c in codes) arr.put(c)
        prefs(ctx).edit().putString(KEY_CODES, arr.toString()).apply()
    }

    fun loadCodes(ctx: Context): List<Int> {
        val raw = prefs(ctx).getString(KEY_CODES, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            val out = ArrayList<Int>(arr.length())
            for (i in 0 until arr.length()) out.add(arr.getInt(i))
            out
        } catch (e: Exception) {
            emptyList()
        }
    }

    fun saveLastSync(ctx: Context, millis: Long) {
        prefs(ctx).edit().putLong(KEY_LAST_SYNC, millis).apply()
    }

    fun lastSync(ctx: Context): Long = prefs(ctx).getLong(KEY_LAST_SYNC, 0L)

    fun clear(ctx: Context) {
        prefs(ctx).edit().clear().apply()
    }
}
