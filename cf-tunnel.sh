#!/bin/bash
# cf-named-tunnel.sh — Named Tunnel 一键启动（Token 模式）
# 适用：Zero Trust → Networks → Tunnels → 某隧道 → Connectors → 复制 token
set -e

# === 颜色 ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[1;34m'; NC='\033[0m'

CLOUDFLARED_BIN="/usr/local/bin/cloudflared"
SERVICE_PATH="/etc/systemd/system/cloudflared-tunnel.service"
LOG_PATH="/var/log/cloudflared.log"

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

"$CLOUDFLARED_BIN" --version | head -1

# ============================================================
# 2) 读入 Token（优先环境变量，否则交互输入）
# ============================================================
if [[ -n "$TUNNEL_TOKEN" ]]; then
    TOKEN="$TUNNEL_TOKEN"
    echo -e "${GREEN}[✓] 使用环境变量 TUNNEL_TOKEN${NC}"
else
    echo ""
    echo -e "${YELLOW}请把你在 Zero Trust → Tunnel → Connectors 页面拿到的 Token 粘贴进来${NC}"
    echo -e "${YELLOW}（就是 eyJhIjoi... 那一长串，粘贴后回车）${NC}"
    read -rp "TUNNEL_TOKEN: " TOKEN
fi

if [[ -z "$TOKEN" || "$TOKEN" != eyJ* ]]; then
    echo -e "${RED}[!] Token 格式不对，应该以 eyJ 开头（Base64URL JWT）${NC}"
    exit 1
fi

# ============================================================
# 3) 旧服务处理
# ============================================================
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

# ============================================================
# 4) 运行模式
# ============================================================
echo ""
echo -e "${YELLOW}请选择运行方式：${NC}"
echo "1) 前台运行（调试用，Ctrl+C 停止）"
echo "2) 后台服务（systemd 开机自启）"
read -rp "输入 1 或 2: " MODE

if [[ "$MODE" == "1" ]]; then
    echo -e "${BLUE}[*] 前台启动 Named Tunnel...${NC}"
    echo -e "${YELLOW}   提示：Public Hostname 路由规则要在 Zero Trust 控制台里确认已配置${NC}"
    exec "$CLOUDFLARED_BIN" tunnel run --token "$TOKEN"

elif [[ "$MODE" == "2" ]]; then
    echo -e "${BLUE}[*] 注册 systemd 服务...${NC}"

    # 把 Token 存到一个受保护文件里，避免直接裸露在 service 文件参数里
    TOKEN_FILE="/etc/cloudflared/tunnel.token"
    sudo mkdir -p /etc/cloudflared
    printf '%s\n' "$TOKEN" | sudo tee "$TOKEN_FILE" >/dev/null
    sudo chown root:root "$TOKEN_FILE"
    sudo chmod 600 "$TOKEN_FILE"

    sudo bash -c "cat > $SERVICE_PATH" <<EOF
[Unit]
Description=Cloudflare Named Tunnel Connector
After=network.target

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c '/usr/local/bin/cloudflared tunnel run --token $(cat /etc/cloudflared/tunnel.token)'
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now cloudflared-tunnel

    echo -e "${GREEN}[✓] 服务已启动${NC}"
    echo -e "  查看状态: ${BLUE}sudo systemctl status cloudflared-tunnel${NC}"
    echo -e "  查看日志: ${BLUE}sudo journalctl -u cloudflared-tunnel.service -f{NC}"
else
    echo -e "${RED}无效输入${NC}"; exit 1
fi