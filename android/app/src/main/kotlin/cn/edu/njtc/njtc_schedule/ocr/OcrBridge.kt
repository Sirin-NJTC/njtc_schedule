package cn.edu.njtc.njtc_schedule.ocr

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max

/**
 * 离线 OCR / PDF 识别的 Dart ↔ 原生桥。
 *
 * 三条能力：
 *  - `recognizeImage`：一张图片（相册/拍照/截图）→ 文字。走 Tesseract4Android（离线，不需要
 *    Google 服务，国产 ROM 也能用），语言模型是 `assets/tessdata/` 下的 `.traineddata` 文件。
 *  - `recognizePdf`：一份 PDF → 文字。用 Android 自带的 [PdfRenderer] 把每页渲染成位图再 OCR，
 *    所以文字版和扫描版走的是同一条路，也不必自带 pdfium（APK 不涨体积）。
 *  - `info`：诊断用（模型文件是否就位、引擎能否初始化），集成测试与真机排查都靠它。
 *
 * 线程：OCR 一张图要几秒到几十秒，绝不能在平台线程上跑；这里统一丢到后台线程，
 * 结果再 post 回主线程（MethodChannel.Result 按约定在主线程回调最稳）。
 */
class OcrBridge(private val context: Context, messenger: BinaryMessenger) {

    private val main = Handler(Looper.getMainLooper())

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            // 桥里抛异常绝不能让 handler「什么都不回」：那样 Dart 侧看到的是
            // MissingPluginException（像是桥没注册），排查会被彻底带偏。统一回错。
            try {
                when (call.method) {
                    "recognizeImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.error("bad_args", "缺少图片字节（bytes）", null)
                            return@setMethodCallHandler
                        }
                        val langs = call.argument<String>("langs") ?: DEFAULT_LANGS
                        val psm = call.argument<Int>("psm") ?: PSM_SINGLE_BLOCK
                        runAsync(result) {
                            val bitmap = decodeImage(bytes)
                            val engine = newEngine(langs, psm)
                            try {
                                val (text, confidence) = recognizeBitmap(engine, bitmap)
                                mapOf(
                                    "text" to text,
                                    "confidence" to confidence,
                                    "width" to bitmap.width,
                                    "height" to bitmap.height,
                                )
                            } finally {
                                engine.recycle()
                                bitmap.recycle()
                            }
                        }
                    }

                    "recognizePdf" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.error("bad_args", "缺少 PDF 字节（bytes）", null)
                            return@setMethodCallHandler
                        }
                        val langs = call.argument<String>("langs") ?: DEFAULT_LANGS
                        val psm = call.argument<Int>("psm") ?: PSM_SINGLE_BLOCK
                        val maxPages = call.argument<Int>("maxPages") ?: DEFAULT_MAX_PAGES
                        val targetWidth = call.argument<Int>("targetWidth") ?: PDF_RENDER_WIDTH
                        runAsync(result) { recognizePdf(bytes, langs, psm, maxPages, targetWidth) }
                    }

                    "info" -> result.success(info())

                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                Log.e(TAG, "OCR 通道处理 ${call.method} 失败", t)
                result.error("ocr_failed", t.message ?: t.toString(), null)
            }
        }
    }

    // ---------------------------------------------------------------- 图片

    private fun decodeImage(bytes: ByteArray): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw IllegalArgumentException("无法解码这张图片（格式不支持或文件损坏）")
        }
        // 超大图先降采样：4000px 以上的截图对识别没帮助，只会吃内存
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= MAX_WIDTH) sample *= 2
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        var bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
            ?: throw IllegalArgumentException("无法解码这张图片（格式不支持或文件损坏）")
        // 小图放大：Tesseract 对小于 ~20px 的字几乎认不出来
        if (bitmap.width < MIN_WIDTH) {
            val scale = minOf(4f, MIN_WIDTH.toFloat() / bitmap.width)
            val w = (bitmap.width * scale).toInt()
            val h = (bitmap.height * scale).toInt()
            val scaled = Bitmap.createScaledBitmap(bitmap, w, h, true)
            if (scaled !== bitmap) bitmap.recycle()
            bitmap = scaled
        }
        Log.i(TAG, "OCR 输入位图 ${bitmap.width}x${bitmap.height}（原图 ${bounds.outWidth}x${bounds.outHeight}，sample=$sample）")
        return bitmap
    }

    // ----------------------------------------------------------------- PDF

    private fun recognizePdf(
        bytes: ByteArray,
        langs: String,
        psm: Int,
        maxPages: Int,
        targetWidth: Int,
    ): Map<String, Any?> {
        val tmp = File.createTempFile("njtc_pdf_", ".pdf", context.cacheDir)
        try {
            FileOutputStream(tmp).use { it.write(bytes) }
            ParcelFileDescriptor.open(tmp, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
                PdfRenderer(pfd).use { renderer ->
                    val pageCount = renderer.pageCount
                    val limit = minOf(pageCount, max(1, maxPages))
                    val engine = newEngine(langs, psm)
                    val sb = StringBuilder()
                    try {
                        for (i in 0 until limit) {
                            renderer.openPage(i).use { page ->
                                val scale = targetWidth.toFloat() / page.width
                                val w = max(1, targetWidth)
                                val h = max(1, (page.height * scale).toInt())
                                val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                                // PDF 页渲染出来默认是透明底，不铺白底 OCR 会当成黑底
                                Canvas(bitmap).drawColor(Color.WHITE)
                                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                val (text, _) = recognizeBitmap(engine, bitmap)
                                bitmap.recycle()
                                if (text.isNotBlank()) sb.append(text.trim()).append("\n\n")
                            }
                        }
                    } finally {
                        engine.recycle()
                    }
                    Log.i(TAG, "PDF 识别完成：共 $pageCount 页，本次识别 $limit 页，输出 ${sb.length} 字")
                    return mapOf(
                        "text" to sb.toString().trim(),
                        "pages" to pageCount,
                        "recognizedPages" to limit,
                        "truncated" to (limit < pageCount),
                    )
                }
            }
        } finally {
            tmp.delete()
        }
    }

    // -------------------------------------------------------------- 引擎侧

    /**
     * 用同一个引擎连续识别多张位图（PDF 多页共用，省掉每页一次 init）。
     *
     * 返回 `文字 to 平均置信度`。**置信度必须在 `clear()` 之前取**：`clear()` 会把
     * 识别结果一起清掉，之后 `meanConfidence()` 恒为 0（第一版就是这么写的，
     * E2E 打出来「置信度 0%」，界面于是每次都提示「请核对识别结果」）。
     */
    private fun recognizeBitmap(engine: TessBaseAPI, bitmap: Bitmap): Pair<String, Int> {
        engine.setImage(bitmap)
        val text = engine.getUTF8Text() ?: ""
        val confidence = engine.meanConfidence()
        engine.clear()
        return text to confidence
    }

    private fun newEngine(langs: String, psm: Int): TessBaseAPI {
        val dataPath = ensureTessData()
        val actual = pickLanguages(langs)
        val engine = TessBaseAPI()
        if (!engine.init(dataPath, actual)) {
            engine.recycle()
            throw IllegalStateException(
                "OCR 引擎初始化失败：语言模型 $actual 没能加载（assets/tessdata 里缺文件？）"
            )
        }
        // 保留词间空格：课表截图里「课程名 教师 教室」靠列间距分列，丢了空格就不好还原表格
        engine.setVariable("preserve_interword_spaces", "1")
        engine.setPageSegMode(psm)
        return engine
    }

    /**
     * assets 里某个文件的**未压缩**字节数。
     *
     * `openFd()` 只认未压缩的资产，压缩过的会抛
     * `FileNotFoundException: This file can not be opened as a file descriptor; it is probably compressed`。
     * `traineddata` 已经在 `android/app/build.gradle.kts` 的 `androidResources.noCompress` 里
     * 排除了压缩（否则连 info() 都拿不到），这里再兜一层：拿不到就用流读到底数数。
     */
    private fun assetLength(path: String): Long = try {
        context.assets.openFd(path).use { it.length }
    } catch (t: Throwable) {
        Log.w(TAG, "asset $path 读不到 fd（可能是压缩过的），退回流式计数", t)
        context.assets.open(path).use { input ->
            var total = 0L
            val buf = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                total += n
            }
            total
        }
    }

    /**
     * 把 assets/tessdata 里的语言模型复制到 `filesDir/tessdata/`（Tesseract 只认这个目录结构），
     * 已经复制过且大小一致的跳过。返回 `filesDir` 的路径。
     */
    private fun ensureTessData(): String {
        val destDir = File(context.filesDir, "tessdata")
        if (!destDir.exists()) destDir.mkdirs()
        val names = context.assets.list("tessdata") ?: emptyArray()
        var copied = 0
        for (name in names) {
            if (!name.endsWith(".traineddata")) continue
            val dest = File(destDir, name)
            val assetSize = assetLength("tessdata/$name")
            if (dest.exists() && dest.length() == assetSize) continue
            context.assets.open("tessdata/$name").use { input ->
                FileOutputStream(dest).use { output -> input.copyTo(output) }
            }
            copied++
        }
        if (copied > 0) Log.i(TAG, "已复制 $copied 个语言模型到 $destDir")
        return context.filesDir.absolutePath
    }

    /** 挑了实际存在的语言：优先「中文+英文」，缺哪个就退到哪个。 */
    private fun pickLanguages(requested: String): String {
        val wanted = requested.split('+').map { it.trim() }.filter { it.isNotEmpty() }
        val destDir = File(context.filesDir, "tessdata")
        val have = wanted.filter { File(destDir, "$it.traineddata").exists() }
        val actual = if (have.isEmpty()) wanted else have
        return if (actual.isEmpty()) requested else actual.joinToString("+")
    }

    private fun info(): Map<String, Any?> {
        val destDir = File(context.filesDir, "tessdata")
        val files = (context.assets.list("tessdata") ?: emptyArray())
            .filter { it.endsWith(".traineddata") }
            .map { name ->
                name to mapOf(
                    "assetBytes" to assetLength("tessdata/$name"),
                    "installed" to File(destDir, name).exists(),
                )
            }
            .toMap()
        return mapOf(
            "channel" to CHANNEL,
            "tessdataDir" to destDir.absolutePath,
            "files" to files,
            "languages" to pickLanguages(DEFAULT_LANGS),
        )
    }

    // ---------------------------------------------------------------- 工具

    /** 后台线程干活、结果回主线程；异常统一变成 Dart 侧的 PlatformException。 */
    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        Thread {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (t: Throwable) {
                Log.e(TAG, "OCR 失败", t)
                val message = t.message ?: t.toString()
                main.post { result.error("ocr_failed", message, null) }
            }
        }.start()
    }

    companion object {
        private const val TAG = "NjtcOcr"
        const val CHANNEL = "cn.edu.njtc.njtc_schedule/ocr"

        /** 默认语言：中文简体 + 英文（楼栋号、Python、B213 这类拉丁字符）。 */
        const val DEFAULT_LANGS = "chi_sim+eng"

        /** psm 6 = 当作一整块文本（课表截图基本就是这个形态）。 */
        const val PSM_SINGLE_BLOCK = 6

        /** 一次最多识别多少页 PDF：多了太慢，用户可以先拆页。 */
        const val DEFAULT_MAX_PAGES = 8

        /** 渲染 PDF 页面时的目标宽度（像素）：1500 左右能兼顾速度与中文识别率。 */
        const val PDF_RENDER_WIDTH = 1600

        private const val MIN_WIDTH = 1000
        private const val MAX_WIDTH = 4000
    }
}
