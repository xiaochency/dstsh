#!/bin/bash
# Cloudflare Tunnel 服务管理脚本

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

CLOUDFLARED_BIN="/usr/local/bin/cloudflared"
SERVICE_NAME="cf-tunnel"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
ENV_FILE="/etc/default/${SERVICE_NAME}"

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] 此脚本需要 root 权限运行，请使用 sudo 执行。${NC}"
    exit 1
fi

# 安装服务（强制重新安装）
install_service() {
    # === 新增：如果服务正在运行，先停止 ===
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo -e "${YELLOW}[*] 停止当前运行的服务...${NC}"
        systemctl stop "$SERVICE_NAME"
    fi

    # === 新增：强制删除已有二进制 ===
    if [[ -f "$CLOUDFLARED_BIN" ]]; then
        echo -e "${YELLOW}[*] 删除已存在的 cloudflared，以重新安装...${NC}"
        rm -f "$CLOUDFLARED_BIN"
    fi

    # 选择镜像并下载（原逻辑不变，但总是执行下载）
    echo -e "${BLUE}[*] 请选择下载镜像源：${NC}"
    echo "1) 官方 (github.com)"
    echo "2) github.dpik.top"
    echo "3) cdn.gh-proxy.org"
    echo "4) edgeone.gh-proxy.org"
    echo "5) ghfast.top"
    read -rp "请输入选项 [1-5]: " MIRROR_CHOICE

    case "$MIRROR_CHOICE" in
        1) URL="https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
        2) URL="https://github.dpik.top/https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
        3) URL="https://cdn.gh-proxy.org/https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
        4) URL="https://edgeone.gh-proxy.org/https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
        5) URL="https://ghfast.top/https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
        *) echo -e "${RED}无效选项${NC}"; return ;;
    esac

    echo -e "${BLUE}[*] 正在下载 cloudflared...${NC}"
    curl -L "$URL" -o "$CLOUDFLARED_BIN"
    chmod +x "$CLOUDFLARED_BIN"
    echo -e "${GREEN}[✓] 下载完成${NC}"

    # 输入本地地址
    read -p "请输入要穿透的本地地址（例如 127.0.0.1:8080）: " LOCAL_ADDR
    if [[ -z "$LOCAL_ADDR" ]]; then
        echo -e "${RED}[!] 地址不能为空${NC}"
        return
    fi

    # 创建环境文件（覆盖旧配置）
    echo "LOCAL_ADDR=$LOCAL_ADDR" > "$ENV_FILE"
    echo -e "${GREEN}[✓] 环境文件已创建: $ENV_FILE${NC}"

    # 创建 systemd 服务单元（覆盖旧文件）
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
EnvironmentFile=$ENV_FILE
ExecStart=$CLOUDFLARED_BIN tunnel --url \$LOCAL_ADDR
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    echo -e "${GREEN}[✓] systemd 服务已重新安装: $SERVICE_NAME${NC}"
    echo -e "${YELLOW}提示：使用菜单选项 1 启动服务${NC}"
}

# 启动服务
start_service() {
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${YELLOW}[!] 服务已在运行${NC}"
    else
        systemctl start "$SERVICE_NAME"
        systemctl enable "$SERVICE_NAME" &>/dev/null || true
        echo -e "${GREEN}[✓] 服务已启动${NC}"
    fi
}

# 停止服务
stop_service() {
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        systemctl stop "$SERVICE_NAME"
        echo -e "${GREEN}[✓] 服务已停止${NC}"
    else
        echo -e "${YELLOW}[!] 服务未运行${NC}"
    fi
}

# 查看实时日志
view_logs() {
    if systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
        echo -e "${BLUE}[*] 按 Ctrl+C 退出日志查看${NC}"
        journalctl -u "$SERVICE_NAME" -f -n 50
    else
        echo -e "${RED}[!] 服务未安装${NC}"
    fi
}

# 查看穿透域名
view_domain() {
    if ! systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
        echo -e "${RED}[!] 服务未安装${NC}"
        return
    fi
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${YELLOW}[!] 服务未运行，请先启动${NC}"
        return
    fi

    echo -e "${BLUE}[*] 正在从日志中提取域名...${NC}"
    DOMAIN=$(journalctl -u "$SERVICE_NAME" --since "30 seconds ago" --output=cat | grep -oP 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' | tail -1)
    if [[ -z "$DOMAIN" ]]; then
        DOMAIN=$(journalctl -u "$SERVICE_NAME" --output=cat | grep -oP 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' | tail -1)
    fi

    if [[ -n "$DOMAIN" ]]; then
        echo ""
        echo -e "${GREEN}🎉 当前穿透域名：${NC}"
        echo -e "${GREEN}=========================================${NC}"
        echo -e "${GREEN}     $DOMAIN${NC}"
        echo -e "${GREEN}=========================================${NC}"
    else
        echo -e "${YELLOW}[!] 未在日志中找到域名，可能尚未获取或未输出。${NC}"
        echo -e "${YELLOW}建议等待数秒后重试，或查看日志确认。${NC}"
    fi
}

# 主菜单
main_menu() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}     Cloudflare Tunnel 服务管理菜单     ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${GREEN} 0) 安装服务${NC}"
    echo -e "${YELLOW} 1) 启动服务${NC}"
    echo -e "${YELLOW} 2) 停止服务${NC}"
    echo -e "${YELLOW} 3) 查看实时日志${NC}"
    echo -e "${YELLOW} 4) 查看穿透后的域名${NC}"
    echo -e "${RED} 5) 退出${NC}"
    echo -e "${BLUE}=========================================${NC}"
    read -rp "请输入选项 [0-5]: " choice
    case $choice in
        0) install_service ;;
        1) start_service ;;
        2) stop_service ;;
        3) view_logs ;;
        4) view_domain ;;
        5) echo -e "${GREEN}再见！${NC}"; exit 0 ;;
        *) echo -e "${RED}无效选项${NC}"; sleep 1 ;;
    esac
    echo ""
    read -rp "按回车键返回主菜单..."
    main_menu
}

# 启动菜单
main_menu