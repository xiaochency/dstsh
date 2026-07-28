#!/bin/bash

###########################################
# 用户自定义设置请修改下方变量，其他变量请不要修改 #
###########################################

# --------------- ↓可修改↓ --------------- #
PORT=""  # 改为空值，将在启动时询问
CONFIG_DIR="./data"
LEVEL="info"
PORT_FILE="${CONFIG_DIR}/dmp_port.env"  # 新增：端口配置文件
# --------------- ↑可修改↑ --------------- #

###########################################
#     下方变量请不要修改，否则可能会出现异常     #
###########################################

USER=$(whoami)
ExeFile="$HOME/dmp"
install_dir="$HOME/dst"
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
    echo "   ║          饥荒管理平台 (DMP) 一体化管理脚本 v1.0.4        ║"
    echo "   ║                 Don't Starve Together                    ║"
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

check_curl() {
    print_info "检查 curl 命令..."
    if ! curl --version >/dev/null 2>&1; then
        OS=$(grep -P "^ID=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g")
        if [[ ${OS} == "ubuntu" ]]; then
            apt install -y curl
        else
            if grep -P "^ID_LIKE=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g" | grep rhel; then
                yum install -y curl
            fi
        fi
    fi
}

check_strings() {
    print_info "检查 strings 命令..."
    if ! strings --version >/dev/null 2>&1; then
        OS=$(grep -P "^ID=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g")
        if [[ ${OS} == "ubuntu" ]]; then
            apt install -y binutils
        else
            if grep -P "^ID_LIKE=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g" | grep rhel; then
                yum install -y binutils
            fi
        fi
    fi
}

check_glibc() {
    check_strings
    print_info "检查 GLIBC 版本..."
    OS=$(grep -P "^ID=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g")
    if [[ ${OS} == "ubuntu" ]]; then
        if ! strings /lib/x86_64-linux-gnu/libc.so.6 | grep GLIBC_2.34 >/dev/null 2>&1; then
            apt update
            apt install -y libc6
        fi
    else
        print_warning "非 Ubuntu 系统，如 GLIBC 小于 2.34，请手动升级"
    fi
}

check_sqlite3() {
    if ! command -v sqlite3 &> /dev/null; then
        print_warning "检测到未安装 sqlite3，正在安装..."
        OS=$(grep -P "^ID=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g")
        case $OS in
            ubuntu|debian)
                if apt-get update && apt-get install -y sqlite3; then
                    print_success "sqlite3 安装成功"
                else
                    print_error "sqlite3 安装失败，请手动安装"
                    return 1
                fi
                ;;
            centos|rhel|fedora|rocky|alma)
                if yum install -y sqlite3; then
                    print_success "sqlite3 安装成功"
                else
                    print_error "sqlite3 安装失败，请手动安装"
                    return 1
                fi
                ;;
            alpine)
                if apk add sqlite; then
                    print_success "sqlite3 安装成功"
                else
                    print_error "sqlite3 安装失败，请手动安装"
                    return 1
                fi
                ;;
            *)
                print_error "不支持的操作系统: $OS，请手动安装 sqlite3"
                print_warning "安装命令参考:"
                echo "  Ubuntu/Debian: sudo apt-get install sqlite3"
                echo "  CentOS/RHEL: sudo yum install sqlite3"
                echo "  Alpine: sudo apk add sqlite"
                return 1
                ;;
        esac
    fi
    return 0
}

download() {
    local url="$1"
    local tries="$2"
    local timeout="$3"

    # 使用 curl 下载，参数说明：
    # -L              跟随重定向
    # --progress-bar  显示进度条
    # --retry         重试次数（默认3次，若未传参）
    # --connect-timeout 连接超时（默认10秒，若未传参）
    # -O              保存为远程文件名
    curl -L --progress-bar \
         --retry "${tries:-3}" \
         --connect-timeout "${timeout:-10}" \
         -O "$url"
    return $?
}

install_dmp() {
    check_curl

    local dmp_urls=(
        "https://github.dpik.top/github.com/miracleEverywhere/dst-management-platform-api/releases/download/v3.1.6/dmp.tgz"
        "https://cdn.gh-proxy.org/github.com/miracleEverywhere/dst-management-platform-api/releases/download/v3.1.6/dmp.tgz"
        "https://gh.927223.xyz/github.com/miracleEverywhere/dst-management-platform-api/releases/download/v3.1.6/dmp.tgz"
        "https://edgeone.gh-proxy.org/github.com/miracleEverywhere/dst-management-platform-api/releases/download/v3.1.6/dmp.tgz"
        "https://ghfast.top/github.com/miracleEverywhere/dst-management-platform-api/releases/download/v3.1.6/dmp.tgz"
    )

    echo "请选择下载镜像源："
    for i in "${!dmp_urls[@]}"; do
        echo "$((i+1))) ${dmp_urls[$i]}"
    done
    echo "0) 输入自定义 URL"
    read -p "请输入选项 [0-${#dmp_urls[@]}]: " choice

    local selected_url=""
    if [[ $choice -ge 1 && $choice -le ${#dmp_urls[@]} ]]; then
        selected_url="${dmp_urls[$((choice-1))]}"
    elif [[ $choice -eq 0 ]]; then
        read -p "请输入自定义下载 URL: " selected_url
    else
        print_error "无效选项"
        return 1
    fi

    print_info "正在从 $selected_url 下载 dmp.tgz..."
    # 调用 download 函数，重试 10 次，超时 10 秒
    if download "$selected_url" 10 10; then
        if tar -tzf dmp.tgz >/dev/null 2>&1; then
            tar zxvf dmp.tgz >/dev/null
            rm -f dmp.tgz
            chmod +x "$ExeFile"
            print_success "安装 dmp 成功"
        else
            print_error "压缩包损坏"
            return 1
        fi
    else
        print_error "下载 dmp 失败"
        return 1
    fi
}

check_dmp() {
    sleep 1
    if pgrep dmp >/dev/null; then
        print_success "启动成功"
    else
        print_error "启动失败"
        exit 1
    fi
}

# 新增：加载端口配置
load_port_config() {
    if [[ -f "$PORT_FILE" ]]; then
        PORT=$(cat "$PORT_FILE")
        print_info "已从配置文件加载端口: $PORT"
    fi
}

# 新增：保存端口配置
save_port_config() {
    mkdir -p "$CONFIG_DIR"
    echo "$PORT" > "$PORT_FILE"
    print_success "端口已保存到配置文件: $PORT_FILE"
}

# 修改：start_dmp函数，添加端口输入逻辑
start_dmp() {
    # 首先尝试加载已保存的端口配置
    load_port_config
    
    # 如果PORT为空，则提示用户输入
    while [[ -z "$PORT" ]]; do
        read -p "请输入已开放的TCP端口 [默认: 80]: " input_port
        PORT=${input_port:-80}
        
        # 验证端口是否为数字且在有效范围内
        if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
            print_error "端口必须是1-65535之间的数字"
            PORT=""
        fi
    done
    
    # 检查端口是否被占用
    port=$(ss -ltnp | awk -v port=${PORT} '$4 ~ ":"port"$" {print $4}')
    if [ -n "$port" ]; then
        print_error "端口 $PORT 已被占用: $port"
        echo "请修改端口后重新运行"
        exit 1
    fi

    check_glibc

    if [ -e "$ExeFile" ]; then
        nohup "$ExeFile" -bind ${PORT} -dbpath ${CONFIG_DIR} -level ${LEVEL} >/dev/null 2>&1 &
    else
        install_dmp
        nohup "$ExeFile" -bind ${PORT} -dbpath ${CONFIG_DIR} -level ${LEVEL} >/dev/null 2>&1 &
    fi
    
    # 保存端口配置
    save_port_config
}

stop_dmp() {
    pkill -9 dmp
    print_success "关闭成功"
    sleep 1
}

clear_dmp() {
    print_info "正在执行清理"
    rm -f dmp dmp.tgz logs/*
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
    echo -e 'vm.swappiness = 20\nvm.min_free_kbytes = 100000\n' >/etc/sysctl.d/dmp_swap.conf

    print_success "系统 swap 设置成功"
}

enable_auto_start() {
    CRON_JOB="@reboot /bin/bash -c 'source /etc/profile && cd /root && echo 1 | /root/run.sh'"
    if crontab -l 2>/dev/null | grep -Fq "$CRON_JOB"; then
        print_warning "已发现开机自启配置，无需重复添加"
    else
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        print_success "已成功设置开机自启"
    fi
}

disable_auto_start() {
    CRON_JOB="@reboot /bin/bash -c 'source /etc/profile && cd /root && echo 1 | /root/run.sh'"
    if crontab -l 2>/dev/null | grep -Fq "$CRON_JOB"; then
        # 移除包含该任务的行
        crontab -l 2>/dev/null | grep -vF "$CRON_JOB" | crontab -
        print_success "已成功关闭开机自启"
    else
        print_warning "未发现开机自启配置，无需关闭"
    fi
}

auto_start_dmp() {
    while true; do
        clear
        print_header
        print_section "DMP 开机自启管理"
        echo -e "${CYAN}  1) 开启 DMP 开机自启${NC}"
        echo -e "${CYAN}  2) 关闭 DMP 开机自启${NC}"
        echo -e "${CYAN}  0) 返回主菜单${NC}"
        print_divider
        read -p "请选择 [0-2]: " choice
        case $choice in
            1)
                enable_auto_start
                pause_and_return
                ;;
            2)
                disable_auto_start
                pause_and_return
                ;;
            0)
                return 0
                ;;
            *)
                print_error "无效选择"
                sleep 1
                ;;
        esac
    done
}

list_users() {
    if [[ ! -f "${CONFIG_DIR}/dmp.db" ]]; then
        print_error "数据库文件 ${CONFIG_DIR}/dmp.db 不存在！"
        return 1
    fi

    print_info "当前平台注册的用户名如下："
    echo "--------------------------------"
    sqlite3 "${CONFIG_DIR}/dmp.db" "SELECT username FROM users;" | while read -r user; do
        echo -e "${GREEN}  - $user${NC}"
    done
    [[ $? -ne 0 ]] && print_warning "（暂无用户或查询失败）"
    echo "--------------------------------"
}

change_password() {
    if [[ ! -f "${CONFIG_DIR}/dmp.db" ]]; then
        print_error "数据库文件 ${CONFIG_DIR}/dmp.db 不存在！"
        return 1
    fi

    print_header
    print_section "修改用户密码"
    read -r -p "请输入要修改的用户名: " USERNAME

    exists=$(sqlite3 "${CONFIG_DIR}/dmp.db" "SELECT COUNT(*) FROM users WHERE username='$USERNAME';")
    if [[ "$exists" -eq 0 ]]; then
        print_error "用户 '$USERNAME' 不存在！"
        return 1
    fi

    read -s -r -p "请输入新密码: " PASSWORD
    echo
    read -s -r -p "请再次输入新密码: " PASSWORD2
    echo

    if [[ "$PASSWORD" != "$PASSWORD2" ]]; then
        print_error "两次输入的密码不一致！"
        return 1
    fi

    if [[ -z "$PASSWORD" ]]; then
        print_error "密码不能为空！"
        return 1
    fi

    db_password=$(echo -n "$PASSWORD" | sha512sum | awk '{print $1}')
    sqlite3 "${CONFIG_DIR}/dmp.db" "UPDATE users SET password='$db_password' WHERE username='$USERNAME';"

    if [[ $? -eq 0 ]]; then
        print_success "用户 '$USERNAME' 的密码修改成功！"
    else
        print_error "密码修改失败，请检查数据库权限或 SQLite 是否正常"
    fi
}

# 新增：修改端口函数
change_port() {
    print_header
    print_section "修改 DMP 服务端口"
    
    # 显示当前端口
    load_port_config
    if [[ -n "$PORT" ]]; then
        print_info "当前端口: $PORT"
    else
        print_warning "当前未设置端口"
    fi
    
    # 获取新端口
    while true; do
        read -p "请输入新的TCP端口 [1-65535，默认: 80]: " new_port
        new_port=${new_port:-80}
        
        # 验证端口是否为数字且在有效范围内
        if ! [[ "$new_port" =~ ^[0-9]+$ ]] || (( new_port < 1 || new_port > 65535 )); then
            print_error "端口必须是1-65535之间的数字"
            continue
        fi
        
        # 检查端口是否被占用
        port_check=$(ss -ltnp | awk -v port=${new_port} '$4 ~ ":"port"$" {print $4}')
        if [ -n "$port_check" ]; then
            print_warning "端口 $new_port 已被占用: $port_check"
            read -p "是否仍要使用此端口？(y/n): " force_use
            if [[ "$force_use" != "y" && "$force_use" != "Y" ]]; then
                continue
            fi
        fi
        
        break
    done
    
    # 更新端口
    PORT=$new_port
    save_port_config
    
    print_success "端口已修改为: $PORT"
    print_warning "修改后需要重启 DMP 服务才能生效！"
    pause_and_return
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
        print_error "无效选项"
        return 1
    fi

    print_info "正在从 $selected_url 下载 steamcmd_linux.tar.gz..."
    # 调用 download 函数：重试 10 次，超时 10 秒
    if download "$selected_url" 10 10; then
        # 检查文件大小（至少 1MB）
        file_size=$(stat -c%s "steamcmd_linux.tar.gz" 2>/dev/null || stat -f%z "steamcmd_linux.tar.gz" 2>/dev/null || echo "0")
        if [ "$file_size" -lt 1000000 ]; then
            print_warning "下载的文件大小异常 ($file_size 字节)，可能损坏"
            rm -f steamcmd_linux.tar.gz
            print_error "下载的文件可能损坏，请重试"
            return 1
        fi
        print_success "steamcmd 下载成功，文件大小验证通过"
        return 0
    else
        print_error "下载 steamcmd 失败"
        return 1
    fi
}

install_dst() {
    read -p "您确定要安装 Don't Starve Together 服务器吗？(y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_warning "安装已取消."
        return
    fi

    print_info "正在安装 Don't Starve Together 服务器..."
    dpkg --add-architecture i386
    apt-get update
    apt-get install -y screen unzip lib32gcc-s1
    apt-get install -y libcurl4-gnutls-dev:i386
    apt-get install -y libcurl4-gnutls-dev
    print_success "环境依赖安装完毕"

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
        if [ -d "$HOME/dst/bin/" ]; then
            cd "$HOME/dst/bin/" && {
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
        cp "$HOME/steamcmd/linux32/libstdc++.so.6" "$HOME/dst/bin/lib32/" 2>/dev/null
        cp "$HOME/steamcmd/linux32/steamclient.so" "$HOME/dst/bin/lib32/" 2>/dev/null
        cp "$HOME/steamcmd/linux64/steamclient.so" "$HOME/dst/bin64/lib64/" 2>/dev/null
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
    cp $HOME/steamcmd/linux32/steamclient.so $HOME/dst/bin/lib32/ 2>/dev/null
    cp $HOME/steamcmd/linux64/steamclient.so $HOME/dst/bin64/lib64/ 2>/dev/null
    cp $HOME/steamcmd/linux32/libstdc++.so.6 $HOME/dst/bin/lib32/ 2>/dev/null
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

set_root_password() {
    print_info "正在设置 root 密码..."
    echo "请输入新的 root 密码："
    passwd root
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
    systemctl restart ssh
    print_success "远程 root 登录已启用，root 密码已设置。"
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
    echo -e "${GREEN}  [0]${NC}  全新安装并启动 DMP 平台"
    print_divider
    echo -e "${GREEN}  [1]${NC}  启动 DMP 平台"
    echo -e "${GREEN}  [2]${NC}  关闭 DMP 平台"
    echo -e "${GREEN}  [3]${NC}  设置 DMP 开机自启"
    print_divider
    echo -e "${GREEN}  [4]${NC}  下载 DST 服务器程序"
    echo -e "${GREEN}  [5]${NC}  更新 DST 服务器程序"
    echo -e "${GREEN}  [6]${NC}  管理 steamcmd 自动更新任务"
    print_divider
    echo -e "${GREEN}  [7]${NC}  修改 root 密码并开启远程登录"
    echo -e "${GREEN}  [8]${NC}  禁用 Ubuntu 自动更新"
    echo -e "${GREEN}  [9]${NC}  查看 DMP 所有用户名"
    print_divider
    echo -e "${GREEN}  [10]${NC} 修改 DMP 用户密码"
    echo -e "${GREEN}  [11]${NC} 设置虚拟内存 (Swap)"
    echo -e "${GREEN}  [12]${NC} 修改 DMP 服务端口"
    print_divider
    echo -e "${RED}  [q/Q]${NC} 退出脚本"
    print_divider
    echo -n -e "${CYAN}请输入选项 [0-12/q]: ${NC}"
}

# ==================== 主程序入口 ====================
cd "$HOME" || exit

if [[ "${USER}" != "root" ]]; then
    print_error "请使用 root 用户执行此脚本"
    exit 1
fi

while true; do
    show_main_menu
    read -r choice
    case $choice in
        0)
            clear_dmp
            install_dmp
            start_dmp
            check_dmp
            break
            ;;
        1)
            start_dmp
            check_dmp
            break
            ;;
        2)
            stop_dmp
            break
            ;;
        3)
            auto_start_dmp
            ;;
        4)
            install_dst
            break
            ;;
        5)
            update_dst
            break
            ;;
        6)
            manage_crontab
            ;;
        7)
            set_root_password
            break
            ;;
        8)
            disable_ubuntu_autoupdate
            break
            ;;
        9)
            check_sqlite3
            list_users
            pause_and_return
            ;;
        10)
            check_sqlite3
            change_password
            print_warning "修改后需要重启 DMP 生效！"
            pause_and_return
            ;;
        11)
            set_swap
            break
            ;;
        12)
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