package dev.beibing.chinaphone.audit

import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build

/**
 * 被审计应用的信息模型。
 *
 * 设计要点（v1.0.2 重构）：
 * 旧版以「命中规则就展示」为逻辑，导致微信、支付宝这类正常应用被大量误报。
 * 新版引入「可见性」概念 —— 真正值得警惕的是**用户看不见的组件**，
 * 而不是权限多的正常应用。
 */
data class AppInfo(
    val packageName: String,
    val label: String,
    val versionName: String?,
    val versionCode: Long,

    // ── 位置与来源 ──
    /** 是否为系统预装 */
    val isSystemApp: Boolean,
    /** 系统应用但被商店更新过（说明厂商在持续维护它） */
    val isUpdatedSystemApp: Boolean,
    /** APK 所在路径 */
    val apkPath: String?,

    // ── 可见性（关键判据）──
    /**
     * 是否有启动图标。
     * 有图标的应用用户能在桌面看到、能主动打开；
     * 没图标意味着用户「不知道它存在」——这才是可疑的前提。
     */
    val hasLauncherIcon: Boolean,
    /**
     * 是否在系统设置的应用列表里对用户可见。
     * 部分系统组件被标记为不可见（甚至连"应用信息"都进不去）。
     */
    val isUserVisible: Boolean,

    // ── 权限画像 ──
    /** 已授予的权限（short name） */
    val grantedPermissions: Set<String>,
    /** 申请的权限（含未授予，short name） */
    val requestedPermissions: Set<String>,

    // ── 组件暴露面 ──
    /** 导出的、且无权限保护的组件 */
    val unprotectedExportedComponents: List<ExportedComponent>,

    /** 是否为平台签名 */
    val isPlatformSigned: Boolean,

    /** 是否为核心系统包（android、systemui 等，永不报告） */
    val isCoreSystemPackage: Boolean = false,
) {
    /**
     * 用户能否「感知」到这个应用的存在。
     *
     * true  = 有图标或能在设置里看到 → 用户知道它，不该当成隐蔽组件
     * false = 完全不可见 → 这才是需要核查的对象
     */
    val isUserAware: Boolean
        get() = hasLauncherIcon || isUserVisible
}

data class ExportedComponent(
    val name: String,
    /** Service / Activity / Receiver / Provider */
    val type: String,
)

/**
 * 一个规则命中。
 */
data class Hit(
    val ruleId: String,
    val ruleName: String,
    val weight: Double,
    val type: String,
    /** 具体证据，人可读 */
    val evidence: String,
    val description: String,
    val advice: String,
)

/**
 * 单个应用的审计结果。
 */
data class AppFinding(
    val app: AppInfo,
    val hits: List<Hit>,
    val score: Double,
    val level: RiskLevel,
) {
    val topRule: Hit? get() = hits.maxByOrNull { it.weight }
}

/**
 * 风险等级。
 *
 * v1.0.2 起语义变化：
 * - HIGH   = 隐蔽组件 + 高危特征，优先看
 * - MEDIUM = 隐蔽组件但特征一般，值得了解
 * - LOW    = 不展示（默认隐藏）
 */
enum class RiskLevel(val label: String, val order: Int) {
    HIGH("高", 2),
    MEDIUM("中", 1),
    LOW("低", 0);

    companion object {
        fun fromScore(score: Double, high: Double = 60.0, medium: Double = 30.0): RiskLevel =
            when {
                score >= high -> HIGH
                score >= medium -> MEDIUM
                else -> LOW
            }
    }
}

/**
 * 整体扫描结果。
 */
data class ScanResult(
    val device: DeviceInfo,
    val findings: List<AppFinding>,
    val totalApps: Int,
    val systemApps: Int,
    val userApps: Int,
    /** 被跳过的正常应用数（有图标/用户可见） */
    val skippedNormal: Int,
    /** 被跳过的核心系统包数 */
    val skippedCore: Int,
    val rulesVersion: String,
    val warnings: List<String>,
    val usageStatsGranted: Boolean,
) {
    val high: List<AppFinding> get() = findings.filter { it.level == RiskLevel.HIGH }
    val medium: List<AppFinding> get() = findings.filter { it.level == RiskLevel.MEDIUM }
    val low: List<AppFinding> get() = findings.filter { it.level == RiskLevel.LOW }
}

data class DeviceInfo(
    val manufacturer: String,
    val brand: String,
    val model: String,
    val androidVersion: String,
    val sdkInt: Int,
    val fingerprint: String,
    val securityPatch: String,
    val securityPatchSdk: String,
) {
    companion object {
        fun collect(pm: PackageManager): DeviceInfo {
            val patch = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Build.VERSION.SECURITY_PATCH ?: "未知"
            } else "未知"
            return DeviceInfo(
                manufacturer = Build.MANUFACTURER ?: "未知",
                brand = Build.BRAND ?: "未知",
                model = Build.MODEL ?: "未知",
                androidVersion = Build.VERSION.RELEASE ?: "未知",
                sdkInt = Build.VERSION.SDK_INT,
                fingerprint = Build.FINGERPRINT ?: "未知",
                securityPatch = patch,
                securityPatchSdk = Build.VERSION.SDK_INT.toString(),
            )
        }
    }
}
