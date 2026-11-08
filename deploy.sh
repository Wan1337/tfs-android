#!/system/bin/sh
# =============================================================================
#  TFS-Android 部署脚本
#  把 fastboot/adb 二进制 + 依赖库 + tfs.sh 安装到 /data/local/tmp/tfs
#  /sdcard 是 fuse 文件系统，chmod 无效，所以必须复制到 data 分区才能执行
#  用法：sh deploy.sh [源目录]      源目录默认 = 本脚本所在目录
# =============================================================================
DST=/data/local/tmp/tfs

case "$0" in
  */*) SRCDIR="${0%/*}" ;;
  *)   SRCDIR="$(pwd)" ;;
esac
[ -n "$1" ] && SRCDIR="$1"
[ -d "$SRCDIR" ] || SRCDIR=/sdcard/TFS_Android

echo "源目录: $SRCDIR"
echo "目标  : $DST"

# root 检查
if [ "$(id -u)" != "0" ]; then
  if command -v su >/dev/null 2>&1; then
    echo "需要 root，提权重新执行..."
    exec su -c "sh '$SRCDIR/deploy.sh' '$SRCDIR'"
  fi
  echo "[错误] 需要 root 才能写入 $DST"
  exit 1
fi

mkdir -p "$DST/bin" "$DST/lib" "$DST/logs" "$DST/rom" || exit 1

for f in fastboot adb; do
  [ -f "$SRCDIR/bin/$f" ] && cp -f "$SRCDIR/bin/$f" "$DST/bin/$f"
done
for f in libfmt.so libc++_shared.so libz.so.1; do
  [ -f "$SRCDIR/lib/$f" ] && cp -f "$SRCDIR/lib/$f" "$DST/lib/$f"
done
# adb 需要一大堆 abseil/protobuf/brotli/zstd/lz4，整目录带上
for f in "$SRCDIR/lib/"*.so*; do
  [ -f "$f" ] && cp -f "$f" "$DST/lib/"
done
[ -f "$SRCDIR/tfs.sh" ]   && cp -f "$SRCDIR/tfs.sh" "$DST/tfs.sh"
[ -f "$SRCDIR/config.conf" ] && cp -f "$SRCDIR/config.conf" "$DST/config.conf"
mkdir -p "$DST/docs"
for f in "$SRCDIR/docs/"*.txt; do [ -f "$f" ] && cp -f "$f" "$DST/docs/"; done

chmod 755 "$DST/bin/fastboot" "$DST/bin/adb" "$DST/tfs.sh" 2>/dev/null
chmod 755 "$DST/lib/"*.so "$DST/lib/libz.so.1" 2>/dev/null

# 校验
echo "--- 校验 ---"
if [ -x "$DST/bin/fastboot" ]; then
  VER="$(LD_LIBRARY_PATH=$DST/lib "$DST/bin/fastboot" --version 2>&1 | head -1)"
  echo "fastboot: $VER"
else
  echo "[错误] fastboot 未就位"
  exit 1
fi
[ -x "$DST/tfs.sh" ] && echo "tfs.sh  : OK" || echo "[错误] tfs.sh 未就位"

# 生成 sdcard 侧入口（MT 扩展包指向这个文件即可）
RUN=/sdcard/TFS_Android/run.sh
cat > "$RUN" <<'EOS'
#!/system/bin/sh
# MT 管理器扩展包入口：把所有参数透传给 /data/local/tmp/tfs/tfs.sh
exec su -c "sh /data/local/tmp/tfs/tfs.sh $*"
EOS
echo "入口    : $RUN"
echo "完成。MT 扩展包命令建议填："
echo "  sh /sdcard/TFS_Android/run.sh"