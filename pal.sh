#!/bin/bash
# ============================================================
# 幻兽帕鲁 (Palworld) 服务端管理脚本 for Ubuntu 24.04 LTS
# 功能：启动、更新、查看状态、关闭、查看聊天日志、下载程序
# 使用 screen 管理后台会话，会话名：pal
# 特别注意：服务端禁止 root 运行，脚本会自动切换至普通用户
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
PAL_DIR="/palworld"                      # 服务端安装目录（保留在根目录，可根据需要调整）
SCREEN_NAME="pal"
SERVER_SCRIPT="./PalServer.sh"
SERVER_ARGS="-useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS"
APP_ID=2394010

# steamcmd 相关变量将在 detect_run_user 中动态设置
STEAMCMD_DIR=""      # 将在 detect_run_user 中赋值为用户家目录下的 steamcmd
STEAMCMD=""          # 将在 detect_run_user 中赋值为 $STEAMCMD_DIR/steamcmd.sh

# ------------------------- 用户切换逻辑 -------------------------
detect_run_user() {
    if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
        RUN_USER="$SUDO_USER"
    elif [[ "$USER" != "root" ]]; then
        RUN_USER="$USER"
    else
        print_warn "当前为 root 用户，Palworld 不允许 root 运行。"
        print_info "请输入一个普通用户名（将用于运行服务端，若不存在则创建）："
        read -p "用户名 [palworld]: " input_user
        RUN_USER="${input_user:-palworld}"
        if ! id "$RUN_USER" &>/dev/null; then
            print_info "用户 $RUN_USER 不存在，正在创建..."
            useradd -m -s /bin/bash "$RUN_USER"
            if [[ $? -ne 0 ]]; then
                print_error "创建用户失败，请手动创建或重新运行脚本。"
                exit 1
            fi
            print_info "用户 $RUN_USER 已创建。"
        fi
    fi
    export RUN_USER
    print_info "将使用用户 '$RUN_USER' 运行服务端相关操作。"

    # ---------- 修改点：根据 RUN_USER 的家目录设置 steamcmd 路径 ----------
    USER_HOME=$(sudo -u "$RUN_USER" bash -c 'echo $HOME')
    if [[ -z "$USER_HOME" ]]; then
        print_error "无法获取用户 $RUN_USER 的家目录"
        exit 1
    fi
    STEAMCMD_DIR="${USER_HOME}/steamcmd"
    STEAMCMD="${STEAMCMD_DIR}/steamcmd.sh"
    export STEAMCMD_DIR STEAMCMD
    print_info "steamcmd 将安装到: $STEAMCMD_DIR"
}

ensure_ownership() {
    if [[ -d "$PAL_DIR" ]]; then
        chown -R "$RUN_USER":"$RUN_USER" "$PAL_DIR" 2>/dev/null
    fi
}

# ------------------------- 辅助函数 -------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用 root 或 sudo 运行此脚本。"
        exit 1
    fi
}

install_dependencies() {
    print_step "检查并安装依赖 (screen)..."
    apt update -qq
    if ! command -v screen &> /dev/null; then
        print_info "安装 screen..."
        apt install -y screen
    else
        print_info "screen 已安装"
    fi

    # 检查 steamcmd 是否已存在（使用动态设置的 STEAMCMD）
    if [[ -f "$STEAMCMD" ]]; then
        print_info "steamcmd 已存在于 $STEAMCMD"
    else
        print_info "steamcmd 未找到，请选择下载源："
        echo "1) https://github.dpik.top/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        echo "2) https://gh.927223.xyz/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        echo "3) https://cdn.gh-proxy.org/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        echo "4) https://edgeone.gh-proxy.org/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        echo "5) https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz (官方源)"
        read -p "请输入数字 [1-5]: " src_choice
        case $src_choice in
            1) DOWNLOAD_URL="https://github.dpik.top/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz" ;;
            2) DOWNLOAD_URL="https://gh.927223.xyz/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz" ;;
            3) DOWNLOAD_URL="https://cdn.gh-proxy.org/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz" ;;
            4) DOWNLOAD_URL="https://edgeone.gh-proxy.org/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz" ;;
            5) DOWNLOAD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" ;;
            *) print_error "无效选择，使用官方源"; DOWNLOAD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" ;;
        esac

        print_info "下载 steamcmd 从 $DOWNLOAD_URL"
        TMP_DIR=$(mktemp -d)
        cd "$TMP_DIR" || return 1
        wget -q --show-progress "$DOWNLOAD_URL" -O steamcmd_linux.tar.gz
        if [[ $? -ne 0 ]]; then
            print_error "下载失败，请检查网络"
            return 1
        fi

        # 创建目标目录并解压（以 RUN_USER 身份，确保权限正确）
        sudo -u "$RUN_USER" mkdir -p "$STEAMCMD_DIR"
        sudo -u "$RUN_USER" tar -xzf steamcmd_linux.tar.gz -C "$STEAMCMD_DIR"
        if [[ $? -ne 0 ]]; then
            print_error "解压失败"
            return 1
        fi
        cd - >/dev/null
        rm -rf "$TMP_DIR"
        print_info "steamcmd 安装到 $STEAMCMD_DIR"
    fi

    # 确保 steamclient.so 复制到用户目录 ~/.steam/sdk64/
    print_step "设置 steamclient.so 到用户目录..."
    SOURCE_SO="${STEAMCMD_DIR}/linux64/steamclient.so"
    if [[ ! -f "$SOURCE_SO" ]]; then
        print_error "未找到 $SOURCE_SO，请确保 steamcmd 正确安装"
        return 1
    fi
    USER_HOME=$(sudo -u "$RUN_USER" bash -c 'echo $HOME')
    SDK_DIR="${USER_HOME}/.steam/sdk64"
    sudo -u "$RUN_USER" mkdir -p "$SDK_DIR"
    sudo -u "$RUN_USER" cp "$SOURCE_SO" "$SDK_DIR/"
    if [[ $? -eq 0 ]]; then
        print_info "steamclient.so 已复制到 $SDK_DIR"
    else
        print_error "复制 steamclient.so 失败"
        return 1
    fi
}

check_pal_dir() {
    if [[ ! -d "$PAL_DIR" ]]; then
        print_error "服务端目录不存在: $PAL_DIR"
        print_info "请先执行选项 6 下载程序"
        return 1
    fi
    if [[ ! -f "${PAL_DIR}/${SERVER_SCRIPT}" ]]; then
        print_error "服务端启动脚本不存在: ${PAL_DIR}/${SERVER_SCRIPT}"
        print_info "请先执行选项 6 下载程序"
        return 1
    fi
    return 0
}

is_screen_running() {
    sudo -u "$RUN_USER" screen -list | grep -q "\.${SCREEN_NAME}\s"
}

get_server_pid() {
    pid=$(sudo -u "$RUN_USER" screen -S "$SCREEN_NAME" -Q stuff "ps aux | grep PalServer | grep -v grep | awk '{print \$2}'" 2>/dev/null | tail -1)
    echo "$pid"
}

# ------------------------- 菜单功能实现 -------------------------

# 1. 启动服务器
start_server() {
    print_title ">>> 启动 Palworld 服务器"
    if ! check_pal_dir; then
        return 1
    fi
    ensure_ownership

    if is_screen_running; then
        print_warn "服务器已经在运行 (screen 会话存在)"
        return 0
    fi

    print_info "正在以用户 $RUN_USER 后台启动服务器 (screen 会话: $SCREEN_NAME)..."
    cd "$PAL_DIR" || return 1

    sudo -u "$RUN_USER" screen -dmS "$SCREEN_NAME" bash -c "chmod +x ${SERVER_SCRIPT} && ${SERVER_SCRIPT} ${SERVER_ARGS}; exec bash"
    if [[ $? -eq 0 ]]; then
        print_info "服务器启动成功，screen 会话已创建 (用户: $RUN_USER)"
        print_info "使用 'sudo -u $RUN_USER screen -r $SCREEN_NAME' 可查看控制台输出"
    else
        print_error "启动失败，请检查日志"
        return 1
    fi
}

# 2. 更新服务器
update_server() {
    print_title ">>> 更新 Palworld 服务器"
    # 修改点：检查 steamcmd 是否可执行（使用变量）
    if [[ ! -f "$STEAMCMD" ]]; then
        print_error "steamcmd 未安装，请先执行选项 6 下载程序（会自动安装 steamcmd）"
        return 1
    fi

    if [[ ! -d "$PAL_DIR" ]]; then
        mkdir -p "$PAL_DIR"
        chown "$RUN_USER":"$RUN_USER" "$PAL_DIR"
    fi
    ensure_ownership

    print_info "开始通过 SteamCMD 更新服务端 (AppID: $APP_ID)..."
    sudo -u "$RUN_USER" "$STEAMCMD" +force_install_dir "$PAL_DIR" +login anonymous +app_update "$APP_ID" validate +quit
    if [[ $? -eq 0 ]]; then
        print_info "更新完成！"
        chmod +x "${PAL_DIR}/${SERVER_SCRIPT}" 2>/dev/null
        ensure_ownership
        if is_screen_running; then
            print_warn "服务器正在运行，建议重启使更新生效"
        fi
    else
        print_error "更新失败，请检查网络或 SteamCMD 输出"
        return 1
    fi
}

# 3. 查看服务器状态
status_server() {
    print_title ">>> 查看 Palworld 服务器状态"
    if is_screen_running; then
        print_info "✅ 服务器正在运行 (screen 会话: $SCREEN_NAME, 用户: $RUN_USER)"
        pid=$(get_server_pid)
        if [[ -n "$pid" ]]; then
            print_info "进程 PID: $pid"
        else
            print_warn "未能获取进程 PID，但 screen 会话存在"
        fi
        sudo -u "$RUN_USER" screen -list | grep "\.${SCREEN_NAME}\s"
    else
        print_warn "❌ 服务器未运行 (未找到 screen 会话)"
    fi
}

# 4. 关闭服务器
stop_server() {
    print_title ">>> 关闭 Palworld 服务器"
    if ! is_screen_running; then
        print_warn "服务器未运行 (screen 会话不存在)"
        return 0
    fi

    print_info "正在关闭 screen 会话 $SCREEN_NAME ..."
    sudo -u "$RUN_USER" screen -S "$SCREEN_NAME" -X stuff $'\003'
    sleep 2
    if is_screen_running; then
        print_warn "优雅关闭未响应，尝试强制终止 screen 会话"
        sudo -u "$RUN_USER" screen -S "$SCREEN_NAME" -X quit
        sleep 1
    fi

    if ! is_screen_running; then
        print_info "服务器已关闭"
    else
        print_error "关闭失败，请手动处理 screen 会话"
        return 1
    fi
}

# 5. 查看聊天日志
view_chat_log() {
    print_title ">>> 查看 Palworld 聊天日志"
    if ! check_pal_dir; then
        return 1
    fi
    LOG_DIR="${PAL_DIR}/Pal/Saved/Logs"
    if [[ ! -d "$LOG_DIR" ]]; then
        print_warn "日志目录不存在: $LOG_DIR"
        print_info "可能服务端尚未运行或未产生日志"
        return 0
    fi

    log_files=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -5)
    if [[ -z "$log_files" ]]; then
        print_warn "未找到日志文件"
        return 0
    fi

    print_info "找到以下日志文件（最近5个）："
    echo "$log_files" | nl
    print_info "正在搜索聊天记录（关键词：Chat, 聊天, [Chat]）..."
    echo "--------------------- 聊天记录 (最近) ---------------------"
    find "$LOG_DIR" -name "*.log" -exec grep -i -E "chat|聊天" {} \; 2>/dev/null | tail -20
    if [[ $? -ne 0 ]]; then
        print_warn "未找到任何聊天记录"
    else
        echo "--------------------------------------------------------"
    fi
}

# 6. 下载程序（初始安装）
download_server() {
    print_title ">>> 下载 Palworld 服务端程序"

    # 安装系统依赖并安装 steamcmd（此时 RUN_USER 已确定）
    install_dependencies

    if [[ ! -f "$STEAMCMD" ]]; then
        print_error "steamcmd 安装失败，请检查"
        return 1
    fi

    if [[ -d "$PAL_DIR" ]]; then
        print_warn "目录 $PAL_DIR 已存在"
        read -p "是否覆盖或重新下载？(y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "取消下载"
            return 0
        fi
    else
        mkdir -p "$PAL_DIR"
    fi
    chown "$RUN_USER":"$RUN_USER" "$PAL_DIR"

    print_info "开始下载/安装服务端 (AppID: $APP_ID) 到 $PAL_DIR"
    print_info "这个过程可能需要一些时间，请耐心等待..."
    sudo -u "$RUN_USER" "$STEAMCMD" +force_install_dir "$PAL_DIR" +login anonymous +app_update "$APP_ID" validate +quit
    if [[ $? -eq 0 ]]; then
        print_info "下载/安装完成！"
        chmod +x "${PAL_DIR}/${SERVER_SCRIPT}" 2>/dev/null
        ensure_ownership
        print_info "服务端位于: $PAL_DIR"
        print_info "现在可以使用选项 1 启动服务器"
    else
        print_error "下载/安装失败，请检查网络或 SteamCMD 输出"
        return 1
    fi
}

# ------------------------- 主菜单 -------------------------
show_menu() {
    clear
    echo "=============================================="
    print_title "幻兽帕鲁 (Palworld) 服务端管理1.0.0"
    echo "=============================================="
    echo -e "${COLOR_CYAN} 1.${COLOR_RESET} 启动服务器"
    echo -e "${COLOR_CYAN} 2.${COLOR_RESET} 更新服务器"
    echo -e "${COLOR_CYAN} 3.${COLOR_RESET} 查看服务器状态"
    echo -e "${COLOR_CYAN} 4.${COLOR_RESET} 关闭服务器"
    echo -e "${COLOR_CYAN} 5.${COLOR_RESET} 查看聊天日志"
    echo -e "${COLOR_CYAN} 6.${COLOR_RESET} 下载服务端程序"
    echo -e "${COLOR_CYAN} 0.${COLOR_RESET} 退出"
    echo "=============================================="
    echo -n "请输入选项 [0-6]: "
}

# ------------------------- 主程序入口 -------------------------
main() {
    check_root
    detect_run_user
    
    while true; do
        show_menu
        read choice
        case $choice in
            1) start_server; read -p "按 Enter 继续..." ;;
            2) update_server; read -p "按 Enter 继续..." ;;
            3) status_server; read -p "按 Enter 继续..." ;;
            4) stop_server; read -p "按 Enter 继续..." ;;
            5) view_chat_log; read -p "按 Enter 继续..." ;;
            6) download_server; read -p "按 Enter 继续..." ;;
            0) print_info "退出脚本"; exit 0 ;;
            *) print_error "无效选项，请重新输入"; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi