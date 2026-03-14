#!/bin/bash
# grant-tcc.sh — 开发期自动授权 Screen Recording 和 Accessibility 权限
# 使用方法：sudo bash scripts/grant-tcc.sh
#
# 原理：直接写入用户 TCC 数据库，跳过系统弹窗
# 注意：仅用于开发调试，不影响发布版本

set -euo pipefail

BUNDLE_ID="com.anotherme.app"
TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"

if [[ ! -f "$TCC_DB" ]]; then
    echo "❌ TCC 数据库不存在: $TCC_DB"
    exit 1
fi

echo "🔧 为 $BUNDLE_ID 授权开发权限..."

# Screen Recording (kTCCServiceScreenCapture)
sqlite3 "$TCC_DB" "DELETE FROM access WHERE service='kTCCServiceScreenCapture' AND client='$BUNDLE_ID';"
sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, flags) VALUES ('kTCCServiceScreenCapture', '$BUNDLE_ID', 0, 2, 3, 1, 0);"
echo "✅ Screen Recording 已授权"

# Accessibility (kTCCServiceAccessibility)
sqlite3 "$TCC_DB" "DELETE FROM access WHERE service='kTCCServiceAccessibility' AND client='$BUNDLE_ID';"
sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, flags) VALUES ('kTCCServiceAccessibility', '$BUNDLE_ID', 0, 2, 3, 1, 0);"
echo "✅ Accessibility 已授权"

echo ""
echo "✨ 完成！重新启动 app 即可生效（无需重启系统）"
echo "⚠️  如果 macOS 版本 >= 14，Screen Recording 可能仍需首次手动确认"
