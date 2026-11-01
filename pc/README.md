# 手机隐蔽上报组件审计工具

一套用 adb 检查国产 ROM 是否存在「隐蔽上报 / 采集」组件的脚本。

判据来源：2026-11 小米 HyperOS 实测样本（详见文末「背景」）。

---

## 一、这套工具回答什么问题

> 我的手机里，有没有那种「偷偷把应用列表 / 设备标识 / 录屏 上报给厂家或运营商」的组件？

图里那种情况（小米 HyperOS 上的 `com.miui.guardprovider` + `com.mobiletools.systemhelper`）不是孤例。
这套脚本做的事，就是**把那种人工排查流程自动化**：

1. 拉全部应用清单，标出哪些在 `/system/priv-app` 这种特权位置
2. 拉每个候选包的权限，看有没有「设备标识 + 应用枚举 + 使用统计」这种组合
3. 找 `ELAPSED_WAKEUP` 常驻闹钟（用户从没打开过却长期保活）
4. 找 `exported=true` 且没有权限保护的 Service/Activity（本地提权入口）
5. 按规则库打分，出「高/中/低」三级报告

---

## 二、前置条件

### 电脑侧

- Windows（脚本用 PowerShell 写，5.1 和 7 都能跑）
- **adb**。本机已知路径：
  ```
  C:\Users\17367\AppData\Local\Android\Sdk\platform-tools\adb.exe
  ```
  脚本会自动找，也可以 `-AdbPath` 手动指定。

### 手机侧（关键）

1. **设置 → 关于手机 → 连续点「版本号」7 次**，开启开发者选项
2. **设置 → 系统和更新 → 开发者选项 → 打开「USB 调试」**
3. 华为/荣耀**额外**要打开：
   - 「仅充电模式下允许 ADB 调试」
   - 「允许 ADB 调试」
4. 用**能传数据的线**连电脑（纯充电线不行）
5. 手机下拉通知栏，USB 模式选**「传输文件 / MTP」**
6. 屏幕弹出「允许 USB 调试吗？」→ 勾「始终允许」→ 确定

> **验证是否连上**：
> ```powershell
> adb devices
> ```
> 显示 `xxxxxxxx    device` 才算成功。显示 `unauthorized` 表示没点授权；列表为空表示没连上。

###  HarmonyOS NEXT（纯血鸿蒙 5.x）不适用

纯血鸿蒙已经**移除 adb**，要用华为的 `hdc`；而且华为对 `hdc shell` 权限限制很严，
第三方应用目录读不到（需要 `ohos.permission.ACCESS_BUNDLE_DIR` 系统权限）。

脚本会自动检测这种情况并提示，不会硬报错。

---

## 三、怎么跑

### 1. 完整审计

```powershell
cd D:\ChinaPhone\scripts
powershell -ExecutionPolicy Bypass -File .\audit_android.ps1
```

输出落在 `D:\ChinaPhone\reports\<时间戳>\`：

- `audit.json` —— 机器可读，方便二次处理
- `report.md` —— 人可读，直接翻

### 2. 端点排查（可选，但很有用）

```powershell
powershell -ExecutionPolicy Bypass -File .\endpoint_check.ps1
```

专门看有没有回连**运营商 DM 平台**（如 `dm.wo.com.cn`）的迹象。
不需要 root，靠「包名特征 → 已知端点」映射也能给出高置信度线索。

也可以离线分析已有的网络数据：

```powershell
adb shell netstat -tn > net.txt
powershell -ExecutionPolicy Bypass -File .\endpoint_check.ps1 -FromFile .\net.txt
```

### 3. 常用参数

| 参数 | 作用 |
| --- | --- |
| `-Serial <序列号>` | 多台设备时指定目标 |
| `-OutputRoot <目录>` | 改报告输出位置 |
| `-RulesPath <路径>` | 用自定义规则库 |
| `-AdbPath <路径>` | 手动指定 adb.exe |
| `-JsonOnly` | 只输出 JSON（日志转 stderr，方便管道） |
| `-SkipAlarm` | 跳过 `dumpsys alarm`（这步在部分 ROM 上很慢） |

例：
```powershell
.\audit_android.ps1 -Serial ABC123 -SkipAlarm
```

---

## 四、怎么读报告

### 风险分级

| 分数 | 级别 | 含义 |
| --- | --- | --- |
| ≥ 70 | 🔴 高 | 多个高危特征叠加，必须人工确认 |
| ≥ 40 | 🟠 中 | 有可疑特征，值得看一眼 |
| < 40 | 🟢 低 | 常规系统组件/遥测 |

> **重要**：命中规则 ≠ 恶意。这只是「需要进一步确认」的信号。
> 厂商的常规遥测、应用商店、推送服务都可能命中中低风险规则。

### 重点看什么

1. **高风险包里，有没有你完全不认识的** —— 这是最值得警惕的
2. **`priv-app` 且用户从没打开过的** —— 小米样本 SystemHelper 的 `appLaunchCount=0` 就是这个特征
3. **权限组合命中 R004 / R005 的** —— 设备标识 + 应用枚举 / 录音 + 应用枚举，这两组最接近「上报」能力
4. **导出的无保护组件** —— 别的应用能直接 bind 它，是攻击面

---

## 五、怎么处置

### 安全原则：**先停用，别卸载**

```powershell
# 1. 先备份清单
adb shell pm list packages -f > packages-backup.txt

# 2. 停用（可回滚）
adb shell pm disable-user --user 0 com.example.suspicious

# 3. 想恢复
adb shell pm enable com.example.suspicious
```

### 不要做的事

- ❌ **不要 root 后删 `/system` 里的文件** —— 会导致 OTA 失败、系统异常，甚至变砖
- ❌ 不要一次性批量停用 —— 停用错了可能导致手机功能异常
- ❌ 不要相信「一键清理」类工具 —— 它们自己就是上报组件

### 想彻底卸载用户态应用

```powershell
adb shell pm uninstall --user 0 com.example.suspicious
```

这只是对当前用户卸载，系统分区原件还在，恢复出厂设置会回来。

---

## 六、规则库

规则都在 `rules.json` 里，可以直接编辑增删。

### 规则类型

| type | 说明 |
| --- | --- |
| `package_keyword` | 包名正则命中 |
| `privapp` | 位于 priv-app 目录 |
| `permission_combo` | 权限组合齐备才命中（match 是数组） |
| `permission_keyword` | 单个权限正则命中 |
| `exported_component` | 有未保护的导出组件 |
| `alarm_pattern` | 闹钟常驻特征 |
| `endpoint_domain` | 端点域名命中 |

### 例：加一条自己的规则

```json
{
  "id": "R999",
  "name": "我怀疑的某个包",
  "enabled": true,
  "weight": 100,
  "type": "package_keyword",
  "target": "package",
  "match": "(?i)^com\\.suspicious\\.app$",
  "description": "自己发现的",
  "advice": "停用试试"
}
```

改完重跑脚本即可，不用改代码。

---

## 七、局限

说得清楚一点，免得误判：

1. **静态特征，不等于行为证据。** 脚本读的是「声明了什么权限」，不是「实际做了什么」。
2. **非 root 设备读不到实时网络连接。** `netstat` 往往被限制，所以端点排查主要靠包名映射。
3. **规则库是启发式的。** 没命中不代表安全，命中也不代表恶意。
4. **要拿到铁证需要抓包。** 见 `endpoint_check.ps1` 报告里的「补充说明」章节。

想拿到确凿证据的路线：

- **root + tcpdump**：`adb shell tcpdump -i any -w /sdcard/cap.pcap`
- **PC 端抓包**：手机连电脑热点，Wireshark 抓热点网卡，过滤 `dns`
- **私有 DNS 日志**：手机设置 → 网络 → 私人 DNS 填可记录日志的 DoH 服务

---

## 八、文件说明

| 文件 | 作用 |
| --- | --- |
| `DeviceAudit.Common.ps1` | 公共库：adb 定位、设备选择、超时调用、UTF-8 解码、规则加载、打分 |
| `audit_android.ps1` | 主审计脚本 |
| `endpoint_check.ps1` | 端点排查脚本 |
| `rules.json` | 规则库（可编辑） |
| `README.md` | 本文件 |

---

## 九、背景：这份判据是怎么来的

2026 年 11 月，X 平台用户 `@MEterminator666` 与 `@Verluntas` 发布了针对小米 HyperOS 的实测排查结果。核心结论：

### 「系统安全组件」

- 包名：`com.miui.guardprovider`
- 上报：第三方应用清单（包名、版本、签名摘要、名称）、扫描截图、仿冒应用检测结果
- 端点：`fraud-detection.engine.miui.com`、`flash.sec.miui.com`
- 录屏采集链路（按帖文描述）：
  ```
  取得录屏对象
  → 录制约 3 秒屏幕到私有缓存
  → 读取 MP4，转 Base64
  → 加密上传小米云端
  → 等「是否风险」回执
     ├ 未命中：删片段，延时 2 秒重录，循环
     └ 命中：保留片段供反馈，弹警告并停止
  ```
  分辨率 720×1280，24fps，固定竖屏尺寸。

### 「SystemHelper」

- 包名：`com.mobiletools.systemhelper`
- 位置：`/system/priv-app/`，小米平台签名
- **本质是运营商 DM 客户端**，不是小米自研。证据：中国联通《Android 终端 DM 适配使用指南》里就写着
  `vendor/sprd/operator/cucc/prebuild/app/SystemHelper_debug.apk` —— 按运营商渠道定制分区预装。
- 回传地址：`http://dm.wo.com.cn:18080/register`（中国联通设备管理平台，**明文 HTTP**）
- 本地落库：建了 SQLite 表 `dmregister(jsonString)`
- 采集：`READ_PRIVILEGED_PHONE_STATE` + 后台定位（内置百度定位 SDK，硬编码 API key）
  + `QUERY_ALL_PACKAGES` + `PACKAGE_USAGE_STATS` → 含 IMEI / IMSI / ICCID
- 常驻：两个 `ELAPSED_WAKEUP` 闹钟（信号上报、定时注册），`appLaunchCount=0`（用户从没打开过）
- 导出面：`RegisterHelperService` 任意应用可 bind，`TestActivity` 直接 exported
- **最讽刺的点**：手机插的是中国移动卡（46000），却往联通服务器注册 → 说明这是渠道定制组件

> 这些是帖文作者的实测结论，本工具把它们抽象成了可复用的检测规则。
> 对具体设备而言，**是否命中要看你自己的检测结果**，不要直接照搬结论。

---

## 十、参考

- [MuMu/论坛：小米 SystemHelper 讨论](https://memeosupdates.com/apps/com.mobiletools.systemhelper/31)
- [中国联通 Android 终端 DM 适配使用指南](https://bbs.16rd.com/thread-583828-1-1.html)
- [学术论文：手机数据异常行为分析（含 guardprovider 行为）](http://www.twisc.org/tw/wp-content/uploads/2020/09/手機資料異常行為分析相關研究.pdf)
- [HarmonyOS-Tools（hdc 权限限制说明）](https://github.com/wrlu/HarmonyOS-Tools)
