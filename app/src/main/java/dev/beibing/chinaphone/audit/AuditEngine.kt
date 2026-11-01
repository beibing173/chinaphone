package dev.beibing.chinaphone.audit

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 审计引擎（v1.0.2 重构）。
 *
 * ══════════════════════════════════════════════════════════════
 * 核心变化：从「命中就报」改成「不可见才报」
 * ══════════════════════════════════════════════════════════════
 *
 * v1.0.1 → 一次扫出 200 条，微信/支付宝/系统应用全在里面，全是噪音。
 *
 * v1.0.2 → 三层过滤：
 *
 *   第一层（包级）：核心系统包直接跳过
 *      android、com.android.systemui、settings…
 *
 *   第二层（可见性）：用户能感知到的应用跳过
 *      有启动图标 → 桌面上能看到 → 用户知道 → 不报
 *      能在设置里看到 → 用户能找到 → 不报
 *
 *   第三层（能力）：剩下的不可见组件，只有具备
 *      「上报/采集能力」证据的才报
 *
 * 这样结果通常只剩个位数，且每一条都值得看。
 */
class AuditEngine(private val context: Context) {

    private val pm: PackageManager = context.packageManager

    suspend fun scan(onProgress: (Int, Int) -> Unit = { _, _ -> }): ScanResult =
        withContext(Dispatchers.IO) {
            val warnings = mutableListOf<String>()

            val device = DeviceInfo.collect(pm)

            val packages: List<PackageInfo> = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    pm.getInstalledPackages(
                        PackageManager.PackageInfoFlags.of(
                            PackageManager.GET_PERMISSIONS.toLong() or
                                PackageManager.GET_SIGNING_CERTIFICATES.toLong()
                        )
                    )
                } else {
                    @Suppress("DEPRECATION")
                    pm.getInstalledPackages(
                        PackageManager.GET_PERMISSIONS or
                            PackageManager.GET_SIGNING_CERTIFICATES
                    )
                }
            } catch (e: Exception) {
                warnings.add("枚举应用失败：${e.message}")
                emptyList()
            }

            if (packages.isEmpty()) {
                warnings.add("未能读取任何应用信息，可能是系统权限限制。")
            }

            // 一次查出所有有启动图标的包，避免对每个包做昂贵查询
            val launcherPackages = queryLauncherPackages()

            val findings = mutableListOf<AppFinding>()
            var systemCount = 0
            var userCount = 0
            var skippedNormal = 0
            var skippedCore = 0

            packages.forEachIndexed { index, pkg ->
                onProgress(index + 1, packages.size)
                val pkgName = pkg.packageName ?: return@forEachIndexed

                // ── 第一层：核心系统包跳过 ──
                if (isCoreSystemPackage(pkgName)) {
                    skippedCore++
                    return@forEachIndexed
                }

                val info = try {
                    buildAppInfo(pkg, launcherPackages)
                } catch (e: Exception) {
                    null
                } ?: return@forEachIndexed

                if (info.isSystemApp) systemCount++ else userCount++

                // ── 第二层：用户能感知到的跳过 ──
                // 这是 v1.0.2 最关键的变化。
                // 有图标 = 用户知道它存在 = 不是「隐蔽组件」= 不报
                if (info.isUserAware) {
                    skippedNormal++
                    return@forEachIndexed
                }

                // ── 第三层：评估上报/采集能力 ──
                val hits = evaluate(info)
                if (hits.isEmpty()) return@forEachIndexed

                val seen = mutableSetOf<String>()
                val distinct = hits.filter { seen.add(it.ruleId) }
                var score = distinct.sumOf { it.weight }
                if (score > 100.0) score = 100.0

                val level = RiskLevel.fromScore(
                    score,
                    Rules.HIGH_THRESHOLD,
                    Rules.MEDIUM_THRESHOLD
                )

                // 低风险不展示，减少噪音
                if (level == RiskLevel.LOW) return@forEachIndexed

                findings.add(
                    AppFinding(
                        app = info,
                        hits = distinct,
                        score = score,
                        level = level
                    )
                )
            }

            ScanResult(
                device = device,
                findings = findings.sortedByDescending { it.score },
                totalApps = packages.size,
                systemApps = systemCount,
                userApps = userCount,
                skippedNormal = skippedNormal,
                skippedCore = skippedCore,
                rulesVersion = Rules.VERSION,
                warnings = warnings,
                usageStatsGranted = checkUsageStatsPermission()
            )
        }

    // ─────────────────────────────────────────────────────────
    // 第一层：核心系统包判定
    // ─────────────────────────────────────────────────────────
    private fun isCoreSystemPackage(pkgName: String): Boolean {
        if (Rules.CORE_SYSTEM_PACKAGES.contains(pkgName)) return true
        if (Rules.ALWAYS_SKIP.contains(pkgName)) return true
        for (prefix in Rules.CORE_SYSTEM_PREFIXES) {
            if (pkgName.startsWith(prefix)) return true
        }
        return false
    }

    // ─────────────────────────────────────────────────────────
    // 查询所有有启动图标的应用
    // ─────────────────────────────────────────────────────────
    private fun queryLauncherPackages(): Set<String> {
        val result = mutableSetOf<String>()
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        try {
            val infos: List<ResolveInfo> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.queryIntentActivities(
                    intent,
                    PackageManager.ResolveInfoFlags.of(0L)
                )
            } else {
                @Suppress("DEPRECATION")
                pm.queryIntentActivities(intent, 0)
            }
            infos.forEach { ri ->
                ri.activityInfo?.packageName?.let { result.add(it) }
            }
        } catch (e: Exception) {
            // 查询失败时返回空集，会导致更多应用被判为「不可见」，
            // 但后续还有权限组合门槛，不会炸量。
        }
        return result
    }

    // ─────────────────────────────────────────────────────────
    // 构建 AppInfo
    // ─────────────────────────────────────────────────────────
    private fun buildAppInfo(pkg: PackageInfo, launcherPackages: Set<String>): AppInfo? {
        val ai: ApplicationInfo = pkg.applicationInfo ?: return null
        val pkgName = pkg.packageName ?: return null

        val label = try {
            pm.getApplicationLabel(ai).toString()
        } catch (e: Exception) {
            pkgName
        }

        val requested = (pkg.requestedPermissions ?: emptyArray()).toSet()
        val granted = requested.filter { perm ->
            try {
                pm.checkPermission(perm, pkgName) == PackageManager.PERMISSION_GRANTED
            } catch (e: Exception) {
                false
            }
        }.toSet()

        fun short(p: String) = p.substringAfterLast('.')

        val grantedShort = granted.map(::short).toSet()
        val requestedShort = requested.map(::short).toSet()

        val isSystem = try {
            (ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0
        } catch (e: Exception) {
            false
        }
        val isUpdatedSystem = try {
            (ai.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
        } catch (e: Exception) {
            false
        }

        val apkPath = try {
            ai.sourceDir
        } catch (e: Exception) {
            null
        }

        // ── 可见性判定 ──
        // 核心思路：用户安装的应用必然可见（他能从桌面/设置找到），
        // 系统应用则要看有没有启动图标 —— 没图标的才是「用户看不见」的。
        val hasLauncherIcon = launcherPackages.contains(pkgName)

        // 用户自己安装的应用，无论有无图标，用户都是「装过它」的，算可见。
        // 系统预装且无图标 → 用户不知道它存在 → 不可见。
        val isUserVisible = !isSystem

        val exported = collectUnprotectedExported(pkg)
        val platformSigned = isPlatformSigned(pkg)

        return AppInfo(
            packageName = pkgName,
            label = label,
            versionName = pkg.versionName,
            versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                pkg.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                pkg.versionCode.toLong()
            },
            isSystemApp = isSystem,
            isUpdatedSystemApp = isUpdatedSystem,
            apkPath = apkPath,
            hasLauncherIcon = hasLauncherIcon,
            isUserVisible = isUserVisible,
            grantedPermissions = grantedShort,
            requestedPermissions = requestedShort,
            unprotectedExportedComponents = exported,
            isPlatformSigned = platformSigned,
        )
    }

    /**
     * 找出 exported 且无权限保护的组件。
     * 注：pkg.activities/services/receivers 的元素本身是 Info 类型，没有 .info。
     * ActivityInfo.FLAG_EXPORTED 是内部常量，公开 API 只有 exported 字段（API 33+）。
     */
    private fun collectUnprotectedExported(pkg: PackageInfo): List<ExportedComponent> {
        val result = mutableListOf<ExportedComponent>()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pkg.activities?.forEach { info ->
                    if (info.exported && info.permission == null) {
                        result.add(ExportedComponent(info.name ?: "", "Activity"))
                    }
                }
                pkg.services?.forEach { info ->
                    if (info.exported && info.permission == null) {
                        result.add(ExportedComponent(info.name ?: "", "Service"))
                    }
                }
                pkg.receivers?.forEach { info ->
                    if (info.exported && info.permission == null) {
                        result.add(ExportedComponent(info.name ?: "", "Receiver"))
                    }
                }
            }
        } catch (e: Exception) {
            // 权限不足时静默跳过
        }
        return result
    }

    private fun isPlatformSigned(pkg: PackageInfo): Boolean {
        return try {
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val si = pkg.signingInfo ?: return false
                if (si.hasMultipleSigners()) si.apkContentsSigners else si.signingCertificateHistory
            } else {
                @Suppress("DEPRECATION")
                pkg.signatures
            }
            if (signatures.isEmpty()) return false

            val androidInfo = pm.getPackageInfo("android", PackageManager.GET_SIGNING_CERTIFICATES)
            val androidSigs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val si = androidInfo.signingInfo ?: return false
                if (si.hasMultipleSigners()) si.apkContentsSigners else si.signingCertificateHistory
            } else {
                @Suppress("DEPRECATION")
                androidInfo.signatures
            }

            val ours = signatures.map { it.toByteArray().toList() }.toSet()
            val theirs = androidSigs.map { it.toByteArray().toList() }.toSet()
            ours.any { theirs.contains(it) }
        } catch (e: Exception) {
            false
        }
    }

    // ─────────────────────────────────────────────────────────
    // 规则评估
    // ─────────────────────────────────────────────────────────
    private fun evaluate(info: AppInfo): List<Hit> {
        val hits = mutableListOf<Hit>()

        for (rule in Rules.ALL) {
            if (!rule.enabled) continue

            val evidence = when (rule.type) {
                "package_keyword" -> matchPackageKeyword(rule, info)
                "permission_combo" -> matchPermissionCombo(rule, info)
                "permission_keyword" -> matchPermissionKeyword(rule, info)
                "exported_component" -> matchExported(info)
                "platform_signed" -> if (info.isPlatformSigned) "使用平台密钥签名" else null
                "privapp" -> if (info.apkPath?.contains("/priv-app/") == true) {
                    "APK 位于 priv-app"
                } else null
                "updateable_system" -> if (info.isSystemApp && info.isUpdatedSystemApp) {
                    "系统应用已被商店更新"
                } else null
                else -> null
            }

            if (evidence != null) {
                hits.add(
                    Hit(
                        ruleId = rule.id,
                        ruleName = rule.name,
                        weight = rule.weight,
                        type = rule.type,
                        evidence = evidence,
                        description = rule.description,
                        advice = rule.advice
                    )
                )
            }
        }

        return hits
    }

    private fun matchPackageKeyword(rule: Rule, info: AppInfo): String? {
        val targets = listOf(info.packageName, info.label)
        for (pattern in rule.matchPattern) {
            for (target in targets) {
                if (Regex(pattern).containsMatchIn(target)) {
                    return if (target == info.packageName) {
                        "包名 ${info.packageName} 命中"
                    } else {
                        "应用名「${info.label}」命中"
                    }
                }
            }
        }
        return null
    }

    private fun matchPermissionCombo(rule: Rule, info: AppInfo): String? {
        val need = rule.matchPattern
        val have = mutableListOf<String>()
        for (perm in need) {
            val granted = info.grantedPermissions.any { it.contains(perm) }
            if (granted) have.add(perm)
        }
        return if (have.size == need.size) {
            "权限齐备：${have.joinToString(" + ")}"
        } else null
    }

    private fun matchPermissionKeyword(rule: Rule, info: AppInfo): String? {
        for (perm in rule.matchPattern) {
            val g = info.grantedPermissions.firstOrNull { it.contains(perm) }
            if (g != null) return "已授予 $g"
        }
        return null
    }

    private fun matchExported(info: AppInfo): String? {
        val comps = info.unprotectedExportedComponents
        if (comps.isEmpty()) return null
        val preview = comps.take(3).joinToString("; ") { "${it.type} ${it.name.substringAfterLast('.')}" }
        val more = if (comps.size > 3) " 等 ${comps.size} 个" else ""
        return "无保护导出：$preview$more"
    }

    private fun checkUsageStatsPermission(): Boolean {
        return try {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE)
                as? android.app.AppOpsManager ?: return false
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    context.packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    context.packageName
                )
            }
            mode == android.app.AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }
}
