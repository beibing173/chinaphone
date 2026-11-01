# 声明与致谢

## 一、项目的起点

本项目的灵感来自 2026 年 11 月 X（原 Twitter）上的两条公开推文。
完整原文已照录在 [docs/inspiration.md](docs/inspiration.md)。

### 原始推文链接

| 作者 | 内容 | 链接 |
| --- | --- | --- |
| **@MEterminator666**（MeT） | 小米 14 隐蔽上报的首次排查 | <https://x.com/MeTerminator666/status/2116504516317376942> |
| **@Verluntas**（白雨禾） | 拆解 SystemHelper，确认包名与行为 | <https://x.com/Verluntas/status/2116608387500978522> |

**没有这两条推文，就没有这个项目。** 感谢两位作者把排查过程和结论公开。

推文原文、图表、截图等内容的版权归原作者所有。本项目仅出于技术研究与
问题追溯的目的引用，并完整标注来源链接。

---

## 二、第三方来源清单

本项目在制定检测规则时参考了以下公开资料。
每条结论的可信度分级与详细出处见 [docs/evidence.md](docs/evidence.md)。

### 2.1 运营商规范（A 级）

| 来源 | 用途 |
| --- | --- |
| 中国联通《Android 终端 DM 适配使用指南》<br><https://bbs.16rd.com/thread-583828-1-1.html> | 确认 `SystemHelper_debug.apk` 的预置路径<br>`vendor/sprd/operator/cucc/prebuild/app/` |

### 2.2 厂商官方文档（A 级）

| 来源 | 用途 |
| --- | --- |
| 华为《关于智能检测与隐私的声明》<br><https://terms-dra.platform.dbankcloud.com/agreement/scope/huawei/hiviewcare/privacy-statement/cn_b0_20251010_2/default/privacy-statement-zh-cn.htm> | 确认华为采集「已安装应用列表」的方式（明示 vs 隐蔽） |
| 华为开发者文档（MDM 接口）<br><https://developer.huawei.com/consumer/cn/> | `com.huawei.systemmanager.permission.ACCESS_INTERFACE` 权限说明 |

### 2.3 学术研究（C 级）

| 来源 | 用途 |
| --- | --- |
| University of Edinburgh, Liu H. (2023)<br><https://era.ed.ac.uk/bitstream/handle/1842/41248/LiuH_2023.pdf> | 记录了 `diagnosis.ad.xiaomi.com`、`tracking.miui.com`、`port.sec.miui.com`、`dm.wo.com.cn` 等端点 |
| 台灣資安研究（手機資料異常行為分析）<br><http://www.twisc.org/tw/wp-content/uploads/2020/09/手機資料異常行為分析相關研究.pdf> | 记录 `com.miui.guardprovider` 开机运行、每 30 分钟上报的行为 |

### 2.4 社区实测与工具（B 级）

| 来源 | 用途 |
| --- | --- |
| NGA 论坛讨论帖<br><https://ngabbs.com/read.php?tid=35273994> | MIUI EU 版仍内置 `com.miui.guardprovider`，使用腾讯天御模块 |
| MediaTek Modem Helper 页面<br><https://memeosupdates.com/apps/com.mobiletools.systemhelper/31> | `com.mobiletools.systemhelper` 的官方描述 |
| 阿里云隐私告警文档<br><https://help.aliyun.com/zh/document_detail/616139.html> | `com.huawei.hwid` 旧版 SDK 在授权前提前收集应用列表 |
| HarmonyOS-Tools (wrlu)<br><https://github.com/wrlu/HarmonyOS-Tools> | 纯血鸿蒙 hdc 权限限制说明 |
| NOIR 审计工具（推文回复中提及） | 同类工具的思路参考 |

---

## 三、技术栈

### 手机版
- Kotlin
- Jetpack Compose
- Android SDK 34

### 电脑版
- PowerShell 5.1 / 7+
- C#（.NET Framework 4.x，用系统自带 `csc.exe` 编译）
- Android Debug Bridge (adb)

### CI
- GitHub Actions
- Gradle

以上均为各自所有者的商标或作品，本项目仅按其许可条款使用。

---

## 四、免责声明

本项目是一个**只读的诊断工具**，目的是帮助用户了解自己设备上的应用状况。

1. **不做任何修改。** 不修改系统设置、不停用应用、不读写用户数据。
2. **不上传任何数据。** 手机版不申请网络权限，所有分析在本机完成。
3. **不提供攻击能力。** 没有提权、注入、绕过安全机制的代码或说明。
4. **结论是启发式的。** 命中规则只代表「值得进一步确认」，不构成对任何
   厂商或应用的恶意指控。

如果本项目的任何内容侵犯了您的权益，请通过
[Issues](https://github.com/beibing173/chinaphone/issues) 联系，我们会及时处理。

---

## 五、引用规范

如果你要转载或引用本项目的内容，请注意：

- **代码**：遵循 [MIT License](LICENSE)
- **推文原文**：请引用原作者，链接到原推文
- **检测规则**：欢迎使用，注明来源即可
- **调研报告**：可自由引用，但请保留可信度分级

---

_最后更新：2026-11-01_
