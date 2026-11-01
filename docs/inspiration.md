# 灵感来源：两条推文

这个项目不是凭空冒出来的。起点是 2026 年 11 月 X（原 Twitter）上的两条推文。

本文原文照录，供追溯。

---

## 一、原始推文

### 1.1 @MEterminator666 的排查帖

- **账号**：MeTerminator666（显示名 MeT）
- **链接**：<https://x.com/MeTerminator666/status/2116504516317376942>
- **时间**：2026-11-01 03:08
- **数据**：36.1 万查看 / 1,504 赞 / 1,163 书签

原文：

> 【奉劝大家不要用国产机翻墙，不要在国产机上安装境外 APP】
>
> 我某些朋友用的国产安卓手机，前不久被当地公安打电话，要求卸载 X 和 Telegram，因为我其中一个朋友的小米 14 已经 root 了，我觉得因为梯子配置不当导致的 DNS 泄露，或者别的原因，可能性不大，我就重点排查手机上会上报应用列表的应用
>
> 经排查，我朋友的小米 14，HyperOS 3，其中的“系统安全组件”和“SystemHelper”，会分别把应用列表上报给小米反诈引擎（fraud-detection.engine.miui[.]com/hyperos/fraud/app/report 和 flash.sec.miui[.]com/detect/app）和联通的某个网址（dm.wo[.]com[.]cn:18080/register）
>
> SystemHelper 会默认统计过去 24 小时内有使用记录的应用，枚举已安装应用，关联使用统计和流量，跳过包名以 com[.]android 开头的条目。载荷的序列化实现还包含 IMEI、IMSI、ICCID 等字段，因此具备将应用情况与设备/SIM 标识关联上报的能力。
>
> 系统安全组件会上报第三方应用清单、包名、版本、签名摘要、名称，另有扫描结果和仿冒应用上报；有电话/QQ/微信语音反诈、屏幕视频采集、转写文本和视频片段云检测，以及用户反馈上传原始音频的实现
>
> 关于系统安全组件的录屏采集功能，分辨率 720 × 1280，24 fps，固定竖屏尺寸。相关的流程如下：
>
> 取得系统录屏对象
> → 录制约 3 秒屏幕画面到私有缓存文件
> → 读取整段 MP4，转为 Base64
> → 加密后上传小米云端
> → 等待返回“是否风险”
> &nbsp;&nbsp;&nbsp;&nbsp;├ 未命中：删除临时片段，延时 2 秒后继续录制，重复上述行为
> &nbsp;&nbsp;&nbsp;&nbsp;└ 命中：保留一份片段供反馈，显示警告并停止服务
>
> 这些应用，SystemHelper 貌似是和 SIM 卡激活相关的，系统安全组件貌似……

### 1.2 @Verluntas 的拆解帖

- **账号**：Verluntas
- **链接**：<https://x.com/Verluntas/status/2116608387500978522>
- **配图**：帖子附了一张对照表

原文：

> 刚刚让大肥鱼检查了一下我的小米17Pro Max
> 您猜怎么着…

对照表内容：

> 都存在，而且名字对得上。三个不同的东西：
>
> | 你提到的 | 实际包名 | label | 位置 / 签名 |
> | --- | --- | --- | --- |
> | 系统安全组件 | `com.miui.guardprovider` | System security components | 小米预装，已被商店更新到 3.0.7 |
> | SystemHelper | `com.mobiletools.systemhelper` | SystemHelper | `/system/priv-app/`，小米平台签名 |
> | System Helper Service | `com.qualcomm.qti.services.systemhelper` | System Helper Service | 高通，system 进程在跑 |
>
> **SystemHelper 值得说一下——我把它拆了**
>
> 它不是木马，签名链是 `CN=MIUI, O=Xiaomi`，官方预装的特权应用。但行为很像“运营商埋的探针”：
>
> - **回传地址**：`http://dm.wo.com.cn:18080/register` —— `wo.com.cn` 是**中国联通**的设备管理（DM）平台，而且是**明文 HTTP**
> - **本地存证**：建了张 SQLite 表 `dmregister(jsonString)`，攒着待上报的数据
> - **监听**：开机广播（priority=2147483647，最高优先级）、SIM 状态变化、网络变化、信号强度
> - **采集**：`READ_PRIVILEGED_PHONE_STATE` + 后台定位（内置百度定位 SDK，带硬编码 API key）+ `QUERY_ALL_PACKAGES` + `PACKAGE_USAGE_STATS` → 设备信息、`SIM/ICCID`、位置、已安装应用列表
> - **常驻**：两个 `ELAPSED_WAKEUP` 闹钟在跑（信号上报、定时注册），`appLaunchCount=0`，用户从没打开过，纯后台
> - **导出面**：`RegisterHelperService` 任意应用可 bind，还有一个 `TestActivity` 直接 exported
>
> 有意思的是你现在插的是**中国移动**的卡（46000），它却往联通服务器注册——说明这是**联通渠道机/定制分区**的组件，装在机器上但不是给你这个运营商的。

### 1.3 白雨禾的回复

- **账号**：白雨禾（Verluntas）
- **配图说明**：转发了 NOIR 审计工具的介绍

> 我制作了一个审计工具：NOIR
> NOIR 是一个跑在电脑上的审计工具，通过 adb 读取已连接 Android 设备的应用清单、权限和 APK 里的网络端点，给出分类、风险评分和可执行的处置建议。它也可以在…

---

## 二、这两条推文说了什么

### 2.1 事件链

1. 有人因为手机装了 X / Telegram，被当地公安打电话要求卸载
2. 当事人怀疑是「梯子 DNS 泄露」，排查后发现不是
3. 实际原因：手机上的**系统组件主动上报了应用列表**
4. 小米 14（HyperOS 3）确认存在两个上报通道：
   - 「系统安全组件」`com.miui.guardprovider` → 小米反诈引擎
   - 「SystemHelper」`com.mobiletools.systemhelper` → 联通 DM 平台
5. 另一台小米 17 Pro Max 验证，两个组件都存在

### 2.2 最值得注意的三个点

**第一，明文 HTTP。**

`http://dm.wo.com.cn:18080/register` 是 `http://` 不是 `https://`。
意味着链路上任意节点都能读到上报内容。这不是「合规的隐私采集」该有的姿态。

**第二，`appLaunchCount=0`。**

用户从来没有打开过这个应用，它靠两个 `ELAPSED_WAKEUP` 闹钟常驻后台。
装在你手机上，但你不知道它存在。

**第三，插移动卡却连联通服务器。**

说明这不是「为你服务的组件」，而是**渠道定制分区预装的探针**，
注册目标在出厂时就写死了。

### 2.3 后来查证发现的背景

本项目进一步查证后确认（详见 [evidence.md](evidence.md)）：

- `com.mobiletools.systemhelper` 是**运营商 DM 客户端**，中国联通《Android 终端 DM 适配使用指南》
  里明确写了预置路径：`vendor/sprd/operator/cucc/prebuild/app/SystemHelper_debug.apk`
- 这是**运营商入库规范**的强制要求，三大运营商都有，跨品牌普遍存在
- 台湾的学术研究也记录过 `com.miui.guardprovider` 开机运行、每 30 分钟上报的行为

---

## 三、这个项目是怎么来的

看到这两条推文之后，第一反应是：

> 「我怎么知道我自己的手机有没有？」

于是有了这个项目。做两件事：

1. **把帖文里的判据变成可执行的检测规则** —— 13 条规则，覆盖包名特征、
   权限组合、导出面、常驻行为、端点域名
2. **做成普通人能用的工具** —— 不用懂 adb、不用懂 dumpsys，
   装上（手机版）或双击（电脑版）就能跑

### 设计上受到的启发

| 推文里提到的 | 项目里的对应 |
| --- | --- |
| 「枚举已安装应用」 | `R012` 全量应用枚举能力 |
| 「IMEI、IMSI、ICCID 字段」 | `R004` 电话状态权限组合 |
| 「后台定位」 | `R007` 后台定位 + 设备标识 |
| 「两个 ELAPSED_WAKEUP 闹钟」 | 电脑版 `R009` 闹钟常驻检测 |
| 「RegisterHelperService 随便 bind」 | `R006` 导出组件检测 |
| 「明文 HTTP 回传」 | `R011` 运营商 DM 端点 |
| 「appLaunchCount=0」 | 结合使用统计权限判断 |
| 「签名链 CN=MIUI, O=Xiaomi」 | `R010` 平台签名检测 |

### 特意没做的

推文里有些内容**没有**变成规则，因为无法验证或不该武断：

- 「录屏云检测」—— 静态检查看不到录屏行为，规则库里没有对应项
- 「仿冒应用上报」—— 属于风控正常功能，不宜一刀切标记为恶意
- 具体的「是否风险」回执流程 —— 需要抓包才能确认，工具做不到

**宁可漏报，不能诬告。** 命中的规则只是「值得确认」的信号。

---

## 四、对读者的话

如果你是看到这两条推文找过来的：

1. **先别恐慌。** 上报应用列表在国内 ROM 上是普遍现象，华为、OPPO、vivo
   的官方隐私声明里都写了（见 [huawei-components.md](huawei-components.md)）
2. **区别在于态度。** 写在隐私声明里、可以在设置里关，和「你不知道它存在、
   还明文 HTTP 上传」，是两回事
3. **用工具查你自己的。** 不同品牌、不同渠道机型的情况不一样，
   不要照搬小米的结论
4. **想拿铁证需要抓包。** 静态检查只能告诉你「该怀疑谁」

---

## 五、引用与出处

| 内容 | 链接 |
| --- | --- |
| @MEterminator666 原帖 | <https://x.com/MeTerminator666/status/2116504516317376942> |
| @Verluntas 拆解帖 | <https://x.com/Verluntas/status/2116608387500978522> |
| 中国联通 DM 适配指南 | <https://bbs.16rd.com/thread-583828-1-1.html> |
| NOIR 审计工具（另一位作者） | 见推文回复 |
| 台湾学术研究 | [PDF](http://www.twisc.org/tw/wp-content/uploads/2020/09/手機資料異常行為分析相關研究.pdf) |

---

_本文照录推文原文，仅供技术研究与追溯。推文内容属原作者观点，本项目仅引用其技术观察部分。_
