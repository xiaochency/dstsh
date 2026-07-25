#!/bin/bash

install_dir="$HOME/dst-dedicated-server"
steamcmd_dir="$HOME/steamcmd"

# ==================== 颜色定义 ====================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly LINE="${WHITE}————————————————————————————————————————————————————————————${NC}"

# ==================== 辅助函数 ====================
print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "   ╔══════════════════════════════════════════════════════════╗"
    echo "              Dst-admin-go管理脚本 v1.0.1                      "
    echo "                 Don't Starve Together                         " 
    echo "   ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_section() {
    echo -e "${YELLOW}${BOLD}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

print_divider() {
    echo -e "${DIM}${LINE}${NC}"
}

pause_and_return() {
    echo
    print_warning "按 Enter 键返回主菜单..."
    read -r
}

# ==================== 核心功能函数（保持原逻辑不变）====================
echo_red() { echo -e "${RED}$*${NC}"; }
echo_green() { echo -e "${GREEN}$*${NC}"; }
echo_yellow() { echo -e "${YELLOW}$*${NC}"; }
echo_cyan() { echo -e "${CYAN}$*${NC}"; }

install_dst_dependencies() {
    # ========== 权限处理 ==========
    local SUDO=""
    if [[ $EUID -ne 0 ]]; then
        if ! command -v sudo &> /dev/null; then
            echo "❌ 非 root 用户且未找到 sudo，无法安装依赖"
            return 1
        fi
        SUDO="sudo"
    fi

    echo "🔍 检查并安装 DST 运行依赖..."

    # ========== 启用 32 位架构（DST 服务端必需） ==========
    if ! dpkg --print-foreign-architectures | grep -qx i386; then
        echo "📐 启用 i386 架构..."
        if ! $SUDO dpkg --add-architecture i386; then
            echo "❌ 启用 i386 架构失败"
            return 1
        fi
    else
        echo "✅ i386 架构已启用，跳过"
    fi

    # ========== 刷新软件源 ==========
    echo "📦 刷新软件源..."
    if ! $SUDO apt-get update; then
        echo "❌ apt update 失败，请检查网络或软件源配置"
        return 1
    fi

    # ========== 批量安装所有依赖 ==========
    echo "📥 安装依赖包..."
    if ! $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates \
        curl \
        procps \
        screen \
        unzip \
        lib32gcc-s1 \
        libcurl4-gnutls-dev:i386 \
        libcurl4-gnutls-dev; then
        echo "❌ 依赖安装失败"
        return 1
    fi

    echo "✅ 所有依赖安装完成"
} 

#安装dstgo
install_dstgo() {
    # 安装依赖
    install_dst_dependencies

    local dstgo_urls=(
        "https://github.dpik.top/github.com/carrot-hu23/dst-admin-go/releases/download/1.6.1/dst-admin-go.1.6.1.tar.gz"
        "https://ghproxy.net/github.com/carrot-hu23/dst-admin-go/releases/download/1.6.1/dst-admin-go.1.6.1.tar.gz"
        "https://github.ikgy.top/github.com/carrot-hu23/dst-admin-go/releases/download/1.6.1/dst-admin-go.1.6.1.tar.gz"
        "https://ghfast.top/github.com/carrot-hu23/dst-admin-go/releases/download/1.6.1/dst-admin-go.1.6.1.tar.gz"
    )

    echo "请选择下载镜像源："
    for i in "${!dstgo_urls[@]}"; do
        echo "$((i+1))) ${dstgo_urls[$i]}"
    done
    echo "0) 输入自定义 URL"
    read -p "请输入选项 [0-${#dstgo_urls[@]}]: " choice

    local selected_url=""
    if [[ $choice -ge 1 && $choice -le ${#dstgo_urls[@]} ]]; then
        selected_url="${dstgo_urls[$((choice-1))]}"
    elif [[ $choice -eq 0 ]]; then
        read -p "请输入自定义下载 URL: " selected_url
    else
        echo "❌ 无效选项"
        return 1
    fi

    if [[ -z "$selected_url" ]]; then
        echo "❌ 下载 URL 不能为空"
        return 1
    fi

    local tmp_archive="dst-admin-go.tar.gz"
    local extract_dir="dstgo"

    echo "📥 开始下载: $selected_url"
    if ! curl -fL --retry 3 -o "$tmp_archive" "$selected_url"; then
        echo "❌ 下载失败，请检查网络或镜像源"
        return 1
    fi

    echo "📦 解压文件中..."
    if ! tar -xzf "$tmp_archive"; then
        echo "❌ 解压失败，文件可能损坏"
        rm -f "$tmp_archive"
        return 1
    fi

    # 查找解压后的目录
    local extracted_folder
    extracted_folder=$(find . -maxdepth 1 -type d -name "dst-admin-go*" | head -n 1)

    if [[ -z "$extracted_folder" ]]; then
        echo "❌ 未找到解压后的目录"
        rm -f "$tmp_archive"
        return 1
    fi

    echo "📂 重命名目录为 $extract_dir"
    rm -rf "$extract_dir"
    mv "$extracted_folder" "$extract_dir"

    local binary_path="$extract_dir/dst-admin-go"
    if [[ ! -f "$binary_path" ]]; then
        echo "❌ 未找到可执行文件: $binary_path"
        return 1
    fi

    echo "🔧 赋予可执行权限"
    chmod +x "$binary_path"

    echo "✅ 安装完成！"
    echo "👉 可执行文件位于: $(pwd)/$binary_path"

    # 清理压缩包
    rm -f "$tmp_archive"

    # 创建文件夹
    mkdir -p ~/.klei/DoNotStarveTogether/MyDediServer
    mkdir -p ~/.klei/DoNotStarveTogether/backup
    mkdir -p ~/.klei/DoNotStarveTogether/download_mod
    cp -r ~/dstgo/static/Master ~/.klei/DoNotStarveTogether/MyDediServer/
    cp -r ~/dstgo/static/Caves ~/.klei/DoNotStarveTogether/MyDediServer/

    # 写入相关配置
    cat > ~/dstgo/dst_config <<EOF
steamcmd=/root/steamcmd
force_install_dir=/root/dst-dedicated-server
donot_starve_server_directory=
persistent_storage_root=
cluster=MyDediServer
backup=/root/.klei/DoNotStarveTogether/backup
mod_download_path=/root/.klei/DoNotStarveTogether/download_mod
bin=32
beta=0
EOF
    
    # 返回主目录
    cd ~
}

# 启动 dstgo
start_dstgo() {
    local LOG_FILE="$HOME/dstgo/dst-admin-go.log"
    local WORK_DIR="$HOME/dstgo"

    # 检查二进制文件是否存在
    if [[ ! -f "$WORK_DIR/dst-admin-go" ]]; then
        echo -e "${RED}错误: 未找到 dstgo 可执行文件: $WORK_DIR/dst-admin-go${NC}"
        return 1
    fi

    # 检查是否已有实例在运行（通过进程名匹配）
    local PID=$(pgrep -f "dst-admin-go" 2>/dev/null | head -n1)
    if [[ -n "$PID" ]]; then
        echo -e "${YELLOW}检测到已有 dstgo 进程 (PID: $PID)，正在停止...${NC}"
        kill -9 "$PID" 2>/dev/null
        sleep 1
        if pgrep -f "dst-admin-go" > /dev/null; then
            echo -e "${RED}无法停止旧进程，请手动处理。${NC}"
            return 1
        fi
        echo -e "${GREEN}旧进程已停止。${NC}"
    fi

    # 切换到工作目录并启动程序
    echo -e "${CYAN}正在启动 dstgo...${NC}"
    cd "$WORK_DIR" || { echo -e "${RED}无法进入目录 $WORK_DIR${NC}"; return 1; }
    nohup ./dst-admin-go > "$LOG_FILE" 2>&1 &
    local NEW_PID=$!
    cd - > /dev/null
    sleep 2

    # 检查进程是否存活
    if kill -0 "$NEW_PID" 2>/dev/null; then
        echo -e "${GREEN}启动成功！进程 PID: $NEW_PID${NC}"
        echo -e "${GREEN}日志文件: $LOG_FILE${NC}"
        if [[ -f "$LOG_FILE" ]]; then
            echo -e "${DIM}--- 最新日志 (最后5行) ---${NC}"
            tail -n 5 "$LOG_FILE" | sed 's/^/  /'
        fi
    else
        echo -e "${RED}启动失败！进程未能持续运行。${NC}"
        if [[ -f "$LOG_FILE" ]]; then
            echo -e "${RED}--- 错误日志 (最后10行) ---${NC}"
            tail -n 10 "$LOG_FILE" | sed 's/^/  /'
        else
            echo -e "${RED}未生成日志文件，请检查程序或路径。${NC}"
        fi
        return 1
    fi
}

# 停止dstgo
stop_dstgo() {
    # 查找所有包含 "dst-admin-go" 的进程（匹配命令行任意部分）
    local PIDS
    PIDS=$(pgrep -f "dst-admin-go" 2>/dev/null)
    if [[ -z "$PIDS" ]]; then
        echo -e "${YELLOW}未发现运行中的 dstgo 进程。${NC}"
        return 0
    fi

    echo -e "${CYAN}发现以下 dstgo 进程:${NC}"
    ps -p "$PIDS" -o pid,cmd --no-headers 2>/dev/null || echo "$PIDS"

    # 1. 尝试优雅终止 (SIGTERM)
    echo -e "${CYAN}正在停止进程 (PID: $PIDS)...${NC}"
    kill -15 $PIDS 2>/dev/null

    # 等待最多 5 秒
    local wait_time=0
    while pgrep -f "dst-admin-go" > /dev/null && [[ $wait_time -lt 5 ]]; do
        sleep 1
        ((wait_time++))
    done

    # 2. 如果仍有残留，强制终止 (SIGKILL)
    if pgrep -f "dst-admin-go" > /dev/null; then
        echo -e "${YELLOW}进程未响应 SIGTERM，强制终止...${NC}"
        kill -9 $PIDS 2>/dev/null
        sleep 1
        if pgrep -f "dst-admin-go" > /dev/null; then
            echo -e "${RED}强制终止失败，请手动检查。${NC}"
            return 1
        else
            echo -e "${GREEN}强制终止成功。${NC}"
        fi
    else
        echo -e "${GREEN}已成功停止所有 dstgo 进程。${NC}"
    fi
    return 0
}

clear_dstgo() {
    print_info "正在执行清理"
    rm -f $HOME/dst-admin-go.1.6.1.tar.gz
    rm -f ._dst-admin-go.1.6.1
    rm -rf $HOME/dstgo/
}

# dstgo 开机自启管理
auto_start_dstgo() {
    local DSTGO_BIN="$HOME/dstgo/dst-admin-go"
    local SERVICE_NAME="dstgo.service"
    local SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
    local LOG_FILE="$HOME/dstgo/dst-admin-go.log"

    while true; do
        clear
        print_header
        print_section "dstgo 开机自启管理"

        # 显示当前状态
        local is_enabled=false
        if systemctl is-enabled "$SERVICE_NAME" &> /dev/null; then
            is_enabled=true
        fi

        if $is_enabled; then
            echo -e "${GREEN}  当前状态：已开启开机自启${NC}"
        else
            echo -e "${YELLOW}  当前状态：未开启开机自启${NC}"
        fi
        print_divider

        echo -e "${CYAN}  1) 开启 dstgo 开机自启${NC}"
        echo -e "${CYAN}  2) 关闭 dstgo 开机自启${NC}"
        echo -e "${CYAN}  0) 返回主菜单${NC}"
        print_divider
        read -p "请选择 [0-2]: " autostart_choice

        case $autostart_choice in
            1)
                # ---- 开启自启 ----
                if [[ ! -f "$DSTGO_BIN" ]]; then
                    print_error "未找到 dstgo 可执行文件: $DSTGO_BIN"
                    print_warning "请先执行 [0] 全新安装 或手动安装 dstgo"
                    pause_and_return
                    continue
                fi

                print_info "正在写入 systemd service 文件..."

                # 创建 service 文件（使用绝对路径）
                cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Dst-admin-go Service
After=network.target

[Service]
Type=simple
WorkingDirectory=$HOME/dstgo
ExecStart=$DSTGO_BIN
Restart=on-failure
RestartSec=5
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

                # 重载 systemd 并启用服务
                systemctl daemon-reload
                if systemctl enable "$SERVICE_NAME" 2>/dev/null; then
                    print_success "已设置开机自启"
                else
                    print_error "设置开机自启失败，请检查 systemd 权限"
                    pause_and_return
                    continue
                fi

                # 如果服务未运行，则启动
                if ! systemctl is-active --quiet "$SERVICE_NAME"; then
                    if systemctl start "$SERVICE_NAME" 2>/dev/null; then
                        print_success "dstgo 服务已启动"
                    else
                        print_error "启动 dstgo 服务失败，请检查日志: $LOG_FILE"
                        pause_and_return
                        continue
                    fi
                else
                    print_success "dstgo 服务已在运行中"
                fi

                # 显示简要状态
                systemctl status "$SERVICE_NAME" --no-pager | head -n 10
                pause_and_return
                ;;

            2)
                # ---- 关闭自启 ----
                if [[ ! -f "$SERVICE_FILE" ]]; then
                    print_warning "未检测到 dstgo service 文件，无需关闭"
                    pause_and_return
                    continue
                fi

                print_info "正在关闭 dstgo 开机自启并停止服务..."
                systemctl stop "$SERVICE_NAME" 2>/dev/null
                systemctl disable "$SERVICE_NAME" 2>/dev/null
                rm -f "$SERVICE_FILE"
                systemctl daemon-reload

                print_success "已关闭开机自启，服务已停止，service 文件已移除"
                pause_and_return
                ;;

            0)
                return 0
                ;;

            *)
                print_error "无效选择，请输入 0-2 之间的数字"
                sleep 1
                ;;
        esac
    done
}

# 修改端口
change_port() {
    local config_file="$HOME/dstgo/config.yml"
    if [[ ! -f "$config_file" ]]; then
        print_error "配置文件 $config_file 不存在，请先安装dstgo"
        pause_and_return
        return 1
    fi

    # 读取当前端口
    local current_port
    current_port=$(grep -E '^port:' "$config_file" | awk '{print $2}' | head -n1)
    if [[ -z "$current_port" ]]; then
        print_warning "未找到port配置，可能格式不正确"
        current_port="未知"
    fi

    print_info "当前端口配置: $current_port"
    read -p "请输入新的端口号 (1-65535): " new_port
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 ]] || [[ "$new_port" -gt 65535 ]]; then
        print_error "端口号必须是1-65535之间的数字"
        pause_and_return
        return 1
    fi

    # 替换 port 行
    if sed -i "s/^port:.*/port: $new_port/" "$config_file"; then
        print_success "端口已修改为 $new_port"
    else
        print_error "修改端口失败"
        pause_and_return
        return 1
    fi

    read -p "是否立即重启dstgo使配置生效？(y/n): " restart_choice
    if [[ "$restart_choice" == "y" || "$restart_choice" == "Y" ]]; then
        print_info "正在重启dstgo..."
        stop_dstgo
        start_dstgo
        print_success "dstgo已重启，新端口 $new_port 生效"
    else
        print_warning "请手动重启dstgo以使配置生效"
    fi
    pause_and_return
}

set_swap() {
    SWAPFILE=/swap.img
    SWAPSIZE=2G

    if [ -b /dev/dm-1 ] || [ -f $SWAPFILE ]; then
        print_success "检测到已有 swap 设备 (/dev/dm-1) 或 swap 文件 ($SWAPFILE)，跳过创建步骤"
    else
        print_info "未检测到 swap 设备或文件，正在创建 swap 文件..."
        sudo fallocate -l $SWAPSIZE $SWAPFILE
        sudo chmod 600 $SWAPFILE
        sudo mkswap $SWAPFILE
        sudo swapon $SWAPFILE
        print_success "交换文件创建并启用成功"

        if ! grep -q "$SWAPFILE" /etc/fstab; then
            print_info "将交换文件添加到 /etc/fstab"
            echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab
            print_success "交换文件已添加到开机启动"
        else
            print_success "交换文件已在 /etc/fstab 中，跳过添加步骤"
        fi
    fi

    sysctl -w vm.swappiness=20
    sysctl -w vm.min_free_kbytes=100000
    echo -e 'vm.swappiness = 20\nvm.min_free_kbytes = 100000\n' >/etc/sysctl.d/dstgo_swap.conf

    print_success "系统 swap 设置成功"
}

# 下载 steamcmd
download_steamcmd() {
    # 预置镜像列表
    local steamcmd_urls=(
        "https://github.dpik.top/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://gh.927223.xyz/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://cdn.gh-proxy.org/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://edgeone.gh-proxy.org/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
    )

    echo "请选择 steamcmd 下载镜像源："
    for i in "${!steamcmd_urls[@]}"; do
        echo "$((i+1))) ${steamcmd_urls[$i]}"
    done
    echo "0) 输入自定义 URL"
    read -p "请输入选项 [0-${#steamcmd_urls[@]}]: " choice

    local selected_url=""
    if [[ $choice -ge 1 && $choice -le ${#steamcmd_urls[@]} ]]; then
        selected_url="${steamcmd_urls[$((choice-1))]}"
    elif [[ $choice -eq 0 ]]; then
        read -p "请输入自定义下载 URL: " selected_url
    else
        echo "❌ 无效选项"
        return 1
    fi

    if [[ -z "$selected_url" ]]; then
        echo "❌ 下载 URL 不能为空"
        return 1
    fi

    local tmp_archive="steamcmd_linux.tar.gz"

    # 检查并删除已存在的文件
    if [[ -f "$tmp_archive" ]]; then
        echo "🗑️ 检测到已存在的 $tmp_archive，正在删除..."
        rm -f "$tmp_archive"
    fi

    echo "📥 正在从 $selected_url 下载 steamcmd..."

    if ! curl -fL --retry 10 --connect-timeout 10 --max-time 300 -o "$tmp_archive" "$selected_url"; then
        echo "❌ 下载 steamcmd 失败"
        rm -f "$tmp_archive"
        return 1
    fi

    echo "✅ steamcmd 下载成功"
    return 0
}

install_dst() {
    read -p "您确定要安装 Don't Starve Together 服务器吗？(y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_warning "安装已取消."
        return
    fi

    # 安装依赖
    install_dst_dependencies

    mkdir -p "$HOME/steamcmd"
    cd "$HOME/steamcmd" || exit 1

    # ---------- 调用新函数，手动选择镜像下载 ----------
    if ! download_steamcmd; then
        print_error "=================================================="
        print_error "✘✘✘ steamcmd 下载失败！"
        print_error "=================================================="
        print_error "无法下载 steamcmd，请检查网络连接后重试！"
        exit 1
    fi

    print_success "文件验证通过，开始解压..."
    tar -xvzf steamcmd_linux.tar.gz

    # 以下为原有的 steamcmd 执行、安装验证、依赖修复等，完全不变
    ./steamcmd.sh +force_install_dir "$install_dir" +login anonymous +app_update 343050 validate +quit

    max_retries=3
    retry_count=0
    install_success=false

    while [ $retry_count -lt $max_retries ]; do
        print_info "正在验证服务器安装 (尝试 $((retry_count+1))/$((max_retries+1)))..."
        if [ -d "$install_dir/bin/" ]; then
            cd "$install_dir/bin/" && {
                install_success=true
                break
            }
        fi
        if [ $retry_count -lt $max_retries ]; then
            print_warning "服务器安装验证失败，正在尝试重新安装 ($((retry_count+1))/$max_retries)..."
            cd "$HOME/steamcmd" || break
            ./steamcmd.sh +force_install_dir "$install_dir" +login anonymous +app_update 343050 validate +quit
            retry_count=$((retry_count+1))
            sleep 2
        fi
    done

    if [ "$install_success" = true ]; then
        print_success "✅ 服务器安装验证通过！"
        cp "$HOME/steamcmd/linux32/libstdc++.so.6" "$install_dir/bin/lib32/" 2>/dev/null
        cp "$HOME/steamcmd/linux32/steamclient.so" "$install_dir/bin/lib32/" 2>/dev/null
        cp "$HOME/steamcmd/linux64/steamclient.so" "$install_dir/bin64/lib64/" 2>/dev/null
        print_success "依赖已修复"
        print_success "✅ Don't Starve Together 服务器安装完成！"
    else
        print_error "经过 $((max_retries+1)) 次尝试后，服务器安装仍然失败！"
        cd "$HOME"
        exit 1
    fi

    cd "$HOME"
    echo
}

update_dst() {
    print_info "正在更新 Don't Starve Together 服务器..."
    cd "$steamcmd_dir" || exit 1
    ./steamcmd.sh +force_install_dir "$install_dir" +login anonymous +app_update 343050 validate +quit
    print_success "服务器更新完成，请重新执行脚本"
    cp $HOME/steamcmd/linux32/steamclient.so $install_dir/bin/lib32/ 2>/dev/null
    cp $HOME/steamcmd/linux64/steamclient.so $install_dir/bin64/lib64/ 2>/dev/null
    cp $HOME/steamcmd/linux32/libstdc++.so.6 $install_dir/bin/lib32/ 2>/dev/null
    print_success "MOD 更新 bug 已修复"
}

manage_crontab() {
    while true; do
        clear
        print_header
        print_section "steamcmd 自动更新任务管理"
        echo -e "${CYAN}  1) 添加 6:10 自动更新任务${NC}"
        echo -e "${CYAN}  2) 添加 22:10 自动更新任务${NC}"
        echo -e "${CYAN}  3) 移除所有 steamcmd 更新任务${NC}"
        echo -e "${CYAN}  0) 返回主菜单${NC}"
        print_divider
        read -p "请选择 [0-3]: " crontab_choice

        morning_task="10 6 * * * cd /root/steamcmd && /root/steamcmd/steamcmd.sh +quit > /dev/null 2>&1"
        evening_task="10 22 * * * cd /root/steamcmd && /root/steamcmd/steamcmd.sh +quit > /dev/null 2>&1"

        case $crontab_choice in
            1)
                if crontab -l | grep -F "$morning_task" > /dev/null; then
                    print_warning "6:10 自动任务已存在，无需重复添加"
                else
                    (crontab -l 2>/dev/null; echo "$morning_task") | crontab -
                    print_success "6:10 自动任务添加成功"
                fi
                pause_and_return
                ;;
            2)
                if crontab -l | grep -F "$evening_task" > /dev/null; then
                    print_warning "22:10 自动任务已存在，无需重复添加"
                else
                    (crontab -l 2>/dev/null; echo "$evening_task") | crontab -
                    print_success "22:10 自动任务添加成功"
                fi
                pause_and_return
                ;;
            3)
                crontab -l 2>/dev/null | grep -v "steamcmd" > /tmp/crontab_new
                crontab /tmp/crontab_new
                rm -f /tmp/crontab_new
                print_success "steamcmd 自动任务已成功移除"
                pause_and_return
                ;;
            0)
                return 0
                ;;
            *)
                print_error "无效选择，请输入 0-3 之间的数字"
                sleep 1
                ;;
        esac
    done
}

disable_ubuntu_autoupdate() {
    print_info "正在禁用 Ubuntu 自动更新..."
    systemctl stop unattended-upgrades
    systemctl disable unattended-upgrades
    systemctl stop apt-daily.timer
    systemctl disable apt-daily.timer
    systemctl stop apt-daily-upgrade.timer
    systemctl disable apt-daily-upgrade.timer

    AUTO_UPGRADE_FILE="/etc/apt/apt.conf.d/20auto-upgrades"
    if [ -f "$AUTO_UPGRADE_FILE" ]; then
        cp "$AUTO_UPGRADE_FILE" "$AUTO_UPGRADE_FILE.bak"
        if grep -q 'APT::Periodic::Update-Package-Lists "1";' "$AUTO_UPGRADE_FILE"; then
            sed -i 's/APT::Periodic::Update-Package-Lists "1";/APT::Periodic::Update-Package-Lists "0";/' "$AUTO_UPGRADE_FILE"
        fi
        if grep -q 'APT::Periodic::Unattended-Upgrade "1";' "$AUTO_UPGRADE_FILE"; then
            sed -i 's/APT::Periodic::Unattended-Upgrade "1";/APT::Periodic::Unattended-Upgrade "0";/' "$AUTO_UPGRADE_FILE"
        fi
    else
        echo 'APT::Periodic::Update-Package-Lists "0";' > "$AUTO_UPGRADE_FILE"
        echo 'APT::Periodic::Unattended-Upgrade "0";' >> "$AUTO_UPGRADE_FILE"
    fi
    print_success "Ubuntu 自动更新已禁用。"
}

# ==================== 主菜单 ====================
show_main_menu() {
    print_header
    echo -e "${WHITE}${BOLD}  主菜单${NC}"
    print_divider
    echo -e "${GREEN}  [0]${NC}  全新安装 dstgo 平台"
    print_divider
    echo -e "${GREEN}  [1]${NC}  启动 dstgo 平台"
    echo -e "${GREEN}  [2]${NC}  关闭 dstgo 平台"
    echo -e "${GREEN}  [3]${NC}  设置 dstgo 开机自启"
    print_divider
    echo -e "${GREEN}  [4]${NC}  下载 DST 服务器程序"
    echo -e "${GREEN}  [5]${NC}  更新 DST 服务器程序"
    echo -e "${GREEN}  [6]${NC}  管理 steamcmd 自动更新任务"
    print_divider
    echo -e "${GREEN}  [7]${NC}  禁用 Ubuntu 自动更新"
    echo -e "${GREEN}  [8]${NC}  设置虚拟内存 (Swap)"
    echo -e "${GREEN}  [9]${NC}  修改 dstgo 服务端口"
    print_divider
    echo -e "${RED}  [q/Q]${NC} 退出脚本"
    print_divider
    echo -n -e "${CYAN}请输入选项 [0-12/q]: ${NC}"
}

# ==================== 主程序入口 ====================
cd "$HOME" || exit

# ==================== 检查 root 权限 ====================
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：此脚本需要 root 权限运行。请使用 sudo 执行。${NC}"
    exit 1
fi

while true; do
    show_main_menu
    read -r choice
    case $choice in
        0)
            clear_dstgo
            install_dstgo
            pause_and_return
            ;;
        1)
            start_dstgo
            pause_and_return
            ;;
        2)
            stop_dstgo
            pause_and_return
            ;;
        3)
            auto_start_dstgo
            ;;
        4)
            install_dst
            ;;
        5)
            update_dst
            ;;
        6)
            manage_crontab
            ;;
        7)
            disable_ubuntu_autoupdate
            ;;
        8)
            set_swap
            ;;
        9)
            change_port
            ;;
        q|Q)
            echo -e "${GREEN}感谢使用，再见！${NC}"
            exit 0
            ;;
        *)
            print_error "请输入正确的选项 [0-11 或 q]"
            sleep 1
            ;;
    esac
done