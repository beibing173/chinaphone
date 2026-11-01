package dev.beibing.chinaphone.audit

import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build

/**
 * 被审计应用的信息模型。
 */
data class AppInfo(
    val packageName: String,
    val label: String,
    val versionName: String?,
    val versionCode: Long,
    /** 是否为系统预装 */
    val isSystemApp: Boolean,
    /** 是否已更新过（系统应用但被商店替换过） */
    val isUpdatedSystemApp: Boolean,
    /** APK 所在路径 */
    val apkPath: String?,
    /** 已授予的权限（short name，去掉 android.permission. 前缀） */
    val grantedPermissions: Set<String>,
    /** 申请的权限（含未授予） */
    val requestedPermissions: Set<String>,
    /** 导出的、且无权限保护的组件 */
    val unprotectedExportedComponents: List<ExportedComponent>,
    /** 是否为平台签名 */
    val isPlatformSigned: Boolean,
)

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

enum class RiskLevel(val label: String, val order: Int) {
    HIGH("高", 2),
    MEDIUM("中", 1),
    LOW("低", 0);

    companion object {
        fun fromScore(score: Double, high: Double = 70.0, medium: Double = 40.0): RiskLevel =
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
