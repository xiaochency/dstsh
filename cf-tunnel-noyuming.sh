#!/bin/bash
# https://github.com/sky22333/shell
set -e
# === 颜色定义 ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # 清除颜色

CLOUDFLARED_BIN="/usr/local/bin/cloudflared"
SERVICE_PATH="/etc/systemd/system/cloudflared-tunnel.service"
LOG_PATH="/var/log/cloudflared.log"

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
        1)
            URL="https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64"
            ;;
        2)
            URL="https://github.dpik.top/https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64"
            ;;
        3)
            URL="https://cdn.gh-proxy.org/https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64"
            ;;
        4)
            URL="https://edgeone.gh-proxy.org/https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64"
            ;;
        5)
            URL="https://gh.llkk.cc/github.com/https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64"
            ;;
        *)
            echo -e "${RED}[!] 无效选项，使用官方 GitHub${NC}"
            URL="https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64"
            ;;
    esac

    echo -e "${BLUE}[*] 正在从以下地址下载 cloudflared...${NC}"
    echo -e "${YELLOW}$URL${NC}"

    curl -L "$URL" -o "$CLOUDFLARED_BIN"
    chmod +x "$CLOUDFLARED_BIN"
fi
# 检查服务是否存在
if sudo systemctl list-units --full --all 2>/dev/null | grep -q 'cloudflared-tunnel.service'; then
    echo -e "${YELLOW}[!] 检测到已有 cloudflared-tunnel.service${NC}"
    read -rp "是否卸载旧服务并重建？(y/n): " UNINSTALL
    if [[ "$UNINSTALL" =~ ^[Yy]$ ]]; then
        sudo systemctl stop cloudflared-tunnel 2>/dev/null || true
        sudo systemctl disable cloudflared-tunnel 2>/dev/null || true
        sudo rm -f "$SERVICE_PATH" "$LOG_PATH"
        sudo systemctl daemon-reload
        echo -e "${GREEN}[✓] 旧服务已清理${NC}"
    fi
fi
# 用户选择运行模式
echo ""
echo -e "${YELLOW}请选择运行模式：${NC}"
echo "1) 临时运行（前台运行并显示临时访问域名）"
echo "2) 后台运行（自动配置后台服务并显示访问域名）"
read -p "请输入 1 或 2: " MODE
# 输入内网地址
read -p "请输入要穿透的本地地址（例如 127.0.0.1:8080）: " LOCAL_ADDR
if [[ "$MODE" == "1" ]]; then
    echo -e "${BLUE}正在前台运行 cloudflared...${NC}"
    LOGFILE=$(mktemp)
    stdbuf -oL "$CLOUDFLARED_BIN" tunnel --url "$LOCAL_ADDR" 2>&1 | tee "$LOGFILE" &
    PID=$!
    echo -e "${YELLOW}等待 cloudflared 输出访问域名...${NC}"
    for i in {1..60}; do
        DOMAIN=$(grep -oP 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$LOGFILE" | head -n1)
        if [[ -n "$DOMAIN" ]]; then
            echo ""
            echo -e "${GREEN}成功获取公网临时访问域名：$DOMAIN${NC}"
            echo ""
            wait $PID
            exit 0
        fi
        sleep 1
    done
    echo -e "${RED}超时未能获取临时域名，日志保存在：$LOGFILE${NC}"
    kill $PID 2>/dev/null || true
    exit 1
elif [[ "$MODE" == "2" ]]; then
    echo -e "${BLUE}正在配置 systemd 服务...${NC}"
    if [[ "$SERVICE_EXISTS" == false ]]; then
        sudo bash -c "cat > $SERVICE_PATH" <<EOF
[Unit]
Description=Cloudflared Tunnel Service
After=network.target
[Service]
ExecStart=$CLOUDFLARED_BIN tunnel --url $LOCAL_ADDR
Restart=always
StandardOutput=append:$LOG_PATH
StandardError=append:$LOG_PATH
[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl enable --now cloudflared-tunnel
    else
        echo -e "${YELLOW}更新 systemd 服务配置中的穿透地址...${NC}"
        sudo truncate -s 0 "$LOG_PATH" || sudo bash -c "> $LOG_PATH"
        sudo sed -i "s|ExecStart=.*|ExecStart=$CLOUDFLARED_BIN tunnel --url $LOCAL_ADDR|" "$SERVICE_PATH"
        sudo systemctl daemon-reload
        sudo systemctl restart cloudflared-tunnel
    fi
    echo -e "${GREEN}服务已启动，日志保存在 $LOG_PATH${NC}"
    echo -e "${YELLOW}等待 cloudflared 输出访问域名...${NC}"
    for i in {1..30}; do
        DOMAIN=$(grep -oP 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$LOG_PATH" | head -n1)
        if [[ -n "$DOMAIN" ]]; then
            echo ""
            echo -e "${GREEN}成功获取公网访问域名：$DOMAIN${NC}"
            echo ""
            exit 0
        fi
        sleep 1
    done
    echo -e "${RED}超时未能获取公网访问域名，请稍后手动查看：$LOG_PATH${NC}"
    exit 1
else
    echo -e "${RED}无效输入，请输入 1 或 2${NC}"
    exit 1
fi
