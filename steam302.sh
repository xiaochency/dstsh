#!/bin/bash

# ============ 配置区 ============
SERVICE_NAME="steam302"
SERVICE_USER="root"
INSTALL_DIR="$HOME/Steamcommunity_302"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

MIRROR_URLS=(
    "https://cdn.gh-proxy.org"
    "https://github.dpik.top"
    "https://gh.927223.xyz"
    "https://edgeone.gh-proxy.org"
    "https://gh.llkk.cc"
)
MIRROR_NAMES=(
    "镜像源1 (cdn.gh-proxy.org)"
    "镜像源2 (github.dpik.top)"
    "镜像源3 (gh.927223.xyz)"
    "镜像源4 (edgeone.gh-proxy.org)"
    "镜像源5 (gh.llkk.cc)"
)

GITHUB_RELEASE_PATH="/xiaochency/dstsh/releases/download/1st/Steamcommunity_302.tar.gz"

# ============ 颜色输出 ============
echo_red()    { echo -e "\033[31m$1\033[0m"; }
echo_green()  { echo -e "\033[32m$1\033[0m"; }
echo_yellow() { echo -e "\033[33m$1\033[0m"; }
echo_cyan()   { echo -e "\033[36m$1\033[0m"; }

# ============ 下载函数 ============
download() {
    local url="$1"
    local retries="${2:-3}"
    local timeout="${3:-20}"
    local output="$4"
    
    for ((i=1; i<=retries; i++)); do
        echo_cyan "尝试下载 (第 $i/$retries 次)..."
        if command -v curl &> /dev/null; then
            curl -L --connect-timeout "$timeout" --max-time 180 -o "$output" "$url" 2>/dev/null && return 0
        elif command -v wget &> /dev/null; then
            wget --timeout="$timeout" -O "$output" "$url" 2>/dev/null && return 0
        fi
        sleep 2
    done
    return 1
}

# ============ 镜像源选择 ============
select_mirror() {
    echo_cyan "请选择下载镜像源："
    for i in "${!MIRROR_NAMES[@]}"; do
        echo_cyan "  $((i+1)). ${MIRROR_NAMES[$i]}"
    done
    echo_cyan "  $((${#MIRROR_NAMES[@]}+1)). 退出"
    
    while true; do
        read -p "请输入选择 [1-$((${#MIRROR_NAMES[@]}+1))]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $((${#MIRROR_NAMES[@]}+1)) ]; then
            if [ "$choice" -eq $((${#MIRROR_NAMES[@]}+1)) ]; then
                return 1
            fi
            SELECTED_MIRROR_INDEX=$((choice-1))
            SELECTED_MIRROR_URL="${MIRROR_URLS[$SELECTED_MIRROR_INDEX]}"
            return 0
        fi
        echo_red "无效选择，请重试。"
    done
}

# ============ 安装函数 ============
install_steam302() {
    echo_cyan "=== Steamcommunity 302 安装 ==="
    
    if [ "$EUID" -ne 0 ]; then
        echo_red "错误：安装需要root权限，请使用 sudo 运行"
        return 1
    fi
    
    echo_cyan "--- 步骤1/4: 选择下载镜像源 ---"
    if ! select_mirror; then
        echo_yellow "安装已取消。"
        return 1
    fi
    
    echo_green "✅ 已选择: ${MIRROR_NAMES[$SELECTED_MIRROR_INDEX]}"
    
    local download_url="${SELECTED_MIRROR_URL}/https://github.com${GITHUB_RELEASE_PATH}"
    local temp_file="/tmp/Steamcommunity_302.tar.gz"
    
    echo_cyan "--- 步骤2/4: 下载文件 ---"
    echo_cyan "下载地址: $download_url"
    
    rm -f "$temp_file"
    if ! download "$download_url" 3 20 "$temp_file"; then
        echo_red "❌ 下载失败，请尝试其他镜像源"
        return 1
    fi
    
    echo_green "✅ 下载完成"
    
    echo_cyan "--- 步骤3/4: 验证文件 ---"
    local file_size
    file_size=$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null || echo "0")
    
    if [ "$file_size" -lt 1000000 ]; then
        echo_red "❌ 文件大小异常 ($file_size bytes)，下载可能不完整"
        rm -f "$temp_file"
        return 1
    fi
    
    if ! tar -tzf "$temp_file" >/dev/null 2>&1; then
        echo_red "❌ 压缩文件损坏"
        rm -f "$temp_file"
        return 1
    fi
    
    echo_green "✅ 文件验证通过"
    
    echo_cyan "--- 步骤4/4: 安装到 $INSTALL_DIR ---"
    
    mkdir -p "$INSTALL_DIR"
    rm -rf "${INSTALL_DIR:?}"/*
    
    if ! tar -zxvf "$temp_file" -C "$INSTALL_DIR" --strip-components=1; then
    echo_red "❌ 解压失败"
    rm -f "$temp_file"
    return 1
    fi
    
    rm -f "$temp_file"
    
    chmod +x "$INSTALL_DIR"/steamcommunity_302.cli
    chmod +x "$INSTALL_DIR"/steamcommunity_302.caddy 2>/dev/null || true
    chmod +x "$INSTALL_DIR"/Steamcommunity_302 2>/dev/null || true
    
    echo_green "✅ 安装完成！文件已安装至 $INSTALL_DIR"
    
    create_systemd_service
}

# ============ 创建systemd服务 ============
create_systemd_service() {
    echo_cyan "正在创建systemd服务..."
    
    if [ ! -f "$INSTALL_DIR/steamcommunity_302.cli" ]; then
        echo_red "错误：$INSTALL_DIR/steamcommunity_302.cli 不存在"
        return 1
    fi
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Steamcommunity 302 Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/steamcommunity_302.cli
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    
    echo_green "✅ systemd服务已创建并设置为开机自启"
    echo_cyan "  启动: systemctl start steam302"
    echo_cyan "  停止: systemctl stop steam302"
    echo_cyan "  状态: systemctl status steam302"
    echo_cyan "  日志: journalctl -u steam302 -f"
}

# ============ 启动函数 ============
start_steam302() {
    echo_cyan "=== 启动 Steamcommunity 302 ==="
    
    if [ ! -f "$SERVICE_FILE" ]; then
        echo_red "❌ systemd服务不存在，请先安装"
        return 1
    fi
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo_yellow "⚠️  服务已在运行中"
        systemctl status "$SERVICE_NAME" --no-pager -l
        return 0
    fi
    
    echo_cyan "正在启动服务..."
    systemctl start "$SERVICE_NAME"
    sleep 2
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo_green "✅ Steamcommunity 302 服务已启动"
        systemctl status "$SERVICE_NAME" --no-pager -l
    else
        echo_red "❌ 服务启动失败"
        echo_cyan "查看日志: journalctl -u $SERVICE_NAME -n 50"
        return 1
    fi
}

# ============ 停止函数 ============
stop_steam302() {
    echo_cyan "=== 停止 Steamcommunity 302 ==="
    
    if [ ! -f "$SERVICE_FILE" ]; then
        echo_yellow "systemd服务不存在"
        return 0
    fi
    
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        echo_green "✅ 服务未在运行"
        return 0
    fi
    
    systemctl stop "$SERVICE_NAME"
    sleep 1
    
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        echo_green "✅ Steamcommunity 302 服务已停止"
    else
        echo_red "❌ 服务停止失败"
        systemctl status "$SERVICE_NAME" --no-pager
        return 1
    fi
}

# ============ 查看日志 ============
view_logs() {
    echo_cyan "=== Steamcommunity 302 日志 ==="
    
    echo_cyan "请选择查看方式："
    echo_cyan "  1. 最近100行"
    echo_cyan "  2. 实时跟踪日志"
    echo_cyan "  0. 返回"
    
    read -p "请输入选择 [0-2]: " choice
    
    case "$choice" in
        1)
            journalctl -u "$SERVICE_NAME" -n 100 --no-pager
            ;;
        2)
            echo_cyan "实时跟踪日志 (Ctrl+C 退出)..."
            journalctl -u "$SERVICE_NAME" -f
            ;;
        0)
            return 0
            ;;
        *)
            echo_red "无效选择"
            ;;
    esac
}

# ============ 主菜单 ============
main_menu() {
    while true; do
        clear
        echo_green "================================================"
        echo_green "      Steamcommunity 302 管理工具"
        echo_green "================================================"
        
        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            echo_green "  状态: ✅ 运行中"
        elif [ -f "$SERVICE_FILE" ]; then
            echo_yellow "  状态: ⏸️  已安装但未运行"
        else
            echo_red "  状态: ❌ 未安装"
        fi
        
        echo_green "================================================"
        echo_cyan "  1. 安装 Steamcommunity 302"
        echo_cyan "  2. 启动服务"
        echo_cyan "  3. 停止服务"
        echo_cyan "  4. 查看日志"
        echo_cyan "  0. 退出"
        echo_green "================================================"
        
        read -p "请输入选择 [0-4]: " choice
        
        case "$choice" in
            1) install_steam302 ;;
            2) start_steam302 ;;
            3) stop_steam302 ;;
            4) view_logs ;;
            0) echo_green "再见！"; exit 0 ;;
            *) echo_red "无效选择，请输入 0-4 之间的数字" ;;
        esac
        
        echo ""
        read -p "按回车键继续..."
    done
}

main_menu