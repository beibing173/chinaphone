package dev.beibing.chinaphone.audit

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 审计引擎：采集本机应用信息，按规则库打分。
 *
 * 全程只读，不修改任何系统状态，不联网。
 */
class AuditEngine(private val context: Context) {

    private val pm: PackageManager = context.packageManager

    /**
     * 执行完整扫描。
     */
    suspend fun scan(onProgress: (Int, Int) -> Unit = { _, _ -> }): ScanResult =
        withContext(Dispatchers.IO) {
            val warnings = mutableListOf<String>()

            // ── 1. 采集设备信息 ──
            val device = DeviceInfo.collect(pm)

            // ── 2. 枚举已安装应用 ──
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

            // ── 3. 逐个应用构建信息并打分 ──
            val findings = mutableListOf<AppFinding>()
            var systemCount = 0
            var userCount = 0

            packages.forEachIndexed { index, pkg ->
                onProgress(index + 1, packages.size)
                val info = try {
                    buildAppInfo(pkg)
                } catch (e: Exception) {
                    null
                } ?: return@forEachIndexed

                if (info.isSystemApp) systemCount++ else userCount++

                val hits = evaluate(info)
                if (hits.isEmpty()) return@forEachIndexed

                val seen = mutableSetOf<String>()
                val distinctHits = hits.filter { seen.add(it.ruleId) }
                var score = distinctHits.sumOf { it.weight }
                if (score > 100.0) score = 100.0

                findings.add(
                    AppFinding(
                        app = info,
                        hits = distinctHits,
                        score = score,
                        level = RiskLevel.fromScore(
                            score,
                            Rules.HIGH_THRESHOLD,
                            Rules.MEDIUM_THRESHOLD
                        )
                    )
                )
            }

            // ── 4. 使用统计权限状态 ──
            val usageGranted = checkUsageStatsPermission()

            ScanResult(
                device = device,
                findings = findings.sortedByDescending { it.score },
                totalApps = packages.size,
                systemApps = systemCount,
                userApps = userCount,
                rulesVersion = Rules.VERSION,
                warnings = warnings,
                usageStatsGranted = usageGranted
            )
        }

    // ─────────────────────────────────────────────────────────
    // 构建 AppInfo
    // ─────────────────────────────────────────────────────────
    private fun buildAppInfo(pkg: PackageInfo): AppInfo? {
        val ai: ApplicationInfo = pkg.applicationInfo ?: return null
        val pkgName = pkg.packageName ?: return null

        val label = try {
            pm.getApplicationLabel(ai).toString()
        } catch (e: Exception) {
            pkgName
        }

        // 已授予 vs 已申请
        val requested = (pkg.requestedPermissions ?: emptyArray()).toSet()
        val granted = requested.filter { perm ->
            try {
                pm.checkPermission(perm, pkgName) == PackageManager.PERMISSION_GRANTED
            } catch (e: Exception) {
                false
            }
        }.toSet()

        // 去掉 android.permission. 前缀，便于规则匹配
        fun short(p: String) = p.substringAfterLast('.')

        val grantedShort = granted.map(::short).toSet()
        val requestedShort = requested.map(::short).toSet()

        // 系统应用判定
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

        // 导出的、且无权限保护的组件
        val exported = collectUnprotectedExported(pkg, pkgName)

        // 平台签名判定
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
            grantedPermissions = grantedShort,
            requestedPermissions = requestedShort,
            unprotectedExportedComponents = exported,
            isPlatformSigned = platformSigned,
        )
    }

    /**
     * 找出 exported=true 且没有 permission 保护的组件。
     *
     * 说明：不申请 DUMP 类特权或特殊权限时，只能看到本应用
     * 和部分系统应用的组件。这是 Android 的隐私设计，属预期限制。
     */
    private fun collectUnprotectedExported(
        pkg: PackageInfo,
        pkgName: String
    ): List<ExportedComponent> {
        val result = mutableListOf<ExportedComponent>()

        // 说明：
        // 1. pkg.activities / services / receivers 的元素本身就是 ActivityInfo /
        //    ServiceInfo / ReceiverInfo（都继承 ComponentInfo），没有 .info 属性；
        //    只有 actions / providers 这类才是 PackageInfo 包装类型。
        // 2. ActivityInfo.FLAG_EXPORTED 是 @hide 的内部常量，公开 SDK 里没有。
        //    公开 API 只有 ComponentInfo.exported 布尔字段（API 33+），
        //    所以这里只用 exported，代码块本身已限定 TIRAMISU+。
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

            // 判定方式：系统预装 + 与 android 包的签名哈希一致即视为平台签名
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
                "system_app" -> if (info.isSystemApp) "系统预装应用" else null
                "privapp" -> if (info.apkPath?.contains("/priv-app/") == true) {
                    "APK 位于 priv-app：${info.apkPath}"
                } else null
                "permission_combo" -> matchPermissionCombo(rule, info)
                "permission_keyword" -> matchPermissionKeyword(rule, info)
                "exported_component" -> matchExported(rule, info)
                "platform_signed" -> if (info.isPlatformSigned) "使用平台密钥签名" else null
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
                        "包名 ${info.packageName} 命中 /$pattern/"
                    } else {
                        "应用名「${info.label}」命中 /$pattern/"
                    }
                }
            }
        }
        return null
    }

    private fun matchPermissionCombo(rule: Rule, info: AppInfo): String? {
        val need = rule.matchPattern
        val have = mutableListOf<String>()
        val missing = mutableListOf<String>()

        for (perm in need) {
            // 子串匹配：READ_PHONE_STATE 也匹配 android.permission.READ_PHONE_STATE
            val granted = info.grantedPermissions.any { it.contains(perm) }
            val requested = info.requestedPermissions.any { it.contains(perm) }
            when {
                granted -> have.add(perm)
                requested -> missing.add("$perm(未授予)")
                else -> missing.add(perm)
            }
        }

        return if (have.size == need.size) {
            "权限齐备：${have.joinToString(" + ")}"
        } else {
            null
        }
    }

    private fun matchPermissionKeyword(rule: Rule, info: AppInfo): String? {
        for (perm in rule.matchPattern) {
            val grantedOne = info.grantedPermissions.firstOrNull { it.contains(perm) }
            if (grantedOne != null) {
                return "已授予权限 $grantedOne"
            }
        }
        return null
    }

    private fun matchExported(rule: Rule, info: AppInfo): String? {
        val comps = info.unprotectedExportedComponents
        if (comps.isEmpty()) return null
        val preview = comps.take(3).joinToString("; ") { "${it.type} ${it.name}" }
        val more = if (comps.size > 3) " 等 ${comps.size} 个" else ""
        return "无权限保护的导出组件：$preview$more"
    }

    // ─────────────────────────────────────────────────────────
    // 使用统计权限检查
    // ─────────────────────────────────────────────────────────
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
