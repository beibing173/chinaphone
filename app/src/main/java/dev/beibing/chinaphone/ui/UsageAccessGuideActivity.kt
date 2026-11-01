package dev.beibing.chinaphone.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.beibing.chinaphone.ui.theme.ChinaPhoneTheme

/**
 * 应用使用统计授权引导页。
 *
 * 部分 ROM 的 usage access 设置入口不同，这里给出手动路径说明。
 */
class UsageAccessGuideActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            ChinaPhoneTheme {
                Surface {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(24.dp),
                        verticalArrangement = Arrangement.Center
                    ) {
                        Text(
                            "如何授予「应用使用统计」",
                            style = MaterialTheme.typography.headlineSmall
                        )
                        Spacer(Modifier.height(16.dp))
                        Text(
                            "设置 → 应用 → 特殊应用权限 → 使用情况访问权限 → 找到「手机自查」→ 允许",
                            style = MaterialTheme.typography.bodyLarge
                        )
                        Spacer(Modifier.height(12.dp))
                        Text(
                            "不同品牌路径略有差异：\n" +
                                "• 华为/荣耀：设置 → 隐私 → 更多隐私设置 → 使用情况访问权限\n" +
                                "• 小米/红米：设置 → 隐私保护 → 特殊权限设置 → 使用情况访问权限\n" +
                                "• OPPO/一加：设置 → 应用 → 特殊应用权限 → 使用情况访问权限\n" +
                                "• vivo/iQOO：设置 → 应用与权限 → 权限管理 → 特殊权限",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(Modifier.height(24.dp))
                        Button(onClick = { finish() }) {
                            Text("知道了")
                        }
                    }
                }
            }
        }
    }
}
