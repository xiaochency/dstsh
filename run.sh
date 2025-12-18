#!/bin/bash

###########################################
# 用户自定义设置请修改下方变量，其他变量请不要修改 #
###########################################

# --------------- ↓可修改↓ --------------- #
# dmp暴露端口，即网页打开时所用的端口
PORT=80

# 数据库文件所在目录，例如：./config
CONFIG_DIR="./"

# --------------- ↑可修改↑ --------------- #

###########################################
#     下方变量请不要修改，否则可能会出现异常     #
###########################################

USER=$(whoami)
ExeFile="$HOME/dmp"
install_dir="$HOME/dst"
steamcmd_dir="$HOME/steamcmd"

cd "$HOME" || exit

function echo_red() {
    echo -e "\033[0;31m$*\033[0m"
}

function echo_green() {
    echo -e "\033[0;32m$*\033[0m"
}

function echo_yellow() {
    echo -e "\033[0;33m$*\033[0m"
}

function echo_cyan() {
    echo -e "\033[0;36m$*\033[0m"
}

function echo_red_blink() {
    echo -e "\033[5;31m$*\033[0m"
}

# 检查用户，只能使用root执行
if [[ "${USER}" != "root" ]]; then
    echo_red "请使用root用户执行此脚本"
    exit 1
fi

if [ -z "$1" ]; then
    acceleration_index=0

else
    acceleration_index=$1
fi

# 设置全局stderr为红色并添加固定格式
function set_tty() {
    exec 2> >(while read -r line; do echo_red "[$(date +'%F %T')] [ERROR] ${line}" >&2; done)
}

# 恢复stderr颜色
function unset_tty() {
    exec 2> /dev/tty
}

# 检查文件
function check_for_file() {
    if [ ! -e "$1" ]; then
        return 1
    fi
    return 0
}


# 检查jq
function check_jq() {
    echo_cyan "正在检查jq命令"
    if ! jq --version >/dev/null 2>&1; then
        OS=$(grep -P "^ID=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g")
        if [[ ${OS} == "ubuntu" ]]; then
            apt install -y jq
        else
            if grep -P "^ID_LIKE=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g" | grep rhel; then
                yum install -y jq
            fi
        fi
    fi
}



function check_strings() {
    echo_cyan "正在检查strings命令"
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

# Ubuntu检查GLIBC, rhel需要下载文件手动安装
function check_glibc() {
    check_strings
    echo_cyan "正在检查GLIBC版本"
    OS=$(grep -P "^ID=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g")
    if [[ ${OS} == "ubuntu" ]]; then
        if ! strings /lib/x86_64-linux-gnu/libc.so.6 | grep GLIBC_2.34 >/dev/null 2>&1; then
            apt update
            apt install -y libc6
        fi
    else
        echo_red "非Ubuntu系统，如GLIBC小于2.34，请手动升级"
    fi
}

# 下载函数:下载链接,尝试次数,超时时间(s)
function download() {
    local download_url="$1"
    local tries="$2"
    local timeout="$3"
    local output_file="$4"  # 添加输出文件参数
    
    wget -q --show-progress --tries="$tries" --timeout="$timeout" -O "$output_file" "$download_url"
    return $?
}

# 安装主程序
function install_dmp() {
    local download_urls=(
        "https://gh.llkk.cc/https://github.com/miracleEverywhere/dst-management-platform-api/releases/download/v2.1.9/dmp.tgz"
        "https://github.dpik.top/https://github.com/miracleEverywhere/dst-management-platform-api/releases/download/v2.1.9/dmp.tgz"
        "https://ghfast.top/https://github.com/miracleEverywhere/dst-management-platform-api/releases/download/v2.1.9/dmp.tgz"
    )
    
    local mirror_names=(
        "镜像源1 (gh.llkk.cc)"
        "镜像源2 (github.dpik.top)" 
        "镜像源3 (ghfast.top)"
    )
    
    # 检查 jq
    if ! check_jq; then
    echo_red "jq安装失败，请检查网络连接"
    exit 1
    fi
    
    echo_cyan "开始安装 DMP..."
    
    # 检查当前目录下是否已存在dmp文件
    if [ -e "dmp" ]; then
        echo_yellow "检测到当前目录下已存在dmp文件，正在删除..."
        rm -f "dmp"
        echo_green "已删除现有dmp文件"
    fi

    # 检查当前目录下是否已存在dmp.tgz文件
    if [ -e "dmp.tgz" ]; then
        echo_yellow "检测到当前目录下已存在dmp.tgz文件，正在删除..."
        rm -f "dmp.tgz"
        echo_green "已删除现有dmp.tgz文件"
    fi
    
    # 显示镜像源选择菜单
    echo_cyan "请选择下载镜像源："
    for i in "${!mirror_names[@]}"; do
        echo_green "$((i+1)). ${mirror_names[i]}"
    done
    
    local selected_mirror
    while true; do
        read -p "请输入选择 [1-3]: " selected_mirror
        
        case $selected_mirror in
            1|2|3)
                break
                ;;
            *)
                echo_red "无效选择，请输入 1-3 之间的数字"
                ;;
        esac
    done
    
    local download_success=false
    local output_file="dmp.tgz"
    
    # 使用选择的镜像源
    local mirror_index=$((selected_mirror-1))
    echo_cyan "使用镜像源：${mirror_names[mirror_index]}"
    echo_cyan "下载链接: ${download_urls[mirror_index]}"
    
    if download "${download_urls[mirror_index]}" 3 15 "$output_file"; then
        echo_green "镜像源 $selected_mirror 下载成功"
        download_success=true
    else
        echo_red "镜像源 $selected_mirror 下载失败"
    fi

    # 处理下载的文件
    if [ "$download_success" = true ] && [ -f "$output_file" ]; then
        echo_cyan "正在解压文件..."
        if tar zxvf "$output_file"; then
            echo_green "文件解压成功"
            chmod 755 dmp
            echo_green "DMP 安装完成"
        else
            echo_red "文件解压失败"
            download_success=false
        fi
    else
        echo_red "镜像源下载失败"
        
        # 提供手动安装指南
        echo_cyan "请尝试以下手动安装方法:"
        echo_cyan "1. 手动下载 dmp.tgz 文件"
        echo_cyan "2. 将文件保存到当前目录并运行: tar zxvf dmp.tgz && chmod +x dmp"
        exit 1
    fi
}

# 检查进程状态
function check_dmp() {
    sleep 1
    if pgrep dmp >/dev/null; then
        echo_green "启动成功"
        echo_green "请浏览器访问http://公网ip:端口"
        echo_green "例如http://192.168.31.100:80"
        echo_green "请执行选项4安装饥荒服务器"
    else
        echo_red "启动失败"
        exit 1
    fi
}

# 检查端口是否合法
function check_port() {
    local port="$1"
    
    # 检查是否为数字
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo_red "端口号必须为数字"
        return 1
    fi
    
    # 检查端口范围
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo_red "端口号必须在 1-65535 范围内"
        return 1
    fi
    
    # 检查常见系统端口
    if [ "$port" -lt 1024 ] && [ "$(whoami)" != "root" ]; then
        echo_yellow "警告：使用 1-1023 范围内的端口需要 root 权限"
    fi
    
    return 0
}

# 修改端口函数
function change_port() {
    echo_cyan "当前端口设置为: $PORT"
    echo_cyan "请输入新的端口号 (1-65535):"
    read -r new_port
    
    # 检查端口是否合法
    if ! check_port "$new_port"; then
        return 1
    fi
    
    # 检查端口是否被占用
    local port_used
    port_used=$(ss -ltnp | awk -v port="${new_port}" '$4 ~ ":"port"$" {print $4}')
    
    if [ -n "$port_used" ]; then
        echo_red "端口 $new_port 已被占用: $port_used"
        echo_red "请选择其他端口"
        return 1
    fi
    
    # 更新端口设置
    PORT=$new_port
    echo_green "端口已成功修改为: $PORT"
    echo_yellow "注意：修改端口后需要重启DMP服务才能生效"
    
    # 询问是否立即重启DMP
    if pgrep dmp >/dev/null; then
        echo_cyan "是否立即重启DMP服务以使新端口生效？(y/n):"
        read -r restart_choice
        if [[ "$restart_choice" == "y" || "$restart_choice" == "Y" ]]; then
            echo_cyan "正在重启DMP服务..."
            stop_dmp
            sleep 2
            start_dmp
            check_dmp
        else
            echo_yellow "请记得手动重启DMP服务以使新端口生效"
        fi
    fi
    
    return 0
}

# 启动主程序
function start_dmp() {
    # 检查端口是否被占用,如果被占用则退出
    port=$(ss -ltnp | awk -v port="${PORT}" '$4 ~ ":"port"$" {print $4}')

    if [ -n "$port" ]; then
       echo_red "端口 $PORT 已被占用: $port", 修改 run.sh 中的 PORT 变量后重新运行
       exit 1
    fi

    check_glibc

    if [ -e "$ExeFile" ]; then
        nohup "$ExeFile" -c -l ${PORT} -s ${CONFIG_DIR} >dmp.log 2>&1 &
    else
        install_dmp
        #create_dstmp_config
        if [ -e "$ExeFile" ]; then
            nohup "$ExeFile" -c -l ${PORT} -s ${CONFIG_DIR} >dmp.log 2>&1 &
        else
            echo_red "安装失败，无法启动 DMP"
            exit 1
        fi
    fi
}

# 关闭主程序
function stop_dmp() {
    echo_cyan "正在停止 DMP 服务..."
    
    # 检查进程是否存在
    if pgrep dmp >/dev/null; then
        # 先尝试正常终止
        pkill dmp
        sleep 2
        
        # 检查是否还在运行，如果还在就强制终止
        if pgrep dmp >/dev/null; then
            echo_yellow "进程仍在运行，尝试强制终止..."
            pkill -9 dmp
            sleep 1
        fi
        
        # 最终确认进程是否已停止
        if pgrep dmp >/dev/null; then
            echo_red "无法停止 DMP 进程，请手动检查"
            return 1
        else
            echo_green "DMP 服务已成功停止"
        fi
    else
        echo_yellow "DMP 进程未运行"
    fi
}

# 设置虚拟内存
function set_swap() {
    SWAPFILE=/swap.img
    SWAPSIZE=2G

    # 检查是否已经存在交换文件
    if [ -f $SWAPFILE ]; then
        echo_green "交换文件已存在，跳过创建步骤"
    else
        echo_cyan "创建交换文件..."
        sudo fallocate -l $SWAPSIZE $SWAPFILE
        sudo chmod 600 $SWAPFILE
        sudo mkswap $SWAPFILE
        sudo swapon $SWAPFILE
        echo_green "交换文件创建并启用成功"
    fi

    # 添加到 /etc/fstab 以便开机启动
    if ! grep -q "$SWAPFILE" /etc/fstab; then
        echo_cyan "将交换文件添加到 /etc/fstab "
        echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab
        echo_green "交换文件已添加到开机启动"
    else
        echo_green "交换文件已在 /etc/fstab 中，跳过添加步骤"
    fi

    # 更改swap配置并持久化
    sysctl -w vm.swappiness=20
    sysctl -w vm.min_free_kbytes=100000
    echo -e 'vm.swappiness = 20\nvm.min_free_kbytes = 100000\n' > /etc/sysctl.d/dmp_swap.conf

    echo_green "系统swap设置成功"
}

# 安装服务器
install_dst() {
    read -p "您确定要安装 Don't Starve Together 服务器吗？(y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo_yellow "安装已取消."
        return
    fi

    echo_cyan "正在安装 Don't Starve Together 服务器..."
    sudo dpkg --add-architecture i386
    sudo apt-get update
    sudo apt-get install -y libcurl4-gnutls-dev:i386
    sudo apt-get install -y lib32gcc1
    sudo apt-get install -y lib32stdc++6
    sudo apt-get install -y libcurl4-gnutls-dev
    sudo apt-get install -y libgcc1
    sudo apt-get install -y libstdc++6
    sudo apt-get install -y screen
    sudo apt-get install -y unzip
    echo_green "环境依赖安装完毕"

    mkdir -p ~/.klei/DMP_BACKUP
    mkdir -p ~/.klei/DMP_MOD/not_ugc
    mkdir -p ~/.klei/DoNotStarveTogether/MyDediServer/Master
    mkdir -p ~/.klei/DoNotStarveTogether/MyDediServer/Caves
    touch ~/.klei/DoNotStarveTogether/MyDediServer/cluster_token.txt
    touch ~/.klei/DoNotStarveTogether/MyDediServer/adminlist.txt
    touch ~/.klei/DoNotStarveTogether/MyDediServer/blocklist.txt
    touch ~/.klei/DoNotStarveTogether/MyDediServer/whitelist.txt
    echo_green "饥荒初始文件夹创建完成"

    set_swap
    echo_cyan "设置虚拟内存2GB"
    mkdir ~/steamcmd
    cd ~/steamcmd
    
    file_name="steamcmd_linux.tar.gz"
    check_for_file "$file_name"

    if [ $? -eq 0 ]; then
        echo_yellow "$file_name 存在，正在删除..."
        rm "$file_name"
    else
        echo_cyan "$file_name 不存在，继续下载steamcmd"
    fi

    wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
    tar -xvzf steamcmd_linux.tar.gz
    ./steamcmd.sh +login anonymous +force_install_dir "$install_dir" +app_update 343050 validate +quit
    
    echo_cyan "正在验证服务器安装..."
    cd ~/dst/bin/ || {
        echo
        echo_red "======================================"
        echo_red "✘ 服务器安装验证失败！"
        echo_red "✘ 请重新安装！"
        echo_red "======================================"
        echo
        cd "$HOME" #返回root根目录
        exit 1
    }

    # 服务器安装验证通过后，执行MOD修复
    if [ -d ~/dst/bin/ ]; then
        echo_green "=================================================="
        echo_green "✅ 服务器安装验证通过！"
        echo_green "=================================================="
        
        echo_cyan "正在执行MOD修复..."
        cp ~/steamcmd/linux32/libstdc++.so.6 ~/dst/bin/lib32/
        cp ~/steamcmd/linux32/steamclient.so ~/dst/bin/lib32/
        echo_green "MOD更新bug已修复"
        
        echo_green "=================================================="
        echo_green "✅ Don't Starve Together 服务器安装完成！"
        echo_green "=================================================="
    else
        echo_red "=================================================="
        echo_red "✘ 服务器安装验证失败！"
        echo_red "✘ 请重新安装！"
        echo_red "=================================================="
        cd "$HOME" #返回root根目录
        exit 1
    fi

    # 无论成功还是失败，最后都返回root根目录
    cd "$HOME"
    echo
}

# 更新服务器
update_dst() {
    echo_cyan "正在更新 Don't Starve Together 服务器..."
    cd "$steamcmd_dir" || exit 1
    ./steamcmd.sh +login anonymous +force_install_dir "$install_dir" +app_update 343050 validate +quit
    echo_green "服务器更新完成,请重新执行脚本"
    cp ~/steamcmd/linux32/steamclient.so ~/dst/bin/lib32/
    echo_green "MOD更新bug已修复"
}

# 显示菜单函数
function show_menu() {
    clear
    echo_green "================================================"
    echo_green "           DMP 管理脚本菜单"
    echo_green "================================================"
    echo
    
    echo_cyan "1. 安装DMP"
    echo_cyan "2. 启动DMP" 
    echo_cyan "3. 停止DMP"
    echo_cyan "4. 安装饥荒服务器"
    echo_cyan "5. 更新饥荒服务器"
    echo_cyan "6. 修改端口"
    echo_cyan "0. 退出脚本"
    
    echo
    echo_green "================================================"
}

# 主菜单循环
function main_menu() {
    while true; do
        show_menu
        read -p "请输入选择 [0-6]: " choice
        
        case $choice in
            1)
                echo_cyan "执行: 安装DMP"
                install_dmp
                #create_dstmp_config
                ;;
            2)
                echo_cyan "执行: 启动DMP"
                start_dmp
                check_dmp
                ;;
            3)
                echo_cyan "执行: 停止DMP"
                stop_dmp
                ;;
            4)
                echo_cyan "执行: 安装DST服务器"
                install_dst
                ;;
            5)
                echo_cyan "执行: 更新DST服务器"
                update_dst
                ;;
            6)
                echo_cyan "执行: 修改端口"
                change_port
                ;;
            0)
                echo_green "感谢使用，再见！"
                exit 0
                ;;
            *)
                echo_red "无效选择，请输入 0-5 之间的数字"
                ;;
        esac
        
        echo
        read -p "按回车键继续..."
    done
}

# 检查是否以交互模式运行（无参数）
if [ -z "$1" ]; then
    main_menu
else
    # 如果有参数，可以根据参数执行相应操作
    case "$1" in
        "install")
            install_dmp
            #create_dstmp_config
            ;;
        "start")
            start_dmp
            check_dmp
            ;;
        "stop")
            stop_dmp
            ;;
        "install-dst")
            install_dst
            ;;
        "update-dst")
            update_dst
            ;;
        "change_port")
            change_port
            ;;
        *)
            echo_red "未知参数: $1"
            echo_cyan "可用参数: install, start, stop, install-dst, update-dst, change_port"
            exit 1
            ;;
    esac
fi