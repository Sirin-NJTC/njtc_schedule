package cn.edu.njtc.njtc_schedule

import android.content.Intent
import cn.edu.njtc.njtc_schedule.ocr.OcrBridge
import cn.edu.njtc.njtc_schedule.reminder.NotificationFactory
import cn.edu.njtc.njtc_schedule.reminder.ReminderBridge
import cn.edu.njtc.njtc_schedule.webimport.WebImportBridge
import cn.edu.njtc.njtc_schedule.widget.WidgetBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    /** 网页登录导入桥（「读取课表」抓取结果要经 Activity result 回传）。 */
    private var webImport: WebImportBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 通知通道要在任何通知发出前创建好，这里在引擎起来时立即建好（幂等）
        NotificationFactory.ensureChannels(this)
        // 课程提醒桥：调度、vivo 原子通知、权限与系统设置跳转
        ReminderBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        // 教务系统网页登录导入桥
        webImport = WebImportBridge(this, flutterEngine.dartExecutor.binaryMessenger) { intent ->
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQ_WEB_IMPORT)
        }
        // 桌面小组件桥：接收课表/节次时间的 JSON 并刷新小组件
        WidgetBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        // 离线 OCR / PDF 识别桥（图片、扫描版 PDF 导入）
        OcrBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        android.util.Log.i("NjtcWebImport", "MainActivity.onActivityResult req=$requestCode res=$resultCode")
        // 必须转发给 super：file_picker 等注册在插件表里的插件依赖这里的回调
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_WEB_IMPORT) {
            webImport?.onActivityResult(resultCode, data)
        }
    }

    companion object {
        private const val REQ_WEB_IMPORT = 20750
    }
}
