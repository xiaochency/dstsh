#!/bin/bash

# ==============================================================================
# 脚本：dst-admin-go 管理脚本
# 描述：适用于ubuntu管理 Don't Starve Together 专用服务器
# 作者：xiaochency
# ==============================================================================

# ==============================================================================
# 常量与配置
# ==============================================================================

readonly INSTALL_DIR="$HOME/dst-dedicated-server"
readonly STEAMCMD_DIR="$HOME/steamcmd"
readonly DSTGO_DIR="$HOME/dstgo"
readonly KLEI_DIR="$HOME/.klei/DoNotStarveTogether"
readonly DSTGO_CONFIG="$DSTGO_DIR/config.yml"
readonly DSTGO_BINARY="$DSTGO_DIR/dst-admin-go"
readonly DSTGO_LOG="$DSTGO_DIR/dst-admin-go.log"
readonly SERVICE_NAME="dstgo.service"
readonly SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"

# DSTGO 下载镜像列表
readonly DSTGO_URLS=(
    "https://github.dpik.top/github.com/carrot-hu23/dst-admin-go/releases/download/1.6.1/dst-admin-go.1.6.1.tar.gz"
    "https://ghproxy.net/github.com/carrot-hu23/dst-admin-go/releases/download/1.6.1/dst-admin-go.1.6.1.tar.gz"
    "https://github.ikgy.top/github.com/carrot-hu23/dst-admin-go/releases/download/1.6.1/dst-admin-go.1.6.1.tar.gz"
    "https://ghfast.top/github.com/carrot-hu23/dst-admin-go/releases/download/1.6.1/dst-admin-go.1.6.1.tar.gz"
)

# SteamCMD 下载镜像列表
readonly STEAMCMD_URLS=(
    "https://github.dpik.top/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
    "https://gh.927223.xyz/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
    "https://cdn.gh-proxy.org/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
    "https://edgeone.gh-proxy.org/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
    "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
)

# ==============================================================================
# 颜色定义
# ==============================================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'          # 无颜色
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly LINE="${WHITE}————————————————————————————————————————————————————————————${NC}"

# ==============================================================================
# 辅助函数：打印信息
# ==============================================================================

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "   ╔══════════════════════════════════════════════════════════╗"
    echo "              Dst-admin-go管理脚本 v1.0.4                      "
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

# ==============================================================================
# 辅助函数：系统操作
# ==============================================================================

# 检查是否以 root 身份运行（脚本要求）
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要 root 权限运行。请使用 sudo 执行。"
        exit 1
    fi
}

# 获取 sudo 前缀（若非 root 则尝试使用 sudo）
get_sudo() {
    local SUDO=""
    if [[ $EUID -ne 0 ]]; then
        if command -v sudo &> /dev/null; then
            SUDO="sudo"
        else
            print_error "非 root 用户且未找到 sudo，无法执行需要特权的操作。"
            return 1
        fi
    fi
    echo "$SUDO"
}

# 选择下载镜像（通用函数）
# 参数：镜像列表数组名称（通过名字引用），提示信息
# 返回：选中的 URL 字符串（通过全局变量 SELECTED_URL 返回）
select_mirror() {
    local -n urls_ref=$1
    local prompt="$2"
    local choice
    local selected_url=""

    echo "$prompt"
    for i in "${!urls_ref[@]}"; do
        echo "$((i+1))) ${urls_ref[$i]}"
    done
    echo "0) 输入自定义 URL"
    read -p "请输入选项 [0-${#urls_ref[@]}]: " choice

    if [[ $choice -ge 1 && $choice -le ${#urls_ref[@]} ]]; then
        selected_url="${urls_ref[$((choice-1))]}"
    elif [[ $choice -eq 0 ]]; then
        read -p "请输入自定义下载 URL: " selected_url
    else
        print_error "无效选项"
        return 1
    fi

    if [[ -z "$selected_url" ]]; then
        print_error "URL 不能为空"
        return 1
    fi

    SELECTED_URL="$selected_url"
    return 0
}

# 通用的下载并解压函数
download_and_extract() {
    local url="$1"
    local archive_name="$2"
    local target_dir="$3"
    local tmp_dir

    print_info "开始下载: $url"
    if ! axel -n 16 -o "$archive_name" "$url"; then
        print_error "下载失败，请检查网络或镜像源"
        return 1
    fi

    print_info "解压文件中..."
    if ! tar -xzf "$archive_name"; then
        print_error "解压失败，文件可能损坏"
        rm -f "$archive_name"
        return 1
    fi

    # 如果指定了目标目录，则移动解压后的内容
    if [[ -n "$target_dir" ]]; then
        # 查找解压出的唯一目录（通常包含可执行文件）
        local extracted_folder
        extracted_folder=$(find . -maxdepth 1 -type d -name "dst-admin-go*" | head -n 1)
        if [[ -z "$extracted_folder" ]]; then
            print_error "未找到解压后的目录"
            rm -f "$archive_name"
            return 1
        fi

        print_info "将解压内容移动到 $target_dir"
        rm -rf "$target_dir"
        mv "$extracted_folder" "$target_dir"
    fi

    rm -f "$archive_name"
    return 0
}

# ==============================================================================
# 核心功能函数
# ==============================================================================

# -------------------- 依赖安装 --------------------
install_dst_dependencies() {
    print_info "检查并安装 DST 运行依赖..."

    dpkg --add-architecture i386
    apt-get update
    apt-get install -y screen unzip ca-certificates procps axel
    apt-get install -y libstdc++6:i386 libgcc1:i386 libcurl4-gnutls-dev:i386

    print_success "所有依赖安装完成"
}

# -------------------- DSTGO 安装 --------------------
install_dstgo() {
    # 安装依赖
    install_dst_dependencies || return 1

    # 选择镜像
    if ! select_mirror DSTGO_URLS "请选择 dst-admin-go 下载镜像源："; then
        return 1
    fi
    local url="$SELECTED_URL"

    # 临时目录
    local tmp_archive="dst-admin-go.tar.gz"
    cd "$HOME" || return 1

    # 下载并解压
    if ! download_and_extract "$url" "$tmp_archive" "$DSTGO_DIR"; then
        return 1
    fi

    # 验证可执行文件
    if [[ ! -f "$DSTGO_BINARY" ]]; then
        print_error "未找到可执行文件: $DSTGO_BINARY"
        return 1
    fi

    chmod +x "$DSTGO_BINARY"
    print_success "安装完成！可执行文件位于: $DSTGO_BINARY"

    # 创建必要目录
    mkdir -p "$KLEI_DIR/MyDediServer"
    mkdir -p "$KLEI_DIR/backup"
    mkdir -p "$KLEI_DIR/download_mod"

    # 复制静态配置（Master / Caves）
    if [[ -d "$DSTGO_DIR/static/Master" ]]; then
        cp -r "$DSTGO_DIR/static/Master" "$KLEI_DIR/MyDediServer/"
    fi
    if [[ -d "$DSTGO_DIR/static/Caves" ]]; then
        cp -r "$DSTGO_DIR/static/Caves" "$KLEI_DIR/MyDediServer/"
    fi

    # 写入 dst_config 配置文件
    cat > "$DSTGO_DIR/dst_config" <<EOF
steamcmd=$STEAMCMD_DIR
force_install_dir=$INSTALL_DIR
donot_starve_server_directory=
persistent_storage_root=
cluster=MyDediServer
backup=$KLEI_DIR/backup
mod_download_path=$KLEI_DIR/download_mod
bin=32
beta=0
EOF

    print_success "dst-admin-go 安装完成！"
}

# -------------------- DSTGO 启动/停止 --------------------
start_dstgo() {
    # 检查二进制文件是否存在
    if [[ ! -f "$DSTGO_BINARY" ]]; then
        print_error "未找到 dstgo 可执行文件: $DSTGO_BINARY"
        return 1
    fi

    # 检查是否已有实例在运行（通过进程名匹配）
    local pid
    pid=$(pgrep -f "dst-admin-go" 2>/dev/null | head -n1)
    if [[ -n "$pid" ]]; then
        print_warning "检测到已有 dstgo 进程 (PID: $pid)，正在停止..."
        kill -9 "$pid" 2>/dev/null
        sleep 1
        if pgrep -f "dst-admin-go" > /dev/null; then
            print_error "无法停止旧进程，请手动处理。"
            return 1
        fi
        print_success "旧进程已停止。"
    fi

    # 切换到工作目录并启动程序
    print_info "正在启动 dstgo..."
    cd "$DSTGO_DIR" || { print_error "无法进入目录 $DSTGO_DIR"; return 1; }
    nohup ./dst-admin-go > "$DSTGO_LOG" 2>&1 &
    local new_pid=$!
    cd - > /dev/null
    sleep 2

    # 检查进程是否存活
    if kill -0 "$new_pid" 2>/dev/null; then
        print_success "启动成功！进程 PID: $new_pid"
        print_success "日志文件: $DSTGO_LOG"
        if [[ -f "$DSTGO_LOG" ]]; then
            echo -e "${DIM}--- 最新日志 (最后5行) ---${NC}"
            tail -n 5 "$DSTGO_LOG" | sed 's/^/  /'
        fi
    else
        print_error "启动失败！进程未能持续运行。"
        if [[ -f "$DSTGO_LOG" ]]; then
            print_error "错误日志 (最后10行):"
            tail -n 10 "$DSTGO_LOG" | sed 's/^/  /'
        else
            print_error "未生成日志文件，请检查程序或路径。"
        fi
        return 1
    fi
}

stop_dstgo() {
    local pids
    pids=$(pgrep -f "dst-admin-go" 2>/dev/null)
    if [[ -z "$pids" ]]; then
        print_warning "未发现运行中的 dstgo 进程。"
        return 0
    fi

    print_info "发现以下 dstgo 进程:"
    ps -p "$pids" -o pid,cmd --no-headers 2>/dev/null || echo "$pids"

    # 先尝试 SIGTERM
    print_info "正在停止进程 (PID: $pids)..."
    kill -15 $pids 2>/dev/null

    local wait_time=0
    while pgrep -f "dst-admin-go" > /dev/null && [[ $wait_time -lt 5 ]]; do
        sleep 1
        ((wait_time++))
    done

    # 如果仍有残留，强制终止
    if pgrep -f "dst-admin-go" > /dev/null; then
        print_warning "进程未响应 SIGTERM，强制终止..."
        kill -9 $pids 2>/dev/null
        sleep 1
        if pgrep -f "dst-admin-go" > /dev/null; then
            print_error "强制终止失败，请手动检查。"
            return 1
        else
            print_success "强制终止成功。"
        fi
    else
        print_success "已成功停止所有 dstgo 进程。"
    fi
    return 0
}

# -------------------- DSTGO 清理 --------------------
clear_dstgo() {
    print_info "正在执行清理"
    rm -f "$HOME/dst-admin-go.1.6.1.tar.gz"
    rm -f "$HOME/._dst-admin-go.1.6.1"
    rm -rf "$DSTGO_DIR"
    print_success "清理完成"
}

# -------------------- DSTGO 开机自启管理 --------------------
auto_start_dstgo() {
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
                # 开启自启
                if [[ ! -f "$DSTGO_BINARY" ]]; then
                    print_error "未找到 dstgo 可执行文件: $DSTGO_BINARY"
                    print_warning "请先执行 [0] 全新安装 或手动安装 dstgo"
                    pause_and_return
                    continue
                fi

                print_info "正在写入 systemd service 文件..."
                cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Dst-admin-go Service
After=network.target

[Service]
Type=simple
WorkingDirectory=$DSTGO_DIR
ExecStart=$DSTGO_BINARY
Restart=on-failure
RestartSec=5
StandardOutput=append:$DSTGO_LOG
StandardError=append:$DSTGO_LOG

[Install]
WantedBy=multi-user.target
EOF

                systemctl daemon-reload
                if systemctl enable "$SERVICE_NAME" 2>/dev/null; then
                    print_success "已设置开机自启"
                else
                    print_error "设置开机自启失败，请检查 systemd 权限"
                    pause_and_return
                    continue
                fi

                # 如果服务未运行则启动
                if ! systemctl is-active --quiet "$SERVICE_NAME"; then
                    if systemctl start "$SERVICE_NAME" 2>/dev/null; then
                        print_success "dstgo 服务已启动"
                    else
                        print_error "启动 dstgo 服务失败，请检查日志: $DSTGO_LOG"
                        pause_and_return
                        continue
                    fi
                else
                    print_success "dstgo 服务已在运行中"
                fi

                systemctl status "$SERVICE_NAME" --no-pager | head -n 10
                pause_and_return
                ;;

            2)
                # 关闭自启
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

# -------------------- 修改 DSTGO 端口 --------------------
change_port() {
    if [[ ! -f "$DSTGO_CONFIG" ]]; then
        print_error "配置文件 $DSTGO_CONFIG 不存在，请先安装 dstgo"
        pause_and_return
        return 1
    fi

    # 读取当前端口
    local current_port
    current_port=$(grep -E '^port:' "$DSTGO_CONFIG" | awk '{print $2}' | head -n1)
    if [[ -z "$current_port" ]]; then
        print_warning "未找到 port 配置，可能格式不正确"
        current_port="未知"
    fi

    print_info "当前端口配置: $current_port"
    read -p "请输入新的端口号 (1-65535): " new_port
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 ]] || [[ "$new_port" -gt 65535 ]]; then
        print_error "端口号必须是 1-65535 之间的数字"
        pause_and_return
        return 1
    fi

    if sed -i "s/^port:.*/port: $new_port/" "$DSTGO_CONFIG"; then
        print_success "端口已修改为 $new_port"
    else
        print_error "修改端口失败"
        pause_and_return
        return 1
    fi

    read -p "是否立即重启 dstgo 使配置生效？(y/n): " restart_choice
    if [[ "$restart_choice" == "y" || "$restart_choice" == "Y" ]]; then
        print_info "正在重启 dstgo..."
        stop_dstgo
        start_dstgo
        print_success "dstgo 已重启，新端口 $new_port 生效"
    else
        print_warning "请手动重启 dstgo 以使配置生效"
    fi
    pause_and_return
}

# -------------------- Swap 设置 --------------------
set_swap() {
    local SWAPFILE="/swap.img"
    local SWAPSIZE="2G"

    if [ -b /dev/dm-1 ] || [ -f "$SWAPFILE" ]; then
        print_success "检测到已有 swap 设备 (/dev/dm-1) 或 swap 文件 ($SWAPFILE)，跳过创建步骤"
    else
        print_info "未检测到 swap 设备或文件，正在创建 swap 文件..."
        sudo fallocate -l "$SWAPSIZE" "$SWAPFILE"
        sudo chmod 600 "$SWAPFILE"
        sudo mkswap "$SWAPFILE"
        sudo swapon "$SWAPFILE"
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
    echo -e 'vm.swappiness = 20\nvm.min_free_kbytes = 100000\n' > /etc/sysctl.d/dstgo_swap.conf

    print_success "系统 swap 设置成功"
}

# -------------------- SteamCMD 下载 --------------------
download_steamcmd() {
    local tmp_archive="steamcmd_linux.tar.gz"

    # 选择镜像
    if ! select_mirror STEAMCMD_URLS "请选择 steamcmd 下载镜像源："; then
        return 1
    fi
    local url="$SELECTED_URL"

    # 删除已存在的文件
    if [[ -f "$tmp_archive" ]]; then
        print_info "检测到已存在的 $tmp_archive，正在删除..."
        rm -f "$tmp_archive"
    fi

    print_info "正在从 $url 下载 steamcmd..."
    if ! axel -n 16 -o "$tmp_archive" "$url"; then
        print_error "下载 steamcmd 失败"
        rm -f "$tmp_archive"
        return 1
    fi

    print_success "steamcmd 下载成功"
    return 0
}

# -------------------- DST 服务器安装 --------------------
install_dst() {
    read -p "您确定要安装 Don't Starve Together 服务器吗？(y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_warning "安装已取消."
        return
    fi

    mkdir -p "$STEAMCMD_DIR"
    cd "$STEAMCMD_DIR" || exit 1

    # 下载 steamcmd
    if ! download_steamcmd; then
        print_error "=================================================="
        print_error "✘✘✘ steamcmd 下载失败！"
        print_error "=================================================="
        print_error "无法下载 steamcmd，请检查网络连接后重试！"
        exit 1
    fi

    print_success "文件验证通过，开始解压..."
    tar -xvzf steamcmd_linux.tar.gz

    # 执行 steamcmd 安装 DST 服务器
    print_info "开始安装 DST 服务器，此过程可能需要较长时间..."
    ./steamcmd.sh +force_install_dir "$INSTALL_DIR" +login anonymous +app_update 343050 validate +quit

    # 重试机制（最多3次额外重试）
    local max_retries=3
    local retry_count=0
    local install_success=false

    while [[ $retry_count -lt $max_retries ]]; do
        print_info "正在验证服务器安装 (尝试 $((retry_count+1))/$((max_retries)))..."
        if [[ -d "$INSTALL_DIR/bin/" ]]; then
            cd "$INSTALL_DIR/bin/" || break
            install_success=true
            break
        fi
        print_warning "服务器安装验证失败，正在尝试重新安装 ($((retry_count+1))/$max_retries)..."
        cd "$STEAMCMD_DIR" || break
        ./steamcmd.sh +force_install_dir "$INSTALL_DIR" +login anonymous +app_update 343050 validate +quit
        retry_count=$((retry_count+1))
        sleep 2
    done

    if $install_success; then
        print_success "✅ 服务器安装验证通过！"
        # 修复依赖库
        # cp "$STEAMCMD_DIR/linux32/libstdc++.so.6" "$INSTALL_DIR/bin/lib32/" 2>/dev/null
        cp "$STEAMCMD_DIR/linux32/steamclient.so" "$INSTALL_DIR/bin/lib32/" 2>/dev/null
        cp "$STEAMCMD_DIR/linux64/steamclient.so" "$INSTALL_DIR/bin64/lib64/" 2>/dev/null
        print_success "依赖已修复"
        print_success "✅ Don't Starve Together 服务器安装完成！"
    else
        print_error "经过 $max_retries 次重试后，服务器安装仍然失败！"
        cd "$HOME"
        exit 1
    fi

    cd "$HOME"
    echo
}

# -------------------- DST 服务器更新 --------------------
update_dst() {
    print_info "正在更新 Don't Starve Together 服务器..."
    cd "$STEAMCMD_DIR" || exit 1
    ./steamcmd.sh +force_install_dir "$INSTALL_DIR" +login anonymous +app_update 343050 validate +quit
    print_success "服务器更新完成，请重新执行脚本"

    # 修复 MOD 更新 bug（复制依赖文件）
    cp "$STEAMCMD_DIR/linux32/steamclient.so" "$INSTALL_DIR/bin/lib32/" 2>/dev/null
    cp "$STEAMCMD_DIR/linux64/steamclient.so" "$INSTALL_DIR/bin64/lib64/" 2>/dev/null
    # cp "$STEAMCMD_DIR/linux32/libstdc++.so.6" "$INSTALL_DIR/bin/lib32/" 2>/dev/null
    print_success "MOD 更新 bug 已修复"
}

# -------------------- Crontab 自动更新任务管理 --------------------
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

        local morning_task="10 6 * * * cd /root/steamcmd && /root/steamcmd/steamcmd.sh +quit > /dev/null 2>&1"
        local evening_task="10 22 * * * cd /root/steamcmd && /root/steamcmd/steamcmd.sh +quit > /dev/null 2>&1"

        case $crontab_choice in
            1)
                if crontab -l 2>/dev/null | grep -F "$morning_task" > /dev/null; then
                    print_warning "6:10 自动任务已存在，无需重复添加"
                else
                    (crontab -l 2>/dev/null; echo "$morning_task") | crontab -
                    print_success "6:10 自动任务添加成功"
                fi
                pause_and_return
                ;;
            2)
                if crontab -l 2>/dev/null | grep -F "$evening_task" > /dev/null; then
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

# -------------------- 禁用 Ubuntu 自动更新 --------------------
disable_ubuntu_autoupdate() {
    print_info "正在禁用 Ubuntu 自动更新..."
    systemctl stop unattended-upgrades
    systemctl disable unattended-upgrades
    systemctl stop apt-daily.timer
    systemctl disable apt-daily.timer
    systemctl stop apt-daily-upgrade.timer
    systemctl disable apt-daily-upgrade.timer

    local AUTO_UPGRADE_FILE="/etc/apt/apt.conf.d/20auto-upgrades"
    if [[ -f "$AUTO_UPGRADE_FILE" ]]; then
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

# ==============================================================================
# 主菜单
# ==============================================================================

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
    echo -n -e "${CYAN}请输入选项 [0-9/q]: ${NC}"
}

# ==============================================================================
# 主程序入口
# ==============================================================================

# 确保脚本以 root 权限运行
check_root

cd "$HOME" || exit

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
        pause_and_return
        ;;
    5)
        update_dst
        pause_and_return
        ;;
    6)
        manage_crontab
        ;;
    7)
        disable_ubuntu_autoupdate
        pause_and_return
        ;;
    8)
        set_swap
        pause_and_return
        ;;
    9)
        change_port
        ;;
    q|Q)
        echo -e "${GREEN}感谢使用，再见！${NC}"
        exit 0
        ;;
    *)
        print_error "请输入正确的选项 [0-9 或 q]"
        sleep 1
        ;;
esac
done