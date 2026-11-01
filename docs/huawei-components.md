# 华为 / HarmonyOS 侧「隐蔽上报 / 采集」组件对照调研

> 调研对象：华为 **JER-AN10**（= **nova 7 Pro 5G**，2020 年 4 月上市），系统 HarmonyOS 4.x / EMUI（基于 AOSP 兼容层，能用 adb、应用包是 `.apk`）。
> 对照基线：小米「系统安全组件」`com.miui.guardprovider` + `SystemHelper` `com.mobiletools.systemhelper`（平台签名 priv-app，回连 `http://dm.wo.com.cn:18080/register` 明文 HTTP，采 IMEI/IMSI/ICCID + 应用列表 + 后台定位 + 双 ELAPSED_WAKEUP 常驻闹钟 + 720x1280 录屏 Base64 上传云端）。
>
> **可信度分级**（全文统一使用）：
> - 【官方】已读厂商官方文档 / 官方隐私声明 / 官方帮助页
> - 【实测】已读第三方实测、可复现的命令输出、卸载日志
> - 【传闻】仅社区帖子 / 论坛讨论，未见原始证据
> - 【待实测】没有可靠来源，必须在真机上验证后才能写结论
>
> **本文不臆造任何包名。** 凡未找到出处的，一律写「待实测确认」。

---

## 0. 一句话结论（先给非专业读者）

华为手机**确实会上报「已安装应用列表」**，但和小米那个 SystemHelper 有本质区别：

| 维度 | 小米 SystemHelper（已确认样本） | 华为（本次调研结论） |
|---|---|---|
| 应用列表上报 | 未公开披露，藏在平台签名 priv-app 里 | **官方隐私声明里明写**，会在隐私政策里披露 |
| 回连运营商 DM 平台 | 有（`dm.wo.com.cn` 明文 HTTP） | **未找到证据**；仅运营商定制机上可能预装 DM 客户端适配，需按渠道核对 |
| 采集 IMEI/IMSI/ICCID | 有 | 官方只披露 **IMSI**（本地读取，用于流量统计/骚扰拦截）；IMEI/ICCID **未见披露，待实测确认** |
| 后台录屏 → 上传云端 → 等风险回执 | 有（720x1280 24fps） | **未发现任何证据**。华为反而有「三方应用录屏必须弹窗授权」的强制设计 |
| 隐蔽性 | 高（名字叫 SystemHelper，普通用户看不出） | 中低（组件名就是「手机管家」「HMS Core」，隐私声明可查） |

**最需要实测确认的三个点**（本文档第 5 节给了命令）：
1. `com.huawei.hiview` / `com.huawei.hiviewtunnel` 这两个日志采集通道到底传了什么（【传闻】级，最不透明）。
2. 你这台 JER-AN10 是不是**运营商定制机**（联通/移动/电信渠道版）。定制机才会额外带运营商 DM 客户端。
3. 手机管家「华为云同步系统配置」上传的「设备标识符 + 应用名称」具体是哪些字段。

---

## 1. 华为侧系统组件对照表

### 1.1 A 类：官方已披露会碰「应用列表」的组件（重点看这张）

| 组件名(用户可见) | 实际包名 | 位置 / 签名 | 是否上报应用列表 | 设备标识(IMEI/IMSI/ICCID) | 录屏 | 后台常驻/上报 | 证据与可信度 |
|---|---|---|---|---|---|---|---|
| 手机管家 | `com.huawei.systemmanager` | `/system/priv-app/HwSystemManager`，**预装系统应用**（平台签名未逐一验证，待实测） | **是**（本地读取；「全部服务模式」下部分数据上云） | 官方声明读到 **IMSI**（流量管理、骚扰拦截，本地）；**IMEI/ICCID 未披露** → 待实测 | 无证据 | 是（开机自启；WLAN 下自动更新病毒库/策略） | 【官方】[手机管家隐私声明](https://h5hosting-drcn.dbankcdn.cn/cch5/sysmgr/appmarket_2xx/default/privacy-statement.htm)；【实测】卸载/路径报告 [UAD issue #410](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation/issues/410) |
| HMS Core（华为移动服务） | `com.huawei.hwid` | 预装系统应用 | **是**，且是**官方明写**：「为了保证您安装的应用安全地使用 HMS Core，我们会收集您的设备信息、**已安装应用程序清单**和应用程序使用情况，用于进行定期的安全检查」 | 装置识别码（官方称不可关联身份）；**无 IMEI/ICCID 披露** → 待实测 | 无证据 | 是（官方称「HMS Core 会在设备中自动启动，以确保为设备提供安全的服务保障」） | 【官方】[HMS Core 隐私声明](https://privacy-drcn.dbankcdn.cn/agreement/scope/huawei/hms-core/privacy-statement/cn_b0_20251223_0/default/privacy-statement-zh-hk.htm)（原文「读取已安装应用程序清单权限」章节） |
| 华为应用市场 | `com.huawei.appmarket` | 预装系统应用 | **是**，官方原文：「我们会收集您的个人信息，同时会**读取并传送已安装应用列表**」（含通过其他商店安装的应用） | 设备标识符、系统设置信息 | 无证据 | 是 | 【官方】[应用市场隐私声明](http://privacy-dre.dbankcdn.com/agreement/scope/huawei/hiapp/privacy-statement/un_b1_20231220_2/default/privacy-statement-zh-cn.htm) |
| 智慧助手 / 华为助手 | `com.huawei.hisuite`（助手类） | 预装 | 是（收集清单含「已安装应用列表、终端使用信息、OAID、设备标识符」） | 设备标识符、OAID | 无证据 | 是 | 【官方】[收集个人信息清单摘要](https://privacy-dra.dbankcdn.com/agreement/scope/huawei/huawei-assistant/privacy-statement/cn_b100_20260120_0/di/privacy-statement-zh-cn.htm) |
| 智慧搜索 | `com.huawei.search`（旧机型 label 为「主页下拉搜索功能」） | 预装 | 官方称「已安装应用列表、本地应用使用信息」**在设备端侧处理，不上传服务器**（需实测验证是否真如此） | — | — | — | 【官方】[搜索隐私声明明示清单](https://privacy-drcn.dbankcdn.cn/agreement/scope/huawei/hisearch/privacy-statement/cn_b0_20230912_0/di/privacy-statement-zh-cn.htm)；包名【实测】[预装包名表](https://github.com/ncov4777/adb-uninstalls-Huawei-phone-pre-installed-apps/blob/9cd64b1a32b1775ca9c2260bfce5e5612427aa76/README.md) |

> **关键判读**：华为的做法是「**明着来**」——应用列表采集写进了隐私声明，可以在设置里查、可以关（部分）。小米 SystemHelper 的问题是「**没告诉你、还起了个看不出身份的名字**」。这两者性质不同，但**采集范围本身并不小**，值得关注。

### 1.2 B 类：日志 / 遥测通道（最不透明，重点实测对象）

| 组件名(用户可见) | 实际包名 | 位置 | 已知行为 | 证据与可信度 |
|---|---|---|---|---|
| hiview（日志服务） | `com.huawei.hiview` | 系统应用，可在「应用管理 → 显示系统程序」中搜到 | 日志采集与上传；社区反馈**禁用后会自行恢复运行** | 【实测】[EMUI/HarmonyOS 无日志解决方法（掘金）](https://juejin.cn/post/7332293353197551650)（给出 `adb shell pm enable com.huawei.hiview`）；【传闻】[贴吧讨论：禁用后仍在运行](https://tieba.baidu.com/p/6402053040) |
| HiViewTunnel（日志通道） | `com.huawei.hiviewtunnel` | 系统应用 | 与 hiview 配对，负责把日志送出设备；**具体上传字段、是否含应用列表：待实测确认** | 【实测】同上掘金文；【传闻】[知乎问答](https://www.zhihu.com/question/477545558) |
| 系统更新 | `com.huawei.android.hwouc` | 预装 | 版本查询/升级；不涉及应用列表 | 【实测】[预装包名表](https://github.com/ncov4777/adb-uninstalls-Huawei-phone-pre-installed-apps/blob/9cd64b1a32b1775ca9c2260bfce5e5612427aa76/README.md)；HUAWEI OUC 在华为企业文档中被描述为预置了 HiAnalytics 打点域名（见第 2 节） |
| 推送服务 | `com.huawei.android.pushagent` | 预装 | 推送通道；官方声明收集装置识别码、Push Token、OAID | 【实测】包名同上；【官方】HMS Core 隐私声明「讯息通知」章节 |
| 用户体验改进计划 | 无独立包名（系统设置开关：设置 → 系统和更新 → 用户体验改进计划） | 系统设置项 | 开启后收集「位置信息、网络信息、设备信息、应用信息」；社区有「每天自动上传大量数据」的抱怨 | 【官方】[IdeaHub 售后文档 6.2.5 用户体验改进计划](https://e.huawei.com/marketingcloud/pep/asset/20000001/Material/a8a34599c4b042d4aa12ad6eb52a379d/M3T1A669N1102191437049520286/IdeaHub%20Board%203%20Pro24_0_0-%E5%94%AE%E5%90%8E%E6%96%87%E6%A1%A3_25H1_.pdf)（同源表述）；【传闻】[华为开发者问答帖](https://developer.huawei.com/consumer/cn/forum/topic/0202569890390950917) |

### 1.3 C 类：安全 / 权限 / 优化类系统组件（有权限、但目前无「上报应用列表」直接证据）

以下全部来自【实测】报告 [UAD issue #410（Mate 20 X 升 HarmonyOS 4 实测卸载）](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation/issues/410)，包名与行为描述为该帖原文，**非臆造**：

| 包名 | 该帖记录的用途 | 与「隐蔽上报」的关系 |
|---|---|---|
| `com.huawei.security.privacycenter` | 权限管理器（Permission Manager）依赖它 | 载体，非采集者 |
| `com.huawei.securitymgr` | 密码保险箱 / 密码管理器 | — |
| `com.huawei.securityserver` | 人脸解锁依赖 | — |
| `com.huawei.systemserver` | 指纹机型的 dark-framework 组件 | 权限等级高，**待实测确认**其网络行为 |
| `com.huawei.iaware` / `com.huawei.powergenie` | 系统调度 / 省电；卸载会卡顿、日志报 `PowerKit: PG Server is not found` | 会**读取**应用行为做调度，**未见上传证据** |
| `com.huawei.hwaps` | 分辨率调度 | — |
| `com.huawei.controlcenter` | 超级终端 / Device+ | — |
| `com.huawei.harmonyos.foundation` | 设置与 APK 安装依赖 | — |
| `com.huawei.hwstartupguide` / `com.huawei.pcassistant` | 开机向导 / 电脑助手（只能停用不能卸载） | — |
| `com.huawei.nearby` / `com.huawei.coauthservice` / `com.huawei.arengine.service` | 近场、协同认证、AR | 均需多项权限 |
| `com.huawei.ohos.*`（服务卡片系列） | 服务卡片运行支撑 | — |

> 说明：这些包**不是**「华为版 SystemHelper」。它们没有公开证据表明在录屏、或回连运营商 DM 平台。列出来是为了让你在 `pm list packages` 输出里认得它们，别误判。

### 1.4 D 类：运营商定制渠道组件（最接近小米 SystemHelper 的那一类）

**机制上华为和小米面对的是同一个东西**：三大运营商的「终端管理（DM / 自注册）」规范，要求厂商在定制机里预装运营商提供的 DM 客户端，开机常驻、定期读设备信息上报。中国联通的自注册方案是「厂商提出适配申请 → 运营商审批 → **运营商提供自注册 APK 给终端厂商集成**」。这正好解释了小米 SystemHelper 为什么会回连 `dm.wo.com.cn`。

- 【实测/技术文档】[国内运营商 DM 功能介绍（CSDN）](https://blog.csdn.net/weixin_51894735/article/details/130157167)：「中国联通的 DM 自注册方案……会提供自注册 APK 给终端厂商集成」
- 【技术文档】[中国联通 Android 终端 DM 适配使用指南（转载帖）](https://bbs.16rd.com/forum.php?mod=viewthread&tid=583828)
- 【官方】华为官方帮助页确认存在「定制机」这一分类：[在华为手机或平板中找不到应用市场](https://consumer.huawei.com/cn/support/content/zh-cn00445301/) —「手机/平板型号为**定制机**未预装，预装的是**运营商提供的应用市场**」

**华为早期联通定制机的运营商预装应用**（【实测】当年评测文章，注意这些是**用户可见的营业厅类 App**，不是隐藏系统组件）：
[华为荣耀+ U8950D 评测（搜狐）](http://digi.it.sohu.com/20121022/n355426343_5.shtml)、[华为 G520 评测（天极）](https://mobile.yesky.com/162/34526662_6.shtml) 记录预装「沃·3G」「沃商店」「手机营业厅」「沃阅读」「116114」。

**结论与红线**：
> - 华为侧**是否存在**与 `com.mobiletools.systemhelper` 对等的隐藏 DM 组件 → **待实测确认**。
> - 证据链上只找到「机制存在 + 评测文章列过运营商 App」，**没有任何一篇给出华为 DM 组件的包名**。此处**不填包名**。
> - 唯一线索（【传闻】，未验证）：XDA 有帖子提到华为系统应用会读取 `autoInstallAPK.xml`，按 MCC/MNC 安装/卸载运营商应用——但该帖无法访问，**不作为结论**，仅留给实测时留意 `autoInstallAPK.xml` 这个文件名。

---

## 2. 华为系遥测 / 统计端点域名

> 用途说明：这些是**排查时该认得的域名**。看见手机连这些域名不等于被监控，它们大多是华为云的正常遥测/日志/帐号服务。真正需要警觉的是**明文 HTTP + 运营商 DM 网段**那类（见 2.3）。

### 2.1 日志 / 打点类（HiAnalytics / hiview log service）

来源：华为企业文档《Message service of HUAWEI CLOUD WeLink》附带的域名清单（[PDF 转存](https://www.product.network/pdfviewer?url=https%3A%2F%2Fwww.product.network%2Fdatasheet%2Fhuaweienterprises%2FEDOC1100489554.pdf)），标注为 **hiview log service addresses** 与 **HiAnalytics 打点域名**。【官方文档（企业侧）】

| 域名 | 用途 | 协议 |
|---|---|---|
| `logservice.hicloud.com` | hiview 日志服务 | **HTTPS**（清单原文为 `https://`） |
| `logservice1.hicloud.com` | 日志服务备用 | HTTPS |
| `logservice.vmall.com` | 日志服务（商城侧） | HTTPS |
| `logbak.hicloud.com` | 日志备份 | HTTPS（【传闻】来源为开源过滤规则集，见下） |
| `logserver.nzxcloud.cn` | 日志服务（第三方域名） | HTTPS |
| `logservice-dra.platform.hicloud.com` / `logservice-dre.platform.hicloud.com` / `logservice-drru.dt.hicloud.com` | 分区域日志服务 | HTTPS |
| `metrics.dt.hicloud.com:6447` | HiAnalytics 打点（**预置在 HwOUC 即系统更新里**，原文 "HiAnalytics data dotting domain name preset in HwOUC"） | HTTPS（6447 端口） |
| `metrics1-drcn.dt.dbankcloud.cn` / `metrics-dra.dt.dbankcloud.cn` / `metrics-dre.dt.dbankcloud.cn` | 分区域 HiAnalytics 打点 | HTTPS |
| `metrics.data.hicloud.com` / `metrics5.data.hicloud.com` | 打点备用域 | HTTPS |
| `nebula-collector.huawei.com` | 采集器 | HTTPS |
| `rnd-aresocean-commercial.huawei.com` / `rnd-cbgpas01.huawei.com` | 广告/运营打点（被开源广告过滤列表列为 Huawei Log Service 相关） | HTTPS |

辅助来源（【传闻】/开源规则，用于交叉验证域名真实性）：
[BadBlock 提交记录](https://codeberg.org/celenity/BadBlock/commit/12a5217e2b8ef64eff908e4201d1ef77bb2c4cd7)、[adblocksmartdnslite.conf](https://raw.githubusercontent.com/Aethersailor/adblockfilters-modified/main/rules/adblocksmartdnslite.conf)、[netify: metrics1-drcn.dt.dbankcloud.cn](https://www.netify.ai/resources/hostnames/metrics1-drcn.dt.dbankcloud.cn)。

### 2.2 帐号 / 基础服务类

| 域名 | 用途 | 协议 | 来源 |
|---|---|---|---|
| `hwid.platform.hicloud.com` / `hwid-drcn.platform.hicloud.com` / `hwid-dra.platform.hicloud.com` / `hwid-dre.platform.hicloud.com` | 华为帐号服务 | **HTTPS**（官方发过 TLS1.0/1.1 关闭通知，证明走 TLS） | 【官方】[华为帐号相关域名的 TLS 关闭通知](https://developer.huawei.com/consumer/cn/doc/hmscore-common-Guides/account-tls-0000001771717837) |
| `login.cloud.huawei.com` / `account.cloud.huawei.com` | 帐号登录 | HTTPS | 同上 / 企业文档 |
| `ping5.hicloud.com`、`query.hicloud.com` | 具体用途**未查证到一手来源** | **待实测确认** | 线索来自团队内部情报，本文未找到官方出处，**不作结论** |

### 2.3 明文 HTTP 端点（这是唯一确认「不走 TLS」的华为域名）

| 端点 | 用途 | 协议 | 是否敏感 | 来源 |
|---|---|---|---|---|
| `http://connectivitycheck.platform.hicloud.com/generate_204` | 网络连通性探测 / 强制门户（Captive Portal）检测，判断「有没有网、要不要弹认证页」 | **明文 HTTP** | **不敏感**：只请求一个空 204，不带设备信息。但它是华为手机上**唯一会常态出现的明文 HTTP 请求**，排查时别把它当嫌疑 | 【实测】[UA3F 配置示例](https://cdn.jsdelivr.net/gh/SunBK201/UA3F@3.6.0/configs/clash/ua3f-socks5-global.yaml)（`url: http://connectivitycheck.platform.hicloud.com/generate_204`）；[各平台 Wi-Fi 认证地址汇总](https://hky.moe/archives/291/)；[urlscan 抓包记录](https://urlscan.io/result/019d9c03-7c03-76fc-8905-604326afbced/) |
| `connectivitycheck.platform.dbankcloud.com` | 同上（备用） | 主要 HTTPS | 不敏感 | 华为企业文档域名清单 |
| `connectivitycheck.cbg-app.huawei.com.cn` | Portal 认证页跳转 | — | 不敏感 | 【实测】[新华三 KMS 问答：华为手机 Portal 弹出页面](https://kms.h3c.com/questions/dispcont/280554) |

**重要对照**：小米 SystemHelper 用的是 `http://dm.wo.com.cn:18080/register` —— **明文 HTTP + 提交 IMEI/IMSI/ICCID**，这是真正的问题点。**华为侧未找到任何等价的「明文 HTTP + 上传设备标识」端点。**

---

## 3. 鸿蒙版本差异：哪些排查手法在 HarmonyOS NEXT 上直接作废

| 维度 | HarmonyOS 1.0 ~ 4.x（**你的 JER-AN10 属于这一档**） | HarmonyOS NEXT / 5.x（纯血鸿蒙） |
|---|---|---|
| 内核与兼容层 | OpenHarmony + **AOSP 兼容层**，双运行环境；能装 APK | 单框架，**不兼容 APK，只装 HAP**；不再使用 Linux 内核 |
| 调试通道 | **adb**（`adb shell pm list packages`、`dumpsys` 全可用） | adb 失效，必须用 **hdc**（HarmonyOS Device Connector） |
| 列已装应用 | `adb shell pm list packages -f -U` | `hdc shell bm dump -a`（只有包名，**拿不到 apk 路径**） |
| 看权限详情 | `adb shell dumpsys package <pkg>` | **无等价命令**（`dumpsys` 在 NEXT 无对应）；`bm dump -n <pkg>` 能看部分信息 |
| 看闹钟/常驻服务 | `adb shell dumpsys alarm` / `dumpsys activity services` | **无等价命令** |
| 看日志 | `adb logcat` | `hilog` 体系 |
| 读 `/system/priv-app` 等系统目录 | 可（`ls` 即可，能否读取看 SELinux） | **不行**。`hdc shell` 权限限制极严，访问不了系统大部分路径；即便有 root 也不提供 |
| 读第三方应用私有目录 | 可（部分机型 `run-as`） | **不行**。需要 `system_basic` 级系统权限 `ohos.permission.ACCESS_BUNDLE_DIR`；`/data/local/tmp` 中转法**已被新版本封禁** |
| root | 受限 | **官方明确不提供 root/越狱能力** |
| 权限模型 | Android 运行时权限 + 华为平台签名权限 | **AccessToken（`ohos.permission.*`）** + 应用沙箱，按 system_grant/user_grant + APL 等级（normal/system_basic/system_core）分级 |
| 应用完整性 | APK 签名 | HAP 签名 + 系统预置公钥证书验签 |

**来源**
- 【官方】[鸿蒙系统与 AOSP 的关系（华为开发者博客）](https://developer.huawei.com/consumer/cn/blog/topic/03220729367578049)：HarmonyOS 1.0~4.x 手机端为「过渡兼容版」，引入 AOSP 是为了兼容存量 APK。
- 【官方】[hdc 调试命令文档](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/hdc)、[如何获取应用包及项目配置项信息](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-ability-162)（给出 `hdc shell bm dump -a`）。
- 【实测】[wrlu/HarmonyOS-Tools README](https://github.com/wrlu/HarmonyOS-Tools)：原文「华为对 hdc shell 的权限限制极为严格，并不能访问系统大部分文件路径的内容，所以无法像 Android 手机一样通过 adb shell 来获取文件」「之前先复制到 `/data/local/tmp` 然后再 recv 的方法在新版本已经被华为封禁」。
- 【官方】[hdc 执行 shell 命令权限问题（华为开发者问答）](https://developer.huawei.com/consumer/cn/forum/topic/0204169991606354002)：「当前 HarmonyOS NEXT 暂时无法提供 root、越狱权限相关能力」，用 `$` / `#` 区分普通用户与 root。
- 【实测】[从 ADB 到 HDC 迁移指南（命令对照表）](https://blog.csdn.net/gold8/article/details/153242166)、[鸿蒙踩坑：hdc 命令差异](https://ost.51cto.com/posts/55925)。

**对你机器的直接影响**：JER-AN10（nova 7 Pro 5G）最高升到 **HarmonyOS 4.2**，不在 HarmonyOS 5 / NEXT 适配名单内（【实测】[华为开发者问答](https://developer.huawei.com/consumer/cn/forum/topic/0203226425679752762)；【实测】[IT之家：nova 7 Pro 5G 于 2023-09 开放 HarmonyOS 4 正式版](https://m.ithome.com/html/718610.htm)）。
→ **好消息：本文档第 5 节的 adb 排查手法对你 100% 可用**，不会遇到 NEXT 的 hdc 限制。

---

## 4. 反诈场景：哪些是第三方 App，哪些是系统预装

这一节要分清三个**完全不同**的东西，混为一谈就会得出错误结论。

| 东西 | 是什么 | 包名 | 预装还是安装 | 来源与可信度 |
|---|---|---|---|---|
| 「国家反诈中心」App | **第三方 App**，公安部刑事侦查局出品，从应用商店下载安装 | `com.hicorenational.antifraud` | **不是系统预装**，用户自己装；可在应用市场卸载 | 【实测】[小米应用商店页面](https://app.mi.com/details?id=com.hicorenational.antifraud)；【官方】[中国长安网：公安部刑事侦查局出品](http://chinapeace.gov.cn/chinapeace/c100007/2021-07/04/content_12506240.shtml) |
| 华为「一键智能防诈 / 星盾防诈 / 亲情防诈」 | **系统内置功能**（在设置 / 手机管家里，不是独立 App） | **无独立包名**（是系统设置项与管家模块） | 系统内置 | 【官方】[一键开启星盾防诈](https://consumer.huawei.com/cn/support/content/zh-cn16104383/)、[一键智能防诈](https://consumer.huawei.com/cn/support/content/zh-cn16090799/)、[亲情防诈](https://consumer.huawei.com/cn/support/content/zh-cn16093693/) |
| 华为「风险应用拦截 / 纯净模式」 | **系统内置策略**（云端黑名单 + 安装管控） | 无独立包名 | 系统内置 | 【官方】[纯净模式官方问答](https://developer.huawei.com/consumer/cn/forum/topic/0214202917493369228)（「开启后仅支持安装经华为应用市场安全检测的应用」）；【实测】[V2EX 实测帖：未装反诈 App 也收到拦截弹窗](https://global.v2ex.co/t/1166451) |

**关于「警方要求卸载 X / Telegram」这类场景，准确的说法是：**
- 它**不是**靠「装了个国家反诈中心 App」实现的——你的机器（2020 年 nova 7 Pro）出厂时根本没有它。
- 真正起作用的是**系统内置的纯净模式 / 风险应用拦截**：安装或启动时命中华为云端黑名单 → 弹窗提示卸载或拦截启动。
- 纯血鸿蒙上这套机制是**强制生效、不可关闭**的（【实测】[华为开发者问答：HarmonyOS 3.0 起纯净模式默认开启](https://developer.huawei.com/consumer/cn/forum/topic/0202182617413976016)）。HarmonyOS 4.x 上「增强防护」可以关闭，但主开关在。
- 法律依据被引用为《反电信网络诈骗法》第 23 条、第 41 条第（五）项（【传闻】V2EX 用户引用，未核对法条原文）。

> **不要写错的一句话**：华为**没有预装** `com.hicorenational.antifraud`。网上「国产手机都内置反诈 App」的说法，混淆了「预装 App」和「系统内置拦截策略」。

---

## 5. 自查方法（JER-AN10 直接可用，adb 全程有效）

> 完整的自动化脚本见 `scripts/audit_android.ps1`（由本团队另一路交付）。这里只给手工核对的判据。

```powershell
# 0) 连上手机
adb devices

# 1) 导全量应用清单（含 apk 路径，用于判断是否 priv-app）
adb shell pm list packages -f -U > allpackages.txt

# 2) 找 priv-app / 平台签名位置（这是小米 SystemHelper 的藏身处）
Select-String -Path allpackages.txt -Pattern "/system/priv-app|/system/app|/vendor/app|/preload|/product/app"

# 3) 找运营商 DM 痕迹（小米样本的关键特征）
Select-String -Path allpackages.txt -Pattern "mobiletools|systemhelper|guardprovider|\.dm\.|DMClient|Sinova|unicom|cmcc|ctcc"

# 4) 看具体包权限（判断是否同时要 IMEI+应用列表+定位+闹钟）
adb shell dumpsys package com.huawei.systemmanager > sysmgr.txt
adb shell dumpsys package com.huawei.hwid         > hwid.txt
# 重点搜：READ_PRIVILEGED_PHONE_STATE / READ_PHONE_STATE / QUERY_ALL_PACKAGES
#         PACKAGE_USAGE_STATS / ACCESS_FINE_LOCATION / RECEIVE_BOOT_COMPLETED

# 5) 找双 ELAPSED_WAKEUP 常驻闹钟（小米 SystemHelper 的核心特征）
adb shell dumpsys alarm > alarm.txt
Select-String -Path alarm.txt -Pattern "ELAPSED_WAKEUP" -Context 2,6

# 6) 找常驻服务
adb shell dumpsys activity services > svc.txt

# 7) 看这两条日志通道是否在跑（最需要人工确认的一步）
adb shell dumpsys activity services | Select-String "hiview|hiviewtunnel"
```

**判据清单（对照小米样本，逐条打勾）**

| 判据 | 小米 SystemHelper | 华为侧本次观察 |
|---|---|---|
| 包名伪装成通用名（mobiletools.systemhelper） | 是 | **未见**；华为组件名与功能一致 |
| 位于 `/system/priv-app/` 且平台签名 | 是 | 手机管家在 `/system/priv-app/HwSystemManager`【实测】；平台签名待实测 |
| 同时持有 IMEI + 应用列表 + 后台定位 | 是 | 应用列表有、IMSI 有（本地）；IMEI+定位组合**待实测** |
| 双 ELAPSED_WAKEUP 闹钟常驻 | 是 | **待实测** |
| 明文 HTTP 回连运营商 DM（dm.wo.com.cn） | 是 | **未找到** |
| 后台录屏并上传 | 是 | **未发现任何证据** |
| 隐私政策里明写 | 否 | **是**（HMS Core / 手机管家 / 应用市场三份声明） |

---

## 6. 遗留问题清单（这些必须在真机上做完才能下结论）

| # | 待确认事项 | 怎么确认 | 当前状态 |
|---|---|---|---|
| 1 | JER-AN10 是否为运营商定制机 | 看包装盒/机身是否有运营商 logo；`adb shell getprop \| findstr -i "carrier\|channel\|op\."` | **待实测确认** |
| 2 | 是否存在华为版运营商 DM 客户端 | 第 5 节命令 3 的正则匹配结果 | **待实测确认** |
| 3 | `com.huawei.hiview` / `hiviewtunnel` 上传内容 | 抓包（`connectivitycheck` 之外看是否连 `logservice*.hicloud.com`）；或看 `dumpsys activity services` 中是否常驻 | **待实测确认** |
| 4 | 手机管家「华为云同步系统配置」上传字段 | 抓包看是否连 `metrics*.hicloud.com`；对比官方声明的「设备标识符 + 应用名称」 | **待实测确认** |
| 5 | 华为是否存在后台录屏组件 | 全量包搜索含 `screenrecord` / `capture` / `mediarecord` 的包；`dumpsys package` 查 `CAPTURE_VIDEO_OUTPUT` | **待实测确认**（目前无任何公开证据） |
| 6 | `query.hicloud.com`、`ping5.hicloud.com` 的真实用途 | 抓包时留意；查华为官方域名清单 | **待实测确认**（本文未找到一手来源） |
| 7 | 华为平台签名白名单 | 无法从用户侧确认（需 `aapt dump badging` + 比对系统证书） | **待实测确认** |

---

## 附录：本文档所有引用来源汇总

**官方文档 / 官方隐私声明**
1. [HMS Core 收集个人信息明示清单 / 隐私声明](https://privacy-drcn.dbankcdn.cn/agreement/scope/huawei/hms-core/privacy-statement/cn_b0_20251223_0/default/privacy-statement-zh-hk.htm) — 应用列表收集、安全检测、装置检查服务
2. [华为手机管家与隐私的声明](https://h5hosting-drcn.dbankcdn.cn/cch5/sysmgr/appmarket_2xx/default/privacy-statement.htm) — 病毒查杀/流量管理/安全策略管理的读取范围与上云条件
3. [华为应用市场与隐私的声明](http://privacy-dre.dbankcdn.com/agreement/scope/huawei/hiapp/privacy-statement/un_b1_20231220_2/default/privacy-statement-zh-cn.htm) — 「读取并传送已安装应用列表」
4. [智慧搜索隐私声明明示清单](https://privacy-drcn.dbankcdn.cn/agreement/scope/huawei/hisearch/privacy-statement/cn_b0_20230912_0/di/privacy-statement-zh-cn.htm) — 端侧处理声明
5. [华为助手收集个人信息清单](https://privacy-dra.dbankcdn.com/agreement/scope/huawei/huawei-assistant/privacy-statement/cn_b100_20260120_0/di/privacy-statement-zh-cn.htm)
6. [华为帐号相关域名的 TLS 关闭通知](https://developer.huawei.com/consumer/cn/doc/hmscore-common-Guides/account-tls-0000001771717837) — `hwid.platform.hicloud.com` 等
7. [鸿蒙系统与 AOSP 的关系（华为开发者博客）](https://developer.huawei.com/consumer/cn/blog/topic/03220729367578049)
8. [hdc 调试命令文档](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/hdc)、[获取应用包信息 FAQ](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-ability-162)
9. [hdc shell 权限问题（华为开发者问答）](https://developer.huawei.com/consumer/cn/forum/topic/0204169991606354002)
10. [纯净模式说明（华为开发者问答）](https://developer.huawei.com/consumer/cn/forum/topic/0214202917493369228)、[纯净模式默认开启](https://developer.huawei.com/consumer/cn/forum/topic/0202182617413976016)
11. [星盾防诈](https://consumer.huawei.com/cn/support/content/zh-cn16104383/)、[一键智能防诈](https://consumer.huawei.com/cn/support/content/zh-cn16090799/)、[亲情防诈](https://consumer.huawei.com/cn/support/content/zh-cn16093693/)
12. [定制机说明：找不到应用市场](https://consumer.huawei.com/cn/support/content/zh-cn00445301/)
13. [三方应用录屏必须弹窗授权](https://consumer.huawei.com/cn/support/content/zh-cn16002152/) — 反证「华为无后台静默录屏」
14. [Huawei 企业文档域名清单（WeLink / HwOUC HiAnalytics 打点）](https://www.product.network/pdfviewer?url=https%3A%2F%2Fwww.product.network%2Fdatasheet%2Fhuaweienterprises%2FEDOC1100489554.pdf)

**实测报告**
15. [UAD issue #410：HarmonyOS 4 卸载实测包名与后果](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation/issues/410)
16. [wrlu/HarmonyOS-Tools：hdc 权限限制实测](https://github.com/wrlu/HarmonyOS-Tools)
17. [华为预装包名表（adb 卸载实践）](https://github.com/ncov4777/adb-uninstalls-Huawei-phone-pre-installed-apps/blob/9cd64b1a32b1775ca9c2260bfce5e5612427aa76/README.md)
18. [阿里云：华为旧版 SDK 授权前收集应用列表的违规堆栈 `com.huawei.hwid`](https://help.aliyun.com/zh/document_detail/616139.html)
19. [hiview / hiviewtunnel 禁用与恢复实测](https://juejin.cn/post/7332293353197551650)
20. [connectivitycheck 明文 HTTP 端点](https://hky.moe/archives/291/)、[UA3F 配置](https://cdn.jsdelivr.net/gh/SunBK201/UA3F@3.6.0/configs/clash/ua3f-socks5-global.yaml)
21. [国内运营商 DM 机制（自注册 APK 由运营商提供）](https://blog.csdn.net/weixin_51894735/article/details/130157167)
22. [V2EX：华为未装反诈 App 也弹拦截提示（实测帖）](https://global.v2ex.co/t/1166451)
23. 机型印证：[JER-AN10 = nova 7 Pro 5G](https://product.suning.com/0000000000/12107233665.html)、[nova 7 Pro 5G 开放 HarmonyOS 4 正式版（IT之家）](https://m.ithome.com/html/718610.htm)、[不升 HarmonyOS 5（华为开发者问答）](https://developer.huawei.com/consumer/cn/forum/topic/0203226425679752762)

**社区传闻（仅作线索，未采信为结论）**
24. [贴吧：禁用 hiview 后仍自行运行](https://tieba.baidu.com/p/6402053040)
25. [知乎：com.huawei.hiviewtunnel 是干什么的](https://www.zhihu.com/question/477545558)
26. [华为开发者问答：体验改进计划每天上传数据](https://developer.huawei.com/consumer/cn/forum/topic/0202569890390950917)
27. [CN-SEC/CSDN：华为平台签名与 priv-app 关系（未作为结论）](https://bbs.huaweicloud.com/blogs/480650) — 原文要点：**「放在系统目录下不等于有系统签名，签名是编译打包阶段完成的，不是安装位置决定的」**，这一点对判断「平台签名」很关键

---

*文档版本：v1.0 ｜ 调研员：huawei-research ｜ 数据截止 2026-11-01*
*所有「待实测确认」项需在真机（JER-AN10）上按第 5 节命令核验后方可升级为结论。*
