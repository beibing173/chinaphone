package dev.beibing.chinaphone.audit

/**
 * 内置规则库。
 *
 * 判据来源：2026-11 X 平台用户对小米 HyperOS 的实测结论。
 * 详见 docs/evidence.md。
 *
 * 与 pc/rules.json 保持同构 —— 两端共用同一套判据，
 * 修改时请同步两边。
 */
object Rules {

    const val VERSION = "1.0.0"

    /** 评分阈值 */
    const val HIGH_THRESHOLD = 70.0
    const val MEDIUM_THRESHOLD = 40.0

    val ALL: List<Rule> = listOf(

        Rule(
            id = "R001",
            name = "运营商 DM 设备管理客户端",
            weight = 80.0,
            type = "package_keyword",
            matchPattern = listOf(
                "(?i)(systemhelper|dmpackage|dmclient|devicemanage|device_manage)",
                "(?i)(mobiletools|carrierdmp|otamanager)",
                "(?i)\\b(cucc|cmcc|ctcc)\\b"
            ),
            description = "包名命中运营商设备管理(DM)/渠道定制客户端特征。" +
                "小米样本 SystemHelper = com.mobiletools.systemhelper，" +
                "实为中国联通 DM 适配方案，可按运营商指令远程上报与下发操作。",
            advice = "重点核查。非运营商合约机/非本人开通的服务，该组件无正当用途。"
        ),

        Rule(
            id = "R002",
            name = "厂商安全组件 / 应用行为分析模块",
            weight = 65.0,
            type = "package_keyword",
            matchPattern = listOf(
                "(?i)(guardprovider|securitycenter|security\\.center)",
                "(?i)(frauddetection|antifraud|riskscan|appreport)"
            ),
            description = "包名命中厂商「安全组件 / 反诈引擎」。小米样本 系统安全组件 = " +
                "com.miui.guardprovider，会上报第三方应用清单（包名/版本/签名摘要/名称），" +
                "并有录屏云检测实现。",
            advice = "这类组件通常无法卸载。核对是否可停用；重点看它上报了哪些内容。"
        ),

        Rule(
            id = "R003",
            name = "系统预装应用（非用户安装）",
            weight = 40.0,
            type = "system_app",
            matchPattern = emptyList(),
            description = "安装在系统分区的预装应用，不经过用户安装流程，用户通常无法卸载。",
            advice = "逐个确认是否为厂商预置必需品。停用前记录包名以便回滚。"
        ),

        Rule(
            id = "R004",
            name = "超权限组合：电话状态 + 应用枚举 + 使用统计",
            weight = 90.0,
            type = "permission_combo",
            matchPattern = listOf(
                "READ_PHONE_STATE",
                "QUERY_ALL_PACKAGES",
                "PACKAGE_USAGE_STATS"
            ),
            description = "同时具备读取电话状态（含 IMEI/IMSI/ICCID 能力）、枚举全部已安装应用、" +
                "读取应用使用统计三项权限。这三项叠加即可复现小米样本的" +
                "「应用列表 + 设备/SIM 标识关联上报」能力。",
            advice = "最高优先级核查。国内合规应用不应静默持有该组合。"
        ),

        Rule(
            id = "R005",
            name = "录音/录屏 + 应用枚举组合",
            weight = 88.0,
            type = "permission_combo",
            matchPattern = listOf(
                "RECORD_AUDIO",
                "QUERY_ALL_PACKAGES"
            ),
            description = "同时具备录音与全量应用枚举能力。小米样本的录屏采集链路" +
                "（720x1280 24fps → 私有缓存 → Base64 → 加密上传 → 等风控回执）依赖此类能力。",
            advice = "核查是否有用户可感知的录音/录屏场景。系统组件持有该组合且无界面时风险极高。"
        ),

        Rule(
            id = "R006",
            name = "导出面：无权限保护的组件",
            weight = 60.0,
            type = "exported_component",
            matchPattern = emptyList(),
            description = "组件声明 exported 且未设置权限保护，任意第三方应用可拉起或绑定。" +
                "小米样本 SystemHelper 的 RegisterHelperService 任意应用可 bind，另有 TestActivity 直接导出。",
            advice = "这是本地提权与横向利用的入口。非必要不应导出。"
        ),

        Rule(
            id = "R007",
            name = "后台定位 + 设备标识组合",
            weight = 70.0,
            type = "permission_combo",
            matchPattern = listOf(
                "ACCESS_BACKGROUND_LOCATION",
                "READ_PHONE_STATE"
            ),
            description = "同时具备后台定位与设备标识读取能力。小米样本 SystemHelper " +
                "内置百度定位 SDK（硬编码 API key），并在后台上报定位。",
            advice = "核查后台定位的必要性。系统组件内置第三方地图 SDK 属异常设计。"
        ),

        Rule(
            id = "R008",
            name = "可安装应用的组件",
            weight = 65.0,
            type = "permission_keyword",
            matchPattern = listOf("REQUEST_INSTALL_PACKAGES"),
            description = "具备静默/引导安装应用的能力。运营商 DM 客户端的典型能力之一是远程下发安装包。",
            advice = "系统组件持有该权限即可绕过应用商店装应用，需确认来源可信。"
        ),

        Rule(
            id = "R009",
            name = "读取短信 / 通话记录的组件",
            weight = 75.0,
            type = "permission_combo",
            matchPattern = listOf("READ_SMS", "READ_CALL_LOG"),
            description = "同时可读短信与通话记录。学术研究记录过类似组件将通话时长、响铃时间、" +
                "最后联系时间上报后端的行为。",
            advice = "极高敏感权限。核查该组件是否为主流短信/电话应用；否则建议停用。"
        ),

        Rule(
            id = "R010",
            name = "平台签名特权应用",
            weight = 55.0,
            type = "platform_signed",
            matchPattern = emptyList(),
            description = "使用系统平台的签名密钥签名，享有系统级特权，可访问普通应用无法触及的接口。",
            advice = "平台签名通常意味着厂商自有组件，但也意味着更高权限，值得了解其用途。"
        ),

        Rule(
            id = "R011",
            name = "可被商店更新的系统组件",
            weight = 45.0,
            type = "updateable_system",
            matchPattern = emptyList(),
            description = "系统预装但可被应用商店覆盖更新的组件。" +
                "小米样本 系统安全组件 com.miui.guardprovider 就属于此类（已被商店更新到 3.0.7），" +
                "意味着其行为可能随商店更新而变化。",
            advice = "关注其更新历史与权限变化。"
        ),

        Rule(
            id = "R012",
            name = "全量应用枚举能力",
            weight = 50.0,
            type = "permission_keyword",
            matchPattern = listOf("QUERY_ALL_PACKAGES"),
            description = "具备枚举设备上全部已安装应用的能力，这是「上报应用列表」的前置条件。",
            advice = "单独看是常规能力（商店、杀毒、启动器都用），需结合其他规则判断。"
        ),

        Rule(
            id = "R013",
            name = "后台录音能力",
            weight = 72.0,
            type = "permission_keyword",
            matchPattern = listOf("RECORD_AUDIO"),
            description = "具备录音权限。结合后台运行能力时需警惕。",
            advice = "核查是否有用户可感知的录音场景。"
        ),
    )

    fun byId(id: String): Rule? = ALL.firstOrNull { it.id == id }
}
