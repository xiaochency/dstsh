#!/bin/bash

# ==================== 基础配置 ====================
USER=$(whoami)
HOME_DIR="$HOME"
EXE_DIR="$HOME_DIR/dstgo"
INSTALL_DIR="$HOME_DIR/dst"
STEAMCMD_DIR="$HOME_DIR/steamcmd"
SERVICE_NAME="dstgo"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# ==================== 颜色输出 ====================
echo_red() { echo -e "\033[0;31m$*\033[0m"; }
echo_green() { echo -e "\033[0;32m$*\033[0m"; }
echo_yellow() { echo -e "\033[0;33m$*\033[0m"; }
echo_cyan() { echo -e "\033[0;36m$*\033[0m"; }

# ==================== 前置检查 ====================
# 必须root运行
if [[ "${USER}" != "root" ]]; then
    echo_red "请使用root用户执行此脚本"
    exit 1
fi

# 确保curl已安装
if ! command -v curl &> /dev/null; then
    echo_cyan "正在安装curl依赖..."
    apt-get update -qq && apt-get install -y curl
fi

# ==================== 镜像源配置 ====================
MIRROR_URLS=(
    "https://github.dpik.top"
    "https://cdn.gh-proxy.org"
    "https://gh.927223.xyz"
    "https://edgeone.gh-proxy.org"
    "https://github.ikgy.top"
)
MIRROR_NAMES=(
    "镜像源1 (github.dpik.top)"
    "镜像源2 (cdn.gh-proxy.org)"
    "镜像源3 (gh.927223.xyz)"
    "镜像源4 (edgeone.gh-proxy.org)"
    "镜像源5 (github.ikgy.top)"
)

SELECTED_MIRROR_INDEX=""
SELECTED_MIRROR_URL=""

# 选择镜像源
select_mirror() {
    local total=${#MIRROR_URLS[@]}
    echo_green "================================================"
    echo_green "           请选择下载镜像源"
    echo_green "================================================"
    for ((i=0; i<total; i++)); do
        echo_cyan "$((i+1)). ${MIRROR_NAMES[i]}"
    done
    echo_cyan "0. 取消"
    echo_green "================================================"

    while true; do
        read -p "请输入选择 [0-$total]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if (( choice == 0 )); then
                SELECTED_MIRROR_INDEX=""
                SELECTED_MIRROR_URL=""
                return 1
            elif (( choice >= 1 && choice <= total )); then
                SELECTED_MIRROR_INDEX=$((choice-1))
                SELECTED_MIRROR_URL="${MIRROR_URLS[SELECTED_MIRROR_INDEX]}"
                echo_green "✅ 已选择: ${MIRROR_NAMES[SELECTED_MIRROR_INDEX]}"
                return 0
            fi
        fi
        echo_red "无效输入，请重新输入"
    done
}

# ==================== 系统功能 ====================
# 禁用Ubuntu自动更新
disable_ubuntu_autoupdate() {
    echo_cyan "正在禁用Ubuntu自动更新..."
    systemctl disable --now unattended-upgrades apt-daily.timer apt-daily-upgrade.timer

    local conf="/etc/apt/apt.conf.d/20auto-upgrades"
    cat > "$conf" << EOF
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
EOF
    echo_green "✅ Ubuntu自动更新已禁用"
}

# 设置虚拟内存
set_swap() {
    SWAPFILE=/swap.img
    SWAPSIZE=2G

    if [ -b /dev/dm-1 ] || [ -f $SWAPFILE ]; then
        echo_green "检测到已有 swap 设备 (/dev/dm-1) 或 swap 文件 ($SWAPFILE)，跳过创建步骤"
    else
        echo_cyan "未检测到 swap 设备或文件，正在创建 swap 文件..."
        sudo fallocate -l $SWAPSIZE $SWAPFILE
        sudo chmod 600 $SWAPFILE
        sudo mkswap $SWAPFILE
        sudo swapon $SWAPFILE
        echo_green "交换文件创建并启用成功"

        if ! grep -q "$SWAPFILE" /etc/fstab; then
            echo_cyan "将交换文件添加到 /etc/fstab"
            echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab
            echo_green "交换文件已添加到开机启动"
        else
            echo_green "交换文件已在 /etc/fstab 中，跳过添加步骤"
        fi
    fi

    sysctl -w vm.swappiness=20
    sysctl -w vm.min_free_kbytes=100000
    echo -e 'vm.swappiness = 20\nvm.min_free_kbytes = 100000\n' >/etc/sysctl.d/dmp_swap.conf

    echo_green "系统 swap 设置成功"
}

# ==================== DSTGO 服务管理 ====================
# 生成systemd服务文件
generate_service_file() {
    if [ ! -f "$SERVICE_FILE" ]; then
        cat > "$SERVICE_FILE" << EOF
[Unit]
Description=DST Admin Go Service
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$EXE_DIR
ExecStart=$EXE_DIR/dst-admin-go
ExecStop=/bin/kill -s TERM \$MAINPID
Restart=on-failure
RestartSec=5
StandardOutput=append:$EXE_DIR/log.log
StandardError=append:$EXE_DIR/log.log

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        echo_green "✅ systemd服务文件已生成"
    fi
    if ! systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl enable "$SERVICE_NAME"
        echo_green "✅ 已自动设置dstgo开机自启"
    fi
}

# 启动dstgo
start_dstgo() {
    generate_service_file

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        read -p "服务已在运行，是否重启？(y/n): " restart_choice
        [[ "$restart_choice" =~ ^[Yy]$ ]] && systemctl restart "$SERVICE_NAME" || return 0
    else
        systemctl start "$SERVICE_NAME"
    fi

    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo_green "=================================================="
        echo_green "✅ dstgo 启动成功！"
        echo_green "📝 日志文件: $EXE_DIR/log.log"
        echo_green "📋 查看日志: journalctl -u $SERVICE_NAME"
        echo_green "=================================================="
    else
        echo_red "❌ dstgo 启动失败！最近日志如下："
        journalctl -u "$SERVICE_NAME" --no-pager --since "1min ago" | tail -20
        return 1
    fi
}

# 停止dstgo
stop_dstgo() {
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        echo_yellow "⚠️  dstgo 服务当前未运行"
        return 0
    fi
    systemctl stop "$SERVICE_NAME"
    echo_green "✅ dstgo 服务已停止"
}

# 安装dstgo
install_dstgo() {
    local github_path="/xiaochency/dst-admin-go/releases/download/1.6.1/dstgo.tar.gz"
    
    echo_cyan "开始安装 dstgo..."
    
    if ! select_mirror; then
        echo_yellow "安装已取消"
        return 1
    fi

    if [[ -z "$SELECTED_MIRROR_URL" ]]; then
        echo_red "未选择镜像源，安装失败"
        return 1
    fi

    local download_url="${SELECTED_MIRROR_URL}/https://github.com${github_path}"
    local output_file="$HOME_DIR/dstgo.tar.gz"

    echo_cyan "下载地址: $download_url"

    # 清理旧文件
    rm -f "$output_file"
    rm -rf "$EXE_DIR"

    # 使用curl下载
    if curl -L --retry 3 --connect-timeout 15 -o "$output_file" "$download_url" --progress-bar; then
        echo_green "✅ 下载成功"
    else
        echo_red "❌ 下载失败，请尝试更换镜像源"
        rm -f "$output_file"
        return 1
    fi

    # 验证文件
    if [ ! -f "$output_file" ] || [ $(stat -c%s "$output_file" 2>/dev/null || echo 0) -lt 1000 ]; then
        echo_red "❌ 下载文件异常"
        rm -f "$output_file"
        return 1
    fi

    if ! tar -tzf "$output_file" >/dev/null 2>&1; then
        echo_red "❌ 压缩包损坏"
        rm -f "$output_file"
        return 1
    fi

    # 解压并部署
    tar -zxmf "$output_file" -C "$HOME_DIR"
    mkdir -p "$HOME_DIR/.klei/DoNotStarveTogether"/{backup,download_mod}
    cp -r "$EXE_DIR/static/MyDediServer" "$HOME_DIR/.klei/DoNotStarveTogether/"
    chmod +x "$EXE_DIR/dst-admin-go"

    # 生成服务文件
    generate_service_file

    rm -f "$output_file"
    echo_green "=================================================="
    echo_green "✅ dstgo 安装完成！"
    echo_green "💡 使用 systemctl enable $SERVICE_NAME 设置开机自启"
    echo_green "=================================================="
}

# 修改端口
change_port() {
    local config_file="$EXE_DIR/config.yml"
    
    [ ! -f "$config_file" ] && echo_red "❌ 配置文件不存在，请先安装dstgo" && return 1
    
    local current_port=$(grep -E "^port:" "$config_file" | grep -oE '[0-9]+' || echo "8082")
    echo_cyan "当前端口: $current_port"
    
    while true; do
        read -p "请输入新端口号 (1-65000): " new_port
        if [[ "$new_port" =~ ^[0-9]+$ ]] && (( new_port >= 1 && new_port <= 65000 )); then
            break
        fi
        echo_red "端口号必须是1-65000之间的整数"
    done

    sed -i "s/^port:.*/port: $new_port/" "$config_file"
    if grep -q "port: $new_port" "$config_file"; then
        echo_green "✅ 端口已修改为 $new_port，重启服务后生效"
    else
        echo_red "❌ 端口修改失败"
        return 1
    fi
}

# ==================== DST服务器管理 ====================
# 安装DST服务器
install_dst() {
    read -p "确定要安装Don't Starve Together服务器吗？(y/n): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo_yellow "已取消" && return

    echo_cyan "正在安装依赖..."
    dpkg --add-architecture i386
    apt-get update -qq
    apt-get install -y screen unzip lib32gcc-s1 libcurl4-gnutls-dev:i386 libcurl4-gnutls-dev procps

    mkdir -p "$STEAMCMD_DIR"
    cd "$STEAMCMD_DIR" || exit 1

    rm -f steamcmd_linux.tar.gz

    # SteamCMD下载地址
    local steamcmd_urls=(
        "https://github.dpik.top/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://gh.927223.xyz/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://cdn.gh-proxy.org/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://edgeone.gh-proxy.org/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
    )

    echo_cyan "请选择steamcmd下载地址："
    echo_green "1. 镜像源1 | 2. 镜像源2 | 3. 镜像源3 | 4. 镜像源4 | 5. 官方源"
    
    local choice url_index selected_url
    while true; do
        read -p "请输入选择 [1-5]: " choice
        [[ "$choice" =~ ^[1-5]$ ]] && break
        echo_red "无效选择"
    done
    url_index=$((choice-1))
    selected_url="${steamcmd_urls[$url_index]}"

    echo_cyan "正在下载steamcmd..."
    if ! curl -L --retry 3 --connect-timeout 30 -o steamcmd_linux.tar.gz "$selected_url" --progress-bar; then
        echo_red "❌ steamcmd下载失败"
        exit 1
    fi

    echo_cyan "正在解压..."
    tar -xzf steamcmd_linux.tar.gz
    chmod +x steamcmd.sh

    echo_cyan "正在安装DST服务器（可能需要较长时间）..."
    ./steamcmd.sh +force_install_dir "$INSTALL_DIR" +login anonymous +app_update 343050 validate +quit

    if [ -d "$INSTALL_DIR/bin" ]; then
        # 修复依赖
        cp linux32/libstdc++.so.6 "$INSTALL_DIR/bin/lib32/" 2>/dev/null
        cp linux32/steamclient.so "$INSTALL_DIR/bin/lib32/" 2>/dev/null
        cp linux64/steamclient.so "$INSTALL_DIR/bin64/lib64/" 2>/dev/null
        echo_green "=================================================="
        echo_green "✅ DST服务器安装完成！"
        echo_green "=================================================="
    else
        echo_red "❌ DST服务器安装失败"
        exit 1
    fi
}

# 更新DST服务器
update_dst() {
    echo_cyan "正在更新DST服务器..."
    cd "$STEAMCMD_DIR" || exit 1
    ./steamcmd.sh +force_install_dir "$INSTALL_DIR" +login anonymous +app_update 343050 validate +quit
    
    # 修复更新后依赖丢失
    cp linux32/libstdc++.so.6 "$INSTALL_DIR/bin/lib32/" 2>/dev/null
    cp linux32/steamclient.so "$INSTALL_DIR/bin/lib32/" 2>/dev/null
    cp linux64/steamclient.so "$INSTALL_DIR/bin64/lib64/" 2>/dev/null
    
    echo_green "✅ 服务器更新完成"
}

# 管理自动更新任务
manage_crontab() {
    echo_green "================================================"
    echo_green "        DST服务器自动更新任务"
    echo_green "================================================"
    echo_cyan "1. 每天6:10自动更新"
    echo_cyan "2. 每天22:10自动更新"
    echo_cyan "3. 移除所有DST自动更新任务"
    echo_cyan "0. 返回主菜单"
    echo_green "================================================"

    local morning="10 6 * * * cd $STEAMCMD_DIR && ./steamcmd.sh +login anonymous +force_install_dir $INSTALL_DIR +app_update 343050 validate +quit >/dev/null 2>&1"
    local evening="10 22 * * * cd $STEAMCMD_DIR && ./steamcmd.sh +login anonymous +force_install_dir $INSTALL_DIR +app_update 343050 validate +quit >/dev/null 2>&1"

    read -p "请输入选择 [0-3]: " choice
    case $choice in
        1)
            crontab -l 2>/dev/null | grep -v "steamcmd" | crontab -
            (crontab -l 2>/dev/null; echo "$morning") | crontab -
            echo_green "✅ 6:10自动更新任务已添加"
            ;;
        2)
            crontab -l 2>/dev/null | grep -v "steamcmd" | crontab -
            (crontab -l 2>/dev/null; echo "$evening") | crontab -
            echo_green "✅ 22:10自动更新任务已添加"
            ;;
        3)
            crontab -l 2>/dev/null | grep -v "steamcmd" | crontab -
            echo_green "✅ DST自动更新任务已移除"
            ;;
        0) return ;;
        *) echo_red "无效选择" ;;
    esac
}

# ==================== 主菜单 ====================
show_menu() {
    clear
    echo_green "================================================"
    echo_green "         DSTGO 管理脚本 v1.1.0"
    echo_green "================================================"
    echo_cyan "1. 安装dstgo"
    echo_cyan "2. 启动dstgo"
    echo_cyan "3. 停止dstgo"
    echo_cyan "4. 安装饥荒服务器"
    echo_cyan "5. 更新饥荒服务器"
    echo_cyan "6. 修改dstgo端口"
    echo_cyan "7. 管理自动更新任务"
    echo_cyan "8. 禁用Ubuntu自动更新"
    echo_cyan "9. 开启虚拟内存"
    echo_cyan "0. 退出脚本"
    echo_green "================================================"
}

main_menu() {
    while true; do
        show_menu
        read -p "请输入选择 [0-9]: " choice
        case $choice in
            1) install_dstgo ;;
            2) start_dstgo ;;
            3) stop_dstgo ;;
            4) install_dst ;;
            5) update_dst ;;
            6) change_port ;;
            7) manage_crontab ;;
            8) disable_ubuntu_autoupdate ;;
            9) set_swap ;;
            0) echo_green "再见！"; exit 0 ;;
            *) echo_red "无效选择，请输入0-9之间的数字" ;;
        esac
        echo
        read -p "按回车键继续..."
    done
}

main_menu