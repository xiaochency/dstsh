#!/usr/bin/env bash
#
# setup_dst_lib32.sh
# 安装 32 位运行库并备份 DST 自带的 libstdc++.so.6
#

set -euo pipefail

# ---------- 日志函数 ----------
log()  { echo -e "\033[1;32m[INFO]\033[0m  $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
err()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# ---------- 检查 root / sudo ----------
if [[ $EUID -eq 0 ]]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    err "需要 root 权限或已安装 sudo。"
    exit 1
fi

# ---------- 1. 添加 i386 架构 ----------
log "添加 i386 架构支持..."
$SUDO dpkg --add-architecture i386

# ---------- 2. 更新软件源 ----------
log "更新软件包索引..."
$SUDO apt update

# ---------- 3. 安装 32 位运行库 ----------
log "安装 lib32stdc++6 lib32gcc-s1 lib32z1 ..."
$SUDO apt install -y lib32stdc++6 lib32gcc-s1 lib32z1

# ---------- 4. 备份 DST 自带的 libstdc++.so.6 ----------
DST_LIB_DIR="$HOME/dst/bin/lib32"
TARGET="$DST_LIB_DIR/libstdc++.so.6"
BACKUP="$DST_LIB_DIR/libstdc++.so.6.bak"

if [[ ! -d "$DST_LIB_DIR" ]]; then
    err "目录不存在: $DST_LIB_DIR"
    err "请确认 DST 服务端已正确安装。"
    exit 1
fi

cd "$DST_LIB_DIR"

if [[ -e "$BACKUP" ]]; then
    warn "备份文件已存在: $BACKUP ，跳过备份步骤。"
elif [[ -e "$TARGET" ]]; then
    log "备份 libstdc++.so.6 -> libstdc++.so.6.bak"
    mv "$TARGET" "$BACKUP"
else
    warn "未找到 $TARGET ，无需备份。"
fi

log "全部完成 ✅"
