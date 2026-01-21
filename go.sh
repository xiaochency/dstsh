#!/bin/bash

USER=$(whoami)
ExeFile="$HOME/dstgo"
install_dir="$HOME/dst-dedicated-server"
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
function install_dstgo() {
    local download_urls=(
        "https://gh.llkk.cc/github.com/xiaochency/dst-admin-go/releases/download/1.5.3/dstgo.tar.gz"
        "https://github.dpik.top/github.com/xiaochency/dst-admin-go/releases/download/1.5.3/dstgo.tar.gz"
        "https://ghfast.top/github.com/xiaochency/dst-admin-go/releases/download/1.5.3/dstgo.tar.gz"
    )
    
    local mirror_names=(
        "镜像源1 (gh.llkk.cc)"
        "镜像源2 (github.dpik.top)" 
        "镜像源3 (ghfast.top)"
    )
    
    echo_cyan "开始安装 dstgo..."
    
    # 检查当前目录下是否已存在dstgo文件
    if [ -e "dstgo.tar.gz" ]; then
        echo_yellow "检测到当前目录下已存在dstgo文件，正在删除..."
        rm -f "dstgo.tar.gz"
        echo_green "已删除现有dstgo文件"
    fi
    if [ -d "dstgo" ]; then
        echo_yellow "检测到当前目录下已存在dstgo文件夹，正在删除..."
        rm -rf "dstgo"
        echo_green "已删除现有dstgo文件夹"
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
    local output_file="dstgo.tar.gz"
    
    # 使用选择的镜像源
    local mirror_index=$((selected_mirror-1))
    echo_cyan "使用镜像源：${mirror_names[mirror_index]}"
    echo_cyan "下载链接: ${download_urls[mirror_index]}"
    
    if download "${download_urls[mirror_index]}" 3 15 "$output_file"; then
        echo_green "镜像源 $selected_mirror 下载成功"
        
        # 文件验证步骤
        echo_cyan "验证下载的文件完整性..."
        
        # 1. 检查文件是否存在
        if [ ! -f "$output_file" ]; then
            echo_red "错误：下载的文件不存在"
            return 1
        fi
        
        # 2. 检查文件大小
        file_size=$(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file" 2>/dev/null || echo "0")
        if [ "$file_size" -lt 1000 ]; then
            echo_red "错误：下载的文件大小异常（$file_size 字节），可能下载失败"
            rm -f "$output_file"
            return 1
        fi
        
        # 3. 测试压缩包完整性
        if ! tar -tzf "$output_file" >/dev/null 2>&1; then
            echo_red "错误：压缩文件损坏或格式不正确"
            rm -f "$output_file"
            return 1
        fi
        
        echo_green "文件验证通过，开始解压..."
        if ! tar -zxvf "$output_file"; then
            echo_red "错误：解压失败，文件可能已损坏"
            rm -f "$output_file"
            return 1
        fi
        
        download_success=true
        
        # 后续配置操作
        mkdir -p $HOME/.klei/DoNotStarveTogether/backup
        mkdir -p $HOME/.klei/DoNotStarveTogether/download_mod
        echo "steamcmd=/root/steamcmd" >> /root/dstgo/dst_config
        echo "force_install_dir=/root/dst-dedicated-server" >> /root/dstgo/dst_config
        echo "cluster=MyDediServer" >> /root/dstgo/dst_config
        echo "backup=/root/.klei/DoNotStarveTogether/backup" >> /root/dstgo/dst_config
        echo "mod_download_path=/root/.klei/DoNotStarveTogether/download_mod" >> /root/dstgo/dst_config
        
        echo_green "✅ dstgo 安装完成！"
    else
        echo_red "镜像源 $selected_mirror 下载失败"
        return 1
    fi
}

# 启动主程序
function start_dstgo() {
    cd "$ExeFile" || {
        echo_red "错误：无法进入目录 $ExeFile"
        return 1
    }

    BIN=dst-admin-go
    
    # 检查可执行文件是否存在
    if [ ! -f "$BIN" ]; then
        echo_red "错误：可执行文件 $BIN 不存在"
        echo_red "请先执行安装操作（选项1）"
        return 1
    fi
    
    # 检查文件权限，如果没有执行权限则添加
    if [ ! -x "$BIN" ]; then
        echo_yellow "警告：$BIN 没有执行权限，正在添加执行权限..."
        chmod +x "$BIN"
        if [ $? -eq 0 ]; then
            echo_green "执行权限添加成功"
        else
            echo_red "执行权限添加失败"
            return 1
        fi
    fi
    
    # 检查程序是否已经在运行
    PID=$(ps -ef | grep "${BIN}" | grep -v grep | awk '{print $2}')
    if [ -n "$PID" ]; then
        echo_yellow "检测到 dstgo 服务已在运行 (PID: $PID)"
        read -p "是否要重启服务？(y/n): " restart_confirm
        if [[ "$restart_confirm" == "y" || "$restart_confirm" == "Y" ]]; then
            echo_cyan "正在停止现有服务..."
            kill -9 $PID
            sleep 2
        else
            echo_green "服务保持运行状态"
            return 0
        fi
    fi
    
    echo_cyan "正在启动 dstgo 服务..."
    
    # 启动服务
    nohup ./$BIN >log.log 2>&1 &
    local start_pid=$!
    
    # 等待一段时间检查进程是否启动成功
    sleep 3
    
    # 检查进程是否成功启动
    NEW_PID=$(ps -ef | grep "${BIN}" | grep -v grep | awk '{print $2}')
    if [ -n "$NEW_PID" ]; then
        echo_green "=================================================="
        echo_green "✅ dstgo 服务启动成功！"
        echo_green "✅ 请浏览器访问ip+端口"
        echo_green "=================================================="
        
        return 0
    else
        echo_red "=================================================="
        echo_red "❌ dstgo 服务启动失败！"
        echo_red "=================================================="
        
        # 检查日志文件获取错误信息
        if [ -f "log.log" ]; then
            echo_red "最后几行日志内容："
            tail -10 log.log
        fi
        
        return 1
    fi
}

# 关闭主程序
function stop_dstgo() {
    BIN=dst-admin-go
    
    echo_cyan "正在检查 dstgo 服务状态..."
    
    # 获取进程ID
    PID=$(ps -ef | grep "${BIN}" | grep -v grep | awk '{print $2}')
    
    if [ -z "$PID" ]; then
        echo_yellow "⚠️  dstgo 服务当前未运行"
        return 0
    fi
    
    echo_yellow "检测到运行中的 dstgo 服务 (PID: $PID)"
    
    echo_cyan "正在停止 dstgo 服务..."
    
    # 优雅停止，先发送SIGTERM信号
    kill $PID
    local wait_count=0
    local max_wait=10
    
    # 等待进程结束
    while [ $wait_count -lt $max_wait ]; do
        if ps -p $PID > /dev/null 2>&1; then
            echo_yellow "等待进程结束... ($((wait_count+1))/$max_wait)"
            sleep 1
            ((wait_count++))
        else
            break
        fi
    done
    
    # 如果进程仍然存在，强制杀死
    if ps -p $PID > /dev/null 2>&1; then
        echo_red "进程未正常退出，正在强制终止..."
        kill -9 $PID
        sleep 2
    fi
    
    # 再次检查进程是否已停止
    PID=$(ps -ef | grep "${BIN}" | grep -v grep | awk '{print $2}')
    if [ -z "$PID" ]; then
        echo_green "✅ dstgo 服务已成功停止！"
        return 0
    else
        echo_red "❌ dstgo 服务停止失败！"
        echo_red "当前进程ID: $PID"
        return 1
    fi
}

# 修改端口
function change_port() {
    local config_file="$HOME/dstgo/config.yml"
    
    # 检查配置文件是否存在
    if [ ! -f "$config_file" ]; then
        echo_red "错误：配置文件不存在，请先安装dstgo"
        return 1
    fi
    
    # 显示当前端口
    local current_port=$(grep -E "port: [0-9]+" "$config_file" | grep -oE '[0-9]+' | head -1)
    echo_cyan "当前端口: ${current_port:-8082}"
    
    # 输入新端口
    while true; do
        read -p "请输入新端口号 (1-65000): " new_port
        
        # 验证输入
        if ! [[ "$new_port" =~ ^[0-9]+$ ]]; then
            echo_red "端口号必须是数字"
            continue
        fi
        
        if [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65000 ]; then
            echo_red "端口号必须在 1-65000 之间"
            continue
        fi
        
        break
    done
    
    # 修改端口
    if grep -q "port:" "$config_file"; then
        sed -i "s/port:.*/port: $new_port/g" "$config_file"
    else
        echo "port: $new_port" >> "$config_file"
    fi
    
    # 验证修改
    local updated_port=$(grep -E "port: [0-9]+" "$config_file" | grep -oE '[0-9]+' | head -1)
    if [ "$updated_port" = "$new_port" ]; then
        echo_green "✅ 端口修改成功！新端口: $new_port"
        echo_green "请重启dstgo服务生效"
    else
        echo_red "❌ 端口修改失败"
        return 1
    fi
    
    return 0
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
    echo -e 'vm.swappiness = 20\nvm.min_free_kbytes = 100000\n' > /etc/sysctl.d/dstgo_swap.conf

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
    dpkg --add-architecture i386
    apt-get update
    apt-get install -y screen unzip lib32gcc-s1
    apt-get install -y libcurl4-gnutls-dev:i386
    apt-get install -y libcurl4-gnutls-dev
    apt-get install -y procps
    echo_green "环境依赖安装完毕"

    set_swap
    echo_cyan "设置虚拟内存2GB"
    mkdir $HOME/steamcmd
    cd $HOME/steamcmd

    if [ -e "steamcmd_linux.tar.gz" ]; then
        echo_yellow "检测到当前目录下已存在steamcmd_linux.tar.gz文件，正在删除..."
        rm -f "steamcmd_linux.tar.gz"
        echo_green "已删除现有steamcmd_linux.tar.gz文件"
    fi

    # 定义多个steamcmd下载地址
    steamcmd_urls=(
        "https://github.dpik.top/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://ghfast.top/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
    )

    # 显示下载地址选择菜单
    echo_cyan "请选择steamcmd下载地址："
    echo_green "1. 镜像源1 (github.dpik.top)"
    echo_green "2. 镜像源2 (ghfast.top)" 
    echo_green "3. 官方源 (steamcdn-a.akamaihd.net)"
    
    local download_choice
    while true; do
        read -p "请输入选择 [1-3]: " download_choice
        
        case $download_choice in
            1|2|3)
                break
                ;;
            *)
                echo_red "无效选择，请输入 1-3 之间的数字"
                ;;
        esac
    done

    # 手动选择模式：使用指定地址
    local url_index=$((download_choice-1))
    local selected_url="${steamcmd_urls[$url_index]}"
    
    case $download_choice in
        1) echo_cyan "使用镜像源1: $selected_url" ;;
        2) echo_cyan "使用镜像源2: $selected_url" ;;
        3) echo_cyan "使用官方源: $selected_url" ;;
    esac
    
    echo_yellow "正在下载: $selected_url"
    if wget -q --show-progress --tries=3 --timeout=30 "$selected_url"; then
        echo_green "下载成功！"
        download_success=true
    else
        echo_red "下载失败！"
        # 删除可能下载失败的文件
        rm -f steamcmd_linux.tar.gz 2>/dev/null
        
        # 询问是否尝试其他地址
        read -p "是否尝试其他下载地址？(y/n): " retry_confirm
        if [[ "$retry_confirm" == "y" || "$retry_confirm" == "Y" ]]; then
            echo_cyan "请重新选择下载地址："
            for i in "${!steamcmd_urls[@]}"; do
                if [ $i -ne $url_index ]; then  # 跳过已尝试的地址
                    case $((i+1)) in
                        1) echo_green "$((i+1)). 镜像源1 (github.dpik.top)" ;;
                        2) echo_green "$((i+1)). 镜像源2 (ghfast.top)" ;;
                        3) echo_green "$((i+1)). 官方源 (steamcdn-a.akamaihd.net)" ;;
                    esac
                fi
            done
            
            local new_choice
            while true; do
                read -p "请输入选择: " new_choice
                if [[ "$new_choice" =~ ^[1-3]$ ]] && [ "$new_choice" -ne "$download_choice" ]; then
                    download_choice=$new_choice
                    url_index=$((download_choice-1))
                    selected_url="${steamcmd_urls[$url_index]}"
                    break
                elif [ "$new_choice" -eq "$download_choice" ]; then
                    echo_red "不能选择已尝试的地址，请选择其他地址"
                else
                    echo_red "无效选择，请输入 1-3 之间的数字"
                fi
            done
            
            echo_yellow "正在重新下载: $selected_url"
            if wget -q --show-progress --tries=3 --timeout=30 "$selected_url"; then
                echo_green "下载成功！"
                download_success=true
            else
                echo_red "再次下载失败！"
                rm -f steamcmd_linux.tar.gz 2>/dev/null
                download_success=false
            fi
        else
            download_success=false
        fi
    fi

    # 检查下载是否成功
    if [ "$download_success" = false ]; then
        echo_red "=================================================="
        echo_red "✘✘✘ 下载失败！"
        echo_red "=================================================="
        echo_red "无法下载 steamcmd，请检查网络连接后重试！"
        exit 1
    fi

    # 验证下载的文件
    if [ ! -f "steamcmd_linux.tar.gz" ]; then
        echo_red "下载的文件不存在，请检查下载过程"
        exit 1
    fi

    file_size=$(stat -c%s "steamcmd_linux.tar.gz" 2>/dev/null || stat -f%z "steamcmd_linux.tar.gz" 2>/dev/null || echo "0")
    if [ "$file_size" -lt 1000000 ]; then  # 小于1MB可能是错误页面
        echo_yellow "下载的文件大小异常 ($file_size 字节)，可能下载了错误页面"
        rm -f steamcmd_linux.tar.gz
        echo_red "下载的文件可能损坏，请重试或手动下载"
        exit 1
    fi

    echo_green "文件验证通过，开始解压..."
    tar -xvzf steamcmd_linux.tar.gz
    
    # 初始安装
    ./steamcmd.sh +login anonymous +force_install_dir "$install_dir" +app_update 343050 validate +quit
    
    # 设置最大重试次数
    max_retries=3
    retry_count=0
    install_success=false
    
    # 验证安装并重试
    while [ $retry_count -lt $max_retries ]; do
        echo_cyan "正在验证服务器安装 (尝试 $((retry_count+1))/$((max_retries+1)))..."
        
        # 检查安装目录是否存在
        if [ -d "$HOME/dst-dedicated-server/bin/" ]; then
            cd $HOME/dst-dedicated-server/bin/ && {
                install_success=true
                break
            }
        fi
        
        # 如果验证失败，尝试重新安装
        if [ $retry_count -lt $max_retries ]; then
            echo_red "======================================"
            echo_red "✘✘ 服务器安装验证失败！"
            echo_red "✘✘ 正在尝试重新安装 ($((retry_count+1))/$max_retries)..."
            echo_red "======================================"
            
            # 进入steamcmd文件夹重新执行安装命令
            cd $HOME/steamcmd || {
                echo_red "无法进入 $HOME/steamcmd 目录"
                break
            }
            
            echo_cyan "正在重新执行安装命令..."
            ./steamcmd.sh +login anonymous +force_install_dir "$install_dir" +app_update 343050 validate +quit
            
            # 增加重试计数器
            retry_count=$((retry_count+1))
            
            # 等待一下再继续
            sleep 2
        fi
    done
    
    # 检查最终安装结果
    if [ "$install_success" = true ]; then
        echo_green "=================================================="
        echo_green "✅ 服务器安装验证通过！"
        echo_green "=================================================="
        
        # 修复依赖
        cp $HOME/steamcmd/linux32/libstdc++.so.6 $HOME/dst-dedicated-server/bin/lib32/ 2>/dev/null
        cp $HOME/steamcmd/linux32/steamclient.so $HOME/dst-dedicated-server/bin/lib32/ 2>/dev/null
        cp $HOME/steamcmd/linux64/steamclient.so $HOME/dst-dedicated-server/bin64/lib64/ 2>/dev/null
        echo_green "依赖已修复"
        
        echo_green "=================================================="
        echo_green "✅ Don't Starve Together 服务器安装完成！"
        echo_green "=================================================="
    else
        echo_red "=================================================="
        echo_red "✘✘ 经过 $((max_retries+1)) 次尝试后，服务器安装仍然失败！"
        echo_red "✘✘ 请检查网络连接或手动安装！"
        echo_red "=================================================="
        cd "$HOME"
        exit 1
    fi

    # 返回root根目录
    cd "$HOME"
    echo
}

# 更新服务器
update_dst() {
    echo_cyan "正在更新 Don't Starve Together 服务器..."
    cd "$steamcmd_dir" || exit 1
    ./steamcmd.sh +login anonymous +force_install_dir "$install_dir" +app_update 343050 validate +quit
    echo_green "服务器更新完成,请重新执行脚本"
    cp $HOME/steamcmd/linux32/steamclient.so $HOME/dst-dedicated-server/bin/lib32/ 2>/dev/null
    cp $HOME/steamcmd/linux64/steamclient.so $HOME/dst-dedicated-server/bin64/lib64/ 2>/dev/null
    cp $HOME/steamcmd/linux32/libstdc++.so.6 $HOME/dst-dedicated-server/bin/lib32/ 2>/dev/null
    echo_green "MOD更新bug已修复"
}

# steamcmd自动更新
function manage_crontab() {
    echo_green "================================================"
    echo_green "           steamcmd更新任务"
    echo_green "================================================"
    echo_cyan "1. 添加6:10自动更新任务"
    echo_cyan "2. 添加22:10自动更新任务" 
    echo_cyan "3. 移除steamcmd更新任务"
    echo_cyan "0. 返回主菜单"
    echo_green "================================================"
    
    read -p "请输入选择 [0-3]: " crontab_choice
    
    # 定义任务内容
    morning_task="10 6 * * * cd /root/steamcmd && /root/steamcmd/steamcmd.sh +quit > /dev/null 2>&1"
    evening_task="10 22 * * * cd /root/steamcmd && /root/steamcmd/steamcmd.sh +quit > /dev/null 2>&1"
    
    case $crontab_choice in
        1)
            echo_cyan "正在检查是否已存在6:10任务..."
            if crontab -l | grep -F "$morning_task" > /dev/null; then
                echo_red "6:10自动任务已存在，无需重复添加"
            else
                # 备份当前crontab
                crontab -l > /tmp/crontab_backup 2>/dev/null || echo "# Crontab backup" > /tmp/crontab_backup
                
                # 添加新任务
                (crontab -l 2>/dev/null; echo "$morning_task") | crontab -
                
                if [ $? -eq 0 ]; then
                    echo_green "6:10自动任务添加成功"
                    echo_cyan "任务内容: $morning_task"
                else
                    echo_red "任务添加失败"
                fi
            fi
            ;;
        2)
            echo_cyan "正在检查是否已存在22:10任务..."
            if crontab -l | grep -F "$evening_task" > /dev/null; then
                echo_red "22:10自动任务已存在，无需重复添加"
            else
                # 备份当前crontab
                crontab -l > /tmp/crontab_backup 2>/dev/null || echo "# Crontab backup" > /tmp/crontab_backup
                
                # 添加新任务
                (crontab -l 2>/dev/null; echo "$evening_task") | crontab -
                
                if [ $? -eq 0 ]; then
                    echo_green "22:10自动任务添加成功"
                    echo_cyan "任务内容: $evening_task"
                else
                    echo_red "任务添加失败"
                fi
            fi
            ;;
        3)
            echo_cyan "正在查找并移除steamcmd相关自动任务..."
            # 创建临时文件，过滤掉包含steamcmd的任务
            crontab -l 2>/dev/null | grep -v "steamcmd" > /tmp/crontab_new
            
            # 安装新的crontab
            crontab /tmp/crontab_new
            
            if [ $? -eq 0 ]; then
                echo_green "steamcmd自动任务已成功移除"
                # 显示当前剩余的自动任务
                current_tasks=$(crontab -l 2>/dev/null | wc -l)
                if [ $current_tasks -eq 0 ]; then
                    echo_yellow "当前没有自动任务"
                else
                    echo_cyan "当前剩余的自动任务:"
                    crontab -l
                fi
            else
                echo_red "任务移除失败"
            fi
            
            # 清理临时文件
            rm -f /tmp/crontab_new
            ;;
        0)
            echo_green "返回主菜单"
            return 0
            ;;
        *)
            echo_red "无效选择，请输入 0-3 之间的数字"
            ;;
    esac
    
    # 显示当前crontab状态
    echo
    echo_green "当前自动任务列表:"
    crontab -l 2>/dev/null || echo_yellow "当前没有自动任务"
}

# 显示菜单函数
function show_menu() {
    clear
    echo_green "================================================"
    echo_green "           dstgo 管理脚本菜单"
    echo_green "================================================"
    echo
    
    echo_cyan "1. 安装dstgo"
    echo_cyan "2. 启动dstgo" 
    echo_cyan "3. 停止dstgo"
    echo_cyan "4. 安装饥荒服务器"
    echo_cyan "5. 更新饥荒服务器"
    echo_cyan "6. 修改端口"
    echo_cyan "7. steamcmd自动更新"
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
                echo_cyan "执行: 安装dstgo"
                install_dstgo
                ;;
            2)
                echo_cyan "执行: 启动dstgo"
                start_dstgo
                ;;
            3)
                echo_cyan "执行: 停止dstgo"
                stop_dstgo
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
            7)  # 新增选项处理
                echo_cyan "执行: 管理自动任务"
                manage_crontab
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
            install_dstgo
            ;;
        "start")
            start_dstgo
            ;;
        "stop")
            stop_dstgo
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
        "manage-crontab")  # 新增参数支持
            manage_crontab
            ;;
        *)
            echo_red "未知参数: $1"
            echo_cyan "可用参数: install, start, stop, install-dst, update-dst, change_port, manage-crontab"
            exit 1
            ;;
    esac
fi