#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="WeDesk"
INSTALL_TARGET="/Applications/${APP_NAME}.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
# TMPDIR 末尾自带斜杠，先去掉，否则 mktemp 出来的路径会有双斜杠，后面的前缀比对会失配。
TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
# 可能藏有残留副本的位置（/tmp 是符号链接，必须用 -H 才会跟随）。
SCAN_ROOTS=(/Applications "$HOME/Applications" "$HOME/Documents" "$TMP_BASE" /private/tmp /private/var/tmp)

registered_paths() {
  "$LSREGISTER" -dump 2>/dev/null \
    | sed -nE 's/^[[:space:]]*path:[[:space:]]*([^ ]+\.app)([[:space:]]|$).*/\1/p' \
    | grep -E "/${APP_NAME}([^/]*)?\.app$" || true
}

# 找出所有指向别处的 WeDesk 记录与磁盘副本，注销并删除，只保留 /Applications 一份。
# 参数 STAGE_PATH：本次构建的临时目录，必须跳过，否则会把刚编好的产物删掉。
sweep_duplicates() {
  local stage="$1" swept=0 path stray

  while IFS= read -r path; do
    [ -z "$path" ] && continue
    [ "$path" = "$INSTALL_TARGET" ] && continue
    "$LSREGISTER" -u "$path" >/dev/null 2>&1 || true
    echo "  注销 Launch Services 记录：$path"
    swept=1
  done < <(registered_paths)

  while IFS= read -r stray; do
    [ -z "$stray" ] && continue
    [ "$stray" = "$INSTALL_TARGET" ] && continue
    case "$stray" in *wedesk-build*) continue ;; esac   # 临时构建目录，永不删除
    if [ -n "$stage" ]; then
      case "$stray" in
        "$stage"*) continue ;;   # 跳过本次构建的临时产物
      esac
    fi
    [ -e "$stray" ] || continue
    rm -rf "$stray"
    echo "  删除磁盘残留副本：$stray"
    swept=1
  done < <(find -H "${SCAN_ROOTS[@]}" -maxdepth 6 -name "${APP_NAME}*.app" -prune 2>/dev/null || true)

  [ "$swept" = 0 ] && echo "  未发现重复项。"
  return 0
}

case "${1:-}" in
  --doctor)
    echo "检查 ${APP_NAME} 的注册情况（不重新构建）："
    sweep_duplicates ""
    echo "当前 Launch Services 注册路径："
    registered_paths | sed 's/^/  /'
    echo "当前磁盘上的 ${APP_NAME} 副本："
    find -H "${SCAN_ROOTS[@]}" -maxdepth 6 -name "${APP_NAME}*.app" -prune 2>/dev/null | sed 's/^/  /' || true
    exit 0
    ;;
esac

# 构建产物放在用户目录之外的临时目录。
# 原因：~/Documents 会被 Spotlight 索引，第二份 .app 一旦被收录，
# Launch Services 就会为同一个 bundle id 生成第二条记录，启动台随即出现重复图标。
STAGE="$(mktemp -d "${TMP_BASE}/wedesk-build.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

APP="$STAGE/${APP_NAME}.app"
BIN="$APP/Contents/MacOS/${APP_NAME}"

# 清掉旧版本遗留在项目里的构建目录（同样是为了不再被索引）。
rm -rf build

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc \
  -swift-version 5 \
  -O \
  -target arm64-apple-macos14.0 \
  -o "$BIN" \
  Sources/*.swift

cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -d Resources ]; then
  cp -R Resources/. "$APP/Contents/Resources/"
fi

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

if [ "${1:-}" = "--install" ]; then
  pkill -TERM -x "$APP_NAME" >/dev/null 2>&1 || true
  sleep 1
  rm -rf "$INSTALL_TARGET"
  ditto "$APP" "$INSTALL_TARGET"
  echo "清理重复注册："
  sweep_duplicates "$STAGE"
  open "$INSTALL_TARGET"
  echo "Installed: $INSTALL_TARGET"
else
  echo "Built: ${APP_NAME}.app（产物只存在于临时目录，不会被索引）"
fi
