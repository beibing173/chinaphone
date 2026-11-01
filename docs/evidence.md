# 判据来源与证据

本项目的检测规则不是凭空设计的，提炼自公开的实测报告、官方文档与学术研究。
本文记录每条关键判据的来源，便于核查与更新。

可信度分级：

- **A 级**：官方文档、运营商规范手册、厂商隐私声明
- **B 级**：公开实测报告、逆向分析（可复现）
- **C 级**：学术研究、社区讨论（有旁证但未完全验证）

---

## 一、核心样本：小米 HyperOS

### 1.1 系统安全组件

| 项目 | 内容 | 可信度 |
| --- | --- | --- |
| 包名 | `com.miui.guardprovider` | B |
| label | System security components | B |
| 位置 | 小米预装，已被应用商店更新到 3.0.7 | B |
| 行为 | 上报第三方应用清单（包名、版本、签名摘要、名称）、扫描截图、仿冒应用上报 | B |
| 端点 | `fraud-detection.engine.miui.com`、`flash.sec.miui.com` | B |

**录屏采集链路**（按贴文描述，B 级）：

```
取得系统录屏对象
→ 录制约 3 秒屏幕到私有缓存文件
→ 读取整段 MP4，转 Base64
→ 加密后上传小米云端
→ 等待返回「是否风险」
   ├ 未命中：删除临时片段，延时 2 秒后继续录制，重复上述行为
   └ 命中：保留一份片段供反馈，显示警告并停止服务
```

分辨率 720×1280，24fps，固定竖屏尺寸。

### 1.2 SystemHelper

| 项目 | 内容 | 可信度 |
| --- | --- | --- |
| 包名 | `com.mobiletools.systemhelper` | A |
| label | SystemHelper | B |
| 位置 | `/system/priv-app/`，小米平台签名 | B |
| 性质 | **运营商 DM（设备管理）客户端**，非小米自研 | A |
| 回连地址 | `http://dm.wo.com.cn:18080/register`（中国联通 DM 平台，**明文 HTTP**） | B |
| 本地落库 | SQLite 表 `dmregister(jsonString)` | B |
| 采集权限 | `READ_PRIVILEGED_PHONE_STATE` + `QUERY_ALL_PACKAGES` + `PACKAGE_USAGE_STATS` | B |
| 采集内容 | IMEI / IMSI / ICCID、已安装应用列表、后台定位（内置百度定位 SDK，硬编码 API key） | B |
| 常驻方式 | 两个 `ELAPSED_WAKEUP` 闹钟（信号上报、定时注册），`appLaunchCount=0` | B |
| 导出面 | `RegisterHelperService` 任意应用可 bind，`TestActivity` 直接 exported | B |
| 监听事件 | 开机广播（priority=2147483647，最高优先级）、SIM 状态变化、网络变化、信号强度 | B |

**关键证据（A 级）**：中国联通《Android 终端 DM 适配使用指南》明确写出路径：

```
vendor/sprd/operator/cucc/prebuild/app/SystemHelper_debug.apk
```

`cucc` = China Unicom。这证明它是**按运营商渠道定制分区预装的组件**，
而非小米自研。也解释了「手机插移动卡却往联通服务器注册」——
注册目标在出厂时就写进了 cucc 分区，与当前 SIM 卡无关。

该手册还要求「不要阻止它开机自启、不要做唤醒对齐」，
等于出厂即锁定行为。

来源：<https://bbs.16rd.com/thread-583828-1-1.html>

---

## 二、运营商 DM 机制的普遍性

| 结论 | 可信度 |
| --- | --- |
| 三大运营商对入库机型强制要求 DM 适配 | A |
| 中国移动自 2017 年起对全部入库机型强制 | A |
| 联通称 DM 为「Android 终端入库的基础」 | A |
| 运营商要求厂商隐藏界面上的 "DM" 字样 | A |
| 凡运营商渠道机都可能预装，包名随方案商不同 | A |

**结论**：`com.mobiletools.systemhelper` 不是孤例，
它是运营商入库规范下的产物，其他品牌渠道机可能有同款（包名不同）。

---

## 三、华为 / HarmonyOS 侧对照

详见 [huawei-components.md](huawei-components.md)（32KB，27 条来源）。

要点：

| 组件 | 包名 | 行为 | 可信度 |
| --- | --- | --- | --- |
| HMS Core | `com.huawei.hwid` | 官方声明收集「已安装应用程序清单 + 应用使用情况」做定期安全检查 | A |
| 手机管家 | `com.huawei.systemmanager` | 本地读应用列表、读 IMSI；全部服务模式下加密上云设备标识符+应用名 | A |
| 应用市场 | `com.huawei.appmarket` | 官方原文「读取并传送已安装应用列表」 | A |

**关键差异**：华为是「明着来」——应用列表采集写在官方隐私声明里，
用户可在设置中查阅。小米样本的问题不在于「收集了什么」
（业界普遍如此），而在于**隐瞒 + 明文 HTTP + 用户无感知**。

**澄清**：华为**没有预装**国家反诈中心（`com.hicorenational.antifraud`）。
那是公安部刑侦局的第三方 App，商店下载、可卸载。
华为内置的是「星盾防诈」设置项，**无独立包名**。
网上「国产机都内置反诈 App」是混淆了预装 App 与系统内置拦截策略。

---

## 四、跨品牌对照

详见 [crossbrand-components.md](crossbrand-components.md)（29KB，19 张表）。

| 厂商 | 组件 | 已知能力 | 可信度 |
| --- | --- | --- | --- |
| 小米 | `com.miui.guardprovider` | 应用清单 + 录屏云检测 | B |
| 小米 | `com.mobiletools.systemhelper` | 运营商 DM，明文 HTTP | A/B |
| OPPO | `com.oplus.statistics.rom` | `QUERY_ALL_PACKAGES` + `READ_PRIVILEGED_PHONE_STATE` + `PACKAGE_USAGE_STATS` | B（权限表） |
| vivo | `com.vivo.abe` | 43 项权限，平台签名 | B（权限表） |
| 荣耀 | `com.hihonor.phoneservice` | 含 applist vendor 权限 | B（权限表） |
| 三星国行 | `com.samsung.android.permission.GET_APP_LIST` | 独立权限坐实，具体组件待实测 | B |

**注意**：除小米外，其他厂商的**行为层面**均未被公开逆向，
表格里标 B 级的只是「权限声明」，不等于「实际在做上报」。
本项目规则库因此对这类组件只给中等权重。

**唯一实锤的恶劣案例**：明文 HTTP 传设备标识（小米 SystemHelper）
和 720×1280 录屏风控（小米 guardprovider）。其他厂商未见证据。

---

## 五、其他来源

| 来源 | 内容 | 链接 |
| --- | --- | --- |
| 学术论文（爱丁堡大学） | 记录了 `diagnosis.ad.xiaomi.com`、`tracking.miui.com`、`port.sec.miui.com`、`dm.wo.com.cn` 等端点 | [PDF](https://era.ed.ac.uk/bitstream/handle/1842/41248/LiuH_2023.pdf) |
| 台湾学术研究 | `com.miui.guardprovider` 开机即运行，每 30 分钟上报手机信息 | [PDF](http://www.twisc.org/tw/wp-content/uploads/2020/09/手機資料異常行為分析相關研究.pdf) |
| NGA 讨论 | MIUI 13 EU 版仍内置 `com.miui.guardprovider`，用腾讯天御模块后台分析应用 | [链接](https://ngabbs.com/read.php?tid=35273994) |
| 阿里云隐私告警文档 | `com.huawei.hwid` 曾在用户授权前提前收集应用列表（旧版 SDK） | [链接](https://help.aliyun.com/zh/document_detail/616139.html) |
| MediaTek Modem Helper | `com.mobiletools.systemhelper` 的官方描述 | [链接](https://memeosupdates.com/apps/com.mobiletools.systemhelper/31) |
| HarmonyOS-Tools | 纯血鸿蒙 hdc 权限限制说明 | [GitHub](https://github.com/wrlu/HarmonyOS-Tools) |

---

## 六、待实测确认清单

以下项目无法通过公开资料确认，需要实机验证：

1. 华为侧运营商 DM 组件的具体包名（无任何来源给出）
2. `com.huawei.systemmanager` 是否采集 IMEI / ICCID（官方声明未披露）
3. `com.huawei.hiview` / `com.huawei.hiviewtunnel` 上传的具体字段
4. OPPO / vivo / 荣耀的统计组件是否真的上报应用列表（仅权限声明坐实）
5. 三星国行的具体上报组件包名
6. 各家是否存在类似「录屏云检测」的实现
7. 华为「星盾防诈」的实际数据流向

> 本项目规则库对这些项目保持保守权重，
> 不因「权限像」就判定为高危。

---

## 七、使用方法论

本项目严格遵守以下原则：

1. **不臆造包名。** 拿不准的一律标「待实测确认」。
2. **区分权限声明与行为证据。** 有权限 ≠ 在用。
3. **标注可信度。** A / B / C 三级明确区分。
4. **承认局限。** 静态检查不能替代抓包。
5. **不做道德判断。** 描述事实，不渲染。

---

_最后更新：2026-11-01_
