#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

CLOUDFLARED_BIN="/usr/local/bin/cloudflared"
SCREEN_NAME="cf"
LOG_FILE="/tmp/cf-tunnel.log"

# === 检查 screen ===
if ! command -v screen &> /dev/null; then
    echo -e "${RED}[!] 未检测到 screen，请先安装：${NC}"
    echo -e "${YELLOW}Ubuntu/Debian: sudo apt install -y screen${NC}"
    echo -e "${YELLOW}CentOS/RHEL:   sudo yum install -y screen${NC}"
    exit 1
fi

# === 下载 cloudflared ===
if [[ -f "$CLOUDFLARED_BIN" ]]; then
    echo -e "${GREEN}[✓] cloudflared 已存在，跳过下载${NC}"
else
    echo -e "${BLUE}[*] 请选择 cloudflared 下载镜像源：${NC}"
    echo "1) 官方 GitHub（默认）"
    echo "2) github.dpik.top"
    echo "3) cdn.gh-proxy.org"
    echo "4) edgeone.gh-proxy.org"
    echo "5) gh.llkk.cc"
    read -rp "请输入选项 [1-5]: " MIRROR_CHOICE

    case "$MIRROR_CHOICE" in
        1) URL="https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
        2) URL="https://github.dpik.top/https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
        3) URL="https://cdn.gh-proxy.org/https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
        4) URL="https://edgeone.gh-proxy.org/https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
        5) URL="https://gh.llkk.cc/github.com/https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
        *) URL="https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-amd64" ;;
    esac

    echo -e "${BLUE}[*] 正在下载 cloudflared...${NC}"
    curl -L "$URL" -o "$CLOUDFLARED_BIN"
    chmod +x "$CLOUDFLARED_BIN"
fi

# === 输入本地地址 ===
read -p "请输入要穿透的本地地址（例如 127.0.0.1:8080）: " LOCAL_ADDR

# === 清理同名 screen ===
screen -S "$SCREEN_NAME" -X quit >/dev/null 2>&1 || true

# ✅ 先创建日志文件
rm -f "$LOG_FILE"
touch "$LOG_FILE"

echo -e "${BLUE}[*] 在 screen 会话中启动 cloudflared（会话名: ${SCREEN_NAME}）${NC}"
screen -dmS "$SCREEN_NAME" \
bash -c "$CLOUDFLARED_BIN tunnel --url $LOCAL_ADDR >> $LOG_FILE 2>&1"

# ✅ 等待日志文件有内容
echo -e "${YELLOW}[*] 等待 Cloudflare 返回公网域名...${NC}"

for i in {1..60}; do
    if [[ -s "$LOG_FILE" ]]; then
        DOMAIN=$(grep -oP 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$LOG_FILE" | head -n1)
        if [[ -n "$DOMAIN" ]]; then
            echo ""
            echo -e "${GREEN}🎉 成功获取公网访问域名：${NC}"
            echo -e "${GREEN}=========================================${NC}"
            echo -e "${GREEN}     $DOMAIN${NC}"
            echo -e "${GREEN}=========================================${NC}"
            echo ""
            echo -e "${YELLOW}👉 查看会话： screen -r $SCREEN_NAME${NC}"
            echo -e "${YELLOW}👉 实时日志： tail -f $LOG_FILE${NC}"
            exit 0
        fi
    fi
    sleep 1
done

echo -e "${RED}[!] 超时未获取到域名${NC}"
echo -e "${YELLOW}日志内容：${NC}"
cat "$LOG_FILE"
exit 1