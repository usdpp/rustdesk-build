#!/bin/zsh

set -u

BUNDLE_ID="com.carriez.rustdesk"

echo "RustDesk Mac 权限修复"
echo "===================="
echo
echo "此脚本只会清除 ${BUNDLE_ID} 的以下授权记录："
echo "  1. 屏幕录制"
echo "  2. 辅助功能"
echo "  3. 输入监控"
echo
echo "macOS 不允许脚本自动授予这些权限。记录清除后，仍需由你在系统设置中手动勾选 RustDesk。"
echo
read -r "answer?继续清理 RustDesk 的权限记录？[y/N] "

case "${answer:-}" in
  y|Y|yes|YES)
    ;;
  *)
    echo "已取消，未修改任何权限。"
    read -r "?按回车键关闭窗口。"
    exit 0
    ;;
esac

failed=0
for service in ScreenCapture Accessibility ListenEvent
do
  if /usr/bin/tccutil reset "$service" "$BUNDLE_ID"
  then
    echo "已清理：${service}"
  else
    echo "清理失败：${service}"
    failed=1
  fi
done

echo
if [ "$failed" -eq 0 ]
then
  echo "权限记录已清理。接下来请按提示逐项授权。"
else
  echo "部分记录清理失败；仍可继续检查系统设置中的权限。"
fi

echo
echo "第一步：在“屏幕与系统音频录制”中允许 RustDesk。"
/usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
read -r "?完成后回到终端，按回车键继续。"

echo
echo "第二步：在“辅助功能”中允许 RustDesk。"
/usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
read -r "?完成后回到终端，按回车键继续。"

echo
echo "第三步：在“输入监控”中允许 RustDesk。"
/usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
read -r "?完成后回到终端，按回车键继续。"

echo
echo "授权完成。请使用 Command-Q 完全退出 RustDesk，然后重新打开。"
read -r "?按回车键关闭窗口。"
