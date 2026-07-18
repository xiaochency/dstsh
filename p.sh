#!/bin/bash
# ============================================================
# 幻兽帕鲁 (Palworld) 服务端管理脚本 for Ubuntu 24.04 LTS
# ============================================================

# ------------------------- 颜色定义 -------------------------
COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_PURPLE='\033[0;35m'
COLOR_CYAN='\033[0;36m'
COLOR_BOLD='\033[1m'

print_info()  { echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} $1"; }
print_warn()  { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $1"; }
print_error() { echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1"; }
print_title() { echo -e "${COLOR_BOLD}${COLOR_PURPLE}$1${COLOR_RESET}"; }
print_step()  { echo -e "${COLOR_CYAN}==>${COLOR_RESET} $1"; }

# ------------------------- 配置变量 -------------------------
SERVICE_NAME="palworld.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
SERVER_SCRIPT="./PalServer.sh"
SERVER_ARGS="-useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS"
APP_ID=2394010

# 这些路径将在 detect_run_user 中设置
STEAMCMD_DIR=""
STEAMCMD=""
PAL_DIR=""
USER_HOME=""
RUN_USER="steam"

# ------------------------- 基础检查 -------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用 root 或 sudo 运行此脚本"
        exit 1
    fi
}

detect_run_user() {
    if ! id "$RUN_USER" &>/dev/null; then
        useradd -m -s /bin/bash "$RUN_USER"
        print_info "创建用户 steam"
    fi
    USER_HOME=$(getent passwd "$RUN_USER" | cut -d: -f6)
    STEAMCMD_DIR="${USER_HOME}/steamcmd"
    STEAMCMD="${STEAMCMD_DIR}/steamcmd.sh"
    PAL_DIR="${USER_HOME}/Steam/steamapps/common/PalServer"
    print_info "运行用户: $RUN_USER"
    print_info "服务端目录: $PAL_DIR"
}

# 设置所有相关目录的属主为 steam
ensure_ownership() {
    local dirs=("$PAL_DIR" "$STEAMCMD_DIR" "${USER_HOME}/.steam" "${USER_HOME}/Steam")
    for d in "${dirs[@]}"; do
        if [[ -d "$d" ]]; then
            chown -R "$RUN_USER":"$RUN_USER" "$d" 2>/dev/null || true
        fi
    done
}

# ------------------------- RCON 自检与安装 -------------------------
ensure_rcon() {
    if command -v rcon &>/dev/null; then
        print_info "rcon 已存在: $(command -v rcon)"
        return 0
    fi

    print_warn "未检测到 rcon，请选择下载源："

    URLS=(
        "https://github.dpik.top/github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz"
        "https://ghproxy.com/github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz"
        "https://cdn.gh-proxy.org/github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz"
    )

    PS3="请输入数字 (1-3，直接回车默认选1): "
    select DOWNLOAD_URL in "${URLS[@]}"; do
        if [[ -n "$DOWNLOAD_URL" ]]; then
            break
        else
            DOWNLOAD_URL="${URLS[0]}"
            echo "使用默认源: $DOWNLOAD_URL"
            break
        fi
    done

    print_info "开始下载: $DOWNLOAD_URL"
    TMP_DIR=$(mktemp -d)

    cd "$TMP_DIR" || return 1
    wget -q --show-progress --timeout=30 --tries=3 "$DOWNLOAD_URL" -O rcon.tar.gz
    if [[ $? -ne 0 ]]; then
        print_error "下载失败，请检查网络或手动安装 rcon"
        cd - >/dev/null
        rm -rf "$TMP_DIR"
        return 1
    fi

    tar -xzf rcon.tar.gz

    if [[ -d "rcon-0.10.3-amd64_linux" ]]; then
        cd rcon-0.10.3-amd64_linux || {
            print_error "无法进入目录 rcon-0.10.3-amd64_linux"
            cd - >/dev/null
            rm -rf "$TMP_DIR"
            return 1
        }
    else
        print_error "解压后未找到目录 rcon-0.10.3-amd64_linux"
        cd - >/dev/null
        rm -rf "$TMP_DIR"
        return 1
    fi

    if [[ -f "rcon" ]]; then
        chmod +x rcon
        mv rcon /usr/local/bin/rcon
        print_info "已移动 rcon 到 /usr/local/bin/ 并赋予执行权限"
    else
        print_error "在 rcon-0.10.3-amd64_linux 目录中未找到 rcon 文件"
        cd - >/dev/null
        rm -rf "$TMP_DIR"
        return 1
    fi

    cd - >/dev/null
    cd - >/dev/null
    rm -rf "$TMP_DIR"

    if command -v rcon &>/dev/null; then
        print_info "✅ rcon 安装成功"
    else
        print_error "❌ rcon 安装失败"
        return 1
    fi
}

install_dependencies() {
    print_step "安装系统依赖..."
    dpkg --add-architecture i386
    apt update
    apt install -y lib32gcc-s1 lib32stdc++6 libuuid1:i386 libcurl4:i386

    if [[ -f "$STEAMCMD" ]]; then
        print_info "steamcmd 已存在"
        return
    fi

    echo "选择 steamcmd 下载源:"
    select url in \
        "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz (官方)" \
        "https://github.dpik.top/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz" \
        "https://ghproxy.com/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz" \
        "https://cdn.gh-proxy.org/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
    do
        DOWNLOAD_URL="${url%% *}"
        break
    done

    mkdir -p "$STEAMCMD_DIR"
    wget -q --show-progress "$DOWNLOAD_URL" -O /tmp/steamcmd.tar.gz
    tar -xzf /tmp/steamcmd.tar.gz -C "$STEAMCMD_DIR"
    rm -f /tmp/steamcmd.tar.gz

    # 关键：将 steamcmd 目录属主改为 steam
    chown -R "$RUN_USER":"$RUN_USER" "$STEAMCMD_DIR"
}

generate_systemd_service() {
    print_step "生成 systemd 服务..."

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Palworld Dedicated Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_USER}
WorkingDirectory=${PAL_DIR}
ExecStart=${PAL_DIR}/${SERVER_SCRIPT} ${SERVER_ARGS}
Restart=always
RestartSec=120
LimitNOFILE=100000
Environment="LD_LIBRARY_PATH=${STEAMCMD_DIR}/linux64:${USER_HOME}/.steam/sdk64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    print_info "systemd 服务已生成"
}

check_service_ready() {
    if [[ ! -f "$SERVICE_FILE" ]]; then
        generate_systemd_service
    fi
}

# ------------------------- 功能函数 -------------------------
start_server() {
    print_title ">>> 启动 Palworld 服务器"
    check_service_ready

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_warn "服务器已在运行"
        return
    fi

    ensure_ownership
    systemctl start "$SERVICE_NAME"
    sleep 2

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_info "✅ 启动成功"
        print_info "日志: journalctl -u $SERVICE_NAME -f"
    else
        print_error "❌ 启动失败"
        journalctl -u "$SERVICE_NAME" -n 30 --no-pager
    fi
}

stop_server() {
    print_title ">>> 强制停止 Palworld 服务器"
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        print_warn "服务器未运行"
        return
    fi
    systemctl stop "$SERVICE_NAME"
    print_info "✅ 已停止"
}

status_server() {
    print_title ">>> 服务器状态"
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_info "✅ 正在运行"
        systemctl status "$SERVICE_NAME" --no-pager --lines=10
    else
        print_warn "❌ 未运行"
    fi
}

view_log() {
    print_title ">>> 实时查看 Palworld 完整日志（Ctrl+C 退出）"
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        print_warn "服务器当前未运行，仍会显示历史日志"
    fi
    journalctl -u "$SERVICE_NAME" -f
}

# 以 steam 用户身份执行 steamcmd（真正切换用户）
run_steamcmd_as_user() {
    print_step "以 $RUN_USER 用户执行 steamcmd"

    # 执行下载/更新，若失败则重试最多3次
    local max_retries=3
    local retry_count=0
    local success=0
    while [[ $retry_count -lt $max_retries ]]; do
        ((retry_count++))
        print_info "尝试第 ${retry_count} 次下载/更新..."
        su - "$RUN_USER" -c "HOME=\"${USER_HOME}\" \"${STEAMCMD}\" +login anonymous +app_update $APP_ID validate +quit"
        if [[ $? -eq 0 ]]; then
            success=1
            break
        else
            print_warn "命令执行失败，等待5秒后重试..."
            sleep 5
        fi
    done

    if [[ $success -eq 0 ]]; then
        print_error "多次尝试后仍然失败，请检查网络或手动排查。"
        return 1
    fi
    return 0
}

download_server() {
    print_title ">>> 下载服务端"
    install_dependencies

    run_steamcmd_as_user
    if [[ $? -ne 0 ]]; then
        print_error "下载失败，请检查后重试"
        return 1
    fi

    ensure_ownership
    generate_systemd_service

    # 修复 steamclient.so（由steam用户创建，无需额外复制，但若缺失则复制）
    mkdir -p "${USER_HOME}/.steam/sdk64"
    if [[ -f "${STEAMCMD_DIR}/linux64/steamclient.so" ]]; then
        cp "${STEAMCMD_DIR}/linux64/steamclient.so" "${USER_HOME}/.steam/sdk64/"
        chown -R "$RUN_USER":"$RUN_USER" "${USER_HOME}/.steam"
    fi

    print_info "✅ 下载完成，可使用选项 1 启动"
}

update_server() {
    print_title ">>> 更新服务器"
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true

    run_steamcmd_as_user
    if [[ $? -ne 0 ]]; then
        print_error "更新失败"
        return 1
    fi

    ensure_ownership
    print_info "✅ 更新完成"
}

# ------------------------- 定时重启管理 -------------------------
schedule_restart() {
    print_title ">>> 定时重启Pal服务端"
    
    CRON_COMMENT="# Palworld Auto-Restart"
    CRON_CMD="/bin/systemctl restart ${SERVICE_NAME}"
    
    current_cron=$(crontab -l 2>/dev/null | grep -v "${CRON_COMMENT}")
    
    while true; do
        clear
        print_title "=== 定时重启设置 ==="
        echo "1) 每天06:00重启服务器"
        echo "2) 每天22:00重启服务器"
        echo "3) 移除重启任务"
        echo "0) 返回主菜单"
        echo "======================"
        echo -n "请选择: "
        read -r rc
        
        case $rc in
            1)
                new_cron="${current_cron}\n0 6 * * * ${CRON_CMD} ${CRON_COMMENT}"
                echo -e "${new_cron}" | crontab -
                print_info "✅ 已设置每天06:00自动重启"
                read -p "按回车继续..."
                ;;
            2)
                new_cron="${current_cron}\n0 22 * * * ${CRON_CMD} ${CRON_COMMENT}"
                echo -e "${new_cron}" | crontab -
                print_info "✅ 已设置每天22:00自动重启"
                read -p "按回车继续..."
                ;;
            3)
                echo -e "${current_cron}" | crontab -
                print_info "✅ 已移除定时重启任务"
                read -p "按回车继续..."
                ;;
            0)
                return
                ;;
            *)
                print_error "无效选项"
                read -p "按回车继续..."
                ;;
        esac
    done
}

set_swap() {
    SWAPFILE=/swap.img
    SWAPSIZE=4G

    if [ -b /dev/dm-1 ] || [ -f $SWAPFILE ]; then
        print_info "检测到已有 swap 设备 (/dev/dm-1) 或 swap 文件 ($SWAPFILE)，跳过创建步骤"
    else
        print_info "未检测到 swap 设备或文件，正在创建 swap 文件..."
        sudo fallocate -l $SWAPSIZE $SWAPFILE
        sudo chmod 600 $SWAPFILE
        sudo mkswap $SWAPFILE
        sudo swapon $SWAPFILE
        print_info "交换文件创建并启用成功"

        if ! grep -q "$SWAPFILE" /etc/fstab; then
            print_info "将交换文件添加到 /etc/fstab"
            echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab
            print_info "交换文件已添加到开机启动"
        else
            print_info "交换文件已在 /etc/fstab 中，跳过添加步骤"
        fi
    fi

    sysctl -w vm.swappiness=20
    sysctl -w vm.min_free_kbytes=100000
    echo -e 'vm.swappiness = 20\nvm.min_free_kbytes = 100000\n' >/etc/sysctl.d/dmp_swap.conf

    print_info "系统 swap 设置成功"
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
    print_info "Ubuntu 自动更新已禁用。"
}

# ------------------------- RCON 配置 -------------------------
RCON_HOST="127.0.0.1"
RCON_PORT="25575"

rcon_exec() {
    local pass="$1"
    shift
    local cmd="$*"
    rcon -a "${RCON_HOST}:${RCON_PORT}" -p "$pass" "$cmd"
}

rcon_menu() {
    ensure_rcon || return 1
    read -s -p "请输入 RCON 密码: " rcon_pass
    echo
    while true; do
        clear
        print_title "=== RCON 远程指令 ==="
        echo "1) 广播消息 (Broadcast)"
        echo "2) 保存世界 (Save)"
        echo "3) 踢出玩家 (Kick)"
        echo "4) 关闭服务器 (Shutdown)"
        echo "5) 显示在线玩家 (ShowPlayers)"
        echo "6) 封禁玩家 (Ban)"
        echo "7) 解封玩家 (Unban)"
        echo "8) 显示封禁列表 (ShowBans)"
        echo "9) 传送玩家到自己 (TeleportToMe)"
        echo "10) 传送到玩家位置 (TeleportToPlayer)"
        echo "11) 传送至坐标 (Teleport)"
        echo "12) 设置时间 (SetTime)"
        echo "13) 立即退出 (DoExit)"
        echo "14) 服务器信息 (Info)"
        echo "15) 自定义命令"
        echo "0) 返回主菜单"
        echo "======================="
        echo -n "请选择: "
        read -r rc

        case $rc in
            1)
                read -p "输入广播内容: " msg
                rcon_exec "$rcon_pass" "Broadcast $msg"
                ;;
            2)
                rcon_exec "$rcon_pass" "Save"
                print_info "世界已保存"
                ;;
            3)
                read -p "输入玩家名或 SteamID: " name
                read -p "输入理由(可选，直接回车跳过): " reason
                if [[ -n "$reason" ]]; then
                    rcon_exec "$rcon_pass" "Kick $name $reason"
                else
                    rcon_exec "$rcon_pass" "Kick $name"
                fi
                ;;
            4)
                read -p "关闭倒计时(秒): " t
                read -p "关闭原因: " reason
                rcon_exec "$rcon_pass" "Shutdown $t $reason"
                ;;
            5)
                print_info "在线玩家列表："
                rcon_exec "$rcon_pass" "ShowPlayers"
                ;;
            6)
                read -p "输入玩家名或 SteamID: " name
                read -p "输入理由(可选): " reason
                if [[ -n "$reason" ]]; then
                    rcon_exec "$rcon_pass" "Ban $name $reason"
                else
                    rcon_exec "$rcon_pass" "Ban $name"
                fi
                ;;
            7)
                read -p "输入要解封的玩家名或 SteamID: " name
                rcon_exec "$rcon_pass" "Unban $name"
                ;;
            8)
                print_info "封禁列表："
                rcon_exec "$rcon_pass" "ShowBans"
                ;;
            9)
                read -p "输入玩家名或 SteamID (将传送该玩家到你身边): " player
                rcon_exec "$rcon_pass" "TeleportToMe $player"
                ;;
            10)
                read -p "输入你的玩家名或 SteamID: " yourself
                read -p "输入目标玩家名或 SteamID: " target
                rcon_exec "$rcon_pass" "TeleportToPlayer $yourself $target"
                ;;
            11)
                read -p "输入X坐标: " x
                read -p "输入Y坐标: " y
                read -p "输入Z坐标: " z
                rcon_exec "$rcon_pass" "Teleport $x $y $z"
                ;;
            12)
                read -p "输入时间(0-24, 如 12 表示中午): " hour
                rcon_exec "$rcon_pass" "SetTime $hour"
                ;;
            13)
                rcon_exec "$rcon_pass" "DoExit"
                print_warn "服务器即将退出"
                ;;
            14)
                print_info "服务器信息"
                rcon_exec "$rcon_pass" "Info"
                ;;
            15)
                read -p "输入完整 RCON 命令: " custom
                rcon_exec "$rcon_pass" "$custom"
                ;;
            0)
                return
                ;;
            *)
                print_error "无效选项"
                ;;
        esac
        read -p "按回车继续..."
    done
}

# ------------------------- 菜单 -------------------------
show_menu() {
    clear
    echo "===================================="
    print_title "Palworld 服务端管理1.0.5"
    echo "===================================="
    echo "1) 启动服务器"
    echo "2) 更新服务器"
    echo "3) 查看状态"
    echo "4) 停止服务器"
    echo "5) 查看服务器日志"
    echo "6) RCON 远程指令"
    echo "7) 下载服务端"
    echo "8) 设定定时重启"
    echo "9) 开启虚拟内存"
    echo "10) 禁用ubuntu自动更新"
    echo "0) 退出"
    echo "===================================="
    echo -n "请选择: "
}

main() {
    check_root
    detect_run_user

    while true; do
        show_menu
        read -r choice
        case $choice in
            1) start_server ;;
            2) update_server ;;
            3) status_server ;;
            4) stop_server ;;
            5) view_log ;;
            6) rcon_menu ;;
            7) download_server ;;
            8) schedule_restart ;;
            9) set_swap ;;
            10) disable_ubuntu_autoupdate ;;
            0) exit 0 ;;
            *) print_error "无效选项" ;;
        esac
        read -p "按回车继续..."
    done
}

main