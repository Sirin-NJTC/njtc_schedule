package cn.edu.njtc.njtc_schedule.reminder

import android.app.Notification
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import cn.edu.njtc.njtc_schedule.R
import java.util.Locale

/**
 * vivo（OriginOS / 原子通知 / 原子岛）适配层。
 *
 * 字段命名规则（**极易写错，已用 vivo 官方 demo 逐字核对**）：
 * vivo 官方 demo（`superx_demo`，`LiveNotificationConstants.java` 与
 * `SuperXNormalTemplateDemo.java`）在**每一个嵌套 Bundle 内部也使用完整带前缀的 key**，
 * 而不是短名。例如：
 * ```
 * Bundle baseBundle = new Bundle();
 * baseBundle.putCharSequence("notification.superx.baseInfos.title", "…"); // 不是 "title"
 * bundle.putBundle("notification.superx.baseInfos", baseBundle);
 * ```
 * 原子岛的 key 前缀则从 `notification.superx.` 变成 `island.superx.`，且**子 Bundle 内依旧带全前缀**
 * （`island.superx.leftInfo.content`）。若写成短名，vivo 引擎取不到值 → 原子通知不展示。
 *
 * 其余关键事实：
 * - 原子通知 = 「普通系统通知 + 规定的 superx 字段」，字段挂在 `Notification.extras` 上；
 * - `showNotify` 默认 true —— 原子通知展示失败会自动降级为普通通知，因此「未开通权限」不会丢提醒；
 * - 不支持原子岛的机型会退回 `notification.superx.capsule`（状态栏胶囊）；
 * - 接入需先向 oosyztz@vivo.com 申请准入（见项目根目录 VIVO_ATOMIC_NOTIFICATION.md），
 *   权限开通前系统会忽略 superx 字段、按普通通知展示。
 */
object VivoHelper {
    private const val TAG = "NjtcVivo"

    // ------------------------------------------------------------ 字段名常量
    // 全部取自 vivo 官方 demo 的 LiveNotificationConstants.java，禁止自行缩写。

    /** 原子通知核心参数。 */
    private object K {
        // 顶层
        const val OPERATION = "notification.superx.operation"
        const val TEMPLATE = "notification.superx.template"
        const val SHOW_NOTIFY = "notification.superx.showNotify"
        const val SCENE = "notification.superx.scene"
        const val KEEP_DURATION = "notification.superx.keepDuration"
        const val CLICK_RESP = "notification.superx.clickResp"
        const val CHANGED_RECORD = "notification.superx.changedRecord"
        const val SOUND = "notification.superx.sound"
        const val DISMISS_WHEN_KILL = "notification.superx.dismissWhenKill"

        const val BASE_INFOS = "notification.superx.baseInfos"
        const val INFOS = "notification.superx.infos"
        const val SHORT_INFOS = "notification.superx.shortInfos"
        const val ISLAND = "notification.superx.island"
        const val CAPSULE = "notification.superx.capsule"

        // baseInfos（子 Bundle 内也是全名）
        const val BASE_ICON = "notification.superx.baseInfos.icon"
        const val BASE_TITLE = "notification.superx.baseInfos.title"
        const val BASE_CONTENT = "notification.superx.baseInfos.content"
        const val BASE_SUB_INFO = "notification.superx.baseInfos.subInfo"
        const val BASE_SUB_TEXT = "notification.superx.baseInfos.subText"
        const val BASE_SUB_TEXT_COLOR = "notification.superx.baseInfos.subTextColor"
        const val BASE_SUB_CAPSULE_BG_COLOR = "notification.superx.baseInfos.subCapsuleBgColor"

        // infos（template=1 强调信息）
        const val INFO_DESCRIBE = "notification.superx.infos.describe"
        const val INFO_CORE_INFO = "notification.superx.infos.coreInfo"
        const val INFO_IMAGE = "notification.superx.infos.image"
        const val INFO_IMAGE_CLICK_RESP = "notification.superx.infos.imageClickResp"

        // shortInfos（小卡 / OriginB 锁屏）
        const val SHORT_ICON = "notification.superx.shortInfos.icon"
        const val SHORT_IMAGE = "notification.superx.shortInfos.image"
        const val SHORT_IMAGE_CLICK_RESP = "notification.superx.shortInfos.imageClickResp"
        const val SHORT_ORIGIN_IMAGE = "notification.superx.shortInfos.OriginBImage"
        const val SHORT_DESCRIBE = "notification.superx.shortInfos.describeShort"
        const val SHORT_CORE_INFO = "notification.superx.shortInfos.coreInfoShort"

        // capsule（状态栏胶囊）
        const val CAPSULE_STATE = "notification.superx.capsule.state"
        const val CAPSULE_ICON = "notification.superx.capsule.icon"
        const val CAPSULE_CONTENT = "notification.superx.capsule.content"
        const val CAPSULE_CONTENT_COLOR = "notification.superx.capsule.contentColor"
        const val CAPSULE_BG_COLOR = "notification.superx.capsule.bgColor"

        // island（注意前缀是 island.superx.，子 Bundle 内同样带全前缀）
        const val ISLAND_LEFT_TEMPLATE = "island.superx.leftTemplate"
        const val ISLAND_LEFT_INFO = "island.superx.leftInfo"
        const val ISLAND_LEFT_ICON = "island.superx.leftInfo.icon"
        const val ISLAND_LEFT_CONTENT = "island.superx.leftInfo.content"
        const val ISLAND_RIGHT_TEMPLATE = "island.superx.rightTemplate"
        const val ISLAND_RIGHT_INFO = "island.superx.rightInfo"
        const val ISLAND_RIGHT_CAPSULE_CONTENT = "island.superx.rightInfo.capsuleContent"
        const val ISLAND_RIGHT_CAPSULE_BG_COLOR = "island.superx.rightInfo.capsuleBgColor"
        const val ISLAND_RIGHT_CONTENT = "island.superx.rightInfo.content"
        const val ISLAND_RIGHT_CLICK_RESP = "island.superx.rightInfo.clickResp"
        const val ISLAND_SHOW_TIME = "island.superx.showTime"
        const val ISLAND_CARD_TEMPLATE = "island.superx.template"
        const val ISLAND_CLICK = "island.superx.islandClick"
        const val ISLAND_CLICK_RESP = "island.superx.clickResp"
    }

    // ---- notification.superx.operation 生命周期
    const val OP_CREATE = 0
    const val OP_UPDATE = 1
    const val OP_END = 2

    // ---- notification.superx.template 取值
    const val TEMPLATE_EMPHASIS = 1 // 强调信息
    const val TEMPLATE_PROGRESS = 2 // 进度可视化
    const val TEMPLATE_SYMMETRIC = 3 // 左右信息对称
    const val TEMPLATE_BASIC = 4 // 基础
    const val TEMPLATE_NAVIGATION = 5 // 导航

    // ---- baseInfos.subInfo 取值
    private const val SUB_INFO_TEXT = 1

    // ---- island.superx.leftTemplate
    private const val LEFT_IMAGE_TEXT = 1

    // ---- island.superx.rightTemplate
    private const val RIGHT_CAPSULE_TEXT = 6

    /**
     * 原子岛场景标识。
     *
     * ⚠ 官方 scene 白名单（MOVIE / HEALTH_REGISTER / TAXI / TAKEOUT / DELIEVERY /
     * NAVIGATION / CAR_STATE / METTING / TRAIN / FLIGHT）**不含课程/教育类**，
     * 因此这里先按最接近的「会议日程」METTING 上报（原文拼写即 METTING），
     * 最终取值需由 vivo 在准入审核时定义下发。改动只需修改这一处常量。
     */
    const val SCENE_MEETING = "METTING"

    /** 原子通知在通知中心的存留时长（秒），官方上限 3600。 */
    private const val KEEP_DURATION_SECONDS = 1800

    /** `island.superx.showTime` 官方上限 180 秒（注意：不是 3600）。 */
    private const val ISLAND_SHOW_TIME_SECONDS = 180

    // ------------------------------------------------------------ 设备识别

    /** 是否为 vivo / iQOO 设备。 */
    fun isVivo(): Boolean {
        val signature = listOf(
            Build.BRAND, Build.MANUFACTURER, Build.PRODUCT, Build.DEVICE, Build.HARDWARE,
        ).joinToString("|").lowercase(Locale.ROOT)
        if (signature.contains("vivo") || signature.contains("iqoo") || signature.contains("bbk")) {
            return true
        }
        return !osVersion().isNullOrEmpty()
    }

    /** OriginOS 版本号，如 "OriginOS 5.0"。非 vivo 设备返回 null。 */
    fun osVersion(): String? {
        for (key in listOf("ro.vivo.os.version", "ro.vivo.os.build.display.id", "ro.vivo.product.version")) {
            val v = systemProperty(key)
            if (!v.isNullOrBlank()) return v
        }
        return null
    }

    /**
     * 官方兼容性判定：**ROM 版本 ≥ 5.0 且 FtFeature「vivo.software.disable_island」不为 true**。
     *
     * 官方伪代码：
     * ```
     * float ROM_VERSION = FtBuild.getRomVersion();
     * boolean DISABLE_ISLAND = FtFeature.isFeatureSupport("vivo.software.disable_island");
     * ```
     * 这两个类位于 vivo ROM（未公开包名），故用反射 + 候选类名遍历 + null 安全：
     * 取不到值时**不判为不支持**（默认不配置该 Feature 即表示支持）。
     */
    fun isIslandCapable(): Boolean {
        if (!isVivo()) return false
        val rom = romVersion()
        val osOk = rom == null || rom >= 5.0f
        return osOk && disableIslandFeature() != true
    }

    /** OriginOS ROM 版本号（如 5.0），取不到返回 null。 */
    fun romVersion(): Float? = reflectStaticNumber(
        listOf("android.os.FtBuild", "android.util.FtBuild"), "getRomVersion",
    )

    /** true=明确不支持原子岛；false=明确支持；null=取不到（不能据此判定为不支持）。 */
    private fun disableIslandFeature(): Boolean? = reflectStaticBoolean(
        listOf("android.os.FtFeature", "android.util.FtFeature"),
        "isFeatureSupport",
        "vivo.software.disable_island",
    )

    private fun reflectStaticNumber(classNames: List<String>, method: String): Float? {
        for (cn in classNames) {
            try {
                val v = Class.forName(cn).getMethod(method).invoke(null)
                if (v is Number) return v.toFloat()
            } catch (t: Throwable) {
                // 该类/方法在当前 ROM 上不存在，继续尝试下一个候选
            }
        }
        return null
    }

    private fun reflectStaticBoolean(classNames: List<String>, method: String, arg: String): Boolean? {
        for (cn in classNames) {
            try {
                val cls = Class.forName(cn)
                try {
                    val v = cls.getMethod(method, String::class.java).invoke(null, arg)
                    if (v is Boolean) return v
                } catch (t: Throwable) {
                    // 参数签名不匹配，试无参重载
                }
                try {
                    val v = cls.getMethod(method).invoke(null)
                    if (v is Boolean) return v
                } catch (t: Throwable) {
                    // 无参重载也不存在
                }
            } catch (t: Throwable) {
                // 类不存在
            }
        }
        return null
    }

    private fun systemProperty(key: String): String? = try {
        val cls = Class.forName("android.os.SystemProperties")
        val get = cls.getMethod("get", String::class.java)
        (get.invoke(null, key) as? String)?.takeIf { it.isNotBlank() }
    } catch (t: Throwable) {
        null
    }

    // ------------------------------------------------------------ 场景开关

    /**
     * 反射查询原子通知「场景开关」是否打开。
     *
     * 官方说明：系统在 `NotificationManager` 中新增接口
     * `public boolean getSceneStatus(String pkgName, String sceneName)`，返回 true 代表开关打开。
     * 该接口未公开在 SDK 中，必须反射调用。
     *
     * @return true=开 / false=关 / null=取不到（非 vivo、旧 ROM 或场景未定义）
     */
    fun isSceneEnabled(ctx: Context, scene: String = SCENE_MEETING): Boolean? = try {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        val m = nm.javaClass.getMethod("getSceneStatus", String::class.java, String::class.java)
        m.invoke(nm, ctx.packageName, scene) as? Boolean
    } catch (t: Throwable) {
        null
    }

    // ------------------------------------------------------------ 权限状态

    fun areNotificationsEnabled(ctx: Context): Boolean = try {
        (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager)
            .areNotificationsEnabled()
    } catch (t: Throwable) {
        true
    }

    fun canScheduleExactAlarms(ctx: Context): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (ctx.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager)
                .canScheduleExactAlarms()
        } else {
            true
        }
    } catch (t: Throwable) {
        true
    }

    fun isIgnoringBatteryOptimizations(ctx: Context): Boolean = try {
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        pm.isIgnoringBatteryOptimizations(ctx.packageName)
    } catch (t: Throwable) {
        false
    }

    // ------------------------------------------------------------ 跳转系统设置

    /** 打开本应用的通知设置页。 */
    fun openNotificationSettings(ctx: Context) {
        safeStart(ctx, Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, ctx.packageName)
        }) {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:${ctx.packageName}"))
        }
    }

    /** 打开「精确闹钟」授权页（Android 12+）。 */
    fun openExactAlarmSettings(ctx: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            safeStart(ctx, Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                .setData(Uri.parse("package:${ctx.packageName}"))) {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.parse("package:${ctx.packageName}"))
            }
        }
    }

    /** 请求加入电池优化白名单（未声明 REQUEST_IGNORE_BATTERY_OPTIMIZATIONS 时退化为列表页）。 */
    fun openBatteryOptimizationSettings(ctx: Context) {
        safeStart(
            ctx,
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                .setData(Uri.parse("package:${ctx.packageName}")),
        ) {
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        }
    }

    /**
     * 打开 vivo 的「自启动 / 后台高耗电」管理页。
     *
     * 各 OriginOS 版本的组件名并不统一，这里按常见顺序逐个尝试，
     * 全部落空时退到本应用详情页，由用户自行进入「权限 → 自启动」。
     */
    fun openAutoStartSettings(ctx: Context): String {
        val candidates = listOf(
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.PurviewTabActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            "com.iqoo.secure" to "com.iqoo.secure.MainActivity",
            "com.bbk.launcher2" to "com.bbk.launcher2.installshortcut.PurviewActivity",
        )
        for ((pkg, cls) in candidates) {
            val intent = Intent().apply {
                component = ComponentName(pkg, cls)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (ctx.packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) != null) {
                try {
                    ctx.startActivity(intent)
                    Log.i(TAG, "已打开 vivo 自启动管理页：$pkg/$cls")
                    return "$pkg/$cls"
                } catch (t: Throwable) {
                    Log.w(TAG, "打开 $pkg/$cls 失败：${t.message}")
                }
            }
        }
        Log.w(TAG, "未找到 vivo 自启动管理页，退到应用详情页")
        safeStart(ctx, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:${ctx.packageName}"))) {
            Intent(Settings.ACTION_SETTINGS)
        }
        return "fallback:application_details"
    }

    private fun safeStart(ctx: Context, primary: Intent, fallback: () -> Intent) {
        val withFlags = primary.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
        try {
            ctx.startActivity(withFlags)
        } catch (t: Throwable) {
            Log.w(TAG, "跳转失败 ${withFlags.action}：${t.message}")
            try {
                ctx.startActivity(fallback().apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) })
            } catch (t2: Throwable) {
                Log.w(TAG, "兜底跳转同样失败：${t2.message}")
            }
        }
    }

    // ------------------------------------------------------------ superx 字段

    /**
     * 把 vivo 原子通知 / 原子岛字段挂到通知的 `extras` 上。
     *
     * 覆盖全部触点：通知中心大卡（强调信息模版）+ 小卡 / OriginB 锁屏 + 状态栏胶囊 +
     * 原子岛（OriginOS 5.0+）。不支持原子岛的机型自动使用胶囊；原子通知整体展示失败时
     * 由系统按 `showNotify=true` 降级为普通通知。
     */
    fun attachSuperx(
        ctx: Context,
        notification: Notification,
        title: String,
        content: String,
        subText: String,
        capsuleText: String,
        islandLeftText: String,
        islandRightText: String,
        accentColor: Int,
        clickIntent: PendingIntent,
        scene: String = SCENE_MEETING,
        template: Int = TEMPLATE_EMPHASIS,
        changedRecord: Int = 0,
    ) {
        val extras = notification.extras
        val icon = Icon.createWithResource(ctx, R.mipmap.ic_launcher)

        // ---- 顶层 notification.superx.*
        extras.putInt(K.OPERATION, OP_CREATE)
        extras.putBoolean(K.SHOW_NOTIFY, true)
        extras.putInt(K.TEMPLATE, template)
        extras.putString(K.SCENE, scene)
        extras.putInt(K.KEEP_DURATION, KEEP_DURATION_SECONDS)
        extras.putBoolean(K.SOUND, true)
        extras.putBoolean(K.DISMISS_WHEN_KILL, false)
        extras.putInt(K.CHANGED_RECORD, changedRecord)
        extras.putParcelable(K.CLICK_RESP, clickIntent)

        // ---- notification.superx.baseInfos.*（大卡基础区）
        val baseInfos = Bundle().apply {
            putParcelable(K.BASE_ICON, icon)
            putCharSequence(K.BASE_TITLE, title)
            putCharSequence(K.BASE_CONTENT, content)
            if (subText.isNotEmpty()) {
                putInt(K.BASE_SUB_INFO, SUB_INFO_TEXT)
                putCharSequence(K.BASE_SUB_TEXT, subText)
                putInt(K.BASE_SUB_TEXT_COLOR, accentColor)
                putInt(K.BASE_SUB_CAPSULE_BG_COLOR, accentColor)
            }
        }
        extras.putBundle(K.BASE_INFOS, baseInfos)

        // ---- notification.superx.infos.*（template=1 强调信息模版）
        val infos = Bundle().apply {
            putString(K.INFO_DESCRIBE, if (subText.isEmpty()) title else subText)
            putString(K.INFO_CORE_INFO, content)
            putParcelable(K.INFO_IMAGE, icon)
            putParcelable(K.INFO_IMAGE_CLICK_RESP, clickIntent)
        }
        extras.putBundle(K.INFOS, infos)

        // ---- notification.superx.shortInfos.*（小卡 / OriginB 锁屏）
        // image / describeShort / coreInfoShort 不可缺，缺了走异常逻辑。
        val shortInfos = Bundle().apply {
            putParcelable(K.SHORT_ICON, icon)
            putParcelable(K.SHORT_IMAGE, icon)
            putParcelable(K.SHORT_ORIGIN_IMAGE, icon)
            putParcelable(K.SHORT_IMAGE_CLICK_RESP, clickIntent)
            putString(K.SHORT_DESCRIBE, if (subText.isEmpty()) title else subText)
            putString(K.SHORT_CORE_INFO, content)
        }
        extras.putBundle(K.SHORT_INFOS, shortInfos)

        // ---- notification.superx.capsule.*（不支持原子岛的机型：状态栏胶囊）
        val capsule = Bundle().apply {
            putInt(K.CAPSULE_STATE, 1)
            putParcelable(K.CAPSULE_ICON, icon)
            putString(K.CAPSULE_CONTENT, capsuleText)
            putInt(K.CAPSULE_CONTENT_COLOR, Color.WHITE)
            putInt(K.CAPSULE_BG_COLOR, accentColor)
        }
        extras.putBundle(K.CAPSULE, capsule)

        // ---- notification.superx.island（OriginOS 5.0+ 原子岛）
        // 摄像头左右两侧都必须有内容：左 = 图片 + 文本，右 = 胶囊文本。
        val islandLeftInfo = Bundle().apply {
            putParcelable(K.ISLAND_LEFT_ICON, icon)
            putCharSequence(K.ISLAND_LEFT_CONTENT, islandLeftText)
        }
        val islandRightInfo = Bundle().apply {
            putCharSequence(K.ISLAND_RIGHT_CAPSULE_CONTENT, islandRightText)
            putInt(K.ISLAND_RIGHT_CAPSULE_BG_COLOR, accentColor)
            putCharSequence(K.ISLAND_RIGHT_CONTENT, islandRightText)
            putParcelable(K.ISLAND_RIGHT_CLICK_RESP, clickIntent)
        }
        val island = Bundle().apply {
            putInt(K.ISLAND_LEFT_TEMPLATE, LEFT_IMAGE_TEXT)
            putBundle(K.ISLAND_LEFT_INFO, islandLeftInfo)
            putInt(K.ISLAND_RIGHT_TEMPLATE, RIGHT_CAPSULE_TEXT)
            putBundle(K.ISLAND_RIGHT_INFO, islandRightInfo)
            putInt(K.ISLAND_CLICK, 1) // 点击跳落地页
            putParcelable(K.ISLAND_CLICK_RESP, clickIntent)
            putInt(K.ISLAND_SHOW_TIME, ISLAND_SHOW_TIME_SECONDS)
            putInt(K.ISLAND_CARD_TEMPLATE, template) // 出大卡
            putBundle(K.BASE_INFOS, baseInfos)
            putBundle(K.INFOS, infos)
        }
        extras.putBundle(K.ISLAND, island)

        Log.i(
            TAG,
            "已挂载 superx 字段：scene=$scene template=$template " +
                "rightTemplate=$RIGHT_CAPSULE_TEXT keepDuration=${KEEP_DURATION_SECONDS}s " +
                "islandShowTime=${ISLAND_SHOW_TIME_SECONDS}s",
        )
    }

    /**
     * 供 UI 展示与日志用的设备摘要。
     *
     * **同时打一条 INFO 日志**。原因：真机排障时通常只能拿到用户导出的 logcat，
     * 而用户未必能截到「原子通知 / 原子岛」卡片，这张表恰好覆盖了要回答的全部问题
     * （isVivo / isIslandCapable / romVersion / sceneEnabled / 各项权限）。
     * 2026-10-04 用 vivo 云真机 `10AE1C1NP80011G` 的日志排障时，因为没有这条日志，
     * 只能靠 ROM 自己打的
     * `VivoConfigStore: key:vivo.software.disable_island isCached is true and value is false`
     * 反推出原子岛可用；`romVersion` 与 `sceneEnabled` 则完全取不到 —— 故补上。
     */
    fun deviceSummary(ctx: Context): Map<String, Any?> {
        val summary = mapOf(
            "isVivo" to isVivo(),
            "isIslandCapable" to isIslandCapable(),
            "romVersion" to (romVersion()?.toString() ?: ""),
            "sceneEnabled" to isSceneEnabled(ctx),
            "brand" to Build.BRAND,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "osVersion" to (osVersion() ?: ""),
            "androidSdk" to Build.VERSION.SDK_INT,
            "androidRelease" to Build.VERSION.RELEASE,
            "notificationsEnabled" to areNotificationsEnabled(ctx),
            "exactAlarmAllowed" to canScheduleExactAlarms(ctx),
            "ignoringBatteryOptimizations" to isIgnoringBatteryOptimizations(ctx),
        )
        Log.i(TAG, "设备摘要 $summary")
        return summary
    }
}
