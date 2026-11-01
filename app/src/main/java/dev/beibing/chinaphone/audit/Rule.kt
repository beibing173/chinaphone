package dev.beibing.chinaphone.audit

/**
 * 规则定义。与 pc/rules.json 保持同构，便于两端共用同一套判据。
 */
data class Rule(
    val id: String,
    val name: String,
    val weight: Double,
    /** package_keyword / privapp / system_app / permission_combo /
     *  permission_keyword / exported_component / platform_signed / updateable_system */
    val type: String,
    /** 正则或权限名数组 */
    val matchPattern: List<String>,
    val description: String,
    val advice: String,
    val enabled: Boolean = true,
)
