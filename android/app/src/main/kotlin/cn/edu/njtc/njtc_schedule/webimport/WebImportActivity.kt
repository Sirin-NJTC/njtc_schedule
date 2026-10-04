package cn.edu.njtc.njtc_schedule.webimport

import android.app.Activity
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * 「网页登录导入」页 —— 应用内打开教务系统网页，用户像在浏览器里一样登录，
 * 登录完成后点顶部「读取课表」，把当前页面的课表表格交回 Flutter 解析。
 *
 * 为什么用原生 Activity 而不是 `webview_flutter`：
 * 1. 不引入新的 Flutter 插件依赖（本项目此前已因插件 symlink/compileSdk 踩过坑）；
 * 2. Cookie 天然由 WebView 自己管理，登录态可以跨次使用，不需要在 Dart 侧搬运会话；
 * 3. 抓取需要注入较长 JS 并处理 `target=_blank` 的跳转，原生侧更直接。
 *
 * 抓取结果的传递：抓到的 HTML 可能几百 KB，走 Intent extra 有
 * `TransactionTooLargeException` 风险，因此**写入 cacheDir 下的文件**，
 * 只把文件路径放进 result，由 [MainActivity] 读出来回传给 Flutter。
 */
class WebImportActivity : Activity() {

    private lateinit var webView: WebView
    private lateinit var progress: ProgressBar
    private lateinit var urlField: EditText
    private lateinit var statusText: TextView
    private lateinit var btnExtract: Button

    private var extracting = false
    private var looksLikeTimetable = false
    private var desktopMode = true

    /** 每次抓取自增；回调里拿它判断这次抓取是否已经被作废（页面可能在等待期间跳走）。 */
    private var extractToken = 0

    /** 当前卡在哪一轮（sync / query / net），看门狗报警时写进提示里。 */
    private var extractPhase = ""
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * 本次用户发起的导航里，是否已经因为「域名解析不了」自动回退过一次。
     *
     * 每次用户主动跳转（菜单 / 地址栏 / 刷新）都重置为 false，
     * 避免两条入口互相回退成死循环。
     */
    private var fallbackTried = false

    /**
     * 这个地址是不是**融合门户**（而不是同一台主机上的 CAS 登录页 / 教务接口页）。
     *
     * 必须主机名相等 + 路径带门户特征，不能用子串：`tpass.njtc.edu.cn` 以
     * `pass.njtc.edu.cn` 结尾，子串判断会把 CAS 登录页误判成门户
     * （1.1.4 真机上因此对每次 CAS 网络错误都做了一次无意义回退）。
     */
    private fun isPortalUrl(u: String?): Boolean {
        if (u.isNullOrBlank()) return false
        val uri = try {
            android.net.Uri.parse(u)
        } catch (e: Exception) {
            return false
        }
        val host = uri.host ?: return false
        if (!host.equals(PORTAL_HOST, ignoreCase = true)) return false
        val path = uri.path ?: ""
        return path.contains("portal_v4") || path.contains("center_portal_njtc")
    }

    /**
     * WebView 的原始 UA（手机版），在 [onCreate] 里抓一次。
     *
     * `settings.userAgentString` 是**会被我们自己改写的**，所以不能拿它当
     * 「默认值」来还原手机版 —— 从电脑版切回手机版时必须用这里存的原始值。
     */
    private var defaultUa: String = ""

    /**
     * 探测到课表页后不等用户点按钮、直接抓取并返回。
     *
     * 只有自动化测试会传 `auto_read=true`（正常入口永远是用户手动点「读取课表」）。
     */
    private var autoRead = false
    private var autoReadDone = false

    /** 自动读取前已经重探过几次（页面脚本异步渲染表格时需要重试）。 */
    private var autoReadAttempts = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        Log.i(TAG, "onCreate autoRead=${intent.getBooleanExtra(EXTRA_AUTO_READ, false)}")
        val prefs = prefs()
        desktopMode = prefs.getBoolean(KEY_DESKTOP, true)
        autoRead = intent.getBooleanExtra(EXTRA_AUTO_READ, false)
        val startUrl = intent.getStringExtra(EXTRA_URL)?.takeIf { it.isNotBlank() }
            ?: prefs.getString(KEY_LAST_URL, null)?.takeIf { it.isNotBlank() }
            ?: DEFAULT_URL

        setContentView(buildLayout())

        val settings = webView.settings
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.databaseEnabled = true
        settings.loadWithOverviewMode = true
        settings.useWideViewPort = true
        settings.builtInZoomControls = true
        settings.displayZoomControls = false
        settings.setSupportZoom(true)
        settings.allowFileAccess = true
        settings.allowContentAccess = true
        settings.cacheMode = WebSettings.LOAD_DEFAULT
        settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
        settings.javaScriptCanOpenWindowsAutomatically = true
        settings.setSupportMultipleWindows(true)
        // 先记下系统默认 UA，再按「电脑版/手机版」改写（手机版要去掉 "; wv)" 标记）
        defaultUa = settings.userAgentString ?: ""
        applyUserAgent()

        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

        // 正方/智慧内师有些链接是 target=_blank，这里直接在同一个 WebView 里打开
        webView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                progress.progress = newProgress
                progress.visibility = if (newProgress in 1..99) View.VISIBLE else View.GONE
            }

            override fun onCreateWindow(
                view: WebView?,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: android.os.Message?,
            ): Boolean {
                // 没有多窗口支持时，new-window 请求会被丢弃；这里改为原地加载
                val transport = resultMsg?.obj as? WebView.WebViewTransport ?: return false
                val holder = WebView(this@WebImportActivity)
                holder.webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(
                        v: WebView?,
                        request: WebResourceRequest?,
                    ): Boolean {
                        val u = request?.url?.toString()
                        if (!u.isNullOrBlank()) {
                            webView.loadUrl(u)
                            urlField.setText(u)
                        }
                        holder.destroy()
                        return true
                    }
                }
                transport.webView = holder
                resultMsg.sendToTarget()
                return true
            }
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?,
            ): Boolean {
                val uri = request?.url ?: return false
                val scheme = uri.scheme?.lowercase()
                if (scheme == "http" || scheme == "https") return false
                // tel: / mailto: / market: 等交给系统处理
                return try {
                    startActivity(Intent(Intent.ACTION_VIEW, uri))
                    true
                } catch (t: Throwable) {
                    true
                }
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: android.webkit.WebResourceError?,
            ) {
                Log.w(TAG, "onReceivedError ${request?.url} ${error?.description}")
                if (request?.isForMainFrame != true) return
                val failed = request.url?.toString().orEmpty()
                val code = error?.errorCode ?: 0
                val netLike = code == WebViewClient.ERROR_HOST_LOOKUP ||
                    code == WebViewClient.ERROR_CONNECT ||
                    code == WebViewClient.ERROR_IO ||
                    code == WebViewClient.ERROR_TIMEOUT ||
                    code == WebViewClient.ERROR_UNKNOWN
                // 兜底：融合门户那条路打不开时（域名解析不了 / 连接被拒），
                // 自动切到公网可达的 CAS 深链，别把用户丢在一个打不开的白页上。
                //
                // 判定必须**比主机名 + 路径**，不能写成 `failed.contains(PORTAL_HOST)`：
                // `"tpass.njtc.edu.cn"` 正好以 `"pass.njtc.edu.cn"` 结尾，用子串判断
                // 会把 CAS 登录页也认成门户，于是 CAS 侧任何一次网络错误
                // （回退时浏览器报的 ERR_CACHE_MISS 很常见）都会触发一次原地重载
                // 和一条误导性提示。1.1.4 真机上实测踩到过。
                if (netLike && !fallbackTried && isPortalUrl(failed) && failed != JWGLXT_URL) {
                    fallbackTried = true
                    statusText.text = "门户打不开，已切到备用入口…"
                    toast("打不开融合门户，已自动切到课表查询页")
                    Log.i(TAG, "自动回退 ${failed} -> $JWGLXT_URL")
                    urlField.setText(JWGLXT_URL)
                    webView.loadUrl(JWGLXT_URL)
                } else {
                    statusText.text = "打不开：${error?.description ?: "网络错误"}"
                }
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                Log.i(TAG, "onPageStarted $url")
                urlField.setText(url ?: "")
                statusText.text = "正在加载…"
                looksLikeTimetable = false
                btnExtract.text = "读取课表"
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                urlField.setText(url ?: webView.url ?: "")
                val title = view?.title?.takeIf { it.isNotBlank() } ?: "教务系统"
                statusText.text = title
                Log.i(TAG, "onPageFinished url=$url title=$title")
                // 教务系统老页面常写死 user-scalable=no，这里放开缩放
                webView.evaluateJavascript(VIEWPORT_FIX_JS, null)
                probePage()
            }
        }

        webView.loadUrl(startUrl)
        urlField.setText(startUrl)
    }

    // ------------------------------------------------------------ UI 构建

    private fun buildLayout(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.WHITE)
        }

        // 第一行：返回 | 标题 | 读取课表
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(BRAND)
            setPadding(dp(4), dp(6), dp(8), dp(6))
        }
        val btnBack = Button(this).apply {
            text = "‹"
            textSize = 22f
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.TRANSPARENT)
            minWidth = dp(40)
            minHeight = dp(40)
            setPadding(0, 0, 0, 0)
            setOnClickListener { goBack() }
        }
        val titleText = TextView(this).apply {
            text = "登录教务系统"
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        btnExtract = Button(this).apply {
            text = "读取课表"
            textSize = 13f
            setTextColor(Color.WHITE)
            setBackgroundColor(EXTRACT_BG)
            setPadding(dp(12), dp(4), dp(12), dp(4))
            minWidth = 0
            minHeight = dp(36)
            setOnClickListener { extract() }
        }
        bar.addView(btnBack, LinearLayout.LayoutParams(dp(40), ViewGroup.LayoutParams.WRAP_CONTENT))
        bar.addView(
            titleText,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                .apply { marginStart = dp(4) },
        )
        bar.addView(btnExtract, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(bar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        // 第二行：地址栏 + 前往 + 菜单
        val urlRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Color.parseColor("#F4F5FB"))
            setPadding(dp(6), dp(4), dp(6), dp(4))
        }
        urlField = EditText(this).apply {
            hint = "教务系统网址"
            textSize = 12f
            maxLines = 1
            setSingleLine(true)
            setBackgroundColor(Color.TRANSPARENT)
            imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_GO
            setOnEditorActionListener { _, actionId, _ ->
                if (actionId == android.view.inputmethod.EditorInfo.IME_ACTION_GO) {
                    loadFromField()
                    true
                } else {
                    false
                }
            }
        }
        val btnGo = Button(this).apply {
            text = "前往"
            textSize = 12f
            minWidth = 0
            minHeight = dp(32)
            setPadding(dp(10), 0, dp(10), 0)
            setOnClickListener { loadFromField() }
        }
        val btnMenu = Button(this).apply {
            text = "⋮"
            textSize = 16f
            minWidth = 0
            minHeight = dp(32)
            setPadding(dp(10), 0, dp(10), 0)
            setOnClickListener { showMenu(it) }
        }
        urlRow.addView(
            urlField,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )
        urlRow.addView(btnGo)
        urlRow.addView(btnMenu)
        root.addView(urlRow, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        // 第三行：页面标题 / 状态
        statusText = TextView(this).apply {
            text = "登录后点进「课表查询 / 我的课表」，看到课表再点右上角「读取课表」"
            textSize = 11.5f
            setTextColor(Color.parseColor("#6B7280"))
            setBackgroundColor(Color.parseColor("#F4F5FB"))
            setPadding(dp(10), dp(2), dp(10), dp(6))
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        root.addView(statusText, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            visibility = View.GONE
        }
        root.addView(progress, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(3)))

        webView = WebView(this)
        root.addView(webView, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        return root
    }

    private fun showMenu(anchor: View) {
        val popup = PopupMenu(this, anchor)
        popup.menu.add(0, 1, 0, if (desktopMode) "切换为手机版" else "切换为电脑版")
        popup.menu.add(0, 2, 1, "刷新页面")
        popup.menu.add(0, 3, 2, "打开课表查询页")
        popup.menu.add(0, 5, 3, "融合门户首页")
        popup.menu.add(0, 4, 4, "清除登录状态")
        popup.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                1 -> {
                    desktopMode = !desktopMode
                    prefs().edit().putBoolean(KEY_DESKTOP, desktopMode).apply()
                    applyUserAgent()
                    webView.reload()
                }
                2 -> {
                    fallbackTried = false
                    webView.reload()
                }
                3 -> {
                    fallbackTried = false
                    urlField.setText(JWGLXT_URL)
                    webView.loadUrl(JWGLXT_URL)
                }
                4 -> {
                    CookieManager.getInstance().removeAllCookies(null)
                    CookieManager.getInstance().flush()
                    toast("已清除登录状态")
                    webView.reload()
                }
                5 -> {
                    fallbackTried = false
                    urlField.setText(PORTAL_URL)
                    webView.loadUrl(PORTAL_URL)
                }
            }
            true
        }
        popup.show()
    }

    /**
     * 切换 UA。
     *
     * 手机版 UA 里会带 `; wv)`（WebView 标记），部分教务系统见到它就降级返回
     * 阉割页面，所以这里把它去掉；电脑版直接用内置的桌面 UA 常量。
     */
    private fun applyUserAgent() {
        val mobileUa = defaultUa.replace("; wv)", "").trim()
        webView.settings.userAgentString = if (desktopMode) {
            DESKTOP_UA
        } else {
            mobileUa.ifBlank { defaultUa }
        }
    }

    private fun loadFromField() {
        val url = urlField.text?.toString()?.trim().orEmpty()
        if (url.isEmpty()) return
        val normalized = if (url.startsWith("http://") || url.startsWith("https://")) {
            url
        } else {
            "https://$url"
        }
        fallbackTried = false
        webView.loadUrl(normalized)
    }

    private fun goBack() {
        Log.i(TAG, "goBack canGoBack=${webView.canGoBack()} isFinishing=$isFinishing")
        if (webView.canGoBack()) {
            webView.goBack()
        } else {
            setResult(RESULT_CANCELED)
            finish()
        }
    }

    @Deprecated("WebView 内部的返回优先于 Activity 退出")
    override fun onBackPressed() = goBack()

    // ------------------------------------------------------------ 抓取

    /**
     * `evaluateJavascript` 的回调值是结果的 **JSON 表示**：JS 里 `return 'true'`（字符串）
     * 回调拿到的是带引号的 `"true"`，只有布尔 `true` 才是裸的。两种都认。
     */
    private fun jsIsTrue(value: String?): Boolean {
        val v = value?.trim() ?: return false
        return v == "true" || v.trim('"') == "true"
    }

    /** 轻量探测当前页是否像课表页，用来把「读取课表」按钮变得显眼。 */
    private fun probePage() {
        if (isFinishing || isDestroyed) return
        webView.evaluateJavascript(PROBE_JS) { value ->
            val hit = jsIsTrue(value)
            Log.i(
                TAG,
                "probe raw=$value hit=$hit url=${webView.url} autoRead=$autoRead " +
                    "done=$autoReadDone attempts=$autoReadAttempts",
            )
            looksLikeTimetable = hit
            btnExtract.text = if (hit) "读取课表 ✓" else "读取课表"
            btnExtract.setBackgroundColor(if (hit) EXTRACT_BG_ACTIVE else EXTRACT_BG)
            if (hit) {
                val url = webView.url
                if (!url.isNullOrBlank()) {
                    prefs().edit().putString(KEY_LAST_URL, url).apply()
                }
            } else {
                // 探不到课表时把「这页有什么」打进日志。真机截屏是黑的，页面长什么样
                // 只能靠这一行推断；抓到课表时就不打，避免刷屏。
                webView.evaluateJavascript(DIAG_JS) { diag ->
                    Log.i(TAG, "page diag=$diag url=${webView.url}")
                }
            }
            if (!autoRead || autoReadDone) return@evaluateJavascript
            // 课表表格可能是页面脚本异步渲染出来的：一次没探到就再给几次机会
            if (!hit && autoReadAttempts < AUTO_READ_MAX_ATTEMPTS) {
                autoReadAttempts++
                webView.postDelayed({
                    if (!isFinishing && !isDestroyed) probePage()
                }, AUTO_READ_RETRY_MILLIS)
                return@evaluateJavascript
            }
            autoReadDone = true
            // 表格里的脚本可能还在渲染，稍等一下再抓，避免拿到半截 HTML
            webView.postDelayed({
                Log.i(TAG, "autoRead timer -> extract (finishing=$isFinishing destroyed=$isDestroyed)")
                if (!isFinishing && !isDestroyed) extract()
            }, 900)
        }
    }

    /**
     * 抓取分三轮，任何一轮拿到东西就收工：
     *
     * - **pass 0（sync）**：页面里现成的内联 JSON / 整页 JSON / iframe / DOM 表格。
     * - **pass 1（query）**：真机实测正方课表页刚打开时表格是**空的**，数据要等页面自己发完
     *   AJAX 才有。所以先替用户点一下「查询」，等 1.8 秒再抓一次 DOM。
     * - **pass 2（net）**：两轮 DOM 都空，就用 Kotlin 侧 HTTP 直接 POST 数据接口
     *   （`..._cxXsKb.html`，返回 `{"kbList":[…]}`），Cookie 从 [CookieManager] 取。
     *
     * 为什么不在 JS 里发这个请求：1.1.5 版本用的是**同步 XHR**，真机上把 WebView 的 JS 线程
     * 卡死，`evaluateJavascript` 的回调**永远不返回** —— 用户看到的就是「点了没反应/读取不到」。
     * 同步 XHR 不能设超时也不能中断，所以网络这一步必须挪出 JS。
     *
     * 外加一个看门狗：无论卡在哪一轮，[EXTRACT_TIMEOUT_MS] 之后一定把按钮恢复并给出原因。
     */
    private fun extract() {
        if (extracting) return
        extracting = true
        val token = ++extractToken
        extractPhase = "sync"
        Log.i(TAG, "extract start url=${webView.url}")
        btnExtract.isEnabled = false
        btnExtract.text = "读取中…"
        mainHandler.postDelayed({
            if (token == extractToken && extracting) {
                Log.w(TAG, "extract watchdog fired phase=$extractPhase")
                settleFail("读取超时（卡在 $extractPhase 阶段），请确认页面上已经显示出课表表格")
            }
        }, EXTRACT_TIMEOUT_MS)
        runExtractPass(token, 0)
    }

    private fun runExtractPass(token: Int, pass: Int) {
        extractPhase = if (pass == 0) "sync" else "query"
        webView.evaluateJavascript(EXTRACT_JS) { value ->
            if (token != extractToken) return@evaluateJavascript
            Log.i(TAG, "extract pass=$pass value len=${value?.length ?: -1}")
            val payload = unwrap(value)
            if (payload == null) {
                Log.w(TAG, "unwrap failed, raw=${value?.take(200)}")
                settleFail("读取失败，请等页面加载完成后再试")
                return@evaluateJavascript
            }
            Log.i(TAG, "extract diag pass=$pass ${payload.optJSONObject("diag")}")
            if (hasRows(payload)) {
                // DOM 里有课，但正方页面经常**只画了一部分**（默认只渲染查询结果的第一屏，
                // 或者只画当前周）—— 实测固件页只有 1 个 `.kbcontent`，接口却给 4 行整学期。
                // 所以只要算得出数据接口就先走接口（`canQueryInterface`），
                // 接口失败再回落到这份已经抠到的 DOM（`postForKbList` 的 `fallback`）。
                // ⚠️ 别再改回「有 DOM 就直接 settleOk」：那样接口路径变成死代码，
                // 页面只画一屏时用户就只拿到一屏的课（1.1.6/1.1.7 的真 bug）。
                if (pass == 0 && canQueryInterface(payload)) {
                    startNetPhase(token, payload, fallback = payload)
                    return@evaluateJavascript
                }
                settleOk(payload)
                return@evaluateJavascript
            }
            if (pass == 0) {
                webView.evaluateJavascript(TRIGGER_QUERY_JS) { trig ->
                    if (token != extractToken) return@evaluateJavascript
                    Log.i(TAG, "trigger query -> $trig")
                    mainHandler.postDelayed({
                        if (token == extractToken) runExtractPass(token, 1)
                    }, QUERY_SETTLE_MS)
                }
                return@evaluateJavascript
            }
            startNetPhase(token, payload, fallback = null)
        }
    }

    /** 页面里到底有没有「课」。正方 jwglxt 的课表是 div 网格，所以主要看 .kbcontent 有没有内容。 */
    private fun hasRows(p: JSONObject): Boolean {
        val jr = p.optJSONArray("jsonRows")
        if (jr != null && jr.length() > 0) return true
        if (p.optInt("kbFilled", 0) > 0) return true
        val html = p.optString("tableHtml")
        if (html.length > 800 && (html.contains("kbcontent") || html.contains("kbtable"))) return true
        return p.optString("text").length > 1500
    }

    /** 页面上算得出「数据接口地址 + 学年 + 学期」吗？三个都齐才值得发 POST。 */
    private fun canQueryInterface(p: JSONObject): Boolean {
        val eps = p.optJSONArray("endpoints") ?: return false
        if (eps.length() == 0) return false
        return p.optString("xnm").isNotBlank() && p.optString("xqm").isNotBlank()
    }

    /**
     * 进入 pass 2（Kotlin 侧 POST 数据接口）。
     *
     * [fallback] 是「DOM 里已经抠到课」的那份载荷：接口全军覆没时直接用它，
     * 而不是给用户报错 —— 有课表总比没有好。
     */
    private fun startNetPhase(token: Int, payload: JSONObject, fallback: JSONObject?) {
        val eps = payload.optJSONArray("endpoints")
        val list = ArrayList<String>()
        if (eps != null) for (i in 0 until eps.length()) list.add(eps.optString(i))
        val xnm = payload.optString("xnm")
        val xqm = payload.optString("xqm")
        Log.i(TAG, "net phase endpoints=${list.size} xnm=$xnm xqm=$xqm fallback=${fallback != null}")
        if (list.isEmpty() || xnm.isBlank() || xqm.isBlank()) {
            if (fallback != null && hasRows(fallback)) {
                Log.i(TAG, "接口地址/学年学期不全，直接用页面 DOM")
                settleOk(fallback)
            } else {
                settleFail(describeEmpty(payload) + "（学年/学期或接口地址没读到）")
            }
            return
        }
        extractPhase = "net"
        postForKbList(token, list, xnm, xqm, payload, fallback)
    }

    private fun settleOk(payload: JSONObject) {
        extracting = false
        extractPhase = ""
        btnExtract.isEnabled = true
        btnExtract.text = if (looksLikeTimetable) "读取课表 ✓" else "读取课表"
        finishWithPayload(payload)
    }

    private fun settleFail(msg: String) {
        extracting = false
        extractPhase = ""
        btnExtract.isEnabled = true
        btnExtract.text = if (looksLikeTimetable) "读取课表 ✓" else "读取课表"
        Log.w(TAG, "extract failed: $msg")
        toast(msg)
    }

    private fun describeEmpty(p: JSONObject): String {
        val d = p.optJSONObject("diag")
        return "没读到课表（页面「" + p.optString("title") + "」·表格 " + p.optInt("tableCount") +
            " 个·课程格 " + p.optInt("kbFilled") + " 个·正文 " + (d?.optInt("bodyLen") ?: 0) + " 字）"
    }

    /**
     * pass 2：Kotlin 侧 POST 正方数据接口。
     *
     * 端点清单由页面的 JS 算好（`jsonEndpoints()`，含反向代理部署的反推规则），
     * 这里只负责发请求 —— 能设超时、能带 Referer、能取 WebView 的 Cookie。
     *
     * 只试最像数据接口的 [MAX_NET_TRIES] 条：`jsonEndpoints()` 会把页面地址也当候选塞进来，
     * POST 到页面地址只会拿回 HTML；每条最长 [NET_TIMEOUT_MS]，试太多会顶到 20 秒看门狗。
     * 全失败时回落到 [fallback]（DOM 里抠到的课），不要直接报错。
     */
    private fun postForKbList(
        token: Int,
        endpoints: List<String>,
        xnm: String,
        xqm: String,
        base: JSONObject,
        fallback: JSONObject?
    ) {
        val referer = webView.url ?: ""
        val cookies = try {
            CookieManager.getInstance().getCookie(referer)
        } catch (e: Exception) {
            null
        }
        val (dataish, others) = endpoints.partition { DATA_ENDPOINT_RE.containsMatchIn(it) }
        val tries = (dataish + others).take(MAX_NET_TRIES)
        Thread {
            var lastErr = "未尝试"
            for (ep in tries) {
                if (token != extractToken) return@Thread
                val url = ep + "?doType=query&gnmkdm=N2151"
                val body = "xnm=" + enc(xnm) + "&xqm=" + enc(xqm) +
                    "&kzlx=ck&queryModel.showCount=2000&queryModel.currentPage=1" +
                    "&queryModel.sortName=&queryModel.sortOrder=asc"
                try {
                    val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                        requestMethod = "POST"
                        connectTimeout = NET_TIMEOUT_MS
                        readTimeout = NET_TIMEOUT_MS
                        doOutput = true
                        instanceFollowRedirects = true
                        setRequestProperty(
                            "Content-Type", "application/x-www-form-urlencoded;charset=UTF-8")
                        setRequestProperty("X-Requested-With", "XMLHttpRequest")
                        setRequestProperty("Accept", "application/json, text/javascript, */*; q=0.01")
                        setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9")
                        setRequestProperty(
                            "User-Agent",
                            defaultUa.ifBlank {
                                "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 " +
                                    "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
                            }
                        )
                        if (referer.isNotBlank()) setRequestProperty("Referer", referer)
                        if (!cookies.isNullOrBlank()) setRequestProperty("Cookie", cookies)
                    }
                    conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
                    val code = conn.responseCode
                    val bytes = (if (code in 200..299) conn.inputStream else conn.errorStream)
                        ?.use { it.readBytes() } ?: ByteArray(0)
                    conn.disconnect()
                    val raw = String(bytes, Charsets.UTF_8)
                    Log.i(TAG, "net $ep -> HTTP $code len=${raw.length}")
                    val rows = extractKbList(raw)
                    if (rows != null && rows.length() > 0) {
                        val out = JSONObject(base.toString())
                        out.put("jsonRows", rows)
                        out.put("xnm", xnm)
                        out.put("xqm", xqm)
                        out.put("jsonEndpoint", ep)
                        runOnUiThread { if (token == extractToken) settleOk(out) }
                        return@Thread
                    }
                    lastErr = "HTTP $code 里没有 kbList"
                } catch (e: Exception) {
                    lastErr = e.javaClass.simpleName + ": " + e.message
                    Log.w(TAG, "net $ep 失败：$lastErr")
                }
            }
            if (fallback != null && hasRows(fallback)) {
                Log.i(TAG, "接口没返回课表（$lastErr），回落到页面 DOM")
                runOnUiThread { if (token == extractToken) settleOk(fallback) }
            } else {
                val msg = describeEmpty(base) + "；接口也没返回数据（$lastErr）"
                runOnUiThread { if (token == extractToken) settleFail(msg) }
            }
        }.start()
    }

    /** 从数据接口的响应里取课表行数组；不是 JSON 或没有 kbList 就返回 null。 */
    private fun extractKbList(raw: String): JSONArray? {
        if (raw.indexOf("kbList") < 0) return null
        return try {
            val obj = JSONObject(raw)
            obj.optJSONArray("kbList")
                ?: obj.optJSONArray("items")
                ?: obj.optJSONArray("rows")
                ?: obj.optJSONArray("data")
        } catch (e: Exception) {
            null
        }
    }

    private fun enc(s: String): String = try {
        java.net.URLEncoder.encode(s, "UTF-8")
    } catch (e: Exception) {
        s
    }

    /** `evaluateJavascript` 会把返回值再包一层 JSON，这里解回字符串再解析。 */
    private fun unwrap(value: String?): JSONObject? {
        if (value.isNullOrBlank() || value == "null") return null
        return try {
            val first = JSONTokener(value).nextValue()
            val text = if (first is String) first else first?.toString()
            if (text.isNullOrBlank()) null else JSONObject(text)
        } catch (t: Throwable) {
            null
        }
    }

    private fun finishWithPayload(payload: JSONObject) {
        try {
            Log.i(TAG, "finishWithPayload len=${payload.toString().length}")
            val file = File(cacheDir, "webimport_payload.json")
            file.writeText(payload.toString())
            val url = payload.optString("url")
            if (url.isNotBlank()) prefs().edit().putString(KEY_LAST_URL, url).apply()
            setResult(
                RESULT_OK,
                Intent().putExtra(EXTRA_PAYLOAD_PATH, file.absolutePath),
            )
        } catch (t: Throwable) {
            Log.e(TAG, "write payload failed", t)
            setResult(
                RESULT_CANCELED,
                Intent().putExtra(EXTRA_ERROR, "写入抓取结果失败：${t.message}"),
            )
        }
        finish()
    }

    private fun prefs(): SharedPreferences = getSharedPreferences(PREFS, MODE_PRIVATE)

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun toast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy isFinishing=$isFinishing isChangingConfigurations=$isChangingConfigurations")
        try {
            webView.stopLoading()
            // 必须先把 WebView 从视图树里摘下来再 destroy。
            // 真机日志（vivo 10AE1C1NP80011G，2026-10-04 12:26:10）里出现过：
            //   cr_AwContents: WebView.destroy() called while WebView is still attached to window.
            //   chromium: [ERROR:aw_browser_terminator.cc(156)] Renderer process (8785) crash detected (code -1).
            // 即"还挂在窗口上就 destroy"会让 chromium 渲染进程以 code -1 崩掉。
            // 对本应用不致命（只崩渲染进程、主进程不受影响），但会刷错误日志，部分 ROM 还会连带回收页面。
            (webView.parent as? ViewGroup)?.removeView(webView)
            webView.destroy()
        } catch (_: Throwable) {
        }
        super.onDestroy()
    }

    companion object {
        private const val TAG = "NjtcWebImport"

        const val EXTRA_URL = "url"
        const val EXTRA_PAYLOAD_PATH = "payload_path"
        const val EXTRA_ERROR = "error"

        /** 仅供自动化测试：探测到课表页后自动抓取，不等待用户点击。 */
        const val EXTRA_AUTO_READ = "auto_read"

        const val PREFS = "njtc_webimport"

        /**
         * 上次停留的地址。
         *
         * 键名带 `_portal` 后缀是**故意**的：1.1.2 及以前默认入口是那条 CAS 深链，
         * 老用户机器上已经存了它的 `last_url`；如果沿用同名键，改默认入口后
         * 他们仍会被 resume 回老地址、根本看不到新版入口。改键名 = 老值自然失效。
         */
        const val KEY_LAST_URL = "last_url_portal"
        const val KEY_DESKTOP = "desktop_mode"

        /** 自动读取前最多重探几次（课表表格可能是页面脚本异步渲染出来的）。 */
        private const val AUTO_READ_MAX_ATTEMPTS = 4

        /** 两次重探之间的间隔（毫秒）。 */
        private const val AUTO_READ_RETRY_MILLIS = 1200L

        /** 点完页面上的「查询」后，等页面自己的 AJAX 把表格渲染出来（毫秒）。 */
        private const val QUERY_SETTLE_MS = 1800L

        /** 整个抓取过程的看门狗：超过这个时间无论如何都收摊，别让按钮一直转。 */
        private const val EXTRACT_TIMEOUT_MS = 20000L

        /** Kotlin 侧 POST 数据接口的连接/读取超时（毫秒）。 */
        private const val NET_TIMEOUT_MS = 8000

        /**
         * 接口最多试几条。
         *
         * `jsonEndpoints()` 会把「页面地址」也算成候选（兜底用），但 POST 到页面地址只会
         * 拿回 HTML。每条最长 [NET_TIMEOUT_MS]，试满 2 条最坏 16 秒，压在
         * [EXTRACT_TIMEOUT_MS] 看门狗（20 秒）之内。
         */
        private const val MAX_NET_TRIES = 2

        /** 「像数据接口」的判据：正方课表接口是 `xskbcx_cxXsKb.html` / `xskbcx_cxXsgrkb.html`。 */
        private val DATA_ENDPOINT_RE = Regex("cxXsKb|cxXsgrkb", RegexOption.IGNORE_CASE)

        /**
         * 融合门户（**公网可达**）。
         *
         * 用户给的链接是 `pass.njtc.edu.cn/frontend/center_portal_njtc/home/index.html`，
         * 但 `pass.njtc.edu.cn` **只在校园网 DNS 里有记录**：真机 WebView 报
         * `net::ERR_NAME_NOT_RESOLVED`，开发机 `Resolve-DnsName` 也是空，
         * 用户能在自己电脑上打开只是因为那台机器在校园网内。
         *
         * 同一个门户在公网主机 `tpass.njtc.edu.cn` 上也能开到（实测 HTTP 200，176 字节的
         * meta refresh 跳到 `/app.php/portal_v4`），`/app.php/portal_v4` 会走统一身份认证
         * （OAuth authorize），登录后回到门户首页。所以默认入口取这个：用户登录后
         * **自己在门户里点进「课表查询」**，看到课表再点右上角「读取课表」。
         */
        const val PORTAL_URL =
            "https://tpass.njtc.edu.cn/app.php/portal_v4"

        /** 校园网内的门户直连地址（校外 DNS 解析不了，仅作记录与备用）。 */
        const val PORTAL_CAMPUS_URL =
            "https://pass.njtc.edu.cn/frontend/center_portal_njtc/home/index.html"

        /** 融合门户主机：用于识别「门户这条路打不开」并自动回退到 CAS 深链。 */
        const val PORTAL_HOST = "tpass.njtc.edu.cn"

        /**
         * CAS 深链入口。
         *
         * 链路：tpass CAS 登录 → proxy.njtc.edu.cn/zytec_proxy/cas_login →
         * jxglpt-njtc-edu-cn-s.proxy.njtc.edu.cn/sso/driotlogin →
         * `kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151`（正方 jwglxt 学生课表页）。
         * CAS 正常时它最省事（已登录的话会直接跳到课表页），且域名公网可解析。
         * 右上角菜单里另有一个「打开课表查询页」，随时可以手动回到这里。
         */
        const val JWGLXT_URL =
            "https://tpass.njtc.edu.cn/auth/cas/login?service=" +
                "https%3A%2F%2Fproxy.njtc.edu.cn%2Fzytec_proxy%2Fcas_login%3Fredirect_uri%3D" +
                "https%253A%252F%252Fjxglpt-njtc-edu-cn-s.proxy.njtc.edu.cn%252Fsso%252Fdriotlogin%253Furl%253D" +
                "kbcx%25252Fxskbcx_cxXskbcxIndex.html%25253Fgnmkdm%25253DN2151"

        /**
         * 默认进入的地址：**融合门户**（用户要求的路径：自己点进课表界面再导入）。
         *
         * `tpass.njtc.edu.cn` 解析到 210.41.176.114，手机与开发机都实测可连
         * （HTTP 200、标题「统一身份认证中心」），所以门户入口在校外也能打开。
         * 万一门户这条路打不开，[isPortalUrl] + `fallbackTried` 会自动切到
         * [JWGLXT_URL]（CAS 深链，直达课表查询页）。
         *
         * 注意：必须在 [PORTAL_URL] **之后**声明 —— companion object 里的
         * `const val` 按声明顺序初始化，前置引用会报
         * `Variable 'PORTAL_URL' must be initialized.`（1.1.4 构建时踩过同类问题）。
         */
        const val DEFAULT_URL = PORTAL_URL

        /** 正方 jwglxt 学生课表页的路径特征，用于识别「当前就在课表查询页」。 */
        const val TIMETABLE_PATH_HINT = "xskbcx_cxXskbcxIndex"

        private const val DESKTOP_UA =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

        private val BRAND = Color.parseColor("#5B6BF0")
        private val EXTRACT_BG = Color.parseColor("#3F4CC7")
        private val EXTRACT_BG_ACTIVE = Color.parseColor("#12B76A")

        /**
         * 解锁页面缩放的补丁。
         *
         * 教务系统老页面普遍带 `user-scalable=no, maximum-scale=1`，导致课表
         * 又小又挤、双指放大失效；这里把 viewport 改写成允许放大。
         * 每次 `onPageFinished` 注入一次即可（页面自己改回去的概率极低）。
         */
        private val VIEWPORT_FIX_JS = """
            (function () {
              try {
                var m = document.querySelector('meta[name="viewport"]');
                if (!m) {
                  m = document.createElement('meta');
                  m.setAttribute('name', 'viewport');
                  (document.head || document.documentElement).appendChild(m);
                }
                m.setAttribute('content', 'width=device-width, initial-scale=1, maximum-scale=5, user-scalable=yes');
              } catch (e) {}
            })()
        """.trimIndent()

        /**
         * 探测当前页是否像课表页。返回 `"true"` / `"false"`。
         * 注意：字符串里不能出现 `$`，否则 Kotlin 会当成模板插值。
         *
         * 选择器与「全局变量也算数」这两条是**借**参考实现 CourseSchedule 的
         * `AcademicCaptureScript`：正方系课表并不只有 `.kbcontent` 一种长相——
         * 老版是 `#Table1` / `#table1`，新版 jwglxt 是 `#kbgrid_table` /
         * `#sycjlrtabGrid`，而且常把整份课表内联成 `veInitDefaultJson` 之类的
         * JS 全局变量（此时 DOM 里根本没有表格）。少认一种就会误判成「没有课表」。
         */
        private val PROBE_JS = """
            (function () {
              try {
                if (document.querySelector(
                    '#kbtable, .kbcontent, #Table1, #kbgrid_table, #table1, #sycjlrtabGrid')) {
                  return 'true';
                }
                var gs = ['veInitDefaultJson', 'kbxx', '__INITIAL_STATE__', 'dateList'];
                for (var g = 0; g < gs.length; g++) {
                  var gv = null;
                  try { gv = window[gs[g]]; } catch (e) { gv = null; }
                  if (!gv) { continue; }
                  var s = '';
                  try { s = typeof gv === 'string' ? gv : JSON.stringify(gv); } catch (e) { s = ''; }
                  // 全局变量里出现课表字段名，才算真的内联了课表
                  if (/kcmc|kcm|kbList|xqj|skxq/.test(s)) { return 'true'; }
                }
                // 注意：`innerText` 对**被 CSS 隐藏**的元素返回空串，正方页面经常把课表
                // 放在隐藏容器里（切页签的 tab），只读 innerText 会以为「这页没有课表」。
                // 所以一律 `innerText || textContent` 兜底。
                var body = document.body
                  ? (document.body.innerText || document.body.textContent || '') : '';

                if (/星期[一二三四五六日天]/.test(body) && /[0-9]+\s*[节课]/.test(body)) {
                  return 'true';
                }
                var bt = body.trim();
                if (bt.length > 3 && (bt.charAt(0) === '[' || bt.charAt(0) === '{') &&
                    /kcmc|kcm|kbList/.test(bt)) {
                  return 'true';
                }
                var fr = document.getElementsByTagName('iframe');
                for (var i = 0; i < fr.length; i++) {
                  try {
                    var d = fr[i].contentDocument;
                    if (d && d.body &&
                        /星期[一二三四五六日天]/.test(
                          d.body.innerText || d.body.textContent || '')) {

                      return 'true';
                    }
                  } catch (e) {}
                }
              } catch (e) {}
              return 'false';
            })()
        """.trimIndent()

        /**
         * 页面「指纹」：把「这页到底有什么」一次性打回日志。
         *
         * 真机上 WebView 内容**截屏是全黑的**（vivo ROM 行为），页面长什么样只能靠
         * 日志推断。参考实现 CourseSchedule 的 `AcademicImportDiagnostics` 也是同一
         * 思路：抓不到课表时先回答「是哪种页面」，而不是继续猜。
         * 只读结构（全局变量名、select 的值、table 的 id/行数、星期几出现次数），
         * 不碰也不上报用户的任何账号、密码、cookie 内容。
         */
        private val DIAG_JS = """
            (function () {
              var globals = [];
              var names = ['veInitDefaultJson', '__INITIAL_STATE__', 'kbxx', 'kckbData',
                'lessonArray', '__NEXT_DATA__', 'dateList', 'activities', 'table0'];
              for (var i = 0; i < names.length; i++) {
                try {
                  if (window[names[i]]) {
                    var s = typeof window[names[i]] === 'string'
                      ? window[names[i]] : JSON.stringify(window[names[i]]);
                    globals.push(names[i] + '(' + (s ? s.length : 0) + ')');
                  }
                } catch (e) {}
              }
              var sels = [];
              try {
                var ss = document.querySelectorAll('select');
                for (var j = 0; j < ss.length && j < 10; j++) {
                  var o = '';
                  try {
                    o = String(ss[j].options[ss[j].selectedIndex].textContent || '').slice(0, 40);
                  } catch (e) {}
                  sels.push((ss[j].id || ss[j].name || '?') + '=' +
                    String(ss[j].value || '').slice(0, 24) + '[' + o + ']');
                }
              } catch (e) {}
              var tabs = [];
              try {
                var ts = document.querySelectorAll('table');
                for (var k = 0; k < ts.length && k < 8; k++) {
                  var nm = ts[k].id ? ('#' + ts[k].id)
                    : (ts[k].className ? ('.' + String(ts[k].className).split(' ')[0]) : 'table');
                  tabs.push(nm + ':' + ts[k].getElementsByTagName('tr').length + 'r');
                }
              } catch (e) {}
              var body = '';
              try {
                body = document.body
                  ? (document.body.innerText || document.body.textContent || '') : '';
              } catch (e) {}

              var days = (body.match(/星期[一二三四五六日天]/g) || []).length;
              return JSON.stringify({title: document.title || '', days: days,
                bodyLen: body.length, globals: globals, selects: sels, tables: tabs});
            })()
        """.trimIndent()

        /**
         * 抓取当前页：优先挑 `#kbtable` / 单元格最多的表，把 `outerHTML` 与整页文本交回。
         *
         * 之所以把**表格 HTML** 而不是解析结果带回去：正方课表格内的字段靠
         * `title="教师" / "周次(节次)" / "地点" / "教学班"` 标注，HTML 保真度最高，
         * 而 Dart 侧 `ZfHtmlParser` 可以离线单元测试。
         *
         * 另外先试一发**正方 jwglxt 自己的课表 JSON 接口**（`xskbcx_cxXskbcxIndex.html`
         * + `doType=query&gnmkdm=N2151`）：页面上一次只渲染一周，而接口给的是整学期，
         * 且 `jcs` / `zcd` / `xqj` 都是原始值而不是渲染后的文字，比抠 DOM 稳。
         * 接口拿不到就照旧回落到 DOM 抓取，两条路互不影响。
         */
        /**
         * 「让页面自己去查一次」的注入脚本。
         *
         * 真机实测：正方课表页刚打开时表格是**空的** —— 数据要等页面自己的 JS 发完 AJAX 才有。
         * 我们的同步抓取只能看到一个空壳，所以先替用户点一下「查询」，等表格渲染出来再抓一次 DOM。
         * 这条路把「取数」交给页面自己的代码（端点和参数都是它自己的，最容易对）。
         */
        private val TRIGGER_QUERY_JS = """
            (function () {
              try {
                var names = ['query', 'search', 'doQuery', 'loadData', 'reloadData', 'refresh'];
                for (var i = 0; i < names.length; i++) {
                  var f = window[names[i]];
                  if (typeof f === 'function') {
                    try { f(); return 'call:' + names[i]; } catch (e) {}
                  }
                }
                var nodes = document.querySelectorAll(
                  'button,a,input[type=button],input[type=submit],.btn');
                for (var j = 0; j < nodes.length; j++) {
                  var el = nodes[j];
                  var t = String(
                    el.innerText || el.textContent || el.value || el.title || ''
                  ).replace(/\s/g, '');

                  if (!t) { continue; }
                  if (t === '查询' || t === '搜索' || t === '查课表' || t.indexOf('查询') === 0) {
                    try { el.click(); return 'click:' + t; } catch (e) {}
                  }
                }
                return 'none';
              } catch (e) { return 'err:' + e; }
            })()
        """.trimIndent()

        private val EXTRACT_JS = """
            (function () {
              function collect(doc, out) {
                try {
                  var ts = doc.getElementsByTagName('table');
                  for (var i = 0; i < ts.length; i++) { out.push(ts[i]); }
                  var fs = doc.getElementsByTagName('iframe');
                  for (var j = 0; j < fs.length; j++) {
                    try {
                      if (fs[j].contentDocument) { collect(fs[j].contentDocument, out); }
                    } catch (e) {}
                  }
                } catch (e) {}
              }
              function textOf(doc) {
                try {
                  return doc.body ? (doc.body.innerText || doc.body.textContent || '') : '';
                } catch (e) { return ''; }
              }
              // 「填充过的课程格」计数：正方 jwglxt 的课表其实是 **div 网格**（.kbcontent），
              // 不是 <table> —— 所以光看 tables.length 判断有没有抓到课表是不准的。
              function filledCells(doc) {
                var n = 0;
                try {
                  var es = doc.getElementsByClassName('kbcontent');
                  for (var i = 0; i < es.length; i++) {
                    var s = String(es[i].innerText || es[i].textContent || '').replace(/\s/g, '');
                    if (s.length > 1) { n++; }
                  }
                } catch (e) {}
                return n;
              }
              function cells(t) {
                try {
                  return t.getElementsByTagName('td').length + t.getElementsByTagName('th').length;
                } catch (e) { return 0; }
              }
              // ── 正方 jwglxt 课表 JSON 接口 ──
              // 端点不写死：从当前路径推出 context-path，换 /jwglxt2/ 之类的部署也能用。
              // 页面本身 + 同源 iframe 的 document（课表页经常整体是嵌在 iframe 里的）
              function docs() {
                var out = [document];
                try {
                  var fs = document.getElementsByTagName('iframe');
                  for (var i = 0; i < fs.length; i++) {
                    try { if (fs[i].contentDocument) { out.push(fs[i].contentDocument); } } catch (e) {}
                  }
                } catch (e) {}
                return out;
              }
              function controlValue(name) {
                var ds = docs();
                for (var d = 0; d < ds.length; d++) {
                  var list = [], i;
                  var ins = ds[d].getElementsByTagName('input');
                  for (i = 0; i < ins.length; i++) { list.push(ins[i]); }
                  var sels = ds[d].getElementsByTagName('select');
                  for (i = 0; i < sels.length; i++) { list.push(sels[i]); }
                  for (i = 0; i < list.length; i++) {
                    var e = list[i];
                    var id = (e.id || '').toLowerCase();
                    var nm = (e.name || '').toLowerCase();
                    if (id === name || nm === name) {
                      var v = e.value;
                      if (v) { return String(v).trim(); }
                    }
                  }
                }
                return '';
              }
              // ── 借参考实现 CourseSchedule（AcademicCaptureScript）的取数顺序 ──
              // 它的经验是：正方系的课表**不一定在表格里**。
              //   1) jwglxt 新版会把整份课表内联成 `veInitDefaultJson` 之类的全局变量；
              //   2) 直接打开接口时，整页就是一个 JSON 响应体；
              //   3) DOM 里的表格 id 各部署不同（#Table1 / #kbgrid_table / #sycjlrtabGrid）。
              // 所以我们先「深度遍历一切拿得到的 JSON，找出最像课表行的数组」，
              // 再去抠 DOM；判定字段照搬参考实现（课名 / 星期 / 节次 / 周次 四类特征）。
              var ROW_NAMES = ['kcmc', 'kcm', 'courseName'];
              var ROW_DAYS = ['xqj', 'xq', 'skxq', 'day', 'weekday'];
              var ROW_SECTIONS = ['jcs', 'jc', 'sksj', 'ksjc', 'skjc', 'startSection'];
              var ROW_WEEKS = ['zcd', 'zc', 'skzc', 'weeks'];
              var ROW_REST = ['xm', 'jsxm', 'jsmc', 'teacher', 'cdmc', 'jxcdmc', 'jasmc',
                'classroom', 'room', 'jsjc', 'endSection', 'cxjc', 'sectionCount'];
              function anyKey(o, ks) {
                for (var i = 0; i < ks.length; i++) {
                  var v = o[ks[i]];
                  if (v !== undefined && v !== null && v !== '') { return true; }
                }
                return false;
              }
              // 只在顶层找是不够的：正方新版会把 星期/节次/周次 一起塞进
              // 嵌套对象里（形如 `{kcmc:'…', id:{skxq:1, jcs:'1-2'}, zcd:'…'}`），
              // 顶层只剩课名，分数会被卡在阈值以下而整行丢掉。
              // 所以往下找一层（数组里的对象也算），深度上限 2。
              function deepAnyKey(o, ks, depth) {
                if (!o || typeof o !== 'object') { return false; }
                if (Object.prototype.toString.call(o) !== '[object Array]' && anyKey(o, ks)) {
                  return true;
                }
                if (depth <= 0) { return false; }
                for (var k in o) {
                  if (!Object.prototype.hasOwnProperty.call(o, k)) { continue; }
                  var v = o[k];
                  if (!v || typeof v !== 'object') { continue; }
                  if (Object.prototype.toString.call(v) === '[object Array]') {
                    for (var i = 0; i < v.length && i < 8; i++) {
                      if (deepAnyKey(v[i], ks, depth - 1)) { return true; }
                    }
                  } else if (deepAnyKey(v, ks, depth - 1)) {
                    return true;
                  }
                }
                return false;
              }
              function rowScore(o) {
                if (!o || typeof o !== 'object') { return 0; }
                if (Object.prototype.toString.call(o) === '[object Array]') { return 0; }
                var s = 0;
                if (deepAnyKey(o, ROW_NAMES, 1)) { s += 4; }
                if (deepAnyKey(o, ROW_DAYS, 1)) { s += 3; }
                if (deepAnyKey(o, ROW_SECTIONS, 1)) { s += 3; }
                if (deepAnyKey(o, ROW_WEEKS, 1)) { s += 2; }
                return s;
              }
              // 在任意 JSON 里挑「最像课表行」的数组：逐层下钻，取平均分行分最高者。
              function deepFindRows(root) {
                var best = null, bestScore = 0, seen = 0;
                function walk(node, depth) {
                  if (!node || typeof node !== 'object' || depth > 6 || seen > 5000) { return; }
                  seen++;
                  if (Object.prototype.toString.call(node) === '[object Array]') {
                    if (node.length) {
                      var sum = 0, n = 0, named = 0;
                      var lim = node.length < 300 ? node.length : 300;
                      for (var i = 0; i < lim; i++) {
                        var r = rowScore(node[i]);
                        if (deepAnyKey(node[i], ROW_NAMES, 1)) { named++; }
                        if (r > 0) { sum += r; n++; }
                      }
                      if (n > 0 && named > 0) {
                        var avg = sum / n;
                        // 既要有「课名 + 星期」这种强度，数组里也真的带课名，
                        // 才认作课表；只有「节次 + 周次」的数组不允许胜出。
                        if (avg >= 7 && avg > bestScore) { bestScore = avg; best = node; }
                      }
                    }
                    for (var j = 0; j < node.length && j < 80; j++) { walk(node[j], depth + 1); }
                    return;
                  }
                  var ks = [];
                  try { ks = Object.keys(node); } catch (e) { return; }
                  for (var k = 0; k < ks.length && k < 100; k++) {
                    var v = node[ks[k]];
                    if (v && typeof v === 'object') { walk(v, depth + 1); }
                  }
                }
                walk(root, 0);
                return best;
              }
              // 可能内联了整份课表的全局变量（与参考实现同名单）
              function globalsRoot() {
                var out = [];
                var names = ['veInitDefaultJson', '__INITIAL_STATE__', 'kbxx', 'kckbData',
                  'lessonArray', '__NEXT_DATA__', 'dateList'];
                for (var i = 0; i < names.length; i++) {
                  try {
                    if (window[names[i]]) { out.push({name: names[i], value: window[names[i]]}); }
                  } catch (e) {}
                }
                return out;
              }
              // 直接打开接口时整页就是个 JSON 文档
              function bodyJson() {
                try {
                  var b = document.body;
                  if (!b) { return null; }
                  var t = (b.innerText || b.textContent || '').trim();
                  if (t.length < 4 || t.length > 800000) { return null; }
                  var c = t.charAt(0);
                  if (c !== '[' && c !== '{') { return null; }
                  return JSON.parse(t);
                } catch (e) { return null; }
              }
              function slimRows(rows) {
                var out = [];
                var keys = ROW_NAMES.concat(ROW_DAYS, ROW_SECTIONS, ROW_WEEKS, ROW_REST);
                for (var r = 0; r < rows.length && r < 800; r++) {
                  var row = rows[r];
                  if (!row || typeof row !== 'object') { continue; }
                  var o = {};
                  // 先按已知键取；再把这一行自己的键也算进来——嵌套对象（如 `id`）
                  // 的名字不在已知键里，但里面的 skxq/jcs 正是我们要的。
                  var probe = keys.slice();
                  try {
                    var own = Object.keys(row);
                    for (var z = 0; z < own.length && z < 200; z++) {
                      if (probe.indexOf(own[z]) < 0) { probe.push(own[z]); }
                    }
                  } catch (e) {}
                  for (var q = 0; q < probe.length; q++) {
                    var k = probe[q], v = row[k];
                    if (v === undefined || v === null) { continue; }
                    if (typeof v === 'object') {
                      if (Object.prototype.toString.call(v) === '[object Array]') {
                        // 数组只收原始值（周次列表这类），对象数组不往上报
                        var flat = [];
                        for (var ai = 0; ai < v.length && ai < 200; ai++) {
                          if (v[ai] === null || typeof v[ai] === 'object') { continue; }
                          flat.push(String(v[ai]));
                        }
                        if (flat.length) { o[k] = flat.join(',').slice(0, 512); }
                      } else {
                        // 正方新版把 星期/节次/周次 塞进嵌套对象（形如 id.skxq）。
                        // 必须把里面的原始值**抬到顶层**，Dart 侧才认得出 xqj/jcs/zcd；
                        // 只把整个对象拼成一个字符串塞在 id 里是没用的。
                        for (var sk in v) {
                          if (!Object.prototype.hasOwnProperty.call(v, sk)) { continue; }
                          var sv = v[sk];
                          if (sv === null || typeof sv === 'object') { continue; }
                          if (o[sk] === undefined) { o[sk] = String(sv).slice(0, 512); }
                        }
                      }
                      continue;
                    }
                    o[k] = String(v).slice(0, 512);
                  }
                  if (!o.kcmc && !o.kcm && !o.courseName) { continue; }
                  out.push(o);
                }
                return out;
              }
              // 先吃页面里现成的 JSON（内联全局 / JSON 响应体）——这是参考实现的主力路径，
              // 不需要用户先在页面上点「查询」，也不依赖任何接口路径。
              function borrowedHit() {
                var roots = globalsRoot();
                var bj = bodyJson();
                if (bj) { roots.push({name: 'bodyJson', value: bj}); }
                for (var i = 0; i < roots.length; i++) {
                  var arr = deepFindRows(roots[i].value);
                  if (!arr || !arr.length) { continue; }
                  var rows = slimRows(arr);
                  if (!rows.length) { continue; }
                  return {endpoint: 'inline:' + roots[i].name, year: '', term: '', rows: rows};
                }
                return null;
              }
              // 学年/学期：先认正方标准的 #xnm / #xqm；认不到再认参考实现那种
              // select[id*=xnxq]（值可能是 2025-2026-1 这种组合值），都没有就放弃。
              function termCodes() {
                var y = controlValue('xnm'), t = controlValue('xqm');
                if (y && t) { return {year: y, term: t}; }
                var ds = docs();
                for (var d = 0; d < ds.length; d++) {
                  var sels = [];
                  try { sels = ds[d].getElementsByTagName('select'); } catch (e) { continue; }
                  for (var i = 0; i < sels.length; i++) {
                    var s = sels[i];
                    var idn = ((s.id || '') + ' ' + (s.name || '')).toLowerCase();
                    if (idn.indexOf('xnxq') < 0 && idn.indexOf('xnm') < 0 &&
                        idn.indexOf('xqm') < 0 && idn.indexOf('term') < 0 &&
                        idn.indexOf('semester') < 0) { continue; }
                    var v = String(s.value || '').trim();
                    var label = '';
                    try { label = String(s.options[s.selectedIndex].textContent || '').trim(); } catch (e) {}
                    var m = label.match(/(20\d{2})/);
                    if (!m) { m = v.match(/(20\d{2})/); }
                    if (!m) { continue; }
                    var tt = '';
                    var tail = v.match(/(\d{1,2})\s*$/);
                    if (tail) {
                      // 正方组合值约定：-1 是第一学期(xqm=3)，-2 是第二学期(xqm=12)
                      tt = tail[1] === '1' ? '3' : (tail[1] === '2' ? '12' : tail[1]);
                    }
                    if (!tt && /第一|第 1|学期1/.test(label)) { tt = '3'; }
                    if (!tt && /第二|第 2|学期2/.test(label)) { tt = '12'; }
                    if (tt) { return {year: m[1], term: tt}; }
                  }
                }
                return null;
              }
              // 接口端点是**推**出来的，因为各校部署路径差别很大：
              //   a) 常规部署：`/jwglxt/kbcx/xskbcx_cxXskbcxIndex.html` → 取 `/kbcx/` 之前的 context-path；
              //   b) 内江师范这类**反向代理**部署：真实地址长这样——
              //      `https://jxglpt-xxx.proxy.njtc.edu.cn/sso/driotlogin?url=kbcx%2Fxskbcx_cxXskbcxIndex.html%3Fgnmkdm%3DN2151`
              //      路径里**根本没有 `/kbcx/` 这一段**（老代码就在这里直接 return null，
              //      于是永远拿不到接口数据，只能退化成抠 DOM，教师/地点就丢了）。
              //      这种要把 `url=` 参数解两遍码，取出真正的相对路径再拼。
              function endpointCandidates() {
                var out = [], seen = {};
                function push(u) {
                  if (!u) { return; }
                  if (seen[u]) { return; }
                  seen[u] = 1;
                  out.push(u);
                }
                var m = location.pathname.match(/^(.*?)\/(?:kbcx|xtgl|xsxxxggl|xkgl)\//i);
                if (m) { push(location.origin + m[1] + '/kbcx/xskbcx_cxXskbcxIndex.html'); }
                var probes = [location.search || '', location.hash || ''];
                for (var i = 0; i < probes.length; i++) {
                  var mm = probes[i].match(/[?&#]url=([^&]+)/i);
                  if (!mm) { continue; }
                  var inner = mm[1];
                  try { inner = decodeURIComponent(inner); } catch (e) {}
                  try { inner = decodeURIComponent(inner); } catch (e) {}
                  var mm2 = inner.match(/^(.*?)(?:kbcx|xtgl|xsxxxggl|xkgl)\//i);
                  var base = mm2 ? mm2[1] : '';
                  base = base.replace(/^\/+/, '');
                  push(location.origin + '/' + base + 'kbcx/xskbcx_cxXskbcxIndex.html');
                }
                push(location.origin + '/kbcx/xskbcx_cxXskbcxIndex.html');
                push(location.origin + '/jwglxt/kbcx/xskbcx_cxXskbcxIndex.html');
                return out;
              }
              // 端点清单：**只算不发**。真正的 HTTP 由 Kotlin 侧去发（能设超时、能带 WebView 的 Cookie）。
              //
              // 这里原来放的是**同步 XHR** 直接 POST 试探。真机上它把 WebView 的 JS 线程卡死：
              // 日志只打出 `extract start`，`evaluateJavascript` 的回调**永远不返回**，
              // 用户看到的现象就是「读取不到」（1.1.5 真机实录）。同步 XHR 既不能设超时、
              // 也不能中断，所以这条路彻底废掉 —— 别再写回来。
              function jsonEndpoints() {
                var out = [], seen = {};
                function push(u) {
                  if (!u) { return; }
                  var s = String(u).split('?')[0];
                  if (seen[s]) { return; }
                  seen[s] = 1;
                  out.push(s);
                }
                // 正方 jwglxt 约定：页面是 `..._cxXskbcxIndex.html`，**数据**接口是 `..._cxXsKb.html`
                // （返回 {"kbList":[...]}）。原来的候选全是页面地址，POST 过去拿不到 kbList。
                var cands = endpointCandidates();
                for (var i = 0; i < cands.length; i++) {
                  push(cands[i].replace(/_cxXskbcxIndex\.html/i, '_cxXsKb.html'));
                }
                for (var j = 0; j < cands.length; j++) { push(cands[j]); }
                return out;
              }
              // 先吃页面里现成的 JSON（正方新版内联的 veInitDefaultJson / 直接打开的 JSON 响应体）。
              // 页面里没有，就交给 Kotlin 按 jsonEndpoints() 去 POST。
              var jsonHit = borrowedHit();
              var tables = [];
              collect(document, tables);
              var best = null, bestScore = -1;
              for (var i = 0; i < tables.length; i++) {
                var t = tables[i];
                var s = cells(t);
                var id = t.id || '';
                var cls = t.className || '';
                var kb = 0;
                try { kb = t.getElementsByClassName('kbcontent').length; } catch (e) {}
                // 课表表格识别：老正方 `xskb_list.do` 的表格本身有 id="kbtable"，
                // 而 jwglxt `xskbcx_cxXskbcxIndex.html` 是外层 <div id="kbtable"> 包着表格、
                // 课程内容放在 .kbcontent 里，所以三种信号都要认。
                // 正方新版页面用的表格 id（取自参考实现的适配器表）
                var zfId = /^(Table1|table1|kbgrid_table|sycjlrtabGrid)$/i.test(id);
                if (zfId) { s += 800000; }
                if (id === 'kbtable' || /kbtable|kbcontent|kbgrid/i.test(cls) || kb > 0) { s += 1000000; }
                if (kb > 0) { s += kb * 10; }
                if (t.parentNode && t.parentNode.id === 'kbtable') { s += 500000; }
                if (s > bestScore) { bestScore = s; best = t; }
              }
              var html = best ? best.outerHTML : '';
              var text = textOf(document);
              var frames = document.getElementsByTagName('iframe');
              for (var k = 0; k < frames.length; k++) {
                try {
                  if (frames[k].contentDocument) {
                    text += String.fromCharCode(10) + textOf(frames[k].contentDocument);
                  }
                } catch (e) {}
              }
              var terms = termCodes();
              var eps = jsonEndpoints();
              var kbFilled = 0;
              var allDocs = docs();
              for (var d2 = 0; d2 < allDocs.length; d2++) { kbFilled += filledCells(allDocs[d2]); }
              return JSON.stringify({
                url: location.href,
                title: document.title || '',
                tableHtml: String(html).slice(0, 400000),
                text: String(text).slice(0, 200000),
                tableCount: tables.length,
                kbFilled: kbFilled,
                jsonRows: jsonHit ? jsonHit.rows : null,
                xnm: (jsonHit && jsonHit.year) ? jsonHit.year : (terms ? terms.year : ''),
                xqm: (jsonHit && jsonHit.term) ? jsonHit.term : (terms ? terms.term : ''),
                jsonEndpoint: jsonHit ? jsonHit.endpoint : '',
                endpoints: eps,
                diag: {
                  tables: tables.length,
                  frames: frames.length,
                  bodyLen: String(text).length,
                  bestId: best ? String(best.id || '') : '',
                  bestScore: bestScore,
                  xnm: terms ? terms.year : '',
                  xqm: terms ? terms.term : ''
                }
              });
            })()
        """.trimIndent()
    }
}
