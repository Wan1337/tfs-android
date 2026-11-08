#!/system/bin/sh
# =============================================================================
#  Tiny Fastboot Script (Android)  v1.7.0-sh
#  对标原版 Tiny Fastboot Script (Windows) v1.7.0 菜单，全项功能移植
#  原版作者：AlphaEva      sh 移植
#  跑法：sh tfs.sh               交互菜单
#        sh tfs.sh check         环境自检
#        sh tfs.sh <目录|xml>     自动刷写
# =============================================================================

VERSION="v1.11.0-sh"
FASTBOOT_HOME="/data/local/tmp/tfs"

# ---------------------------------------------------------------- 定位自身 ---
SELF="$0"
case "$SELF" in
  */*) SELFDIR="${SELF%/*}" ;;
  *)   SELFDIR="$(pwd)" ;;
esac
[ -d "$SELFDIR" ] || SELFDIR="$FASTBOOT_HOME"

# --------------------------------------------------------------- 颜色/边框 ---
if [ -t 1 ] || [ -n "$TFS_COLOR" ]; then
  c_b()  { printf '\033[36m'; }
  c_bb() { printf '\033[94m'; }
  c_g()  { printf '\033[32m'; }
  c_y()  { printf '\033[33m'; }
  c_r()  { printf '\033[31m'; }
  c_d()  { printf '\033[90m'; }
  c_0()  { printf '\033[0m'; }
else
  c_b() { :; }; c_bb() { :; }; c_g() { :; }; c_y() { :; }; c_r() { :; }; c_d() { :; }; c_0() { :; }
fi

BOX_W=56
hline() { printf '%s' "$(c_bb)"; _i=0; while [ "$_i" -lt $((BOX_W)) ]; do printf '='; _i=$((_i+1)); done; printf '%s\n' "$(c_0)"; }
sline() { printf '%s' "$(c_d)"; _i=0; while [ "$_i" -lt $((BOX_W)) ]; do printf '-'; _i=$((_i+1)); done; printf '%s\n' "$(c_0)"; }
line_soft() { sline; }

# 中英混排补空格：UTF-8 三字节汉字按 2 显示列计算宽度（不依赖 ${#} 的字符/字节语义）
pad() {
  _t="$1"; _w="$2"
  _tb=$(printf '%s' "$_t" | wc -c | tr -d ' ')
  _mb=$(printf '%s' "$_t" | tr -d '\000-\177' | wc -c | tr -d ' ')
  _n=$((_mb / 3))
  _len=$(( _tb - _mb + 2 * _n ))
  _sp=$((_w - _len))
  printf '%s' "$_t"
  if [ "$_sp" -gt 0 ]; then
    _i=0; while [ "$_i" -lt "$_sp" ]; do printf ' '; _i=$((_i+1)); done
  fi
}

# --------------------------------------------------------------- 自举/提权 ---
deploy_self() {
  src="$1"
  [ -f "$src/bin/fastboot" ] || return 1
  mkdir -p "$FASTBOOT_HOME/bin" "$FASTBOOT_HOME/lib" 2>/dev/null
  cp -f "$src/bin/fastboot" "$FASTBOOT_HOME/bin/" 2>/dev/null || return 1
  [ -f "$src/bin/adb" ] && cp -f "$src/bin/adb" "$FASTBOOT_HOME/bin/" 2>/dev/null
  cp -f "$src/lib/"*.so* "$FASTBOOT_HOME/lib/" 2>/dev/null
  chmod -R 755 "$FASTBOOT_HOME" 2>/dev/null
  [ -f "$src/tfs.sh" ] && cp -f "$src/tfs.sh" "$FASTBOOT_HOME/tfs.sh" 2>/dev/null
  if [ -d "$src/docs" ]; then mkdir -p "$FASTBOOT_HOME/docs"; cp -f "$src/docs/"*.txt "$FASTBOOT_HOME/docs/" 2>/dev/null; fi
  chmod 755 "$FASTBOOT_HOME/tfs.sh" 2>/dev/null
  [ -f "$FASTBOOT_HOME/bin/fastboot" ]
}

bootstrap() {
  for d in "$TFS_HOME" "$SELFDIR" "$FASTBOOT_HOME"; do
    [ -n "$d" ] || continue
    if [ -x "$d/bin/fastboot" ]; then HOME_DIR="$d"; return 0; fi
  done
  if deploy_self "$SELFDIR" || deploy_self "/sdcard/TFS_Android"; then
    HOME_DIR="$FASTBOOT_HOME"; return 0
  fi
  HOME_DIR="$SELFDIR"; return 1
}

TFS_ARGSTR="$*"
case "$0" in /*) SELF_ABS="$0" ;; *) SELF_ABS="$PWD/$0" ;; esac
bootstrap
export LD_LIBRARY_PATH="$HOME_DIR/lib:$LD_LIBRARY_PATH"
case "$HOME" in ""|"/") HOME="$HOME_DIR" ;; esac
ANDROID_USER_HOME="${ANDROID_USER_HOME:-$HOME_DIR/.android}"
export HOME ANDROID_USER_HOME

if [ "$(id -u)" != "0" ]; then
  if [ -f "$SELF_ABS" ] && command -v su >/dev/null 2>&1; then
    printf '%s[提示] fastboot 需要 root 访问 USB，正在提权执行...%s\n' "$(c_y)" "$(c_0)"
    if [ -n "$TFS_ARGSTR" ]; then exec su -c "TFS_PWD='$PWD' sh '$SELF_ABS' $TFS_ARGSTR"
    else exec su -c "TFS_PWD='$PWD' sh '$SELF_ABS'"; fi
  fi
  printf '%s[警告] 非 root 运行，fastboot 大概率枚举不到设备%s\n' "$(c_y)" "$(c_0)"
fi

FB="$HOME_DIR/bin/fastboot"
ADB="$HOME_DIR/bin/adb"
mkdir -p "$HOME_DIR/rom" 2>/dev/null
# 日志目录：不可写时逐级回退，避免重定向报错刷屏
LOGDIR=""
for cand in "$HOME_DIR/logs" "/sdcard/TFS_Android/logs" "${TMPDIR:-/tmp}"; do
  mkdir -p "$cand" 2>/dev/null
  if [ -w "$cand" ]; then LOGDIR="$cand"; break; fi
done
[ -n "$LOGDIR" ] || LOGDIR="${TMPDIR:-/tmp}"
LOG="$LOGDIR/tfs_$(date +%Y%m%d-%H%M%S).log"
TMPF="$LOGDIR/.tmpout"

# ---------------------------------------------------------------- 配置读取 ---
SKIP_LIST="cid carrier cdt utags devinfo frp persist modemst1 modemst2 fsg logo_a logo_b"
KEEP_DATA=1
DRYRUN=0
WIPE_CONFIRM=1
FASTBOOT_BIN=""
CFG="$HOME_DIR/config.conf"
[ -f "$CFG" ] && . "$CFG"
[ -n "$FASTBOOT_BIN" ] && [ -x "$FASTBOOT_BIN" ] && FB="$FASTBOOT_BIN"

save_cfg() {
  { printf 'SKIP_LIST="%s"\n' "$SKIP_LIST"
    printf 'KEEP_DATA=%s\n' "$KEEP_DATA"
    printf 'WIPE_CONFIRM=%s\n' "$WIPE_CONFIRM"
    printf 'FASTBOOT_BIN="%s"\n' "$FASTBOOT_BIN"
  } > "$CFG" 2>/dev/null
}

# ---------------------------------------------------------------- 输出函数 ---
log()  { printf '%s\n' "$*"; { printf '%s\n' "$*" >> "$LOG"; } 2>/dev/null; }
warn() { printf '%s[警告] %s%s\n' "$(c_y)" "$*" "$(c_0)"; { printf '[警告] %s\n' "$*" >> "$LOG"; } 2>/dev/null; }
err()  { printf '%s[错误] %s%s\n' "$(c_r)" "$*" "$(c_0)"; { printf '[错误] %s\n' "$*" >> "$LOG"; } 2>/dev/null; }
ok()   { printf '%s[完成] %s%s\n' "$(c_g)" "$*" "$(c_0)"; { printf '[完成] %s\n' "$*" >> "$LOG"; } 2>/dev/null; }
info() { printf '%s[信息] %s%s\n' "$(c_b)" "$*" "$(c_0)"; }
hr()   { line_soft; }

runit() {
  "$@" > "$TMPF" 2>&1
  _rc=$?
  while IFS= read -r _l || [ -n "$_l" ]; do
    printf '%s\n' "$_l"
    { printf '%s\n' "$_l" >> "$LOG"; } 2>/dev/null
  done < "$TMPF"
  return $_rc
}

ask() {
  _p="$1"; _d="$2"
  if [ -t 0 ]; then
    printf '%s' "$_p" > /dev/tty 2>/dev/null || printf '%s' "$_p"
    read -r _a
    if [ -n "$_a" ]; then printf '%s' "$_a"; return 0; fi
    printf '%s' "$_d"; return 0
  fi
  printf '%s' "$_d"
}

confirm() {
  [ "$WIPE_CONFIRM" = "0" ] && return 0
  [ -t 0 ] || { warn "非交互环境默认不执行（--yes 或菜单 m 关掉确认）"; return 1; }
  printf '%s%s [y/N]: %s' "$(c_y)" "$1" "$(c_0)"
  read -r _c
  case "$_c" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

pause_key() {
  [ -t 0 ] || return 0
  printf '%s按回车返回菜单...%s' "$(c_d)" "$(c_0)"
  read -r _k
}

usage() {
  hr
  printf ' %sTiny Fastboot Script (Android)%s  %s
' "$(c_b)" "$(c_0)" "$VERSION"
  hr
  printf '用法: tfs.sh [--dry] [--factory] [--yes]\n'
  printf '       [--serial SN] <命令> [参数]\n'

  printf ' check                            环境自检\n'
  printf ' devices                          列出设备\n'
  printf ' info                             设备信息\n'
  printf ' flash <目录|xml> [ALL|AP|BP|BL]  按 XML 刷写\n'
  printf ' ap|bl <目录>                     只刷 AP / BL\n'
  printf ' img <文件> [分区]                单镜像\n'
  printf ' super <目录>                     super 稀疏分片\n'
  printf ' erase data|modem                 擦除\n'
  printf ' slot a|b                         切槽\n'
  printf ' reboot sys|bl|rec|edl|fbcl       重启\n'
  printf ' unlock data|ul|fl|status         解锁\n'
  printf ' adb list|bl|rc|sh|push|pull|kill\n'
  printf '                                  adb 转发操作\n'
  printf ' doc [cid|faq|changelog]          看内置文档\n'
  printf '                                  无参数 = 进菜单\n'
  hr
}
pager() {
  _f="$1"
  if [ ! -f "$_f" ]; then warn "找不到文档：$_f"; return 1; fi
  # 非 tty（脚本/自动化）：直接整篇输出，不分页
  if [ ! -t 0 ]; then cat "$_f"; return 0; fi
  _total=$(wc -l < "$_f" | tr -d ' ')
  _s=1
  sline
  while [ "$_s" -le "$_total" ]; do
    _e=$((_s + 17))
    sed -n "${_s},${_e}p" "$_f"
    if [ "$_e" -ge "$_total" ]; then break; fi
    printf '%s-- (%s/%s) 回车继续，q 退出 --%s' "$(c_d)" "$_e" "$_total" "$(c_0)"
    read -r _k || break
    case "$_k" in q|Q) break ;; esac
    _s=$((_e + 1))
  done
  sline
}

# ---------------------------------------------------------------- 设备操作 ---
fb() { "$FB" ${SERIAL:+-s "$SERIAL"} "$@"; }

have_fb() {
  if [ ! -x "$FB" ]; then
    err "找不到 fastboot：$FB"
    log "把 aarch64 fastboot 放到 $HOME_DIR/bin/fastboot，或跑 deploy.sh"
    return 1
  fi
}

dev_list() { "$FB" devices 2>/dev/null | tr -d '\r' | while read -r s st; do [ -n "$s" ] && printf '%s\n' "$s"; done; }

pick_device() {
  have_fb || return 1
  if [ "$DRYRUN" = "1" ]; then
    SERIAL="${SERIAL:-DRYRUN}"; export SERIAL
    ok "干跑模式：跳过设备检测（SERIAL=$SERIAL）"; return 0
  fi
  DL="$(dev_list)"
  if [ -z "$DL" ]; then
    err "未检测到 fastboot 设备（确认目标机已进 bootloader / OTG 线正常 / 已 root）"
    return 1
  fi
  N=$(printf '%s\n' "$DL" | grep -c .)
  if [ "$N" = "1" ]; then
    SERIAL="$DL"
  else
    log "检测到多个设备："; printf '%s\n' "$DL" | nl -w2 -s') '
    SERIAL="$(ask '请输入序列号: ' "$(printf '%s\n' "$DL" | head -1)")"
  fi
  export SERIAL
  ok "目标设备：$SERIAL"
  return 0
}

getvar() { fb getvar "$1" 2>&1 | tr -d '\r' | sed -n "s/.*$1:[ ]*//p" | head -1; }

# ---------------------------------------------------------------- 刷写引擎 ---
is_skip() { for p in $SKIP_LIST; do [ "$p" = "$1" ] && return 0; done; return 1; }

img_size() {
  [ -f "$1" ] || { printf '缺失'; return; }
  s=$(wc -c < "$1" 2>/dev/null); [ -n "$s" ] || s=0
  if [ "$s" -ge 1048576 ]; then printf '%d.%d MB' $((s/1048576)) $(( (s%1048576)*10/1048576 ))
  elif [ "$s" -ge 1024 ]; then printf '%d.%d KB' $((s/1024)) $(( (s%1024)*10/1024 ))
  else printf '%d B' "$s"; fi
}

ATTR() {
  _s="$1"; _k="$2"
  case "$_s" in
    *"$_k=\""*) _r="$_s"; _r="${_r#*"$_k=\""}"; printf '%s' "${_r%%\"*}" ;;
    *) printf '' ;;
  esac
}

step_flash() {
  _p="$1"; _f="$2"
  if is_skip "$_p"; then printf '%s  . 跳过分区 %s（跳过表）%s\n' "$(c_d)" "$_p" "$(c_0)"; return 0; fi
  case "$_f" in */*) _path="$_f" ;; *) _path="$PKGDIR/$_f" ;; esac
  if [ ! -f "$_path" ]; then err "镜像不存在：$_f"; FAIL=$((FAIL+1)); return 1; fi
  printf '%s  >%s flash %-16s %s%s\n' "$(c_b)" "$(c_0)" "$_p" "$(img_size "$_path")" "$(c_d)"
  if [ "$DRYRUN" = "1" ]; then OKS=$((OKS+1)); return 0; fi
  runit "$FB" ${SERIAL:+-s "$SERIAL"} flash "$_p" "$_path"
  if [ $? -ne 0 ]; then err "刷写失败：$_p"; FAIL=$((FAIL+1)); return 1; fi
  OKS=$((OKS+1)); return 0
}

step_erase() {
  _p="$1"
  if is_skip "$_p"; then printf '%s  . 跳过擦除 %s（跳过表）%s\n' "$(c_d)" "$_p" "$(c_0)"; return 0; fi
  if [ "$KEEP_DATA" = "1" ]; then printf '%s  . skip erase %s（保留数据模式）%s\n' "$(c_d)" "$_p" "$(c_0)"; return 0; fi
  if [ "$_p" = "userdata" ] || [ "$_p" = "metadata" ]; then
    confirm "即将擦除 $_p（全部数据），继续？" || { warn "已取消 $_p"; return 0; }
  fi
  printf '%s  >%s erase %s\n' "$(c_b)" "$(c_0)" "$_p"
  [ "$DRYRUN" = "1" ] && return 0
  runit "$FB" ${SERIAL:+-s "$SERIAL"} erase "$_p"
  if [ $? -ne 0 ]; then err "擦除失败：$_p"; FAIL=$((FAIL+1)); return 1; fi
  return 0
}

step_oem() {
  _v="$1"; _val="$2"
  printf '%s  >%s oem %s %s\n' "$(c_b)" "$(c_0)" "$_v" "$_val"
  [ "$DRYRUN" = "1" ] && return 0
  if [ -n "$_val" ]; then runit "$FB" ${SERIAL:+-s "$SERIAL"} oem "$_v" "$_val"
  else runit "$FB" ${SERIAL:+-s "$SERIAL"} oem "$_v"; fi
  return 0
}

xml_flash() {
  XML="$1"; SCOPE="${2:-ALL}"
  PKGDIR="${XML%/*}"; [ "$PKGDIR" = "$XML" ] && PKGDIR="."
  [ -f "$XML" ] || { err "XML 不存在：$XML"; return 1; }
  CLEAN="$HOME_DIR/logs/.xmlclean"
  tr -d '\r' < "$XML" > "$CLEAN"
  FAIL=0; OKS=0
  N_FLASH=$(grep -c 'operation="flash"' "$CLEAN" 2>/dev/null); [ -n "$N_FLASH" ] || N_FLASH=0

  hr
  printf ' %s清单%s  %s\n' "$(c_b)" "$(c_0)" "$XML"
  printf ' %s目录%s  %s\n' "$(c_b)" "$(c_0)" "$PKGDIR"
  printf ' %s范围%s  %-3s   %s步骤%s %-3s  %s干跑%s %s  %s保留数据%s %s\n' \
    "$(c_b)" "$(c_0)" "$SCOPE" "$(c_b)" "$(c_0)" "$N_FLASH" "$(c_b)" "$(c_0)" "$DRYRUN" "$(c_b)" "$(c_0)" "$KEEP_DATA"
  hr

  CUR_IF=""
  while IFS= read -r ln || [ -n "$ln" ]; do
    case "$ln" in *'interface="'*) CUR_IF="$(ATTR "$ln" interface)" ;; esac
    case "$SCOPE" in
      AP) [ "$CUR_IF" = "BP" ] && continue; [ "$CUR_IF" = "BL" ] && continue ;;
      BP) [ "$CUR_IF" = "BP" ] || continue ;;
      BL) [ "$CUR_IF" = "BL" ] || continue ;;
    esac
    case "$ln" in
      *'operation="flash"'*)  step_flash "$(ATTR "$ln" partition)" "$(ATTR "$ln" filename)" ;;
      *'operation="erase"'*)  step_erase "$(ATTR "$ln" partition)" ;;
      *'operation="oem"'*)    step_oem "$(ATTR "$ln" var)" "$(ATTR "$ln" value)" ;;
      *'operation="reboot"'*) log "  > reboot $(ATTR "$ln" var)"
                              [ "$DRYRUN" = "1" ] || runit "$FB" ${SERIAL:+-s "$SERIAL"} reboot "$(ATTR "$ln" var)" ;;
    esac
  done < "$CLEAN"

  hr
  if [ "$FAIL" = "0" ]; then ok "结果：成功 $OKS 步"
  else err "结果：成功 $OKS 步，失败 $FAIL 步"; fi
  [ "$FAIL" = "0" ]
}

find_xml() {
  for f in "$@"; do case "$f" in *.xml) printf '%s' "$f"; return 0 ;; esac; done
  for n in flashfile.xml servicefile.xml crc.xml; do
    [ -f "$PKGDIR/$n" ] && { printf '%s' "$PKGDIR/$n"; return 0; }
  done
  return 1
}

flash_image() {
  _f="$1"; _p="$2"
  [ -f "$_f" ] || { err "文件不存在：$_f"; return 1; }
  _b="$(basename "$_f")"
  if [ -z "$_p" ]; then
    _p="$(printf '%s' "$_b" | sed 's/\.img.*$//; s/_a$//; s/_b$//')"
    case "$_b" in
      *magisk_patched*) _p="boot" ;;
      *[Tt][Ww][Rr][Pp]*|*recovery*) _p="recovery" ;;
    esac
  fi
  printf '%s  >%s flash %-14s <- %s  %s\n' "$(c_b)" "$(c_0)" "$_p" "$_b" "$(img_size "$_f")"
  [ "$DRYRUN" = "1" ] && return 0
  runit "$FB" ${SERIAL:+-s "$SERIAL"} flash "$_p" "$_f"
  [ $? -eq 0 ] || { err "刷写失败"; return 1; }
  ok "已刷入 $_p"
}

flash_all_img_in_dir() {
  _d="$1"; n=0; f=0
  for img in "$_d"/*.img; do
    [ -f "$img" ] || continue
    case "$(basename "$img")" in super.img|*_b.img) continue ;; esac
    n=$((n+1)); flash_image "$img" || f=$((f+1))
  done
  log "目录内 img：$n 个，失败 $f 个"
}

flash_super_sparse() {
  _d="$1"
  if [ -f "$_d/super.img" ]; then
    warn "检测到整包 super.img（非分片），耗时较长"
    flash_image "$_d/super.img" super; return $?
  fi
  _cnt=$(ls "$_d" 2>/dev/null | grep -c '^super.img_sparsechunk\.')
  if [ "$_cnt" -gt 0 ]; then
    log "检测到 super 稀疏分片 $_cnt 个，按序号刷入"
    ls "$_d" | grep '^super.img_sparsechunk\.' | sort -t. -k3 -n | while IFS= read -r c; do
      printf '%s  >%s flash super %s\n' "$(c_b)" "$(c_0)" "$c"
      [ "$DRYRUN" = "1" ] && continue
      runit "$FB" ${SERIAL:+-s "$SERIAL"} flash super "$_d/$c" || err "分片失败：$c"
    done
    return 0
  fi
  warn "目录里没有 super.img / super.img_sparsechunk.*"
}

do_flash_all() {
  T="$1"; SCOPE="${2:-ALL}"
  if [ -d "$T" ]; then PKGDIR="$T"; else PKGDIR="${T%/*}"; [ "$PKGDIR" = "$T" ] && PKGDIR="."; fi
  X="$(find_xml "$T")"
  if [ -n "$X" ]; then xml_flash "$X" "$SCOPE"
  else warn "目录里没有 flashfile.xml / servicefile.xml，改为逐 img 刷写"; flash_all_img_in_dir "$PKGDIR"; fi
}

# ---------------------------------------------------------- 业务动作封装 ---
act_flash_scope() {
  pick_device || return 1
  d="$(ask '固件目录（含 flashfile.xml / servicefile.xml）: ' "$DEF_DIR")"
  [ -d "$d" ] || { err "目录不存在：$d"; return 1; }
  do_flash_all "$d" "$1"
}

act_flash_full() {   # $1=0 恢复出厂  1 保留数据
  pick_device || return 1
  d="$(ask '固件目录: ' "$DEF_DIR")"
  [ -d "$d" ] || { err "目录不存在：$d"; return 1; }
  OLD_KEEP="$KEEP_DATA"
  KEEP_DATA="$1"
  if [ "$1" = "0" ]; then
    confirm "完整固件刷入 + 恢复出厂设置（清空全部数据），继续？" || { KEEP_DATA="$OLD_KEEP"; return 1; }
  fi
  do_flash_all "$d" ALL
  rc=$?
  if [ "$rc" = "0" ] && [ "$DRYRUN" != "1" ]; then
    info "重新获取分区表（应用 Bootloader 带来的分区变更）"
    runit "$FB" ${SERIAL:+-s "$SERIAL"} getvar all >/dev/null
    if [ "$1" = "0" ]; then
      for p in userdata cache metadata; do
        printf '%s  >%s erase %s\n' "$(c_b)" "$(c_0)" "$p"
        runit "$FB" ${SERIAL:+-s "$SERIAL"} erase "$p"
      done
    fi
  fi
  KEEP_DATA="$OLD_KEEP"
  return $rc
}

act_factory_reset() {
  pick_device || return 1
  confirm "恢复出厂设置：清空 Data + Cache（全部数据丢失），继续？" || return 1
  for p in userdata cache metadata; do
    printf '%s  >%s erase %s\n' "$(c_b)" "$(c_0)" "$p"
    [ "$DRYRUN" = "1" ] && continue
    runit "$FB" ${SERIAL:+-s "$SERIAL"} erase "$p" || printf '%s  . %s 不存在或不可擦除%s\n' "$(c_d)" "$p" "$(c_0)"
  done
  ok "恢复出厂设置完成"
}

act_clear_modem() {
  pick_device || return 1
  confirm "清空基带缓存分区（modemst / mdmlm9kefs / mdmddr / nvdata），继续？" || return 1
  for p in modemst1 modemst2 fsg mdmlm9kefs1 mdmlm9kefs2 mdmlm9kefs3 mdmddr nvdata; do
    printf '%s  >%s erase %s\n' "$(c_b)" "$(c_0)" "$p"
    [ "$DRYRUN" = "1" ] && continue
    runit "$FB" ${SERIAL:+-s "$SERIAL"} erase "$p" || printf '%s  . %s 不存在或不可擦除%s\n' "$(c_d)" "$p" "$(c_0)"
  done
  ok "基带缓存分区已清空"
}

act_recovery() {
  pick_device || return 1
  f="$(ask 'Recovery 镜像路径: ' '')"
  [ -n "$f" ] || { err "没给文件路径"; return 1; }
  [ -f "$f" ] || { err "文件不存在：$f"; return 1; }
  printf '   %s[1]%s 一次性启动（boot，适用于没有真实 recovery 分区的 A/B 设备）\n' "$(c_b)" "$(c_0)"
  printf '   %s[2]%s 刷入真实的 recovery 分区\n' "$(c_b)" "$(c_0)"
  c="$(ask '选择: ' 1)"
  if [ "$c" = "1" ]; then
    printf '%s  >%s boot %s（一次性启动）\n' "$(c_b)" "$(c_0)" "$(basename "$f")"
    [ "$DRYRUN" = "1" ] && return 0
    runit "$FB" ${SERIAL:+-s "$SERIAL"} boot "$f" && ok "已临时启动"
  else
    flash_image "$f" recovery
  fi
}

act_third_party() {
  pick_device || return 1
  f="$(ask '第三方固件 / 镜像路径: ' '')"
  [ -n "$f" ] || { err "没给文件路径"; return 1; }
  [ -f "$f" ] || { err "文件不存在：$f"; return 1; }
  p="$(ask '目标分区（留空自动推断）: ' '')"
  flash_image "$f" "$p"
}

act_switch_slot() {
  pick_device || return 1
  cur="$(getvar current-slot)"; cnt="$(getvar slot-count)"
  printf ' 当前 slot：%s%s%s    slot 数：%s\n' "$(c_g)" "${cur:-未知}" "$(c_0)" "${cnt:-未知}"
  if [ "$cnt" = "2" ] || [ -z "$cnt" ]; then
    tgt="$(ask '切到哪个 slot (a/b): ' "$([ "$cur" = "a" ] && echo b || echo a)")"
    printf '%s  >%s set_active %s\n' "$(c_b)" "$(c_0)" "$tgt"
    [ "$DRYRUN" = "1" ] && return 0
    runit "$FB" ${SERIAL:+-s "$SERIAL"} set_active "$tgt" && ok "已切换至 $tgt"
  else
    warn "该设备不支持 A/B 槽位切换（slot-count=$cnt）"
  fi
}

act_reboot() {
  pick_device || return 1
  case "$1" in
    bl)   runit "$FB" ${SERIAL:+-s "$SERIAL"} reboot bootloader ;;
    sys)  runit "$FB" ${SERIAL:+-s "$SERIAL"} reboot ;;
    rec)  runit "$FB" ${SERIAL:+-s "$SERIAL"} reboot recovery ;;
    edl)  warn "EDL/9008 因机型而异，尝试 oem edl"; runit "$FB" ${SERIAL:+-s "$SERIAL"} oem edl ;;
    fbcl) runit "$FB" ${SERIAL:+-s "$SERIAL"} oem fb_mode_clear ;;
  esac
}

act_unlock() {
  pick_device || return 1
  case "$1" in
    data)   runit "$FB" ${SERIAL:+-s "$SERIAL"} oem get_unlock_data ;;
    ul)     confirm "oem unlock 会清空设备并改变保修状态，继续？" && runit "$FB" ${SERIAL:+-s "$SERIAL"} oem unlock ;;
    fl)     confirm "flashing unlock 会清空设备，继续？" && runit "$FB" ${SERIAL:+-s "$SERIAL"} flashing unlock ;;
    status) fb oem device-info 2>&1 | tr -d '\r' | while IFS= read -r l; do printf '  %s\n' "$l"; done ;;
  esac
}

show_dev_info() {
  pick_device || return 1
  hr; printf ' %s设备信息%s\n' "$(c_b)" "$(c_0)"; hr
  for k in product variant serialno cid current-slot slot-count unlocked secure max-download-size; do
    printf ' %s%-18s%s %s\n' "$(c_b)" "$k" "$(c_0)" "$(getvar "$k")"
  done
  printf ' %s%-18s%s %s\n' "$(c_b)" 'oem device-info' "$(c_0)" "$(fb oem device-info 2>&1 | tr -d '\r' | grep -i unlock | head -1 | cut -c1-26)"
  printf ' %s%-18s%s %s\n' "$(c_b)" 'carrier' "$(c_0)" "$(fb oem device-info 2>&1 | tr -d '\r' | grep -i carrier | head -1 | cut -c1-26)"
  hr
  confirm "导出完整 getvar all 到 logs/？" && {
    OUT="$HOME_DIR/logs/getvarall_$(date +%s).txt"
    fb getvar all > "$OUT" 2>&1; ok "已导出：$OUT"
  }
}

# --------------------------------------------------------------- ADB / DIY ---
menu_adb() {
  [ -x "$ADB" ] || { err "adb 未就位：$ADB"; return 1; }
  case "$1" in
    list) hr; printf ' %sADB 设备%s\n' "$(c_b)" "$(c_0)"; hr; runit "$ADB" devices -l ;;
    bl)   runit "$ADB" reboot bootloader && ok "已重启到 bootloader" ;;
    rc)   runit "$ADB" reboot recovery ;;
    sh)   _c="$(ask 'adb shell 命令: ' 'getprop ro.product.name')"; runit "$ADB" shell "$_c" ;;
    push) _l="$(ask '本地文件: ' '')"; _r="$(ask '目标路径: ' '/data/local/tmp/')"
          [ -n "$_l" ] && runit "$ADB" push "$_l" "$_r" ;;
    pull) _r="$(ask '设备路径: ' '')"; _l="$(ask '保存目录: ' "$HOME_DIR")"
          [ -n "$_r" ] && runit "$ADB" pull "$_r" "$_l" ;;
    kill) runit "$ADB" kill-server; ok "adb server 已结束" ;;
  esac
}

menu_diy() {
  pick_device || return 1
  hr
  printf ' %sDIY 刷写%s\n' "$(c_b)" "$(c_0)"
  printf ' 直接敲 fastboot 子命令，前面不用写 fastboot\n'
  printf ' 例：%sflash boot /sdcard/boot.img%s\n' "$(c_d)" "$(c_0)"
  printf '     %sgetvar all%s  %soem fb_mode_clear%s\n' "$(c_d)" "$(c_0)" "$(c_d)" "$(c_0)"
    "$(c_d)" "$(c_0)" "$(c_d)" "$(c_0)" "$(c_d)" "$(c_0)"
  printf ' 输入 %sq%s 返回菜单\n' "$(c_y)" "$(c_0)"
  hr
  while :; do
    printf '%sfastboot>%s ' "$(c_bb)" "$(c_0)"
    read -r _cmd || break
    case "$_cmd" in ''|q|Q|exit) break ;; esac
    [ -n "$_cmd" ] || break
    printf '%s$ fastboot %s%s\n' "$(c_d)" "$_cmd" "$(c_0)"
    runit "$FB" ${SERIAL:+-s "$SERIAL"} $_cmd
  done
}

# ------------------------------------------------------- Fastboot 版本切换 ---
list_fb_bins() {
  { ls "$HOME_DIR/bin" 2>/dev/null | grep '^fastboot' | sed "s|^|$HOME_DIR/bin/|"
    ls "$HOME_DIR"/mfastboot/*/fastboot 2>/dev/null
    ls "$HOME_DIR"/mfastboot/*/mfastboot 2>/dev/null; } | sort -u
}

menu_fb_version() {
  hr
  printf ' %s更换 Fastboot 版本%s\n' "$(c_b)" "$(c_0)"; hr
  printf ' 当前：%s\n' "${FB#"$HOME_DIR"/}"
  hr
  i=0
  for b in $(list_fb_bins); do
    i=$((i+1))
    _rel="${b#$HOME_DIR/}"
    _ver="$("$b" --version 2>/dev/null | sed -n 's/.*[Ff]astboot[^0-9]*\([0-9][0-9.]*\).*/\1/p' | head -1)"
    [ -n "$_ver" ] || _ver='版本未知'
    printf ' %s[%s]%s %s\n' "$(c_b)" "$i" "$(c_0)" "$_rel"
    printf '     %s[ %s ... ]%s\n' "$(c_d)" "$_ver" "$(c_0)"
  done
  printf ' %s[0]%s恢复默认\n' "$(c_b)" "$(c_0)"
  if [ "$i" = "0" ]; then
    warn "只有一个 fastboot：$FB"
    info "把别的版本复制成 $HOME_DIR/bin/fastboot-34 之类，就会出现在这个列表里"
    return 1
  fi
  n="$(ask '选择要切换的版本: ' 0)"
  if [ "$n" = "0" ]; then FASTBOOT_BIN=""; save_cfg; FB="$HOME_DIR/bin/fastboot"; ok "已恢复默认"; return 0; fi
  j=0
  for b in $(list_fb_bins); do
    j=$((j+1))
    if [ "$j" = "$n" ]; then FASTBOOT_BIN="$b"; save_cfg; FB="$b"; ok "已切换到 $b"; return 0; fi
  done
  warn "无效选择"
}

# --------------------------------------------------------------- 文本页面 ---
doc_path() {
  _n="$1"
  case "$_n" in
    *.*) ;;
    *) _n="$_n.txt" ;;
  esac
  for d in "$HOME_DIR/docs" "$SELFDIR/docs" "/sdcard/TFS_Android/docs"; do
    [ -f "$d/$_n" ] && { printf '%s' "$d/$_n"; return 0; }
  done
  return 1
}

page_about() {
  hr
  printf ' %sTiny Fastboot Script (Android)%s\n' "$(c_bb)" "$(c_0)"
  printf ' 版本       %s\n' "$VERSION"
  printf ' 原版       Tiny Fastboot Script (Windows)\n'
  printf '            v1.7.0 / v1.10.6  作者 AlphaEva\n'
  printf ' 实现       纯 POSIX sh + aarch64 fastboot\n'
  printf '            手机当 host（root + OTG）\n'
  printf ' 目录       %s\n' "$HOME_DIR"
  printf ' 日志       %s\n' "${LOG##*/}"
  printf ' 配置       %s\n' "$CFG"
  printf ' fastboot   %s\n' "$FB"
  hr
  printf ' 功能键对照：\n'
  printf ' 1=AP 系统         2=BP 基带         3=BL 引导\n'
  printf ' 4=Recovery        5=整机+擦除       k=整机保留\n'
  printf ' 6=恢复出厂        7=清基带缓存      8=解锁 BL\n'
  printf ' 9=重启            s=切 A/B 槽       r=第三方固件\n'
  printf ' d=ADB 功能        f=换 fastboot     i=设备信息\n'
  printf ' n=DIY 刷写        b=报错手册        c=CID 说明\n'
  printf ' a=关于            g=更新日志        u=检查更新\n'
  printf ' m=高级配置        x=退出\n'
  hr
}

act_check_update() {
  hr
  printf ' 当前版本 %s\n' "$VERSION"
  printf ' 手机端不做自动下载更新，检查方式：\n'
  printf ' - 原版项目 Tiny Fastboot Script（AlphaEva）\n'
  printf '   对比其 changelog 版本号\n'
  printf ' - 换二进制：替换 bin/fastboot 与 lib/*.so\n'
  printf '   后重跑 deploy.sh\n'
  printf ' - 本脚本更新日志：菜单 %sg%s\n' "$(c_y)" "$(c_0)"
  hr
}

menu_config() {
  hr
  printf ' %s高级配置%s\n' "$(c_b)" "$(c_0)"; hr
  printf ' 跳过分区表：\n'
  _ln='  '; _wd=2
  for _p in $SKIP_LIST; do
    if [ $((_wd + ${#_p})) -gt 52 ]; then printf '%s\n' "${_ln% }"; _ln='  '; _wd=2; fi
    _ln="$_ln$_p "; _wd=$((_wd + ${#_p} + 1))
  done
  printf '%s\n' "${_ln% }"
  printf ' 保留数据  ：%s%s%s\n' "$(c_g)" "$KEEP_DATA" "$(c_0)"
  printf ' 1=开 0=关；保留数据=跳过 XML 里所有 erase\n'
  printf ' 危险确认  ：%s%s%s\n' "$(c_g)" "$WIPE_CONFIRM" "$(c_0)"
  printf ' 干跑预览  ：%s%s%s\n' "$(c_g)" "$DRYRUN" "$(c_0)"
  hr
  printf ' %s[1]%s 追加跳过分区   %s[2]%s 重置跳过表\n' "$(c_b)" "$(c_0)" "$(c_b)" "$(c_0)"
  printf ' %s[3]%s 保留数据开关   %s[4]%s 危险确认开关\n' "$(c_b)" "$(c_0)" "$(c_b)" "$(c_0)"
  printf ' %s[5]%s 干跑开关       %s[0]%s 返回\n' "$(c_b)" "$(c_0)" "$(c_b)" "$(c_0)"
  _c="$(ask '选择: ' 0)"
  case "$_c" in
    1) _n="$(ask '要跳过的分区名（空格分隔）: ' '')"; [ -n "$_n" ] && SKIP_LIST="$SKIP_LIST $_n"; save_cfg ;;
    2) SKIP_LIST="cid carrier cdt utags devinfo frp persist modemst1 modemst2 fsg logo_a logo_b"; save_cfg ;;
    3) if [ "$KEEP_DATA" = "1" ]; then KEEP_DATA=0; else KEEP_DATA=1; fi; save_cfg ;;
    4) if [ "$WIPE_CONFIRM" = "1" ]; then WIPE_CONFIRM=0; else WIPE_CONFIRM=1; fi; save_cfg ;;
    5) if [ "$DRYRUN" = "1" ]; then DRYRUN=0; else DRYRUN=1; fi ;;
    0) return 0 ;;
  esac
  printf ' 已更新：KEEP_DATA=%s DRYRUN=%s\n' "$KEEP_DATA" "$DRYRUN"
}

self_check() {
  hr; printf ' %s环境自检%s\n' "$(c_b)" "$(c_0)"; hr
  printf ' %s目录        %s %s\n' "$(c_b)" "$(c_0)" "$HOME_DIR"
  printf ' %sfastboot    %s %s\n' "$(c_b)" "$(c_0)" "$FB"
  printf ' %s版本        %s %s\n' "$(c_b)" "$(c_0)" "$("$FB" --version 2>&1 | head -1 | cut -c1-26)"
  printf ' %s库路径      %s %s\n' "$(c_b)" "$(c_0)" "$(printf '%s' "$LD_LIBRARY_PATH" | cut -c1-26)"
  for l in libfmt.so libc++_shared.so libz.so.1; do
    if [ -f "$HOME_DIR/lib/$l" ]; then printf '   %s.%s %s OK\n' "$(c_g)" "$(c_0)" "$l"
    else printf '   %s. 缺 %s%s\n' "$(c_y)" "$l" "$(c_0)"; fi
  done
  printf ' %suid         %s %s\n' "$(c_b)" "$(c_0)" "$(id -u) $(id -un 2>/dev/null)"
  printf ' %s在线设备    %s %s\n' "$(c_b)" "$(c_0)" "$(dev_list | grep -c .)"
  printf ' %sadb         %s %s\n' "$(c_b)" "$(c_0)" "$("$ADB" --version 2>/dev/null | head -1 | cut -c1-26)"
  printf ' %s日志        %s %s\n' "$(c_b)" "$(c_0)" "$LOG"
  hr
}

# ---------------------------------------------------------------- 主菜单 UI ---
# 注释列固定从第 38 显示列开始：中文按 2 列宽手工预算，不依赖运行时宽度计算
mrow() { printf '  %s%s%s%s%s\n' "$(c_bb)" "$1" "$(c_d)" "$2" "$(c_0)"; }

# 菜单项：[键]功能名 一行，[ 说明 ... ] 占下一行
mline() {
  _k="$1"; _t="$2"; _d="$3"
  printf ' %s[%s]%s%s%s%s\n' "$(c_b)" "$_k" "$(c_0)" "$(c_bb)" "$_t" "$(c_0)"
  if [ -n "$_d" ]; then
    printf '    %s[ %s ... ]%s\n' "$(c_d)" "$_d" "$(c_0)"
  fi
}
view_menu() {
  hline
  printf ' %s    Tiny Fastboot Script (Android)           %s%s\n' "$(c_bb)" "$VERSION" "$(c_0)"
  hline
  mline 1 "刷入设备基本 AP（系统部分）" "boot + recovery + super / system            "
  mline 2 "刷入设备基本 BP（基带部分）" "radio / modem + fsg                         "
  mline 3 "刷入设备基本 BL（引导部分）" "gpt / pit + bootloader                      "
  mline 4 "刷入设备单个 Recovery 镜像" "recovery / boot 一次性                      "
  mline 5 "刷入设备完整固件（含恢复出厂）" "全部镜像 + 恢复出厂设置                     "
  mline k "刷入设备完整固件（保留数据）" "全部镜像，不恢复出厂设置                    "
  printf '\n'
  mline 6 "恢复出厂设置" "清空 Data + Cache                           "
  mline 7 "清空基带缓存分区" "modemst / mdmlm9kefs / mdmddr / nvdata      "
  printf '\n'
  mline 8 "解锁 Bootloader" "oem unlock / flashing unlock                "
  mline s "切换 A/B 槽位" "set_active a|b                              "
  mline r "刷入第三方固件" "TWRP / 第三方 boot                          "
  mline 9 "重启选项" "Bootloader / System / Recovery / EDL        "
  printf '\n'
  mline b "Fastboot 命令报错怎么办" "内置文档 faq                                "
  mline c "CID 及固件刷写说明" "内置文档 cid                                "
  mline g "更新日志" "内置文档 changelog                          "
  mline d "ADB 功能" "设备列表 / shell / push / pull              "
  mline f "更换 Fastboot 版本" "多版本共存切换                              "
  mline i "获取设备信息" "getvar / unlock 状态                        "
  mline n "DIY 刷写" "手动执行 fastboot 命令                      "
  mline m "高级配置" "跳过分区表 / 保留数据 / 干跑                "
  printf '\n'
  mline a "关于信息" ""
  mline u "检查更新" ""
  mline x "退出脚本" ""
  hline
  printf ' %s日志%s %s\n' "$(c_b)" "$(c_0)" "$LOG"
  hline
}

view_reboot_menu() {
  hr
  printf ' %s重启选项%s\n' "$(c_b)" "$(c_0)"; hr
  mline 1 "重启到 Bootloader" "fastboot 界面                               "
  mline 2 "重启到系统" "正常开机                                    "
  mline 3 "重启到 Recovery" "recovery 界面                               "
  mline 4 "退出工厂模式" "fastboot oem fb_mode_clear                  "
  mline 5 "尝试进入 EDL / 9008" "部分机型支持                                "
  mline 0 "返回" ""
  hr
}
view_unlock_menu() {
  hr
  printf ' %s解锁 Bootloader%s\n' "$(c_b)" "$(c_0)"; hr
  mline 1 "查询解锁状态" "getvar unlocked / oem device-info           "
  mline 2 "获取 unlock data" "需提交给厂商或在线算码                      "
  mline 3 "oem unlock" "旧机型通道                                  "
  mline 4 "flashing unlock" "新机型通道                                  "
  mline 0 "返回" ""
  hr
}

# ------------------------------------------------------------- 非交互模式 ---
run_noninteractive() {
  MODE=""; PARAM=""; PARAM2=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry) DRYRUN=1 ;;
      --factory) KEEP_DATA=0 ;;
      --yes) WIPE_CONFIRM=0 ;;
      --serial) shift; SERIAL="$1"; export SERIAL ;;
      check|info|devices|flash|ap|bl|img|super|erase|slot|reboot|unlock|adb|doc)
        MODE="$1" ;;
      *) if [ -z "$PARAM" ]; then PARAM="$1"; elif [ -z "$PARAM2" ]; then PARAM2="$1"; fi ;;
    esac
    shift
  done

  case "$MODE" in
    check)   self_check ;;
    devices) dev_list ;;
    info)    show_dev_info ;;
    flash)   pick_device && do_flash_all "$PARAM" "${PARAM2:-ALL}" ;;
    ap)      pick_device && do_flash_all "$PARAM" AP ;;
    bl)      pick_device && do_flash_all "$PARAM" BL ;;
    img)     pick_device && flash_image "$PARAM" "$PARAM2" ;;
    super)   pick_device && flash_super_sparse "$PARAM" ;;
    erase)   case "$PARAM" in data) act_factory_reset ;; modem) act_clear_modem ;; *) err "erase 参数：data|modem" ;; esac ;;
    slot)    pick_device && { [ "$DRYRUN" = "1" ] || runit "$FB" ${SERIAL:+-s "$SERIAL"} set_active "$PARAM"; } ;;
    reboot)  case "$PARAM" in sys|bl|rec|edl|fbcl) act_reboot "$PARAM" ;; *) err "reboot 参数：sys|bl|rec|edl|fbcl" ;; esac ;;
    unlock)  case "$PARAM" in data|ul|fl|status) act_unlock "$PARAM" ;; *) err "unlock 参数：data|ul|fl|status" ;; esac ;;
    adb)     case "$PARAM" in list|bl|rc|sh|push|pull|kill) menu_adb "$PARAM" ;; *) err "adb 参数：list|bl|rc|sh|push|pull|kill" ;; esac ;;
    doc)     if [ -z "$PARAM" ]; then
               # 无参数：列出可用文档
               hr; printf ' %s可用文档%s
' "$(c_b)" "$(c_0)"; hr
               _i=0
               for d in "$HOME_DIR/docs" "$SELFDIR/docs" "/sdcard/TFS_Android/docs"; do
                 [ -d "$d" ] || continue
                 for f in "$d"/*.txt; do
                   [ -f "$f" ] || continue
                   _i=$((_i+1)); printf ' [%d] %s
' "$_i" "$(basename "$f" .txt)"
                 done
                 break
               done
               [ "$_i" = "0" ] && warn "docs 目录为空"
               hr
             else
               D="$(doc_path "$PARAM")" || { err "找不到文档：$PARAM（用 tfs.sh doc 查看可用的）"; return 1; }
               pager "$D"
             fi ;;
    *)
      if [ -n "$PARAM" ] && { [ -d "$PARAM" ] || [ -f "$PARAM" ]; }; then
        pick_device || return 1
        case "$PARAM" in *.img) flash_image "$PARAM" "$PARAM2" ;; *) do_flash_all "$PARAM" ALL ;; esac
      else
        return 1
      fi ;;
  esac
  return 0
}

# ------------------------------------------------------------------- 入口 ---
main() {
  have_fb || { err "先跑 deploy.sh 部署 fastboot 到 $FASTBOOT_HOME"; return 1; }

  DEF_DIR="$HOME_DIR/rom"
  for x in flashfile.xml servicefile.xml; do [ -f "$PWD/$x" ] && DEF_DIR="$PWD"; done
  [ -n "$TFS_PWD" ] && [ -d "$TFS_PWD" ] && DEF_DIR="$TFS_PWD"
  [ -n "$TFS_ROMDIR" ] && [ -d "$TFS_ROMDIR" ] && DEF_DIR="$TFS_ROMDIR"

  if [ -n "$TFS_MENU_ONCE" ]; then view_menu; return 0; fi

  if [ $# -gt 0 ]; then
    case "$1" in
      -h|--help|help) usage; return 0 ;;
      -*|check|info|devices|flash|ap|bl|img|super|erase|slot|reboot|unlock|adb|doc)
        run_noninteractive "$@"; return $? ;;
      *)
        if [ -f "$1" ] || [ -d "$1" ]; then
          pick_device || return 1
          case "$1" in *.img) flash_image "$1" ;; *) do_flash_all "$1" ALL ;; esac
          return 0
        fi ;;
    esac
  fi

  if [ ! -t 0 ]; then
    warn "非交互环境（无 tty），改为环境自检。带参数跑：tfs.sh flash <目录>"
    self_check; return 0
  fi

  while :; do
    printf '\n'
    view_menu
    printf ' %s请输入您要执行的选项序号并回车: %s' "$(c_bb)" "$(c_0)"
    read -r sel || break
    case "$sel" in
      1) act_flash_scope AP ;;
      2) act_flash_scope BP ;;
      3) act_flash_scope BL ;;
      4) act_recovery ;;
      5) act_flash_full 0 ;;
      k|K) act_flash_full 1 ;;
      6) act_factory_reset ;;
      7) act_clear_modem ;;
      8) view_unlock_menu
         u="$(ask '选择: ' 0)"
         case "$u" in 1) act_unlock status ;; 2) act_unlock data ;; 3) act_unlock ul ;; 4) act_unlock fl ;; esac ;;
      9) view_reboot_menu
         r="$(ask '选择: ' 0)"
         case "$r" in 1) act_reboot bl ;; 2) act_reboot sys ;; 3) act_reboot rec ;; 4) act_reboot fbcl ;; 5) act_reboot edl ;; esac ;;
      s|S) act_switch_slot ;;
      r|R) act_third_party ;;
      b|B) D="$(doc_path faq.txt)" && pager "$D" || warn "缺 docs/faq.txt" ;;
      c|C) D="$(doc_path cid.txt)" && pager "$D" || warn "缺 docs/cid.txt" ;;
      d|D) hr
           printf ' %sADB 功能%s\n' "$(c_b)" "$(c_0)"; hr
           mline 1 "设备列表" "adb devices -l                              "
           mline 2 "重启到 Bootloader" "adb reboot bootloader                       "
           mline 3 "重启到 Recovery" "adb reboot recovery                         "
           mline 4 "执行 shell" "adb shell 交互                              "
           mline 5 "推送文件 push" "本地 -> 设备                                "
           mline 6 "拉取文件 pull" "设备 -> 本地                                "
           mline 7 "结束 adb server" "adb kill-server                             "
           mline 0 "返回" ""
           a="$(ask '选择: ' 0)"
           case "$a" in 1) menu_adb list ;; 2) menu_adb bl ;; 3) menu_adb rc ;; 4) menu_adb sh ;; 5) menu_adb push ;; 6) menu_adb pull ;; 7) menu_adb kill ;; esac ;;
      f|F) menu_fb_version ;;
      i|I) show_dev_info ;;
      n|N) menu_diy ;;
      m|M) menu_config ;;
      a|A) page_about ;;
      g|G) D="$(doc_path changelog.txt)" && { hr; pager "$D"; } || warn "缺 docs/changelog.txt" ;;
      u|U) act_check_update ;;
      x|X|0|q|Q|exit) log "退出。日志：$LOG"; break ;;
      *) warn "无效选项：$sel" ;;
    esac
    pause_key
  done
}

main "$@"