#!/bin/bash
# cf-tunnel.sh — 使用 screen 管理 Cloudflare Named Tunnel
# 适用：Ubuntu，支持前台/后台(screen)运行，开机自启(cron @reboot)
set -e

# === 颜色 ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[1;34m'; NC='\033[0m'

CLOUDFLARED_BIN="/usr/local/bin/cloudflared"
LOG_PATH="/var/log/cloudflared.log"
SCREEN_SESSION="cloudflared-tunnel"
TOKEN_FILE="/etc/cloudflared/tunnel.token"

# === 检查 root 权限 ===
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] 请使用 sudo 运行此脚本${NC}"
    exit 1
fi

# === 安装 screen（若未安装） ===
if ! command -v screen &>/dev/null; then
    echo -e "${YELLOW}[*] screen 未安装，正在安装...${NC}"
    apt-get update -qq && apt-get install -y screen
    echo -e "${GREEN}[✓] screen 安装完成${NC}"
fi

# ============================================================
# 1) 安装 / 确认 cloudflared
# ============================================================
if [[ -f "$CLOUDFLARED_BIN" ]]; then
    echo -e "${GREEN}[✓] cloudflared 已存在，跳过下载${NC}"
else
    echo -e "${BLUE}[*] 请选择 cloudflared 下载镜像源：${NC}"
    echo "1) 官方 GitHub（默认）"
    echo "2) github.dpik.top 镜像"
    echo "3) cdn.gh-proxy.org 镜像"
    echo "4) edgeone.gh-proxy.org 镜像"
    echo "5) gh.llkk.cc 镜像"
    read -rp "请输入选项 [1-5]: " MIRROR_CHOICE

    case "$MIRROR_CHOICE" in
        1) URL="https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
        2) URL="https://github.dpik.top/https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
        3) URL="https://cdn.gh-proxy.org/https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
        4) URL="https://edgeone.gh-proxy.org/https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
        5) URL="https://gh.llkk.cc/github.com/https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
        *) echo -e "${RED}[!] 无效选项，使用官方 GitHub${NC}"; URL="https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
    esac

    echo -e "${BLUE}[*] 正在从以下地址下载 cloudflared...${NC}"
    echo -e "${YELLOW}$URL${NC}"
    curl -L "$URL" -o "$CLOUDFLARED_BIN"
    chmod +x "$CLOUDFLARED_BIN"
fi

"$CLOUDFLARED_BIN" --version | head -1

# ============================================================
# 2) 读入 Token
# ============================================================
if [[ -n "$TUNNEL_TOKEN" ]]; then
    TOKEN="$TUNNEL_TOKEN"
    echo -e "${GREEN}[✓] 使用环境变量 TUNNEL_TOKEN${NC}"
else
    echo ""
    echo -e "${YELLOW}请粘贴 Zero Trust → Tunnel → Connectors 的 Token（eyJhIjoi...）${NC}"
    read -rp "TUNNEL_TOKEN: " TOKEN
fi

if [[ -z "$TOKEN" || "$TOKEN" != eyJ* ]]; then
    echo -e "${RED}[!] Token 格式不对，应以 eyJ 开头${NC}"
    exit 1
fi

# 保存 Token 供后续使用
mkdir -p /etc/cloudflared
printf '%s\n' "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"

# ============================================================
# 3) 功能函数
# ============================================================
start_tunnel() {
    # 检查是否已在运行
    if screen -list | grep -q "$SCREEN_SESSION"; then
        echo -e "${YELLOW}[!] 隧道已在 screen 会话中运行${NC}"
        return 1
    fi
    echo -e "${BLUE}[*] 启动隧道（后台 screen）...${NC}"
    screen -dmS "$SCREEN_SESSION" bash -c "$CLOUDFLARED_BIN tunnel run --token $(cat $TOKEN_FILE) >> $LOG_PATH 2>&1"
    sleep 1
    if screen -list | grep -q "$SCREEN_SESSION"; then
        echo -e "${GREEN}[✓] 隧道已启动，screen 会话名: $SCREEN_SESSION${NC}"
        echo -e "  查看日志: ${BLUE}tail -f $LOG_PATH${NC}"
        echo -e "  重新附着: ${BLUE}screen -r $SCREEN_SESSION${NC}"
    else
        echo -e "${RED}[!] 启动失败，请查看日志 $LOG_PATH${NC}"
    fi
}

stop_tunnel() {
    if screen -list | grep -q "$SCREEN_SESSION"; then
        echo -e "${BLUE}[*] 停止隧道...${NC}"
        screen -S "$SCREEN_SESSION" -X quit
        echo -e "${GREEN}[✓] 已停止${NC}"
    else
        echo -e "${YELLOW}[!] 隧道未在运行${NC}"
    fi
}

status_tunnel() {
    if screen -list | grep -q "$SCREEN_SESSION"; then
        echo -e "${GREEN}[✓] 隧道正在运行（screen 会话 $SCREEN_SESSION）${NC}"
    else
        echo -e "${RED}[✗] 隧道未运行${NC}"
    fi
}

view_log() {
    if [[ -f "$LOG_PATH" ]]; then
        tail -f "$LOG_PATH"
    else
        echo -e "${YELLOW}[!] 日志文件不存在${NC}"
    fi
}

add_cron() {
    # 检查是否已存在相同命令的 cron 任务
    local cmd="$CLOUDFLARED_BIN tunnel run --token $(cat $TOKEN_FILE) >> $LOG_PATH 2>&1"
    local cron_line="@reboot screen -dmS $SCREEN_SESSION bash -c '$cmd'"
    if crontab -l 2>/dev/null | grep -F "$cmd" &>/dev/null; then
        echo -e "${YELLOW}[!] 开机自启任务已存在${NC}"
        return 1
    fi
    # 添加 cron 任务
    (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
    echo -e "${GREEN}[✓] 已添加开机自启（cron @reboot）${NC}"
}

remove_cron() {
    local cmd="$CLOUDFLARED_BIN tunnel run --token $(cat $TOKEN_FILE) >> $LOG_PATH 2>&1"
    local cron_line="@reboot screen -dmS $SCREEN_SESSION bash -c '$cmd'"
    if crontab -l 2>/dev/null | grep -F "$cmd" &>/dev/null; then
        crontab -l 2>/dev/null | grep -vF "$cmd" | crontab -
        echo -e "${GREEN}[✓] 已移除开机自启${NC}"
    else
        echo -e "${YELLOW}[!] 未找到开机自启任务${NC}"
    fi
}

# ============================================================
# 4) 主菜单
# ============================================================
while true; do
    echo ""
    echo -e "${BLUE}===== Cloudflare Named Tunnel 管理 =====${NC}"
    echo "1) 前台运行（调试）"
    echo "2) 后台运行（screen）"
    echo "3) 后台运行 + 设置开机自启"
    echo "4) 停止后台运行"
    echo "5) 查看运行状态"
    echo "6) 查看实时日志"
    echo "7) 移除开机自启（不影响当前运行）"
    echo "8) 退出"
    read -rp "请选择 [1-8]: " choice

    case $choice in
        1)
            echo -e "${BLUE}[*] 前台启动（Ctrl+C 停止）...${NC}"
            "$CLOUDFLARED_BIN" tunnel run --token "$TOKEN"
            ;;
        2)
            start_tunnel
            ;;
        3)
            start_tunnel
            add_cron
            ;;
        4)
            stop_tunnel
            ;;
        5)
            status_tunnel
            ;;
        6)
            view_log
            ;;
        7)
            remove_cron
            ;;
        8)
            echo -e "${GREEN}再见${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项${NC}"
            ;;
    esac
done