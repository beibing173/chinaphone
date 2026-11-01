package dev.beibing.chinaphone.ui

import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.beibing.chinaphone.audit.*
import dev.beibing.chinaphone.ui.theme.RiskColors
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChinaPhoneApp() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val engine = remember { AuditEngine(context) }

    var result by remember { mutableStateOf<ScanResult?>(null) }
    var scanning by remember { mutableStateOf(false) }
    var progress by remember { mutableStateOf(0 to 0) }
    var error by remember { mutableStateOf<String?>(null) }

    fun startScan() {
        if (scanning) return
        scanning = true
        error = null
        result = null
        scope.launch {
            try {
                result = engine.scan { done, total ->
                    progress = done to total
                }
            } catch (e: Exception) {
                error = e.message ?: "未知错误"
            } finally {
                scanning = false
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("手机自查", fontWeight = FontWeight.Bold)
                        Text(
                            "检查隐蔽上报组件",
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            when {
                scanning -> ScanningView(progress.first, progress.second)
                error != null -> ErrorView(error!!) { startScan() }
                result != null -> ResultView(result!!, context) { startScan() }
                else -> StartView { startScan() }
            }
        }
    }
}

@Composable
private fun StartView(onStart: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.Shield,
            contentDescription = null,
            modifier = Modifier.size(96.dp),
            tint = MaterialTheme.colorScheme.primary
        )
        Spacer(Modifier.height(24.dp))
        Text(
            "检查你的手机里有什么",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )
        Spacer(Modifier.height(12.dp))
        Text(
            "读取已安装应用、权限授予情况、组件导出面，" +
                "找出类似运营商定制组件、厂商安全组件这类" +
                "可能隐蔽上报的预装应用。",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 8.dp)
        )
        Spacer(Modifier.height(32.dp))
        Button(
            onClick = onStart,
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp),
            shape = RoundedCornerShape(16.dp)
        ) {
            Icon(Icons.Default.PlayArrow, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text("开始检查", fontSize = 16.sp, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.height(24.dp))
        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant
            ),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(Modifier.padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Default.Info,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(Modifier.width(8.dp))
                    Text("说明", fontWeight = FontWeight.Bold, fontSize = 13.sp)
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    "• 全程只读，不修改任何东西\n" +
                        "• 所有数据留在本机，不联网不上传\n" +
                        "• 结果是启发式判断，不是定论",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    lineHeight = 20.sp
                )
            }
        }
    }
}

@Composable
private fun ScanningView(done: Int, total: Int) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        CircularProgressIndicator(modifier = Modifier.size(64.dp))
        Spacer(Modifier.height(24.dp))
        Text("正在检查…", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(8.dp))
        if (total > 0) {
            Text(
                "$done / $total",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.height(16.dp))
            LinearProgressIndicator(
                progress = { done.toFloat() / total },
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

@Composable
private fun ErrorView(message: String, onRetry: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            Icons.Default.ErrorOutline,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = RiskColors.high
        )
        Spacer(Modifier.height(16.dp))
        Text("检查失败", style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(8.dp))
        Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(24.dp))
        Button(onClick = onRetry) { Text("重试") }
    }
}

@Composable
private fun ResultView(result: ScanResult, context: Context, onRescan: () -> Unit) {
    var showAllLow by remember { mutableStateOf(false) }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // ── 结论卡片 ──
        item {
            val verdictColor = when {
                result.high.isNotEmpty() -> RiskColors.high
                result.medium.isNotEmpty() -> RiskColors.medium
                else -> RiskColors.low
            }
            val verdictText = when {
                result.high.isNotEmpty() -> "发现 ${result.high.size} 个高风险组件"
                result.medium.isNotEmpty() -> "发现 ${result.medium.size} 个需关注的组件"
                else -> "未发现明显可疑组件"
            }
            Card(
                colors = CardDefaults.cardColors(containerColor = verdictColor.copy(alpha = 0.12f)),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(Modifier.padding(16.dp)) {
                    Text(
                        verdictText,
                        fontWeight = FontWeight.Bold,
                        fontSize = 18.sp,
                        color = verdictColor
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "共扫描 ${result.totalApps} 个应用" +
                            "（系统 ${result.systemApps} / 用户 ${result.userApps}）",
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        // ── 设备信息 ──
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text("设备信息", fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(8.dp))
                    InfoRow("品牌型号", "${result.device.brand} ${result.device.model}")
                    InfoRow("系统", "Android ${result.device.androidVersion} (SDK ${result.device.sdkInt})")
                    InfoRow("安全补丁", result.device.securityPatch)
                    InfoRow("规则库", "v${result.rulesVersion}")
                }
            }
        }

        // ── 使用统计权限提示 ──
        if (!result.usageStatsGranted) {
            item {
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.tertiaryContainer
                    ),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(Modifier.padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Warning, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text("部分判据未启用", fontWeight = FontWeight.Bold)
                        }
                        Spacer(Modifier.height(8.dp))
                        Text(
                            "未授予「应用使用统计」权限，" +
                                "无法判断哪些组件在24小时内被实际使用过。" +
                                "授权后可提高准确度。",
                            fontSize = 13.sp
                        )
                        Spacer(Modifier.height(12.dp))
                        OutlinedButton(onClick = {
                            try {
                                context.startActivity(
                                    Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                            } catch (_: Exception) {
                                try {
                                    context.startActivity(
                                        Intent(Settings.ACTION_SETTINGS)
                                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    )
                                } catch (_: Exception) {}
                            }
                        }) {
                            Text("去授权")
                        }
                    }
                }
            }
        }

        // ── 警告 ──
        if (result.warnings.isNotEmpty()) {
            item {
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer
                    ),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(Modifier.padding(16.dp)) {
                        result.warnings.forEach {
                            Text(it, fontSize = 12.sp)
                        }
                    }
                }
            }
        }

        // ── 高风险 ──
        if (result.high.isNotEmpty()) {
            item { SectionHeader("高风险组件", result.high.size, RiskColors.high) }
            items(result.high) { FindingCard(it) }
        }

        // ── 中风险 ──
        if (result.medium.isNotEmpty()) {
            item { SectionHeader("需关注", result.medium.size, RiskColors.medium) }
            items(result.medium) { FindingCard(it) }
        }

        // ── 低风险（可折叠）──
        if (result.low.isNotEmpty()) {
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    SectionHeader("常规组件", result.low.size, RiskColors.low)
                    Spacer(Modifier.weight(1f))
                    TextButton(onClick = { showAllLow = !showAllLow }) {
                        Text(if (showAllLow) "收起" else "展开")
                    }
                }
            }
            if (showAllLow) {
                items(result.low) { FindingCard(it, compact = true) }
            }
        }

        // ── 底部说明 ──
        item {
            Spacer(Modifier.height(8.dp))
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                ),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(Modifier.padding(16.dp)) {
                    Text("结果怎么读", fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "• 命中规则 ≠ 恶意，只是「值得确认」的信号\n" +
                            "• 厂商常规遥测、应用商店、推送服务都可能命中中低风险\n" +
                            "• 重点看：你完全不认识的包名、系统预装却从没用过的\n" +
                            "• 想拿铁证需要抓包，本工具做不到",
                        fontSize = 12.sp,
                        lineHeight = 19.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        // ── 重新扫描 ──
        item {
            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                onClick = onRescan,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.Refresh, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("重新检查")
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String, count: Int, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(10.dp)
                .background(color, RoundedCornerShape(5.dp))
        )
        Spacer(Modifier.width(8.dp))
        Text(
            title,
            fontWeight = FontWeight.Bold,
            fontSize = 15.sp
        )
        Spacer(Modifier.width(6.dp))
        Text(
            "($count)",
            fontSize = 13.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp)
    ) {
        Text(
            label,
            fontSize = 13.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(80.dp)
        )
        Text(value, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun FindingCard(finding: AppFinding, compact: Boolean = false) {
    var expanded by remember { mutableStateOf(!compact) }
    val levelColor = when (finding.level) {
        RiskLevel.HIGH -> RiskColors.high
        RiskLevel.MEDIUM -> RiskColors.medium
        RiskLevel.LOW -> RiskColors.low
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "${finding.score.toInt()}",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = levelColor
                )
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        finding.app.label,
                        fontWeight = FontWeight.Bold,
                        fontSize = 15.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        finding.app.packageName,
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                if (compact) {
                    IconButton(onClick = { expanded = !expanded }) {
                        Icon(
                            if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                            contentDescription = null
                        )
                    }
                }
            }

            Spacer(Modifier.height(8.dp))

            // 标签行
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (finding.app.isSystemApp) Tag("系统预装")
                if (finding.app.isUpdatedSystemApp) Tag("商店可更新")
                if (finding.app.isPlatformSigned) Tag("平台签名")
                if (finding.hits.isNotEmpty()) {
                    Tag("${finding.hits.size} 条规则", levelColor)
                }
            }

            AnimatedVisibility(visible = expanded) {
                Column {
                    Spacer(Modifier.height(10.dp))
                    HorizontalDivider()
                    Spacer(Modifier.height(10.dp))

                    finding.hits.forEach { hit ->
                        Column(Modifier.padding(bottom = 10.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    hit.ruleId,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = levelColor,
                                    modifier = Modifier
                                        .background(
                                            levelColor.copy(alpha = 0.12f),
                                            RoundedCornerShape(4.dp)
                                        )
                                        .padding(horizontal = 6.dp, vertical = 2.dp)
                                )
                                Spacer(Modifier.width(8.dp))
                                Text(
                                    hit.ruleName,
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Medium
                                )
                            }
                            Spacer(Modifier.height(4.dp))
                            Text(
                                hit.evidence,
                                fontSize = 12.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }

                    HorizontalDivider()
                    Spacer(Modifier.height(10.dp))
                    val topAdvice = finding.hits
                        .map { it.advice }
                        .distinct()
                        .firstOrNull()
                    if (topAdvice != null) {
                        Row {
                            Icon(
                                Icons.Default.Lightbulb,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = levelColor
                            )
                            Spacer(Modifier.width(6.dp))
                            Text(
                                topAdvice,
                                fontSize = 12.sp,
                                lineHeight = 18.sp
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Tag(text: String, color: Color? = null) {
    val c = color ?: MaterialTheme.colorScheme.onSurfaceVariant
    Text(
        text,
        fontSize = 10.sp,
        color = c,
        modifier = Modifier
            .background(c.copy(alpha = 0.1f), RoundedCornerShape(4.dp))
            .padding(horizontal = 6.dp, vertical = 2.dp)
    )
}
