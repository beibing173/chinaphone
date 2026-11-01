# ChinaPhone 手机自查工具

用自己的设备查自己的手机 —— 检查是否存在类似小米 HyperOS 上
`com.miui.guardprovider`（系统安全组件）+ `com.mobiletools.systemhelper`（SystemHelper）
那种「隐蔽上报应用列表 / 设备标识 / 录屏」的组件。

**提供两个版本，各取所需。**

---

## 两个版本

| | 🖥️ 电脑版 | 📱 手机版 |
| --- | --- | --- |
| **形态** | `ChinaPhone.exe`（单文件启动器） | `ChinaPhone-vX.Y.Z.apk` |
| **运行环境** | Windows + 手机 USB 调试 | 直接装在手机上 |
| **需要电脑吗** | 需要 | 不需要 |
| **需要 root 吗** | 不需要 | 不需要 |
| **能查到什么** | 应用清单、权限、导出组件、**闹钟常驻**、**网络端点**、priv-app 路径 | 应用清单、权限、导出组件、签名信息 |
| **优势** | 查得更深（能读 dumpsys 全量数据） | 装上就跑，零门槛 |
| **劣势** | 要开 USB 调试，部分机型麻烦 | 受 Android 权限限制，看不到网络和闹钟 |

> 建议：**先用手机版快速扫一遍**，发现可疑的再用电脑版深挖。

---

## 快速开始

### 手机版（推荐先试）

1. 从 [Releases](../../releases) 下载 `ChinaPhone-vX.Y.Z.apk`
2. 传到手机安装（首次要允许「安装未知来源应用」）
3. 打开，点「开始检查」，等几秒

### 电脑版

1. 从 [Releases](../../releases) 下载 `ChinaPhone-PC-vX.Y.Z.zip`（推荐，含脚本和说明）
2. 解压，双击 `ChinaPhone.exe`
3. 手机开 USB 调试 → 连电脑 → 按提示操作

> 只下 `ChinaPhone.exe` 也行，但需要同目录有 `pc/` 文件夹。

---

## 排查的东西从哪来

判据提炼自 2026-11 X 平台用户对小米 HyperOS 的公开实测结论，详见：

- [docs/evidence.md](docs/evidence.md) —— 原始样本与判据来源
- [docs/huawei-components.md](docs/huawei-components.md) —— 华为 / HarmonyOS 侧对照（32KB，27 条来源）
- [docs/crossbrand-components.md](docs/crossbrand-components.md) —— 跨品牌对照（29KB，19 张表）

核心样本：

| 组件 | 包名 | 行为 |
| --- | --- | --- |
| 系统安全组件 | `com.miui.guardprovider` | 上报应用清单、扫描截图、录屏云检测 |
| SystemHelper | `com.mobiletools.systemhelper` | 运营商 DM 客户端，明文 HTTP 回连 `dm.wo.com.cn:18080`，采集 IMEI/IMSI/ICCID |

---

## 规则库

两套规则，同构设计：

- **手机版**：`app/src/main/java/.../audit/Rules.kt`（编译进 APK，13 条规则）
- **电脑版**：`pc/rules.json`（外置可编辑，13 条规则）

改规则不用动代码逻辑，改数据即可。

### 规则类型

| type | 判据 |
| --- | --- |
| `package_keyword` | 包名 / 应用名正则命中 |
| `permission_combo` | 多个权限同时持有才命中 |
| `permission_keyword` | 单个权限命中 |
| `exported_component` | 存在无权限保护的导出组件 |
| `platform_signed` | 平台密钥签名 |
| `updateable_system` | 系统应用但可被商店更新 |
| `system_app` | 系统预装 |
| `endpoint_domain` | 回连可疑域名 |

---

## 版本与发布

版本号在 **`app/build.gradle.kts`**：

```kotlin
val appVersionCode = 1        // 必须单调递增
val appVersionName = "1.0.0"  // Release 标签用这个
```

推送代码到 `main` 后，GitHub Actions 自动：

1. 读版本号 → 校验格式
2. **并行**构建 APK（Linux）和 EXE（Windows）
3. 检查该版本 Release 是否存在
   - **已存在** → 覆盖资产 + 更新说明
   - **不存在** → 新建 Release
4. 生成更新日志（列出本次提交）和下载表格
5. 发布，附 SHA256 校验

**发新版 = 改版本号 + 提交 + 推送。**

---

## 本地构建（可选）

CI 会自动做，本地不是必须。

```powershell
# 电脑版 EXE
cd pc
.\build-exe.ps1 -Version 1.0.0

# 电脑版自测
.\_selftest.ps1
```

APK 需要 Android SDK + Gradle，交给 CI 更省事。

---

## 项目结构

```
app/                          Android 应用
  src/main/java/.../audit/    审计引擎（采集 → 规则 → 打分）
  src/main/java/.../ui/       Compose 界面
  build.gradle.kts            ★ 版本号在这里
pc/                           电脑版
  audit_android.ps1           主审计脚本
  endpoint_check.ps1          端点排查
  DeviceAudit.Common.ps1      公共库
  rules.json                  规则库
  launcher/Program.cs         EXE 启动器源码
  build-exe.ps1               打包 EXE
  _selftest.ps1               自测
docs/                         调研报告与证据
scripts/version.sh            版本号读取（CI 与本地共用）
.github/workflows/release.yml 自动构建发布
keystore/                    签名密钥（保证版本可覆盖升级）
```

---

## 局限（说清楚，别误会）

1. **静态特征，不是行为证据。** 读的是「声明了什么权限」，不是「实际做了什么」。
2. **手机版看不到网络流量。** 没有 root 拿不到实时连接。
3. **规则库是启发式的。** 没命中不代表安全，命中也不代表恶意。
4. **要拿铁证需要抓包。** 见 `pc/endpoint_check.ps1` 报告里的说明。

---

## 免责声明

本工具基于公开信息的启发式判断，**不能证明**任何应用存在恶意行为。
报告是「需要进一步确认」的信号，请结合厂商公开说明与自身使用场景判断。

**不提供不建议**修改系统分区的操作。
