package cn.edu.njtc.njtc_schedule.webimport

import android.app.Activity
import android.content.Intent
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

/**
 * Flutter <-> 原生 的「网页登录导入」桥。
 *
 * 通道名：`cn.edu.njtc.njtc_schedule/webimport`
 *
 * | 方法 | 入参 | 返回 |
 * | --- | --- | --- |
 * | `open` | `url`(String?) | `{ok, payload}` / `{ok:false, cancelled:true}` / `{ok:false, message}` |
 * | `lastUrl` | — | 上次成功抓到课表的页面地址 |
 *
 * `payload` 是抓取结果的 JSON 文本（`url` / `title` / `tableHtml` / `text` / `tableCount`），
 * 由 Dart 侧 `JwxtService` 解析。这里只搬运，不做业务判断。
 *
 * 抓取结果经过一道「写文件 + 传路径」的中转：课表页 HTML 可能几百 KB，
 * 直接塞 Intent extra 有 `TransactionTooLargeException` 风险。
 */
class WebImportBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val launch: (Intent) -> Unit,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL).also {
        it.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> {
                if (pending != null) {
                    result.error("busy", "已经有一个网页登录窗口在打开中", null)
                    return
                }
                val intent = Intent(activity, WebImportActivity::class.java)
                val url = call.argument<String>("url")
                if (!url.isNullOrBlank()) {
                    intent.putExtra(WebImportActivity.EXTRA_URL, url)
                }
                if (call.argument<Boolean>("autoRead") == true) {
                    intent.putExtra(WebImportActivity.EXTRA_AUTO_READ, true)
                }
                pending = result
                try {
                    launch(intent)
                } catch (t: Throwable) {
                    pending = null
                    Log.e(TAG, "打开网页登录失败：${t.message}", t)
                    result.error("launch_failed", "无法打开网页登录窗口：${t.message}", null)
                }
            }

            "lastUrl" -> result.success(prefsString(WebImportActivity.KEY_LAST_URL))

            "dispose" -> {
                channel.setMethodCallHandler(null)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /** 由 `MainActivity.onActivityResult` 调用，把抓取结果回传给挂起的 Flutter 调用。 */
    fun onActivityResult(resultCode: Int, data: Intent?) {
        Log.i(
            TAG,
            "onActivityResult resultCode=$resultCode pending=${pending != null} " +
                "path=${data?.getStringExtra(WebImportActivity.EXTRA_PAYLOAD_PATH)} " +
                "error=${data?.getStringExtra(WebImportActivity.EXTRA_ERROR)}",
        )
        val result = pending ?: return
        pending = null

        if (resultCode != Activity.RESULT_OK) {
            result.success(mapOf("ok" to false, "cancelled" to true))
            return
        }
        val path = data?.getStringExtra(WebImportActivity.EXTRA_PAYLOAD_PATH)
        if (path.isNullOrBlank()) {
            val message = data?.getStringExtra(WebImportActivity.EXTRA_ERROR)
                ?: "没有拿到页面内容"
            result.success(mapOf("ok" to false, "message" to message))
            return
        }
        try {
            val text = File(path).readText()
            JSONObject(text) // 先校验确实是 JSON，避免把半截文件传给 Dart
            result.success(mapOf("ok" to true, "payload" to text))
        } catch (t: Throwable) {
            Log.e(TAG, "读取抓取结果失败：${t.message}", t)
            result.success(mapOf("ok" to false, "message" to "读取抓取结果失败：${t.message}"))
        }
    }

    private fun prefsString(key: String): String? = activity
        .getSharedPreferences(WebImportActivity.PREFS, Activity.MODE_PRIVATE)
        .getString(key, null)

    companion object {
        private const val TAG = "NjtcWebImport"

        const val CHANNEL = "cn.edu.njtc.njtc_schedule/webimport"

        /**
         * 挂起的 Flutter 调用。
         *
         * 故意放在 companion 上：网页登录窗口在前台时，宿主 Activity 可能因为
         * 「不保留活动」等系统策略被销毁重建，实例字段会丢，静态字段不会。
         */
        private var pending: MethodChannel.Result? = null
    }
}
