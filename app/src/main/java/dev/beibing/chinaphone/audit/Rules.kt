package dev.beibing.chinaphone.audit

/**
 * 内置规则库（v1.0.2 重构）。
 *
 * ══════════════════════════════════════════════════════════════
 * 设计原则
 * ══════════════════════════════════════════════════════════════
 *
 * v1.0.1 的问题：只要命中规则就展示 → 微信、支付宝、系统自带应用
 * 全被刷出来，一次扫 200 条，全是噪音。
 *
 * v1.0.2 的原则：
 *
 *   1. 先看「用户能不能感知它」（由 AuditEngine 前置过滤）
 *      - 有启动图标 → 用户知道它存在 → 不报
 *      - 在设置里可见 → 用户能找到它 → 不报
 *      - 只有完全不可见的组件才进入评估
 *
 *   2. 即使不可见，也要有「上报/采集能力」的证据才报
 *      - 光有权限不算，要形成组合
 *      - 光在 priv-app 不算，要看它干什么
 *
 *   3. 核心系统包一律跳过（android、systemui、settings 等）
 *
 * 一句话：**只报「用户看不见 + 有能力偷偷上报」的组件。**
 */
object Rules {

    const val VERSION = "1.0.2"

    /** 评分阈值（v1.0.2 收紧） */
    const val HIGH_THRESHOLD = 60.0
    const val MEDIUM_THRESHOLD = 30.0

    /**
     * 核心系统包：永不报告。
     * 这些是 Android 与厂商 ROM 的地基，报出来没有意义。
     */
    val CORE_SYSTEM_PACKAGES: Set<String> = setOf(
        "android",
        "com.android.systemui",
        "com.android.settings",
        "com.android.shell",
        "com.android.phone",
        "com.android.providers.settings",
        "com.android.providers.media",
        "com.android.providers.downloads",
        "com.android.providers.contacts",
        "com.android.providers.telephony",
        "com.android.providers.calendar",
        "com.android.server.telecom",
        "com.android.packageinstaller",
        "com.android.permissioncontroller",
        "com.android.launcher",
        "com.android.launcher3",
        "com.google.android.gms",
        "com.google.android.gsf",
        "com.google.android.packageinstaller",
        "com.google.android.permissioncontroller",
    )

    /** 核心系统包名前缀：同样跳过。 */
    val CORE_SYSTEM_PREFIXES: List<String> = listOf(
        "android.",
        "com.android.internal.",
        "com.android.providers.",
    )

    /** 常绿白名单：这些包即使不可见也不报，都是公认必需的系统级组件。 */
    val ALWAYS_SKIP: Set<String> = setOf(
        "android.ext.services",
        "com.android.ext.services",
        "com.android.networkstack",
        "com.android.networkstack.tethering",
        "com.android.certinstaller",
        "com.android.keychain",
        "com.android.se",
        "com.android.storagemanager",
    )

    val ALL: List<Rule> = listOf(

        // ── 最高危：确认过的运营商探针特征 ──
        Rule(
            id = "R001",
            name = "运营商 DM 设备管理客户端",
            weight = 80.0,
            type = "package_keyword",
            matchPattern = listOf(
                "(?i)(systemhelper|dmpackage|dmclient|devicemanage|device_manage)",
                "(?i)(mobiletools|carrierdmp|otamanager)",
            ),
            description = "包名命中运营商设备管理(DM)客户端特征。小米样本 " +
                "SystemHelper = com.mobiletools.systemhelper，实为中国联通 DM 适配方案，" +
                "可按运营商指令远程上报应用列表与设备标识。",
            advice = "非运营商合约机不应有此类组件。可尝试停用，但不建议卸载系统应用。"
        ),

        Rule(
            id = "R002",
            name = "厂商风控/反诈上报组件",
            weight = 65.0,
            type = "package_keyword",
            matchPattern = listOf(
                "(?i)(guardprovider|frauddetection|antifraud|riskscan|appreport)",
            ),
            description = "包名命中厂商「安全组件 / 反诈引擎」。这类组件通常会上报" +
                "第三方应用清单用于风控判定。小米样本 com.miui.guardprovider 属于此类。",
            advice = "厂商风控组件通常无法停用。了解其存在即可，重点看它申请了什么权限。"
        ),

        // ── 权限组合：能偷偷上报的能力 ──
        Rule(
            id = "R003",
            name = "具备完整上报链路",
            weight = 70.0,
            type = "permission_combo",
            matchPattern = listOf(
                "READ_PHONE_STATE",
                "QUERY_ALL_PACKAGES",
            ),
            description = "同时持有「读取电话状态（含设备标识能力）」和「枚举全部应用」两项权限。" +
                "这两项叠加就是「把应用列表和设备标识关联上报」的最小能力集。",
            advice = "不可见的系统组件持有这个组合时，需要确认它到底在干什么。"
        ),

        Rule(
            id = "R004",
            name = "设备标识 + 应用枚举 + 使用统计",
            weight = 85.0,
            type = "permission_combo",
            matchPattern = listOf(
                "READ_PHONE_STATE",
                "QUERY_ALL_PACKAGES",
                "PACKAGE_USAGE_STATS",
            ),
            description = "三项齐备，正好复现小米样本 SystemHelper 的上报能力：" +
                "应用清单 + 使用情况 + 设备标识三者关联。",
            advice = "最高优先级核查。这个组合在正常系统组件里极为罕见。"
        ),

        Rule(
            id = "R005",
            name = "录音能力 + 应用枚举",
            weight = 80.0,
            type = "permission_combo",
            matchPattern = listOf(
                "RECORD_AUDIO",
                "QUERY_ALL_PACKAGES",
            ),
            description = "不可见组件同时具备录音和全量应用枚举能力。",
            advice = "核查是否有用户可感知的录音场景。没有就该处理。"
        ),

        Rule(
            id = "R006",
            name = "后台定位 + 设备标识",
            weight = 70.0,
            type = "permission_combo",
            matchPattern = listOf(
                "ACCESS_BACKGROUND_LOCATION",
                "READ_PHONE_STATE",
            ),
            description = "可后台持续定位，同时能读取设备标识。",
            advice = "不可见组件持有该组合时，需确认定位用途。"
        ),

        Rule(
            id = "R007",
            name = "短信 + 通话记录读取",
            weight = 85.0,
            type = "permission_combo",
            matchPattern = listOf(
                "READ_SMS",
                "READ_CALL_LOG",
            ),
            description = "可读短信与通话记录。极高敏感权限组合。",
            advice = "除非是本机默认短信/电话应用，否则高度可疑。"
        ),

        // ── 单点特征 ──
        Rule(
            id = "R008",
            name = "可静默安装应用",
            weight = 60.0,
            type = "permission_keyword",
            matchPattern = listOf("REQUEST_INSTALL_PACKAGES"),
            description = "具备安装应用的能力。运营商 DM 客户端的典型能力之一就是远程下发安装包。",
            advice = "系统组件持有该权限可绕过应用商店装应用。"
        ),

        Rule(
            id = "R009",
            name = "无权限保护的导出组件",
            weight = 45.0,
            type = "exported_component",
            matchPattern = emptyList(),
            description = "存在 exported 且无权限保护的组件，任意第三方应用可拉起或绑定。" +
                "小米样本 SystemHelper 的 RegisterHelperService 就是这种。",
            advice = "这是本地提权与横向利用的入口，正常系统组件不应如此。"
        ),

        Rule(
            id = "R010",
            name = "平台签名 + 无图标",
            weight = 50.0,
            type = "platform_signed",
            matchPattern = emptyList(),
            description = "使用平台密钥签名却没有任何启动入口，属于用户不可见的特权组件。",
            advice = "平台签名享有系统级权限。确认它是否必要。"
        ),

        Rule(
            id = "R011",
            name = "位于 priv-app 的特权组件",
            weight = 40.0,
            type = "privapp",
            matchPattern = emptyList(),
            description = "APK 位于 /system/priv-app，权限高于普通系统应用，且不经过用户安装。",
            advice = "priv-app 本身是正常机制，但结合不可见 + 上报能力才值得警惕。"
        ),

        Rule(
            id = "R012",
            name = "可被商店静默更新",
            weight = 25.0,
            type = "updateable_system",
            matchPattern = emptyList(),
            description = "系统预装但可被应用商店覆盖更新，意味着其行为可能在用户不知情时变化。" +
                "小米样本 com.miui.guardprovider 已被商店更新到 3.0.7。",
            advice = "关注其更新记录与权限变化。"
        ),
    )

    fun byId(id: String): Rule? = ALL.firstOrNull { it.id == id }
}
