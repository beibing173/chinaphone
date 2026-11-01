#!/usr/bin/env bash
# 读取项目版本号，供 CI 与本地脚本共用。
#
# 用法:
#   ./scripts/version.sh            # 输出 1.0.0
#   ./scripts/version.sh name       # 输出 1.0.0
#   ./scripts/version.sh code       # 输出 1
#   ./scripts/version.sh tag        # 输出 v1.0.0
#   ./scripts/version.sh validate   # 校验版本号格式，非法则非零退出
#
# 单一数据源: app/build.gradle.kts 里的 appVersionName / appVersionCode

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADLE_FILE="$ROOT/app/build.gradle.kts"

if [[ ! -f "$GRADLE_FILE" ]]; then
  echo "ERROR: 找不到 $GRADLE_FILE" >&2
  exit 1
fi

# 提取 val appVersionName = "1.0.0"
VERSION_NAME="$(grep -oE 'val[[:space:]]+appVersionName[[:space:]]*=[[:space:]]*"[^"]+"' "$GRADLE_FILE" \
  | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')"

# 提取 val appVersionCode = 1
VERSION_CODE="$(grep -oE 'val[[:space:]]+appVersionCode[[:space:]]*=[[:space:]]*[0-9]+' "$GRADLE_FILE" \
  | head -n1 | grep -oE '[0-9]+$')"

if [[ -z "${VERSION_NAME:-}" ]]; then
  echo "ERROR: 无法从 build.gradle.kts 解析 appVersionName" >&2
  exit 1
fi
if [[ -z "${VERSION_CODE:-}" ]]; then
  echo "ERROR: 无法从 build.gradle.kts 解析 appVersionCode" >&2
  exit 1
fi

case "${1:-name}" in
  name)     echo "$VERSION_NAME" ;;
  code)     echo "$VERSION_CODE" ;;
  tag)      echo "v$VERSION_NAME" ;;
  validate)
    # 语义化版本: X.Y.Z，允许 -suffix
    if [[ ! "$VERSION_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
      echo "ERROR: 版本号 '$VERSION_NAME' 不符合语义化版本格式 (X.Y.Z)" >&2
      exit 1
    fi
    if ! [[ "$VERSION_CODE" =~ ^[0-9]+$ ]] || [[ "$VERSION_CODE" -lt 1 ]]; then
      echo "ERROR: versionCode '$VERSION_CODE' 必须是正整数" >&2
      exit 1
    fi
    echo "OK versionName=$VERSION_NAME versionCode=$VERSION_CODE"
    ;;
  *)
    echo "未知参数: $1" >&2
    echo "可用: name | code | tag | validate" >&2
    exit 1
    ;;
esac
