# 国产 ROM 同类隐蔽上报组件 · 跨品牌横向对照

> 调研目标：回答「除了小米的 `com.miui.guardprovider` + `com.mobiletools.systemhelper`，还有哪些厂商/ROM 有同类东西」。
> 写作原则：**每条结论都带来源 + 可信度分级；拿不准的一律写「待实测确认」，绝不臆造包名。**
> 本文档只做对照与判据，不代替真机实测。

---

## 0. 可信度分级说明

| 等级 | 含义 | 判定标准 |
|---|---|---|
| **A｜官方文档** | 厂商/运营商/标准组织的公开规范、隐私政策、开发者文档 | 可引用、不易被推翻，但只证明"组件存在/接口存在"，**不证明实际行为** |
| **B｜已读实测报告** | 有人真的拆了 APK / 抓了包 / 跑了设备，并公开了方法与证据 | 最强的一类"行为"证据；注意甄别是否二手转述 |
| **C｜学术论文** | 同行评议或学位论文，附测量方法学 | 覆盖面广、方法严谨，但样本机型/版本有限，需标注版本 |
| **D｜社区传闻** | 论坛、贴吧、评论区、无方法的"我朋友说" | 只能当线索，**不可单独作为结论** |
| **T｜待实测确认** | 包名/行为均未获得独立验证 | 必须在真机上核实后才可写入规则库 |

---

## 1. 小米基线（对照组，已知样本）

先把小米侧已确认的三件东西立成基线，后面所有品牌都跟它比。

| 组件 label | 包名 | 位置 / 签名 | 已知行为 | 明文 HTTP | 来源 | 可信度 |
|---|---|---|---|---|---|---|
| 系统安全组件 | `com.miui.guardprovider` | `/system/priv-app/`，小米自研 | 后台上传**已安装应用列表**（代码内部称 AntiDefraud）；上传内容含 uuid + MIUI 版本 + 应用清单 | 待实测确认 | [AntiAntiDefraud（GitHub，含 logcat 关键字 `responseDetectApp`）](https://github.com/MinaMichita/AntiAntiDefraud)；[NGA 实测帖：用腾讯天御模块回传至 157.148.47.204](https://ngabbs.com/read.php?tid=35273994) | B |
| SystemHelper | `com.mobiletools.systemhelper` | `/system/priv-app/`，**平台签名**；实为 MTK/展锐方案商的 Modem Helper / 运营商 DM 客户端 | 向运营商 DM 平台注册；采集 IMEI/IMSI/ICCID、应用列表、后台定位；双 `ELAPSED_WAKEUP` 闹钟常驻；720x1280 24fps 录屏上传做风控 | **是**（`http://dm.wo.com.cn:18080/register`） | [APKMirror 以 "Xiaomi Inc." 发布 SystemHelper](https://www.apkmirror.com/apk/xiaomi-inc/systemhelper-3/)；[联通《Android 终端 DM 适配使用指南》明写 `vendor/sprd/operator/cucc/prebuild/app/SystemHelper_debug.apk`](https://bbs.16rd.com/thread-583828-1-1.html)；[memeosupdates 称其为 "MediaTek Modem Helper"](https://memeosupdates.com/apps/com.mobiletools.systemhelper/31) | B |
| Reg Service | `com.miui.dmregservice` | 系统应用 | 与中国移动 DM 相关的注册服务；有实测称冻结后解决电话服务异常耗电 | 待实测确认 | [关于 dmregservice（含 CMCC DM SDK 说明）](https://blog.thris.me/archives/regservice.html) | B/C |

**关键定性（本文档最重要的一句）**：
`com.mobiletools.systemhelper` **不是小米自研**，而是 MTK/展锐等**平台方案商**随运营商渠道定制分区预置的 DM 客户端。联通 DM 适配手册直接把它的路径写成 `vendor/sprd/operator/cucc/prebuild/app/SystemHelper_debug.apk` —— 这是**"运营商渠道定制预装"**的铁证，也解释了"插移动卡却向联通 `dm.wo.com.cn` 注册"的荒诞点：**注册目标由出厂时就烧进 `cucc`（联通）分区决定，而非由当前 SIM 卡决定。**

由此推出一条跨品牌结论：

> **凡走运营商渠道入库/销售的定制机，理论上都可能预装一个同类 DM 客户端；包名、签名、端点随厂商与方案商而变。** 这条线的证据是**运营商规范**（A 级），不是某一家厂商的"黑料"。

---

## 2. 跨品牌对照主表

说明：
- 「应用列表上报」「录屏」两列，**只有拿到 B/C 级实测证据才打 ✅**；仅有权限组合支撑的写「⚠️权限具备」，表示"有能力但未观察到"。
- 一切未经验证的包名都写「待实测确认」。

| 厂商 / ROM | 组件（label） | 包名 | 应用列表上报 | 设备标识（IMEI/IMSI/ICCID） | 录屏 | 后台常驻 | 运营商 DM 注册 | 明文 HTTP | 证据来源 | 可信度 |
|---|---|---|---|---|---|---|---|---|---|---|
| **小米 / 澎湃 OS（基线）** | 系统安全组件 | `com.miui.guardprovider` | ✅ | 待实测确认 | ❌ 未见证据 | ✅ | ❌ | 待实测确认 | [GitHub AntiAntiDefraud](https://github.com/MinaMichita/AntiAntiDefraud)、[NGA](https://ngabbs.com/read.php?tid=35273994) | B |
| **小米 / 澎湃 OS（基线）** | SystemHelper | `com.mobiletools.systemhelper` | ✅（随 DM 注册上报） | ✅ | ✅（720x1280 24fps） | ✅（双 `ELAPSED_WAKEUP`） | ✅ `dm.wo.com.cn:18080` | **✅ 明文** | [16rd 联通 DM 手册](https://bbs.16rd.com/thread-583828-1-1.html)、[APKMirror](https://www.apkmirror.com/apk/xiaomi-inc/systemhelper-3/) | B |
| **OPPO / 一加 / realme（ColorOS）** | Basic Data Services（基础数据服务） | `com.oplus.statistics.rom` | ⚠️权限具备（`QUERY_ALL_PACKAGES` + `PACKAGE_USAGE_STATS` + `GET_TASKS`） | ⚠️权限具备（`READ_PRIVILEGED_PHONE_STATE`） | ❌ 未见证据 | ✅（`RECEIVE_BOOT_COMPLETED` + `WAKE_LOCK` + `SCHEDULE_EXACT_ALARM` + `FOREGROUND_SERVICE`） | 待实测确认 | 待实测确认 | [sysapps.bayton.org 包详情（OEM OPPO 签名、26 权限全列）](https://sysapps.bayton.org/packages/com.oplus.statistics.rom)；[UAD 项目标注 "sending user data (can be opted out of)"](https://github.com/0x192/universal-android-debloater/issues/306) | B |
| **OPPO / 一加（ColorOS）** | 手机管家 | `com.coloros.phonemanager` | ⚠️权限具备（`QUERY_ALL_PACKAGES` + `GET_TASKS` + `PACKAGE_USAGE_STATS`） | 待实测确认 | ❌ 未见证据 | ✅（`RECEIVE_BOOT_COMPLETED`、`FOREGROUND_SERVICE`、`WAKE_LOCK`；13 个 tracker 签名） | 待实测确认 | 待实测确认 | [Exodus Privacy 报告 v15.12.0（55 权限 + 13 tracker 全列）](https://reports.exodus-privacy.eu.org/en/reports/522483/) | B |
| **OPPO / 一加（ColorOS）** | 应用安装器 | `com.oplus.appdetail` | ✅ 安装前**上传包信息做云端审核**，属"安装事件上报" | 待实测确认 | ❌ | ✅（安装常驻服务） | ❌ | 待实测确认（端点均 HTTPS） | [璃火牙实测：阻断 3 个域名即可干掉云端检测](https://lihvarya.com/%e5%a4%ba%e5%9b%9e%e8%ae%be%e5%a4%87%e6%8e%a7%e5%88%b6%e6%9d%83%ef%bc%9a%e6%97%a0%e6%84%9f%e5%b1%8f%e8%94%bd-oppo-coloros-%e7%ac%ac%e4%b8%89%e6%96%b9%e5%ba%94%e7%94%a8%e5%ae%89%e8%a3%85%e4%ba%91/) | B |
| **vivo / iQOO（OriginOS）** | Motor inteligente（智能引擎） | `com.vivo.abe` | ⚠️权限具备（`GET_TASKS` + `PACKAGE_USAGE_STATS` + `SET_ACTIVITY_WATCHER`） | ⚠️权限具备（`READ_PHONE_STATE`） | ❌ 未见证据 | ✅（`RECEIVE_BOOT_COMPLETED` + `WAKE_LOCK` + `SYSTEM_ALERT_WINDOW`；平台签名，43 权限） | 待实测确认 | 待实测确认 | [sysapps.bayton.org（vivo 平台签名，43 权限全列）](https://sysapps.bayton.org/packages/com.vivo.abe) | B |
| **vivo / iQOO（OriginOS）** | 手机管家 | `com.iqoo.secure` | ⚠️权限具备（云查杀 + 风险扫描） | 待实测确认 | ❌ 未见证据 | ✅ | 待实测确认 | 待实测确认 | [璃火牙实测（二）：参与安装审查的两个包名](https://lihvarya.com/%e5%a4%ba%e5%9b%9e%e8%ae%be%e5%a4%87%e6%8e%a7%e5%88%b6%e6%9d%83%ef%bc%88%e4%ba%8c%ef%bc%89%ef%bc%9a%e5%b1%8f%e8%94%bd-iqoo-originos-%e7%ac%ac%e4%b8%89%e6%96%b9%e5%ba%94%e7%94%a8%e5%ae%89%e8%a3%85/) | B |
| **荣耀（MagicOS）** | 我的荣耀 My HONOR | `com.hihonor.phoneservice` | ⚠️权限具备（含 vendor 权限 `applist`） | ⚠️权限具备（`READ_PRIVILEGED_PHONE_STATE` + `READ_PHONE_STATE`） | ❌ 未见证据 | ✅（`RECEIVE_BOOT_COMPLETED` + `WAKE_LOCK` + `REBOOT` + `MANAGE_USERS`；53 权限 + 1 analytics tracker） | 待实测确认 | 待实测确认 | [Exodus Privacy 报告 v10.0.7.245（53 权限全列）](https://reports.exodus-privacy.eu.org/en/reports/420433/) | B（权限）/ D（行为） |
| **华为（EMUI / HarmonyOS）** | — | 见 `huawei-components.md` | — | — | — | — | — | — | 由 huawei-research 专项负责，本文不展开 | — |
| **三星国行（One UI）** | 三星自定义"应用列表"权限 | `com.samsung.android.permission.GET_APP_LIST` | ⚠️权限具备（读全量应用列表是三星的**独立运行时权限**，非 `QUERY_ALL_PACKAGES`） | 待实测确认 | ❌ 未见证据 | 待实测确认 | ❌ | 待实测确认 | [三星申请浏览应用列表权限实测（含 `dumpsys package` 验证方法）](https://ewt45.github.io/blog/26-10-14-samsung-query-all-packages/index/) | B（权限存在）/ T（具体组件） |
| **三星国行（One UI）** | 具体上报组件 | 待实测确认 | 待实测确认 | 待实测确认 | 待实测确认 | 待实测确认 | 待实测确认 | 待实测确认 | 国行与海外版预装差异见 [盖乐世社区](https://www.samsungmembers.cn/thread-4120644-29-180.html) | T |

> **三星一列为什么大片空白**：三星国行的"上报"分散在多个 `com.samsung.android.*` 系统应用里，且没有像 Xiaomi 那样被公开逆向过的单点样本。按"禁止臆造包名"的要求，本鱼不填。真机上用第 4 节的判据扫一遍即可定位。

---

## 3. 学术侧的总览证据（跨品牌，非单点）

这两份是回答"到底哪些厂商在收集"的最有价值的第三方材料，覆盖面比单个论坛帖强得多：

| 材料 | 覆盖范围 | 关键结论 | 链接 | 可信度 |
|---|---|---|---|---|
| Liu, Leith, Patras (2023)《Android OS Privacy Under the Loupe — A Tale from the East》爱丁堡大学学位论文 | 三星、小米、华为、Realme、OnePlus 的**中国版固件** | 全部变体都向 OS 厂商与第三方传输"令人担忧体量"的私人数据，包括设备标识符、配置数据、遥测；**应用列表收集**在 Table 3.4 中逐一汇总 | [PDF](https://era.ed.ac.uk/bitstream/handle/1842/41248/LiuH_2023.pdf?sequence=1) | C |
| 同组《On the data privacy practices of Android OEMs》(PLoS ONE) | 同上，含方法论 | 明确写出"所有观测数据均经 HTTPS 传输"，以及**部分数据在 TLS 之外还有一层内层加密**；华为系统应用内嵌证书 SHA256 做证书固定 | [PLoS ONE](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0279942) | C |

**从这两份材料能直接得出的判断**：
1. **应用列表上报是国产 ROM 的普遍现象，不是小米独有。**
2. 但**传输方式分化**：学术观测到的厂商 Telemetry 基本走 HTTPS；小米 SystemHelper 的 DM 注册走**明文 HTTP**，这是它最恶劣的一点（与其他厂商不属同一档）。
3. **运营商的坑可能比厂商还深** —— 论文里明确提到运营商（mobile operators）也在后台收集重要 PII。

---

## 4. 自查判据清单（可直接翻译成检测脚本规则）

这一节是给 `audit_android.ps1` / `rules.json` 用的。每条规则含 **id / 匹配对象 / 匹配表达式 / 权重 / 说明**，`match` 字段写成脚本可直接消费的形式（正则或权限集合）。

### 4.1 分区与路径判据（最先跑，成本最低）

DM 类组件几乎必然落在这些路径下——这是"渠道定制预装"的物理指纹。

| 规则 id | 匹配对象 | 匹配表达式 | 权重 | 说明 |
|---|---|---|---|---|
| `PATH_OPERATOR_PARTITION` | APK 路径（来自 `pm list packages -f`） | `^/(vendor|odm)/operator/` 或 `^/cust/` 或 `^/preload/` 或 `^/product/priv-app/` | 80 | **运营商定制分区**。命中即高度可疑，直指渠道预装 DM 客户端 |
| `PATH_VENDOR_CUCC` | APK 路径 | `/(cucc|cmcc|ctcc|unicom|mobile|telecom)/` | 75 | 以三大运营商代号命名的 vendor 子目录，典型如 `vendor/sprd/operator/cucc/prebuild/app/` |
| `PATH_PRIV_APP` | APK 路径 | `^/system/priv-app/` | 30 | 特权应用区。单独命中只算弱信号（系统应用本来就多），**必须与权限组合叠加** |

> 实操命令：`adb shell pm list packages -f -U | findstr /i "priv-app operator cust preload vendor"`

### 4.2 权限组合判据（核心）

单看任何一个权限都不够，要看**组合**。下面三条是实测样本里最咬人的组合。

| 规则 id | 权限组合（AND 关系） | 权重 | 说明 |
|---|---|---|---|
| `PERM_DM_TELEMETRY_TRIO` | `android.permission.READ_PHONE_STATE` **∧** `android.permission.INTERNET` **∧** `android.permission.RECEIVE_BOOT_COMPLETED` | 45 | 读设备标识 + 联网 + 开机自启 = DM 客户端最小可行集。SystemHelper 就是这个组合 |
| `PERM_PRIVILEGED_PHONE_STATE` | `android.permission.READ_PRIVILEGED_PHONE_STATE` | 60 | **拿到 IMEI/IMSI/ICCID 的钥匙**（Android 10+ 普通应用已无法获取）。`com.oplus.statistics.rom`、`com.hihonor.phoneservice` 均声明此权限 |
| `PERM_APP_LIST_ENUM` | `android.permission.QUERY_ALL_PACKAGES` **∨** `android.permission.PACKAGE_USAGE_STATS` **∨** `android.permission.GET_TASKS` **∨** 厂商自定义含 `applist`/`GET_APP_LIST` 的权限名 | 55 | **枚举已安装应用**。三家（OPPO/vivo/荣耀）都中；三星走的是 `com.samsung.android.permission.GET_APP_LIST` |
| `PERM_ALWAYS_ON_LOCATION` | `ACCESS_FINE_LOCATION` **∧** `ACCESS_BACKGROUND_LOCATION`（或签名级 `LOCATION` 供应商权限） | 40 | 无前台界面却常驻定位 |
| `PERM_CAPTURE_SCREEN` | `android.permission.CAPTURE_VIDEO_OUTPUT` **∨** `android.permission.CAPTURE_AUDIO_OUTPUT` **∨** `android.permission.MEDIA_CONTENT_CONTROL` | 90 | **静默录屏/录制的强信号**。这三个是 signature/privileged 级，普通 App 拿不到；能拿到的系统组件"录屏"不需要用户点同意弹窗 |
| `PERM_SILENT_INSTALL` | `android.permission.INSTALL_PACKAGES` **∨** `android.permission.DELETE_PACKAGES` | 50 | 可静默装/卸其他应用 |
| `PERM_AUDIT_BYPASS` | `android.permission.READ_LOGS` **∨** `android.permission.DUMP` **∨** `android.permission.PACKAGE_USAGE_STATS` | 35 | 能读系统日志/转储，等同旁路审计 |

> 实操命令：`adb shell dumpsys package <pkg>` 然后抓 `requested permissions:` / `grantedPermissions:` 段。
> ⚠️ 注意：**声明 ≠ 授予**。脚本应优先匹配 `granted=true`（或 `grants:` 里出现的），否则误报会爆炸。

### 4.3 端点/域名判据（网络侧）

| 规则 id | 匹配对象 | 匹配表达式（正则） | 权重 | 说明 |
|---|---|---|---|---|
| `EP_OPERATOR_DM` | 抓包 SNI / DNS / `/proc/net` / netstat | `(?i)\bdm\.(wo\|10086\|189)\.(com\|cn)\b` 或 `(?i)\.(cucc\|cmcc\|ctcc)\.(com\|cn)` | 85 | **运营商 DM 平台**。`dm.wo.com.cn` 是联通；移动/电信的 DM 域名具体形态**待实测确认**（不要硬编码猜测值） |
| `EP_DM_PATH` | HTTP 请求行 | `(?i)^(GET\|POST)\s+/register\b` 或 `(?i)/dm(reg\|client)?/` 或 `(?i)(fumo\|omadm\|devdetail)` | 70 | OMA-DM 协议特征路径。`/register` 是自注册的典型端点 |
| `EP_DM_PORT` | 目的端口 | `:18080\b` **∨** `:5683\b`（CoAP） | 50 | `18080` 是联通 DM 实测端口；`5683` 是 CoAP，文献里 DM 调试平台用过 |
| `EP_PLAINTEXT_HTTP` | 协议 | scheme == `http` **且** 端口 ∈ {80, 8080, 18080} **且** 载荷含 IMEI/IMSI/ICCID 形态串 | 95 | **本次小米样本最恶劣的点**：明文 HTTP 传设备标识。全学术论文观测到的厂商遥测都走 HTTPS，明文的基本都是 DM |
| `EP_PII_IN_CLEARTEXT` | HTTP body | `(?i)\b(imei\|imsi\|iccid\|meid)\b\s*[=:"']\s*[0-9A-F]{8,}` | 90 | 明文传输标识符，直接定性 |
| `EP_OEM_TELEMETRY` | 抓包域名 | 见下方「各厂商遥测域名特征表」 | 40 | 厂商自家遥测，属"正常商业行为"区间，权重调低避免噪音 |

**各厂商遥测域名特征（用于归因，不用于定罪）**

| 厂商 | 域名特征（正则） | 来源 | 可信度 |
|---|---|---|---|
| 小米 | `(?i)(tracking\|data\.mistat\|adv\.sec\|update\.avlyun\.sec\|diagnosis\.ad)\.(intl\.)?(miui\|xiaomi)\.com` | [ACL4SSR MIUIPrivacy.list](https://git.moezx.cc/mashiro/ACL4SSR/src/commit/87e5ff73f6a82a5dcd8ed47c870a7af1d371adb7/Clash/Ruleset/MIUIPrivacy.list)；[爱丁堡论文补充材料](https://www.scss.tcd.ie/doug.leith/pubs/additional_material_neversleepingears.pdf) | B/C |
| OPPO / 一加 | `(?i)(app-installer-cn\|virusinfo-cloudscan-cn\|obus-cn\.dc)\.heytapmobi\.com` | [璃火牙实测](https://lihvarya.com/%e5%a4%ba%e5%9b%9e%e8%ae%be%e5%a4%87%e6%8e%a7%e5%88%b6%e6%9d%83%ef%bc%9a%e6%97%a0%e6%84%9f%e5%b1%8f%e8%94%bd-oppo-coloros-%e7%ac%ac%e4%b8%89%e6%96%b9%e5%ba%94%e7%94%a8%e5%ae%89%e8%a3%85%e4%ba%91/) | B |
| vivo / iQOO | `(?i)(prt-stsdk\|isecure\|az\.appstore\|stinmmtn)\.vivo\.com\.cn`；`viav-cse\.avlyun\.com` | [璃火牙实测（二）](https://lihvarya.com/%e5%a4%ba%e5%9b%9e%e8%ae%be%e5%a4%87%e6%8e%a7%e5%88%b6%e6%9d%83%ef%bc%88%e4%ba%8c%ef%bc%89%ef%bc%9a%e5%b1%8f%e8%94%bd-iqoo-originos-%e7%ac%ac%e4%b8%89%e6%96%b9%e5%ba%94%e7%94%a8%e5%ae%89%e8%a3%85/) | B |
| 华为 | `(?i)(logservice\d?\|metrics\d?\.data)\.hicloud\.com`；`nebula-collector\.huawei\.com` | [华为设备出网清单（第三方整理的设备流量表）](https://www.product.network/pdfviewer?url=https%3A%2F%2Fwww.product.network%2Fdatasheet%2Fhuaweienterprises%2FEDOC1100489554.pdf) | B/C（详见 `huawei-components.md`） |
| 三星 | 待实测确认（国行预装组件未获公开逆向） | — | T |
| 荣耀 | 待实测确认 | — | T |

### 4.4 常驻行为判据（dumpsys 侧）

| 规则 id | 匹配对象 | 匹配表达式 | 权重 | 说明 |
|---|---|---|---|---|
| `ALARM_REPEAT_ELAPSED_WAKEUP` | `dumpsys alarm` 输出 | 同一包名下出现 **≥2 条** `ELAPSED_WAKEUP` 且 `when=` 递增间隔固定（周期 < 15 min） | 70 | **实测样本的招牌特征**：双 `ELAPSED_WAKEUP` 闹钟常驻。正常系统应用极少这么干 |
| `ALARM_EXACT_ALLOW_IDLE` | `dumpsys alarm` | 包名同时出现在 `ELAPSED_WAKEUP` 与 `RTC_WAKEUP`，且带 `allowWhileIdle` | 45 | 绕过 Doze 打点，典型后台保活 |
| `SVC_PERSISTENT` | `dumpsys activity services` | `isPersistent=true` 或 `ServiceRecord{...<pkg>...}` 且无 `stopped=true` | 50 | 常驻服务 |
| `SVC_NO_UI` | `pm list packages` ∩ `dumpsys package` | 包**无 launcher 入口**（无 `android.intent.category.LAUNCHER` 的 Activity）**但**有 `FOREGROUND_SERVICE` 或 `INTERNET` | 55 | **用户看不见、删不掉、却在联网** —— 最该警惕的一类 |
| `EXPORTED_UNPROTECTED` | `dumpsys package` | `exported=true` 且 `permission=null` 的 Service/Provider | 40 | 任何本机应用都能调，等于给恶意 App 开后门 |
| `SCREEN_RECORD_SERVICE` | `dumpsys package` / `dumpsys media_projection` | 声明 `MediaProjection` 或含 `CAPTURE_VIDEO_OUTPUT` 的 Service | 85 | 录屏采集的实现路径 |

### 4.5 组合打分建议

脚本别用"命中即报警"的粗暴逻辑，用加权求和：

| 总分 | 定性 | 建议动作 |
|---|---|---|
| ≥ 150 | **高度可疑，等同小米样本** | 记录完整证据链，列入报告首屏 |
| 90 – 149 | 可疑，需人工复核 | 抓包 + 反编译核实 |
| 40 – 89 | 弱信号（多数是正常系统应用） | 只记入附录 |
| < 40 | 忽略 | — |

**几个可以立刻验收的"必然命中"用例**（拿来验证规则库有没有写对）：

| 用例 | 期望命中规则 | 期望总分区间 |
|---|---|---|
| 小米 `com.mobiletools.systemhelper` | `PATH_VENDOR_CUCC` + `PATH_PRIV_APP` + `PERM_DM_TELEMETRY_TRIO` + `PERM_PRIVILEGED_PHONE_STATE` + `ALARM_REPEAT_ELAPSED_WAKEUP` + `EP_OPERATOR_DM` + `EP_PLAINTEXT_HTTP` | ≥ 300 |
| 小米 `com.miui.guardprovider` | `PATH_PRIV_APP` + `PERM_APP_LIST_ENUM` + `EP_OEM_TELEMETRY` | 100 – 160 |
| OPPO `com.oplus.statistics.rom` | `PERM_PRIVILEGED_PHONE_STATE` + `PERM_APP_LIST_ENUM` + `SVC_NO_UI` | 120 – 180 |
| vivo `com.vivo.abe` | `PERM_APP_LIST_ENUM` + `PERM_ALWAYS_ON_LOCATION` + `SVC_NO_UI` | 100 – 150 |
| 普通应用 `com.tencent.mm` | 仅 `PERM_APP_LIST_ENUM`（若声明） | < 60 |

---

## 5. 运营商渠道定制分区：为什么这条线是跨品牌的

这是全文的"结构性原因"，比单点爆料更有解释力。

| 论据 | 内容 | 来源 | 可信度 |
|---|---|---|---|
| 联通 DM 是**入库硬要求** | 《中国联通 Android 终端 DM 适配使用指南》：DM 是"Android 终端入库的基础"，联通按厂商提供的信息下发匹配的 DM APK，厂商直接集成 | [16rd 论坛转载](https://bbs.16rd.com/thread-583828-1-1.html) | A |
| 移动 DM 自 2017 起对**所有入库机型**强制 | 中国移动要求 2017 年及以后所有入其产品库的定制、**非定制** Android 终端均须支持终端管理功能 | [CSDN《中国移动 Android 手机终端 DM 适配使用指南》](https://bbs.16rd.com/thread-581669-1-1.html) | A |
| **"战略合作型"要求排他** | CMCC 的"深度合作型/战略合作型"要求手机内**不能预置其他运营商的 DM 软件** | [CSDN《CMCC 移动 DM 自注册适配指南》](https://blog.csdn.net/wds1181977/article/details/65442760) | A |
| DM 客户端会被**改头换面** | 手册明确要求："CMCC 要求不要出现 DM 字样，请修改 `res/string.xml` 中的 `app_name`，例如 `CTM`" | 同上 | A |
| DM 客户端要求**开机自启且不许被省电策略干扰** | 联通手册原文："若厂商终端内置安全管理应用程序，请不要阻止自注册客户端（包名为 `com.mobiletools.systemhelper`）的开机启动行为""请不要将其唤醒对齐" | [CSDN《中国联通自注册适配包手册》](https://blog.csdn.net/wds1181977/article/details/74408008) | A |
| 平台方案商预置路径 | `vendor/sprd/operator/cucc/prebuild/app/SystemHelper_debug.apk`（展锐），MTK 平台则有 `system/app/MediatekDM.apk`、`SmsReg.apk` | [16rd](https://bbs.16rd.com/thread-583828-1-1.html)、[mweda](http://ee.mweda.com/ask/245724.html) | A/B |
| 自注册必须上报 IMEI | 移动规范：第一次开机必须把 IMEI 及其他基础信息以数据方式发到服务器，"服务器负责解析此 HTTP 消息" | [CSDN《android 平台下移动 DM 接入流程》](https://blog.csdn.net/u011694328/article/details/87881501) | A |
| 定制信息写入独立分区 | 专利 CN108153558B：厂商为不同运营商做定制机，把运营商定制信息搬移到数据分区 | [专利 PDF](https://patentimages.storage.googleapis.com/28/ce/66/0995845a670284/CN108153558B.pdf) | A |

**结论**：
1. **"运营商定制分区预装 DM 客户端"是三大运营商共有的入库规范要求**，不是小米或某一家方案商的私货。
2. 因此**任何一台走运营商渠道出厂的手机，都可能带一个同类组件**——OPPO/vivo/荣耀/华为/三星国行的定制版都跑不掉，只是包名和签名随方案商变。
3. **真正该被质疑的不是"有没有"，而是三点**：① 是否走**明文 HTTP**（小米样本走了，这是硬伤）；② 采集范围是否**超出规范要求**（规范只要求 IMEI 等基础信息，不要求应用列表/录屏）；③ 是否**可关闭/可卸载**（手册明确要求不许阻止它自启，等于出厂就锁死了）。

---

## 6. 待实测确认清单（下一轮真机要补的洞）

按优先级排序，这些是本次调研**没能坐实、必须靠设备验证**的：

| # | 待确认项 | 验证方法 | 优先级 |
|---|---|---|---|
| 1 | 三星国行到底哪个包在枚举应用列表 | `adb shell dumpsys package` 全量扫含 `GET_APP_LIST` 的包 | 高 |
| 2 | 荣耀 `com.hihonor.phoneservice` 的 `applist` vendor 权限是否真的被授予、谁在用 | `dumpsys package com.hihonor.phoneservice \| findstr applist` | 高 |
| 3 | `com.vivo.abe` 是否真向 `vivo.com.cn` 上报应用列表（目前只有权限证据） | 抓包 + 反编译 | 高 |
| 4 | 移动/电信 DM 平台的真实域名与端口（`dm.wo.com.cn` 是联通已实锤） | 抓包观察 /register 请求目标 | 高 |
| 5 | OPPO `com.oplus.statistics.rom` 是否有录屏能力 | 查 `CAPTURE_VIDEO_OUTPUT` 与实际 MediaProjection 调用 | 中 |
| 6 | 各家是否也存在"插 A 卡注册到 B 运营商"的错配 | 对比 `/vendor/operator/` 分区代号与当前 SIM 卡 MCC/MNC | 中 |
| 7 | `com.miui.dmregservice` 回连目标 | 抓包 | 中 |

---

## 7. 一句话回答「还有哪些厂商有类似东西」

> **运营商渠道定制预装的 DM 客户端这条线，是三大运营商入库规范的普遍要求，跨品牌存在**（证据为运营商官方手册，A 级）；
>  **厂商自研的"应用列表上报"这类反诈/安全组件，小米、OPPO、vivo、荣耀都有对应能力**（证据为权限清单 + 部分实测，B/C 级），但**只有小米被公开逆向到具体实现与端点**；
>  **明文 HTTP 传设备标识这一档，目前只有小米 SystemHelper 样本被实锤**，其他厂商的遥测基本走 HTTPS（C 级学术观测）；
>  **"720x1280 录屏上传做风控"目前是小米样本独有**，其他厂商**未见证据**，相关包名一律「待实测确认」。

---

## 附：来源汇总

| # | 来源 | 类型 | 链接 |
|---|---|---|---|
| 1 | AntiAntiDefraud（MIUI 上传应用列表的实现分析） | B | https://github.com/MinaMichita/AntiAntiDefraud |
| 2 | NGA 实测帖（guardprovider 回传 157.148.47.204） | B/D | https://ngabbs.com/read.php?tid=35273994 |
| 3 | 中国联通《Android 终端 DM 适配使用指南》（16rd 转载） | A | https://bbs.16rd.com/thread-583828-1-1.html |
| 4 | 中国移动《Android 手机终端 DM 适配使用指南》（16rd 转载） | A | https://bbs.16rd.com/thread-581669-1-1.html |
| 5 | CMCC 移动 DM 自注册适配指南（含 app_name 改名要求） | A | https://blog.csdn.net/wds1181977/article/details/65442760 |
| 6 | 中国联通自注册适配包手册（明写 `com.mobiletools.systemhelper` 不许阻止自启） | A | https://blog.csdn.net/wds1181977/article/details/74408008 |
| 7 | APKMirror：SystemHelper by Xiaomi Inc. | B | https://www.apkmirror.com/apk/xiaomi-inc/systemhelper-3/ |
| 8 | memeosupdates：`com.mobiletools.systemhelper` = MediaTek Modem Helper | D | https://memeosupdates.com/apps/com.mobiletools.systemhelper/31 |
| 9 | 关于 dmregservice（CMCC DM SDK 说明） | B | https://blog.thris.me/archives/regservice.html |
| 10 | sysapps.bayton.org：`com.oplus.statistics.rom` 权限全表 | B | https://sysapps.bayton.org/packages/com.oplus.statistics.rom |
| 11 | sysapps.bayton.org：`com.vivo.abe` 权限全表 | B | https://sysapps.bayton.org/packages/com.vivo.abe |
| 12 | Exodus Privacy：`com.coloros.phonemanager` v15.12.0（55 权限/13 tracker） | B | https://reports.exodus-privacy.eu.org/en/reports/522483/ |
| 13 | Exodus Privacy：`com.hihonor.phoneservice` v10.0.7.245（53 权限/1 tracker） | B | https://reports.exodus-privacy.eu.org/en/reports/420433/ |
| 14 | 璃火牙：屏蔽 ColorOS 第三方安装云端检测（3 个端点） | B | https://lihvarya.com/%e5%a4%ba%e5%9b%9e%e8%ae%be%e5%a4%87%e6%8e%a7%e5%88%b6%e6%9d%83%ef%bc%9a%e6%97%a0%e6%84%9f%e5%b1%8f%e8%94%bd-oppo-coloros-%e7%ac%ac%e4%b8%89%e6%96%b9%e5%ba%94%e7%94%a8%e5%ae%89%e8%a3%85%e4%ba%91/ |
| 15 | 璃火牙：屏蔽 iQOO/OriginOS 云端检测（`com.iqoo.secure` 等） | B | https://lihvarya.com/%e5%a4%ba%e5%9b%9e%e8%ae%be%e5%a4%87%e6%8e%a7%e5%88%b6%e6%9d%83%ef%bc%88%e4%ba%8c%ef%bc%89%ef%bc%9a%e5%b1%8f%e8%94%bd-iqoo-originos-%e7%ac%ac%e4%b8%89%e6%96%b9%e5%ba%94%e7%94%a8%e5%ae%89%e8%a3%85/ |
| 16 | Liu/Leith/Patras (2023) 学位论文 | C | https://era.ed.ac.uk/bitstream/handle/1842/41248/LiuH_2023.pdf?sequence=1 |
| 17 | 《On the data privacy practices of Android OEMs》(PLoS ONE) | C | https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0279942 |
| 18 | 爱丁堡组补充材料（`tracking.intl.miui.com` 行为说明） | C | https://www.scss.tcd.ie/doug.leith/pubs/additional_material_neversleepingears.pdf |
| 19 | ACL4SSR MIUIPrivacy.list（小米遥测域名） | D | https://git.moezx.cc/mashiro/ACL4SSR/src/commit/87e5ff73f6a82a5dcd8ed47c870a7af1d371adb7/Clash/Ruleset/MIUIPrivacy.list |
| 20 | 三星 `com.samsung.android.permission.GET_APP_LIST` 实测 | B | https://ewt45.github.io/blog/26-10-14-samsung-query-all-packages/index/ |
| 21 | 盖乐世社区：One UI 9.0 国行版特点 | D | https://www.samsungmembers.cn/thread-4120644-29-180.html |
| 22 | UAD 项目：`com.oplus.statistics.rom` 行为标注 | B | https://github.com/0x192/universal-android-debloater/issues/306 |
| 23 | CSDN：android 平台下移动 DM 接入流程（IMEI 以 HTTP 上报） | A | https://blog.csdn.net/u011694328/article/details/87881501 |
| 24 | 专利 CN108153558B：运营商定制信息写入独立分区 | A | https://patentimages.storage.googleapis.com/28/ce/66/0995845a670284/CN108153558B.pdf |
| 25 | mweda：CMCC 要求送测时关闭 DM/SMSReg（`MediatekDM.apk`、`SmsReg.apk` 路径） | B | http://ee.mweda.com/ask/245724.html |
