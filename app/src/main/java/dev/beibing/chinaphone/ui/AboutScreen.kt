package dev.beibing.chinaphone.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.beibing.chinaphone.BuildConfig

/**
 * 关于页：隐私条款、权限清单、开源地址。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutScreen(onBack: () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("关于") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
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
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // ── 应用信息 ──
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text(
                        "ChinaPhone 手机自查",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        "版本 v${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "用自己的手机，查自己的手机。",
                        fontSize = 13.sp
                    )
                }
            }

            // ── 隐私条款 ──
            SectionCard("隐私条款") {
                Text(
                    "一、数据不离机\n" +
                        "本应用所有分析都在你的设备本地完成。不联网、不上传、不收集任何数据。",
                    fontSize = 13.sp, lineHeight = 21.sp
                )
                Spacer(Modifier.height(10.dp))
                Text(
                    "二、不申请网络权限\n" +
                        "APK 的 AndroidManifest 中没有声明 INTERNET 权限，从系统层面就无法联网。这是可验证的。",
                    fontSize = 13.sp, lineHeight = 21.sp
                )
                Spacer(Modifier.height(10.dp))
                Text(
                    "三、只读检查\n" +
                        "不修改任何系统设置，不停用任何应用，不读写用户文件。提供的处置建议需要你自己手动执行。",
                    fontSize = 13.sp, lineHeight = 21.sp
                )
                Spacer(Modifier.height(10.dp))
                Text(
                    "四、结果不做外部传输\n" +
                        "扫描结果只显示在本机屏幕上，不写入日志、不缓存到可被其他应用读取的位置。",
                    fontSize = 13.sp, lineHeight = 21.sp
                )
                Spacer(Modifier.height(10.dp))
                Text(
                    "五、开源可审计\n" +
                        "全部源码公开，任何人都可以检查上面的说法是否属实。",
                    fontSize = 13.sp, lineHeight = 21.sp
                )
            }

            // ── 使用的权限 ──
            SectionCard("使用的权限") {
                PermissionItem(
                    name = "QUERY_ALL_PACKAGES",
                    label = "查询已安装应用",
                    reason = "核心功能。需要枚举设备上的应用才能做审计。这是「上报应用列表」的前置能力，本应用用它来检查，不用它来上报。",
                    required = true
                )
                Divider(Modifier.padding(vertical = 10.dp))
                PermissionItem(
                    name = "PACKAGE_USAGE_STATS",
                    label = "应用使用情况",
                    reason = "可选。用于判断哪些组件在本机被实际使用过（辅助识别「用户从未打开却长期保活」的隐蔽组件）。需你手动到系统设置授权。",
                    required = false
                )
                Divider(Modifier.padding(vertical = 10.dp))
                PermissionItem(
                    name = "READ_PHONE_STATE",
                    label = "读取电话状态",
                    reason = "可选。仅用于判断本应用是否具备读取设备标识的能力（作为权限画像的参照）。不会读取你任何真实的 IMEI/IMSI 内容。",
                    required = false
                )
                Divider(Modifier.padding(vertical = 10.dp))
                PermissionItem(
                    name = "ACCESS_NETWORK_STATE",
                    label = "查看网络状态",
                    reason = "仅用于展示网络可用性判断。注意：没有 INTERNET 权限，本应用无法发起任何网络请求。",
                    required = false
                )
                Spacer(Modifier.height(12.dp))
                Text(
                    "本应用不申请：相机、麦克风、通讯录、短信、通话记录、位置、存储、网络。",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    lineHeight = 19.sp
                )
            }

            // ── 开源地址 ──
            SectionCard("开源地址") {
                LinkRow("GitHub 仓库", "https://github.com/beibing173/chinaphone")
                Spacer(Modifier.height(8.dp))
                LinkRow("问题反馈", "https://github.com/beibing173/chinaphone/issues")
                Spacer(Modifier.height(8.dp))
                LinkRow("最新版本", "https://github.com/beibing173/chinaphone/releases")
                Spacer(Modifier.height(8.dp))
                LinkRow("源码许可", "MIT License")
            }

            // ── 灵感来源 ──
            SectionCard("灵感来源") {
                Text(
                    "本项目源于 2026 年 11 月 X 平台上的两条公开实测：",
                    fontSize = 13.sp, lineHeight = 20.sp
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    "@MEterminator666 —— 首次排查小米 14 隐蔽上报",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.primary
                )
                Text(
                    "@Verluntas —— 拆解 SystemHelper，确认包名与行为",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.primary
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    "推文里提出的问题：为什么一个人装了 X / Telegram，" +
                        "会被要求卸载？排查结果是手机上有预装组件在主动上报应用列表。",
                    fontSize = 12.sp,
                    lineHeight = 19.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            // ── 免责 ──
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer
                ),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(Modifier.padding(16.dp)) {
                    Text("免责声明", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "本工具基于公开信息的启发式判断，不能证明任何应用存在恶意行为。" +
                            "报告是「需要进一步确认」的信号，请结合厂商公开说明与自身使用场景判断。",
                        fontSize = 12.sp, lineHeight = 19.sp
                    )
                }
            }

            Spacer(Modifier.height(8.dp))
            Text(
                "Made with 蓝鲸 🐋 · MIT License",
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.align(Alignment.CenterHorizontally)
            )
            Spacer(Modifier.height(16.dp))
        }
    }
}

@Composable
private fun SectionCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Text(
                title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(10.dp))
            content()
        }
    }
}

@Composable
private fun PermissionItem(
    name: String,
    label: String,
    reason: String,
    required: Boolean
) {
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(label, fontWeight = FontWeight.Medium, fontSize = 14.sp)
            Spacer(Modifier.width(6.dp))
            Surface(
                color = if (required)
                    MaterialTheme.colorScheme.primaryContainer
                else
                    MaterialTheme.colorScheme.surfaceVariant,
                shape = MaterialTheme.shapes.extraSmall
            ) {
                Text(
                    if (required) "必需" else "可选",
                    fontSize = 10.sp,
                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                )
            }
        }
        Spacer(Modifier.height(2.dp))
        Text(
            name,
            fontSize = 10.sp,
            color = MaterialTheme.colorScheme.primary
        )
        Spacer(Modifier.height(4.dp))
        Text(
            reason,
            fontSize = 12.sp,
            lineHeight = 18.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun LinkRow(label: String, value: String) {
    Row {
        Text(
            label,
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(72.dp)
        )
        Text(
            value,
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.primary
        )
    }
}

@Composable
private fun Divider(modifier: Modifier = Modifier) {
    HorizontalDivider(modifier = modifier, color = MaterialTheme.colorScheme.outlineVariant)
}
