#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 目录定义
install_dir="$HOME/dst"
steamcmd_dir="$HOME/steamcmd"
steam_dir="$HOME/Steam"

# 版本配置文件
VERSION_CONFIG_FILE="$HOME/.dst_version"
# 默认版本为32位
DEFAULT_VERSION="32"

# 读取版本配置
function read_version_config() {
    if [ -f "$VERSION_CONFIG_FILE" ]; then
        cat "$VERSION_CONFIG_FILE"
    else
        echo "$DEFAULT_VERSION"
    fi
}

# 保存版本配置
function save_version_config() {
    echo "$1" > "$VERSION_CONFIG_FILE"
}

# 获取当前版本
function get_current_version() {
    read_version_config
}

# 切换版本
function toggle_version() {
    local current_version=$(get_current_version)
    local new_version
    
    if [ "$current_version" = "32" ]; then
        new_version="64"
        echo_info "正在切换到64位版本..."
    else
        new_version="32"
        echo_info "正在切换到32位版本..."
    fi
    
    save_version_config "$new_version"
    echo_success "已切换到${new_version}位版本"
    
    # 检查64位版本是否存在
    if [ "$new_version" = "64" ]; then
        if [ ! -f "$HOME/dst/bin64/dontstarve_dedicated_server_nullrenderer_x64" ]; then
            echo_warning "⚠️  64位服务器程序未安装，启动时将使用32位版本"
            echo_info "请通过选项2更新服务器来安装64位版本"
        else
            echo_success "✅ 64位服务器程序已安装"
        fi
    fi
}

# 输出函数
function echo_error() { echo -e "${RED}错误: $@${NC}" >&2; }
function echo_success() { echo -e "${GREEN}$@${NC}"; }
function echo_warning() { echo -e "${YELLOW}$@${NC}"; }
function echo_info() { echo -e "${BLUE}$@${NC}"; }
function echo_debug() { echo -e "${CYAN}$@${NC}"; }

function fail() {
    echo_error "$@"
    exit 1
}

function check_for_file() {
    if [ ! -e "$1" ]; then
        return 1
    fi
    return 0
}

function download() {
    local download_url="$1"
    local tries="$2"
    local timeout="$3"

    wget -q --show-progress --tries="$tries" --timeout="$timeout" "$download_url"
    return $?
}

# 设置虚拟内存
function settingSwap() {
    SWAPFILE=/swap.img
    SWAPSIZE=2G

    if [ -f $SWAPFILE ]; then
        echo_success "交换文件已存在，跳过创建步骤"
    else
        echo_info "创建交换文件..."
        sudo fallocate -l $SWAPSIZE $SWAPFILE
        sudo chmod 600 $SWAPFILE
        sudo mkswap $SWAPFILE
        sudo swapon $SWAPFILE
        echo_success "交换文件创建并启用成功"
    fi

    if ! grep -q "$SWAPFILE" /etc/fstab; then
        echo_info "将交换文件添加到 /etc/fstab"
        echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab
        echo_success "交换文件已添加到开机启动"
    else
        echo_success "交换文件已在 /etc/fstab 中，跳过添加步骤"
    fi

    sysctl -w vm.swappiness=20
    sysctl -w vm.min_free_kbytes=100000
    echo -e 'vm.swappiness = 20\nvm.min_free_kbytes = 100000\n' > /etc/sysctl.d/dmp_swap.conf

    echo_success "系统swap设置成功 (System swap setting completed)"
}

# 安装服务器
Install_dst() {
    read -p "您确定要安装 Don't Starve Together 服务器吗？(y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo_warning "安装已取消."
        return
    fi

    echo_info "正在安装 Don't Starve Together 服务器..."
    dpkg --add-architecture i386
    apt-get update
    apt-get install -y screen unzip lib32gcc-s1
    apt-get install -y libcurl4-gnutls-dev:i386
    apt-get install -y libcurl4-gnutls-dev
    echo_success "环境依赖安装完毕"

    mkdir -p $HOME/.klei/DoNotStarveTogether/backups/
    mkdir -p $HOME/.klei/DoNotStarveTogether/Cluster_1/
    mkdir -p $HOME/.klei/DoNotStarveTogether/Cluster_1/Master
    mkdir -p $HOME/.klei/DoNotStarveTogether/Cluster_1/Caves
    touch $HOME/.klei/DoNotStarveTogether/Cluster_1/cluster_token.txt
    touch $HOME/.klei/DoNotStarveTogether/Cluster_1/adminlist.txt
    touch $HOME/.klei/DoNotStarveTogether/Cluster_1/blocklist.txt
    touch $HOME/.klei/DoNotStarveTogether/Cluster_1/whitelist.txt
    mkdir -p $HOME/.klei/DoNotStarveTogether/Cluster_2/
    mkdir -p $HOME/.klei/DoNotStarveTogether/Cluster_2/Master
    mkdir -p $HOME/.klei/DoNotStarveTogether/Cluster_2/Caves
    touch $HOME/.klei/DoNotStarveTogether/Cluster_2/cluster_token.txt
    touch $HOME/.klei/DoNotStarveTogether/Cluster_2/adminlist.txt
    touch $HOME/.klei/DoNotStarveTogether/Cluster_2/blocklist.txt
    touch $HOME/.klei/DoNotStarveTogether/Cluster_2/whitelist.txt
    echo_success "饥荒初始文件夹创建完成"

    settingSwap
    echo_info "设置虚拟内存2GB"
    mkdir $HOME/steamcmd
    cd $HOME/steamcmd
    
    file_name="steamcmd_linux.tar.gz"
    check_for_file "$file_name"

    if [ $? -eq 0 ]; then
        echo_warning "$file_name 存在，正在删除..."
        rm "$file_name"
    else
        echo_info "$file_name 不存在，继续下载steamcmd"
    fi

    # 定义多个steamcmd下载地址
    steamcmd_urls=(
        "https://github.dpik.top/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://ghfast.top/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
    )

    # 显示下载地址选择菜单
    echo_info "请选择steamcmd下载地址："
    echo_success "1. 镜像源1 (github.dpik.top)"
    echo_success "2. 镜像源2 (ghfast.top)" 
    echo_success "3. 官方源 (steamcdn-a.akamaihd.net)"
    
    local download_choice
    while true; do
        read -p "请输入选择 [1-3]: " download_choice
        
        case $download_choice in
            1|2|3)
                break
                ;;
            *)
                echo_error "无效选择，请输入 1-3 之间的数字"
                ;;
        esac
    done

    # 手动选择模式：使用指定地址
    local url_index=$((download_choice-1))
    local selected_url="${steamcmd_urls[$url_index]}"
    
    case $download_choice in
        1) echo_info "使用镜像源1: $selected_url" ;;
        2) echo_info "使用镜像源2: $selected_url" ;;
        3) echo_info "使用官方源: $selected_url" ;;
    esac
    
    echo_info "正在下载: $selected_url"
    if wget -q --show-progress --tries=3 --timeout=30 "$selected_url"; then
        echo_success "下载成功！"
        download_success=true
    else
        echo_error "下载失败！"
        # 删除可能下载失败的文件
        rm -f steamcmd_linux.tar.gz 2>/dev/null
        
        # 询问是否尝试其他地址
        read -p "是否尝试其他下载地址？(y/n): " retry_confirm
        if [[ "$retry_confirm" == "y" || "$retry_confirm" == "Y" ]]; then
            echo_info "请重新选择下载地址："
            for i in "${!steamcmd_urls[@]}"; do
                if [ $i -ne $url_index ]; then  # 跳过已尝试的地址
                    case $((i+1)) in
                        1) echo_success "$((i+1)). 镜像源1 (github.dpik.top)" ;;
                        2) echo_success "$((i+1)). 镜像源2 (ghfast.top)" ;;
                        3) echo_success "$((i+1)). 官方源 (steamcdn-a.akamaihd.net)" ;;
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
                    echo_error "不能选择已尝试的地址，请选择其他地址"
                else
                    echo_error "无效选择，请输入 1-3 之间的数字"
                fi
            done
            
            echo_info "正在重新下载: $selected_url"
            if wget -q --show-progress --tries=3 --timeout=30 "$selected_url"; then
                echo_success "下载成功！"
                download_success=true
            else
                echo_error "再次下载失败！"
                rm -f steamcmd_linux.tar.gz 2>/dev/null
                download_success=false
            fi
        else
            download_success=false
        fi
    fi

    # 检查下载是否成功
    if [ "$download_success" = false ]; then
        echo_error "=================================================="
        echo_error "✘✘✘ 下载失败！"
        echo_error "=================================================="
        echo_error "无法下载 steamcmd，请检查网络连接后重试！"
        exit 1
    fi

    # 验证下载的文件
    if [ ! -f "steamcmd_linux.tar.gz" ]; then
        echo_error "下载的文件不存在，请检查下载过程"
        exit 1
    fi

    file_size=$(stat -c%s "steamcmd_linux.tar.gz" 2>/dev/null || stat -f%z "steamcmd_linux.tar.gz" 2>/dev/null || echo "0")
    if [ "$file_size" -lt 1000000 ]; then  # 小于1MB可能是错误页面
        echo_info "下载的文件大小异常 ($file_size 字节)，可能下载了错误页面"
        rm -f steamcmd_linux.tar.gz
        echo_error "下载的文件可能损坏，请重试或手动下载"
        exit 1
    fi

    echo_success "文件验证通过，开始解压..."
    tar -xvzf steamcmd_linux.tar.gz
    
    # 添加重试机制
    local install_success=false
    local retry_count=0
    local max_retries=3
    
    while [ "$install_success" = false ] && [ $retry_count -lt $max_retries ]; do
        echo_info "正在尝试安装 DST 服务器 (尝试 $((retry_count + 1))/$max_retries)..."
        
        ./steamcmd.sh +login anonymous +force_install_dir "$install_dir" +app_update 343050 validate +quit
        
        echo_info "正在验证服务器安装..."
        cd $HOME/dst/bin/ 2>/dev/null
        if [ $? -eq 0 ]; then
            # 服务器安装验证通过后，执行MOD修复
            if [ -d $HOME/dst/bin/ ]; then
                echo_success "=================================================="
                echo_success "✅ 服务器安装验证通过！"
                echo_success "=================================================="
                
                echo_info "正在执行MOD修复和依赖库"
                cp $HOME/steamcmd/linux32/steamclient.so $HOME/dst/bin/lib32/ 2>/dev/null
                cp $HOME/steamcmd/linux64/steamclient.so $HOME/dst/bin64/lib64/ 2>/dev/null
                cp $HOME/steamcmd/linux32/libstdc++.so.6 $HOME/dst/bin/lib32/ 2>/dev/null
                echo_success "MOD更新bug已修复"
                
                echo_success "=================================================="
                echo_success "✅ Don't Starve Together 服务器安装完成！"
                echo_success "=================================================="
                install_success=true
            else
                echo_error "=================================================="
                echo_error "✘✘ 服务器安装验证失败，准备重试..."
                echo_error "=================================================="
                install_success=false
            fi
        else
            echo
            echo_error "======================================"
            echo_error "✘✘ 无法进入服务器目录: $HOME/dst/bin/"
            echo_error "✘✘ 服务器安装失败，准备重试..."
            echo_error "======================================"
            echo
            install_success=false
        fi
        
        if [ "$install_success" = false ]; then
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                echo_warning "等待 6 秒后重试..."
                sleep 6
                # 清理可能的残留文件
                # rm -rf "$install_dir" 2>/dev/null
                cd $HOME/steamcmd
            else
                echo_error "=================================================="
                echo_error "✘✘✘ 已达到最大重试次数 ($max_retries)，安装失败！"
                echo_error "请检查网络连接或手动安装。"
                echo_error "=================================================="
                cd "$HOME"
                fail "服务器安装失败，请检查网络连接后重试！"
            fi
        fi
    done

    cd "$HOME" #返回root根目录
    echo
}

# 更新服务器
Update_dst() {
    echo_info "正在更新 Don't Starve Together 服务器..."
    # 更新前，先关闭相关的 screen 会话
    echo_info "正在关闭相关服务器及监控进程..."
    local sessions=("Cluster_1Master" "Cluster_2Master" "Cluster_1Caves" "Cluster_2Caves" "monitor_Cluster_1" "monitor_Cluster_2")
    
    for session in "${sessions[@]}"; do
        if screen -list | grep -q "$session"; then
            echo_info "  关闭会话: $session"
            screen -X -S "$session" quit 2>/dev/null
        fi
    done
    
    # 给予短暂延迟，确保进程完全关闭
    sleep 2

    cd "$steamcmd_dir" || fail
    ./steamcmd.sh +login anonymous +force_install_dir "$install_dir" +app_update 343050 validate +quit
    echo_success "服务器更新完成,请重新执行脚本"
    echo_info "正在执行MOD修复和依赖库"
    cp $HOME/steamcmd/linux32/steamclient.so $HOME/dst/bin/lib32/ 2>/dev/null
    cp $HOME/steamcmd/linux64/steamclient.so $HOME/dst/bin64/lib64/ 2>/dev/null
    cp $HOME/steamcmd/linux32/libstdc++.so.6 $HOME/dst/bin/lib32/ 2>/dev/null
    echo_success "已修复"
}

# 自动更新所有集群的模组
function AddAutoUpdateMod() {
    local clusters=("1" "2")  # 定义要处理的集群列表
    local modTotal
    local modID
    local processed_count=0  # 记录成功处理的集群数量

    local mods_file="$HOME/dst/mods/dedicated_server_mods_setup.lua"
    
    echo_info "开始自动更新所有集群的模组配置..."
    echo "============================================"

    # 依次处理每个集群
    for cluster_choice in "${clusters[@]}"; do
        local cluster_file
        if [[ "$cluster_choice" -eq 1 ]]; then
            cluster_file="$HOME/.klei/DoNotStarveTogether/Cluster_1/Master/modoverrides.lua"
            echo_info "正在处理 Cluster_1 的模组配置..."
        elif [[ "$cluster_choice" -eq 2 ]]; then
            cluster_file="$HOME/.klei/DoNotStarveTogether/Cluster_2/Master/modoverrides.lua"
            echo_info "正在处理 Cluster_2 的模组配置..."
        fi

        # 检查模组配置文件是否存在
        if [ ! -f "$cluster_file" ]; then
            echo_warning "⚠️  模组配置文件不存在: $cluster_file"
            continue  # 跳过不存在的文件，继续处理下一个集群
        fi

        # 统计模组数量
        modTotal=$(grep -c 'workshop-' "$cluster_file" 2>/dev/null || echo "0")

        if [[ $modTotal -eq 0 ]]; then
            echo_warning "  在 Cluster_$cluster_choice 中没有发现模组"
            continue
        fi

        echo_success "  发现 $modTotal 个模组"

        local added_count=0  # 记录本次添加的模组数量
        local skipped_count=0  # 记录跳过的模组数量

        # 处理每个模组
        for item in $(seq "$modTotal"); do
            modID=$(grep 'workshop-' "$cluster_file" | cut -d '"' -f2 | sed 's#workshop-##g' | awk "NR==$item{print \$0}")

            if [[ -z "$modID" ]]; then
                continue  # 跳过空的模组ID
            fi

            if [[ $(grep -c "$modID" "$mods_file" 2>/dev/null) -eq 0 ]]; then
                echo "        ServerModSetup(\"$modID\")" >> "$mods_file"
                echo_success "  ✅ 添加模组: $modID"
                ((added_count++))
            else
                echo_warning "  ⚠️ 模组已存在: $modID"
                ((skipped_count++))
            fi
        done

        echo_success "  Cluster_$cluster_choice 处理完成: 新增 $added_count 个模组, 跳过 $skipped_count 个已存在模组"
        echo "--------------------------------------------"
        ((processed_count++))
    done

    # 显示最终结果
    echo "============================================"
    if [[ $processed_count -gt 0 ]]; then
        echo_success "✅ 模组配置更新完成! 成功处理了 $processed_count 个集群"
        echo_info "📁 模组配置文件位置: $mods_file"
    else
        echo_warning "⚠️  未找到任何可处理的模组配置"
        echo_info "💡 提示: 请确保存档中已启用模组并保存配置"
    fi
    
    sleep 2s
}

# 启动服务器
function start_server() {
    local cluster=$1
    local shard=$2
    local screen_name="$cluster$shard"
    local token_file="$HOME/.klei/DoNotStarveTogether/$cluster/cluster_token.txt"
    local cluster_dir="$HOME/.klei/DoNotStarveTogether/$cluster"
    
     # 获取当前版本配置
    local current_version=$(get_current_version)
    
    # 检查64位版本是否存在
    local has_64bit=0
    if [ -f "$HOME/dst/bin64/dontstarve_dedicated_server_nullrenderer_x64" ]; then
        has_64bit=1
    fi
    
    # 选择版本
    local version_choice=""
    
    # 如果配置为64位但64位程序不存在，自动降级为32位
    if [ "$current_version" = "64" ] && [ $has_64bit -eq 0 ]; then
        echo_warning "⚠️  64位版本不存在，自动使用32位版本启动"
        version_choice="32"
    else
        version_choice="$current_version"
    fi
    
    # 根据版本设置目录和可执行文件
    local bin_dir=""
    local exec_file=""
    
    if [ "$version_choice" = "64" ]; then
        bin_dir="$HOME/dst/bin64/"
        exec_file="./dontstarve_dedicated_server_nullrenderer_x64"
        echo_info "使用64位版本启动服务器"
    else
        bin_dir="$HOME/dst/bin/"
        exec_file="./dontstarve_dedicated_server_nullrenderer"
        echo_info "使用32位版本启动服务器"
    fi

    # 创建集群目录（如果不存在）
    if [ ! -d "$cluster_dir" ]; then
        echo_info "📁 集群目录不存在，正在创建: $cluster_dir"
        mkdir -p "$cluster_dir" || {
            echo_error "✘ 无法创建集群目录: $cluster_dir"
            return 1
        }
        echo_success "✔ 集群目录创建成功！"
    fi

    #启动前更新模组配置
    AddAutoUpdateMod

    # 检查令牌文件
    if [[ ! -f "$token_file" ]] || [[ ! -s "$token_file" ]]; then
        echo_warning "⚠️ 令牌文件不存在或为空: $token_file"
        echo_info "📋 正在自动写入默认令牌..."
        
        # 创建令牌文件并写入默认令牌
        echo "pds-g^KU_L2d_1Kio^qUZS9ifsEfTU9c5WBE/1J/ULPaTNAon4ZoViMJb8S5c=" > "$token_file" || {
            echo_error "✘ 无法创建或写入令牌文件: $token_file"
            return 1
        }
        
        # 再次检查令牌文件
        if [[ ! -s "$token_file" ]]; then
            echo_error "✘ 令牌文件仍然为空，无法启动服务器"
            return 1
        fi
        
        echo_success "✔ 令牌文件已创建并写入默认令牌！"
    fi

    # 检查服务器是否已在运行
    if screen -list | grep -q "$screen_name"; then
        echo
        echo_warning "======================================"
        echo_warning "⚠️ $screen_name 服务器已经在运行."
        echo_warning "======================================"
        echo
        return 0
    fi

    # 启动服务器
    eval cd $bin_dir || {
        echo
        echo_error "======================================"
        echo_error "✘ 无法进入服务器目录: $bin_dir"
        echo_error "✘ 请检查是否已正确安装饥荒服务器程序"
        echo_error "======================================"
        echo
        return 1
    }
    
    echo_info "🚀 正在启动 $screen_name 服务器($version_choice位)..."
    screen -dmS "$screen_name" $exec_file console_enabled -cluster "$cluster" -shard "$shard"
    
    # 添加延迟确保进程创建
    sleep 2
    
    # 醒目显示启动结果
    if screen -list | grep -q "$screen_name"; then
        echo
        echo_success "=================================================="
        echo_success "✔✔✔ $screen_name 服务器($version_choice位)已成功启动! ✔✔✔"
        echo_success "=================================================="
        echo_success "📺 返回主菜单选项3可以查看已启动的服务器"
        echo_success "🛑 如果未找到程序，请查看服务器日志"
        echo_success "=================================================="
        echo
        
        # 返回0表示成功，让调用者知道应该跳出循环
        return 0
    else
        echo
        echo_error "=================================================="
        echo_error "✘✘✘ $screen_name 服务器启动失败! ✘✘✘"
        echo_error "=================================================="
        echo_error "❗ 请检查以下可能原因:"
        echo_error "  1. 饥荒程序是否正确安装"
        echo_error "  2. 存档配置目录是否存在"
        echo_error "  3. 系统资源是否充足"
        echo_error "=================================================="
        echo
        return 1
    fi
}

# 备份存档
BackupSaves() {
    local backup_choice
    local backup_dirs="$HOME/.klei/DoNotStarveTogether/backups"
    local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    
    # 检查备份目录是否存在，不存在则创建
    if [ ! -d "$backup_dirs" ]; then
        echo_info "备份目录不存在，正在创建: $backup_dirs"
        mkdir -p "$backup_dirs" || {
            echo_error "无法创建备份目录: $backup_dirs"
            return 1
        }
        echo_success "备份目录创建成功！"
    fi

    while true; do
        echo "============================================"
        echo_info "备份前建议关闭世界！"
        echo_info "请选择要备份的存档:"
        echo "1. 备份 Cluster_1 存档"
        echo "2. 备份 Cluster_2 存档"
        echo "0. 返回主菜单"

        read -p "输入您的选择 (0-2): " backup_choice

        case $backup_choice in
            1)
                echo_info "正在备份 Cluster_1 存档..."
                cd "$HOME/.klei/DoNotStarveTogether/Cluster_1" || { 
                    echo_error "无法进入目录: $HOME/.klei/DoNotStarveTogether/Cluster_1"
                    continue
                }
                local backup_file="$backup_dirs/Cluster_1_backup_$timestamp.tar.gz"
                tar -czf "$backup_file" . || {
                    echo_error "备份过程中出错"
                    continue
                }
                echo_success "备份完成，文件位置: $backup_file"
                ;;
            2)
                echo_info "正在备份 Cluster_2 存档..."
                cd "$HOME/.klei/DoNotStarveTogether/Cluster_2" || { 
                    echo_error "无法进入目录: $HOME/.klei/DoNotStarveTogether/Cluster_2"
                    continue
                }
                local backup_file="$backup_dirs/Cluster_2_backup_$timestamp.tar.gz"
                tar -czf "$backup_file" . || {
                    echo_error "备份过程中出错"
                    continue
                }
                echo_success "备份完成，文件位置: $backup_file"
                ;;
            0)
                break
                ;;
            *)
                echo_error "无效选择. 请重试."
                ;;
        esac
    done
}

RestoreSaves() {
    # 自动查找备份文件
    local backup_files=()
    local backup_dirs="$HOME/.klei/DoNotStarveTogether/backups"
    
    echo_info "正在扫描备份文件..."
    for dir in "${backup_dirs[@]}"; do
        if [ -d "$dir" ]; then
            while IFS= read -r -d $'\0' file; do
                backup_files+=("$file")
            done < <(find "$dir" -maxdepth 3 -type f \( -name "*.tar.gz" -o -name "*.zip" \) -print0 2>/dev/null)
        fi
    done
    
    # 如果没有找到备份文件
    if [ ${#backup_files[@]} -eq 0 ]; then
        echo_error "未找到任何备份文件。请确保备份文件位于以下位置:"
        echo "  - $HOME/.klei/DoNotStarveTogether/backups"
        read -p "按回车键返回主菜单..."
        return
    fi
    
    # 检查并自动安装 unzip（用于解压 .zip 文件）
    local unzip_installed=true
    if ! command -v unzip &> /dev/null; then
        unzip_installed=false
        echo_warning "未找到 unzip 工具，正在尝试自动安装..."
        
        # 根据不同的包管理器尝试安装
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y unzip
        elif command -v yum &> /dev/null; then
            sudo yum install -y unzip
        else
            echo_error "无法自动安装 unzip，请手动安装后再试"
            echo "在 Debian/Ubuntu 系统上使用: sudo apt install unzip"
            echo "在 RedHat/CentOS 系统上使用: sudo yum install unzip"
            read -p "按回车键继续..."
        fi
        
        # 再次检查是否安装成功
        if command -v unzip &> /dev/null; then
            unzip_installed=true
            echo_success "unzip 安装成功！"
        else
            echo_error "unzip 安装失败，请手动安装"
        fi
    fi
    
    while true; do
        echo "============================================"
        echo_info "请选择要恢复的存档文件:"
        echo "0. 返回主菜单"
        
        # 显示备份文件列表
        local i=1
        for file in "${backup_files[@]}"; do
            local filename=$(basename "$file")
            local filesize=$(du -h "$file" | cut -f1)
            local filedate=$(date -r "$file" "+%Y-%m-%d %H:%M")
            
            # 标记无法处理的 .zip 文件
            if [[ "$filename" == *.zip ]] && ! $unzip_installed; then
                printf "%2d) %-45s %6s %s [需要 unzip]\n" "$i" "$filename" "$filesize" "$filedate"
            else
                printf "%2d) %-45s %6s %s\n" "$i" "$filename" "$filesize" "$filedate"
            fi
            ((i++))
        done
        
        # 让用户选择文件
        read -p "输入文件编号 (0-${#backup_files[@]}): " file_choice
        
        # 检查输入是否有效
        if [[ "$file_choice" == "0" ]]; then
            return
        elif [[ "$file_choice" =~ ^[0-9]+$ ]] && [ "$file_choice" -ge 1 ] && [ "$file_choice" -le ${#backup_files[@]} ]; then
            local backup_path="${backup_files[$((file_choice-1))]}"
            
            # 检查 .zip 文件是否需要 unzip
            if [[ "$backup_path" == *.zip ]] && ! $unzip_installed; then
                echo_error "无法解压 .zip 文件，因为 unzip 未安装"
                read -p "按回车键继续..."
                continue
            fi
            
            # 自动检测存档类型
            local cluster_type=""
            if [[ "$backup_path" == *"Cluster_1"* ]]; then
                cluster_type="Cluster_1"
            elif [[ "$backup_path" == *"Cluster_2"* ]]; then
                cluster_type="Cluster_2"
            else
                # 无法自动识别，让用户选择
                echo "无法识别存档类型，请手动选择恢复到:"
                echo "1. Cluster_1"
                echo "2. Cluster_2"
                read -p "输入您的选择 (1-2): " cluster_choice
                
                case $cluster_choice in
                    1) cluster_type="Cluster_1" ;;
                    2) cluster_type="Cluster_2" ;;
                    *) 
                        echo_error "无效选择"
                        continue
                        ;;
                esac
            fi
            
            local target_dir="$HOME/.klei/DoNotStarveTogether/$cluster_type"
            
            # 确认操作
            echo_warning "警告：这将覆盖 $target_dir 中的现有存档！"
            read -p "确认恢复存档？(y/n): " confirm
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                echo_info "恢复操作已取消"
                continue
            fi

            #删除旧存档
            rm -rf "$target_dir/Master/save"/*
            rm -rf "$target_dir/Caves/save"/*

            # 添加延迟确保存档已删除
            sleep 3
            
            # 创建目标目录（如果不存在）
            mkdir -p "$target_dir"
            
            # 执行恢复操作
            echo_info "正在恢复 $cluster_type 存档..."
            
            if [[ "$backup_path" == *.tar.gz ]]; then
                tar -xzf "$backup_path" -C "$target_dir"
            elif [[ "$backup_path" == *.zip ]]; then
                unzip -o "$backup_path" -d "$target_dir"
            fi
            
            # 检查恢复是否成功
            if [ $? -eq 0 ]; then
                echo
                echo_success "=================================================="
                echo_success "✔✔✔ 存档恢复成功！ ✔✔✔"
                echo_success "=================================================="
                echo_success "🛑 恢复位置: $target_dir"
                echo_success "=================================================="
                echo
                read -p "按回车键继续..."
            else
                echo
                echo_success "=================================================="
                echo_success "✘✘✘ 恢复过程中出错！ ✘✘✘"
                echo_success "=================================================="
                echo
                read -p "按回车键继续..."
            fi
        else
            echo_error "无效选择，请输入 0-${#backup_files[@]} 之间的数字"
        fi
    done
}

# 删除存档
function DeleteSaves() {
    local cluster_choice
    while true; do
        echo "============================================"
        echo_info "请选择要删除的存档:"
        echo "1. 删除 Cluster_1 存档"
        echo "2. 删除 Cluster_2 存档"
        echo "0. 返回上一级菜单"

        read -p "输入您的选择 (0-2): " cluster_choice
        if [[ "$cluster_choice" =~ ^[0-2]$ ]]; then
            if [[ "$cluster_choice" -eq 0 ]]; then
                return
            fi

            case $cluster_choice in
                1)
                    echo_info "正在删除 Cluster_1 存档..."
                    rm -rf "$HOME/.klei/DoNotStarveTogether/Cluster_1/Master/save"/*
                    rm -rf "$HOME/.klei/DoNotStarveTogether/Cluster_1/Caves/save"/*
                    echo_success "Cluster_1 存档已删除."
                    ;;
                2)
                    echo_info "正在删除 Cluster_2 存档..."
                    rm -rf "$HOME/.klei/DoNotStarveTogether/Cluster_2/Master/save"/*
                    rm -rf "$HOME/.klei/DoNotStarveTogether/Cluster_2/Caves/save"/*
                    echo_success "Cluster_2 存档已删除."
                    ;;
                0)
                    break
                    ;;
            esac
        else
            echo_error "无效选择. 请重试."
        fi
    done
}

# 设置服务器维护任务函数
function setup_maintenance_task() {
    local hour=""
    
    # 获取当前小时作为默认值
    local default_hour=$(date +%H)
    
    echo_info "🕒🕒 设置服务器维护任务"
    echo_info "维护任务包括："
    echo "  - 维护前5分钟发送公告"
    echo "  - 维护前2分钟自动保存"
    echo "  - 指定整点时间关闭所有服务器"
    echo "  - 维护后10分钟自动更新 SteamCMD"
    echo ""
    
    # 输入小时
    while true; do
        read -p "请输入维护时间的小时 (0-23) [默认: $default_hour]: " hour
        if [[ -z "$hour" ]]; then
            hour="$default_hour"
        fi
        
        if [[ "$hour" =~ ^[0-9]+$ ]] && [ "$hour" -ge 0 ] && [ "$hour" -le 23 ]; then
            break
        else
            echo_error "请输入0-23之间的有效数字"
        fi
    done
    
    # 固定分钟为0（整点）
    local minute="00"
    
    # 格式化时间显示
    local formatted_time=$(printf "%02d:%02d" "$hour" "$minute")
    
    # 计算提前时间（分钟固定为55和58）
    local announce_minute="55"
    local save_minute="58"
    local announce_hour=$((hour - 1))
    local save_hour=$((hour - 1))
    
    # 计算 SteamCMD 更新时间（维护后10分钟）
    local steamcmd_hour=$hour
    local steamcmd_minute="10"
    
    # 处理小时负数的情况（当hour=0时）
    if [ $announce_hour -lt 0 ]; then
        announce_hour=23
    fi
    
    if [ $save_hour -lt 0 ]; then
        save_hour=23
    fi
    
    # 显示设置信息
    echo ""
    echo_success "📋📋 维护任务计划如下："
    echo_success "  ⏰⏰ 维护时间: $formatted_time (整点)"
    echo_success "  📢📢 公告时间: $(printf "%02d:%02d" "$announce_hour" "$announce_minute") (提前5分钟)"
    echo_success "  💾💾 保存时间: $(printf "%02d:%02d" "$save_hour" "$save_minute") (提前2分钟)"
    echo_success "  🔄🔄 SteamCMD更新: $(printf "%02d:%02d" "$steamcmd_hour" "$steamcmd_minute") (维护后10分钟)"
    echo ""
    
    # 确认设置
    read -p "确认设置以上维护任务？(y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo_warning "已取消设置维护任务"
        return
    fi
    
    # 删除现有维护任务
    remove_maintenance_task silent
    
    # 添加新的cron任务
    local temp_cron=$(mktemp)
    crontab -l 2>/dev/null > "$temp_cron"
    
    # 添加公告任务
    echo "$announce_minute $announce_hour * * * if screen -list | grep -q 'Cluster_1Master'; then screen -S Cluster_1Master -p 0 -X stuff 'c_announce(\"服务器将于5分钟后维护重启\")\\n'; fi; if screen -list | grep -q 'Cluster_2Master'; then screen -S Cluster_2Master -p 0 -X stuff 'c_announce(\"服务器将于5分钟后维护重启\")\\n'; fi" >> "$temp_cron"
    
    # 添加保存任务
    echo "$save_minute $save_hour * * * if screen -list | grep -q 'Cluster_1Master'; then screen -S Cluster_1Master -p 0 -X stuff 'c_save()\\n'; fi; if screen -list | grep -q 'Cluster_2Master'; then screen -S Cluster_2Master -p 0 -X stuff 'c_save()\\n'; fi" >> "$temp_cron"
    
    # 添加关闭服务器任务
    # echo "$minute $hour * * * screen -X -S Cluster_1Master quit && screen -X -S Cluster_1Caves quit && screen -X -S Cluster_2Master quit && screen -X -S Cluster_2Caves quit" >> "$temp_cron"
    echo "$minute $hour * * * for session in Cluster_1Master Cluster_1Caves Cluster_2Master Cluster_2Caves; do screen -X -S \"\$session\" quit 2>/dev/null; done" >> "$temp_cron"
    
    # 添加 SteamCMD 更新任务（使用更简单的格式便于识别）
    echo "$steamcmd_minute $steamcmd_hour * * * cd $steamcmd_dir && ./steamcmd.sh +quit" >> "$temp_cron"
    
    # 安装新的cron任务
    crontab "$temp_cron"
    rm -f "$temp_cron"
    
    echo ""
    echo_success "=================================================="
    echo_success "✅ 服务器维护任务已成功设置！"
    echo_success "=================================================="
    echo_success "🕒🕒 维护时间: 每天 $formatted_time (整点)"
    echo_success "📢📢 提前公告: 每天 $(printf "%02d:%02d" "$announce_hour" "$announce_minute")"
    echo_success "💾💾 自动保存: 每天 $(printf "%02d:%02d" "$save_hour" "$save_minute")"
    echo_success "🛑🛑 服务器关闭: 每天 $formatted_time"
    echo_success "🔄🔄 SteamCMD更新: 每天 $(printf "%02d:%02d" "$steamcmd_hour" "$steamcmd_minute")"
    echo_success "=================================================="
    echo ""
    
    # 显示当前cron任务
    show_maintenance_status
}

# 显示所有任务
function show_maintenance_status() {
    echo_info "📋📋 当前维护任务状态:"
    
    local has_tasks=0
    local cron_list=$(crontab -l 2>/dev/null || echo "")
    
    if [[ -z "$cron_list" ]]; then
        echo_warning "  暂无维护任务"
        return
    fi
    
    # 查找维护相关任务
    while IFS= read -r line; do
        # 跳过空行和注释行
        if [[ -z "$line" || "$line" =~ ^# ]]; then
            continue
        fi
        
        # 提取cron时间部分和命令部分
        local cron_min=$(echo "$line" | awk '{print $1}')
        local cron_hour=$(echo "$line" | awk '{print $2}')
        local cron_cmd=$(echo "$line" | cut -d' ' -f6-)
        
        # 检查任务类型
        if [[ "$line" =~ c_announce ]]; then
            has_tasks=1
            echo_success "  📢📢 公告任务: $(printf "%02d:%02d" "${cron_hour:-0}" "${cron_min:-0}") 每天"
        elif [[ "$line" =~ c_save ]]; then
            has_tasks=1
            echo_success "  💾💾 保存任务: $(printf "%02d:%02d" "${cron_hour:-0}" "${cron_min:-0}") 每天"
        elif [[ "$line" =~ screen.*quit ]]; then
            has_tasks=1
            echo_success "  🛑🛑 关闭任务: $(printf "%02d:%02d" "${cron_hour:-0}" "${cron_min:-0}") 每天"
        elif [[ "$line" =~ steamcmd\.sh ]]; then
            has_tasks=1
            echo_success "  🔄🔄 SteamCMD更新: $(printf "%02d:%02d" "${cron_hour:-0}" "${cron_min:-0}") 每天"
        fi
    done <<< "$cron_list"
    
    if [[ $has_tasks -eq 0 ]]; then
        echo_warning "  暂无维护任务"
    fi
}

# 删除服务器维护任务函数
function remove_maintenance_task() {
    local silent="${1:-}"
    
    if [[ "$silent" != "silent" ]]; then
        echo_info "正在删除服务器维护任务..."
    fi
    
    # 创建临时cron文件，过滤掉维护任务
    local temp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -v -E '(Cluster_1Master|Cluster_2Master|服务器维护|steamcmd\.sh)' > "$temp_cron" || true
    
    # 如果文件为空，删除crontab
    if [[ ! -s "$temp_cron" ]]; then
        crontab -r 2>/dev/null || true
    else
        crontab "$temp_cron"
    fi
    
    rm -f "$temp_cron"
    
    if [[ "$silent" != "silent" ]]; then
        echo_success "✅ 所有服务器维护任务已删除"
        show_maintenance_status
    fi
}

# 监控崩溃重启
function ms_servers() {
    # 确保 ms.sh 存在
    local ms_script="$HOME/ms.sh"
    
    while true; do
        if [ -f "$ms_script" ]; then
            # 文件存在时确保有执行权限
            if [ ! -x "$ms_script" ]; then
                chmod +x "$ms_script"
                echo_success "已添加执行权限: $ms_script"
            fi
            break  # 文件已存在且权限正确，退出循环
        else
            echo_warning "监控脚本 ms.sh 不存在，正在下载..."
            if download "https://ghfast.top/https://raw.githubusercontent.com/xiaochency/dstsh/refs/heads/main/ms.sh" 5 10; then
                # 下载后验证文件是否真实存在
                if [ -f "$ms_script" ] && [ -s "$ms_script" ]; then
                    echo_success "已成功下载监控脚本 ms.sh"
                    chmod +x "$ms_script"
                    break  # 下载成功且文件存在，退出循环
                else
                    echo_error "下载失败：文件未正确创建或为空文件"
                    # 清理可能存在的无效文件
                    rm -f "$ms_script" 2>/dev/null
                fi
            else
                echo_error "下载失败，请检查网络或URL"
            fi
            
            read -p "是否重试下载？(y/n): " retry_choice
            if [ "$retry_choice" != "y" ]; then
                return 1
            fi
        fi
    done
    
    while true; do
        echo "============================================"
        echo_success "请选择要执行的操作:"
        echo "1. 监控Cluster_1崩溃重启"
        echo "2. 监控Cluster_2崩溃重启"
        echo "3. 关闭监控脚本"
        echo "4. 设置服务器维护任务"
        echo "5. 删除服务器维护任务"
        echo "6. 查看当前维护任务状态"
        echo "0. 返回主菜单"

        read -p "请输入选项 (0-6): " choice

        case $choice in
            1)
                # 调用独立的监控脚本
                bash "$ms_script" start 1
                ;;
            2)
                # 调用独立的监控脚本
                bash "$ms_script" start 2
                ;;
            3)
                echo_info "正在关闭监控脚本..."
                local closed_count=0
                
                # 查找并关闭所有监控会话
                for session in $(screen -list | grep -E "monitor_Cluster" | cut -d. -f1); do
                    screen -S "$session" -X quit
                    echo_success "已关闭监控会话: $session"
                    ((closed_count++))
                done
                
                if [ $closed_count -eq 0 ]; then
                    echo_warning "未找到运行中的监控会话"
                else
                    echo_success "✅ 已关闭 $closed_count 个监控会话"
                fi
                ;;
            4)
                setup_maintenance_task
                ;;
            5)
                remove_maintenance_task
                ;;
            6)
                show_maintenance_status
                ;;
            0)
                echo_info "返回主菜单..."
                return 0
                ;;
            *)
                echo_error "无效的选项,请重试。"
                ;;
        esac
        
        # 添加一个暂停，让用户看到操作结果
        read -p "按回车键继续..."
        echo ""
    done
}

# 发送公告函数
send_announcement() {
    local cluster_name="$1"
    read -p "请输入要发送的公告内容: " announcement

    local master_server="${cluster_name}Master"

    if [[ "$master_server" == "Cluster_1Master" || "$master_server" == "Cluster_2Master" ]]; then
        screen -S "$master_server" -X stuff "c_announce(\"$announcement\")\n"
        echo_success "公告已发送到 $cluster_name 的 Master 服务器。"
    else
        echo_error "无效的集群名称。"
    fi
}

# 回档服务器函数
rollback_server() {
    local cluster_name="$1"
    local rollback_count="$2"

    local master_server="${cluster_name}Master"

    if [[ "$master_server" == "Cluster_1Master" || "$master_server" == "Cluster_2Master" ]]; then
        echo_info "正在回档 $cluster_name 的 Master 服务器 $rollback_count 次..."
        screen -S "$master_server" -X stuff "c_rollback($rollback_count)\n"
        echo_success "$cluster_name 的 Master 服务器已尝试回档。"
    else
        echo_error "无效的集群名称。"
    fi
}

# 重置世界函数
regenerate_world() {
    local cluster_name="$1"
    
    local master_server="${cluster_name}Master"

    read -p "您确定要重置这个世界吗？(y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo_warning "已取消."
        return
    fi
    
    if [[ "$master_server" == "Cluster_1Master" || "$master_server" == "Cluster_2Master" ]]; then
        echo_info "正在重置 $cluster_name 的世界..."
        screen -S "$master_server" -X stuff "c_regenerateworld()\n"
        echo_success "$cluster_name 的世界重置指令已发送。"
    else
        echo_error "无效的集群名称。"
    fi
}

# 拉黑玩家函数
ban_player() {
    local cluster_name="$1"
    read -p "请输入要拉黑的玩家 ID (userid): " userid

    if [[ -z "$userid" ]]; then
        echo_error "玩家 ID 不能为空。"
        return 1
    fi

    local master_server="${cluster_name}Master"

    if [[ "$master_server" == "Cluster_1Master" || "$master_server" == "Cluster_2Master" ]]; then
        echo_info "正在拉黑 $cluster_name 的 Master 服务器上的玩家 $userid..."
        screen -S "$master_server" -X stuff "TheNet:Ban(\"$userid\")\n"
        echo_success "已尝试在 $cluster_name 的 Master 服务器上拉黑玩家 $userid。"
    else
        echo_error "无效的集群名称。"
    fi
}

# 服务器控制台函数
server_console() {
    while true; do
        echo "============================================"
        echo_info "服务器控制台"
        echo "请选择一个选项:"
        echo "1. 发送服务器公告"
        echo "2. 服务器回档"
        echo "3. 拉黑玩家"
        echo "4. 服务器重置世界"
        echo "0. 返回主菜单"

        read -p "输入您的选择 (0-4): " console_choice
        case $console_choice in
            1)
                while true; do
                    echo_info "请选择要发公告的服务器:"
                    echo "1. Cluster_1"
                    echo "2. Cluster_2"
                    echo "0. 返回服务器控制台"
                    read -p "输入您的选择 (0-2): " announce_choice
                    case $announce_choice in
                        1) send_announcement "Cluster_1" ;;
                        2) send_announcement "Cluster_2" ;;
                        0) break ;;
                        *) echo_error "无效选择. 请重试." ;;
                    esac
                done
                ;;
            2)
                while true; do
                    echo_info "请选择要回档的服务器:"
                    echo "1. Cluster_1"
                    echo "2. Cluster_2"
                    echo "0. 返回服务器控制台"
                    read -p "输入您的选择 (0-2): " rollback_choice
                    case $rollback_choice in
                        1)
                            read -p "请输入回档次数: " rollback_count
                            rollback_server "Cluster_1" "$rollback_count"
                            ;;
                        2)
                            read -p "请输入回档次数: " rollback_count
                            rollback_server "Cluster_2" "$rollback_count"
                            ;;
                        0) break ;;
                        *) echo_error "无效选择. 请重试." ;;
                    esac
                done
                ;;
            3)
                while true; do
                    echo_info "请选择要拉黑玩家的服务器:"
                    echo "1. Cluster_1"
                    echo "2. Cluster_2"
                    echo "0. 返回服务器控制台"
                    read -p "输入您的选择 (0-2): " ban_choice
                    case $ban_choice in
                        1) ban_player "Cluster_1" ;;
                        2) ban_player "Cluster_2" ;;
                        0) break ;;
                        *) echo_error "无效选择. 请重试." ;;
                    esac
                done
                ;;
            4)
                while true; do
                    echo_info "请选择要重置世界的服务器:"
                    echo "1. Cluster_1"
                    echo "2. Cluster_2"
                    echo "0. 返回服务器控制台"
                    read -p "输入您的选择 (0-2): " regenerate_world
                    case $regenerate_world in
                        1)
                            regenerate_world "Cluster_1" "$regenerate_world"
                            ;;
                        2)
                            regenerate_world "Cluster_2" "$regenerate_world"
                            ;;
                        0) break ;;
                        *) echo_error "无效选择. 请重试." ;;
                    esac
                done
                ;; 
            0) break ;;
            *) echo_error "无效选择. 请重试." ;;
        esac
    done
}

# 保存服务器函数
shutdown_server() {
    while true; do
        echo "============================================"
        echo_info "请选择一个选项:"
        echo "1. 关闭Cluster_1服务器"
        echo "2. 关闭Cluster_2服务器"
        echo "0. 返回主菜单"
        echo_warning "在关闭服务器前会自动保存！"

        read -p "输入您的选择 (0-2): " view_choice
        case $view_choice in
            1)
                echo_info "正在保存Cluster_1服务器.."
                screen -X -S Cluster_1Master stuff "c_save()\n"
                sleep 6
                echo_info "正在关闭Cluster_1服务器.."
                screen -X -S Cluster_1Master quit
                screen -X -S Cluster_1Caves quit
                echo_success "Cluster_1服务器已关闭."
                ;;
            2)
                echo_info "正在保存Cluster_2服务器.."
                screen -X -S Cluster_2Master stuff "c_save()\n"
                sleep 6
                echo_info "正在关闭Cluster_2服务器.."
                screen -X -S Cluster_2Master quit
                screen -X -S Cluster_2Caves quit
                echo_success "Cluster_2服务器已关闭."
                ;;
            0)
                break
                ;;
            *)
                echo_error "无效选择. 请重试."
                ;;
        esac
    done
}

# 获取公网IP函数
function get_public_ip() {
    local ip_file="$HOME/.dst_public_ip"
    local public_ip=""
    
    # 检查IP文件是否存在且不为空
    if [[ -f "$ip_file" && -s "$ip_file" ]]; then
        public_ip=$(cat "$ip_file" | head -n1 | tr -d '\n\r')
        echo_info "从缓存读取公网IP: $public_ip"
        echo "$public_ip"
        return 0
    fi
    
    # 如果缓存中没有IP，则重新获取
    echo_info "正在获取本机公网IP..."
    
    # 尝试多个获取公网IP的源
    local ip_sources=(
        "https://checkip.amazonaws.com"
        "https://v4.ident.me"
    )
    
    for source in "${ip_sources[@]}"; do
        public_ip=$(curl -s --connect-timeout 5 "$source" 2>/dev/null | tr -d '\n\r')
        
        # 验证IP格式（简单的IPv4验证）
        if [[ "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo_success "成功获取公网IP: $public_ip (来源: $source)"
            
            # 保存到文件
            echo "$public_ip" > "$ip_file"
            chmod 600 "$ip_file" 2>/dev/null || true
            
            echo "$public_ip" | tr -d '\n\r' | head -1
            return 0
        fi
        
        sleep 1  # 避免请求过快
    done
    
    # 所有源都失败
    echo_warning "无法获取公网IP，请检查网络连接"
    echo "未知" > "$ip_file"  # 保存未知状态
    echo "未知"
    return 1
}

# 强制更新公网IP函数
function force_update_public_ip() {
    local ip_file="$HOME/.dst_public_ip"
    rm -f "$ip_file" 2>/dev/null
    echo_info "已清除IP缓存，下次将重新获取公网IP"
}

# 服务器状态
function show_server_status() {
    echo "=== 当前服务器状态 ==="
    local clusters=("Cluster_1" "Cluster_2")
    local shards=("Master" "Caves")
    
    # 记录集群运行状态
    local cluster1_running=0
    local cluster2_running=0
    
    for cluster in "${clusters[@]}"; do
        for shard in "${shards[@]}"; do
            local screen_name="${cluster}${shard}"
            if screen -list | grep -q "$screen_name"; then
                echo "✅ ${cluster}.${shard} - 运行中"
                # 设置集群运行状态
                if [[ "$cluster" == "Cluster_1" ]]; then
                    cluster1_running=1
                else
                    cluster2_running=1
                fi
            else
                echo "❌ ${cluster}.${shard} - 未运行"
            fi
        done
    done
    echo "===================="
    
    # 如果没有集群运行，直接返回
    if [[ $cluster1_running -eq 0 && $cluster2_running -eq 0 ]]; then
        echo_warning "没有检测到运行中的服务器，跳过直连信息显示"
        return
    fi
    
    # 使用新的IP获取函数
    local A1
    A1=$(get_public_ip)
    
    if [[ "$A1" == "未知" ]]; then
        echo_warning "无法获取公网IP，请检查网络连接"
        echo_info "提示：可以尝试在'其他选项'中强制更新IP缓存"
    else
        echo_success "本机公网IP: $A1 (缓存)"
        echo_info "💡 如需更新IP缓存，请在'其他选项'中选择强制更新"
    fi

    echo
    echo "=== 存档直连信息 ==="
    
    # 修复IP地址清理逻辑
    local clean_A1=""
    if [[ "$A1" != "未知" ]]; then
        # 更严格的IP地址提取
        clean_A1=$(echo "$A1" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        
        if [[ -z "$clean_A1" ]]; then
            # 如果正则提取失败，使用更简单的方法
            clean_A1=$(echo "$A1" | tr -cd '0-9.' | sed 's/\.\.*/./g' | sed 's/^\.//' | sed 's/\.$//')
            # 再次验证
            if ! [[ "$clean_A1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                echo_warning "IP地址格式仍然不正确，使用原始值: $A1"
                clean_A1="$A1"
            fi
        fi
    else
        clean_A1="未知"
    fi

    # 检查Cluster_1的配置
    local server_ini_file="$HOME/.klei/DoNotStarveTogether/Cluster_1/Master/server.ini"
    local A2="10999"  # 默认端口
    
    if [[ -f "$server_ini_file" ]]; then
        local port_line=$(grep -E '^server_port\s*=' "$server_ini_file" | head -1)
        if [[ -n "$port_line" ]]; then
            A2=$(echo "$port_line" | sed 's/.*=\s*//' | tr -d ' ')
        else
            echo_warning "Cluster_1未找到server_port配置,使用默认端口10999"
        fi
    else
        echo_warning "Cluster_1的server.ini文件不存在,使用默认端口10999"
    fi
    
    # 检查Cluster_2的配置
    local server_ini_file2="$HOME/.klei/DoNotStarveTogether/Cluster_2/Master/server.ini"
    local B2="10999"  # 默认端口
    
    if [[ -f "$server_ini_file2" ]]; then
        local port_line2=$(grep -E '^server_port\s*=' "$server_ini_file2" | head -1)
        if [[ -n "$port_line2" ]]; then
            B2=$(echo "$port_line2" | sed 's/.*=\s*//' | tr -d ' ')
        else
            echo_warning "Cluster_2未找到server_port配置,使用默认端口10999"
        fi
    else
        echo_warning "Cluster_2的server.ini文件不存在,使用默认端口10999"
    fi

    # 清理端口号
    local clean_A2=$(echo "$A2" | tr -cd '0-9')
    local clean_B2=$(echo "$B2" | tr -cd '0-9')
    
    # 如果端口为空，使用默认值
    [[ -z "$clean_A2" ]] && clean_A2="10999"
    [[ -z "$clean_B2" ]] && clean_B2="10999"

    # 打印直连命令
    if [[ "$clean_A1" != "未知" ]]; then
        echo
        echo_success "════════════════════════════════════════════"
        
        # 构建直连命令
        local connect_cmd1=$(printf 'c_connect("%s", %s)' "$clean_A1" "$clean_A2")
        local connect_cmd2=$(printf 'c_connect("%s", %s)' "$clean_A1" "$clean_B2")
        
        # Cluster_1 显示
        if [[ $cluster1_running -eq 1 ]]; then
            echo_success "📡 Cluster_1 [🟢 运行中]"
            echo "$connect_cmd1"
            echo  # 空行分隔
        else
            echo_warning "📡 Cluster_1 [🔴 未运行]"
            echo "$connect_cmd1 (服务器未运行)"
            echo
        fi
        
        # Cluster_2 显示
        if [[ $cluster2_running -eq 1 ]]; then
            echo_success "📡 Cluster_2 [🟢 运行中]"
            echo "$connect_cmd2"
            echo  # 空行分隔
        else
            echo_warning "📡 Cluster_2 [🔴 未运行]"
            echo "$connect_cmd2 (服务器未运行)"
            echo
        fi
        
        echo_success "════════════════════════════════════════════"
        echo_info "💡 在游戏大厅界面按 ~ 键打开控制台"
        echo_info "💡 输入以上命令即可直连服务器"
    fi
}

# 修改端口
function change_dst_port() {
    while true; do
        echo "=== DST服务器端口修改工具 ==="
        
        # 选择要修改的集群
        echo "请选择要修改的存档："
        echo "1) Cluster_1"
        echo "2) Cluster_2"
        echo "0) 返回上一级"
        read -p "请输入选择 (0-2): " cluster_choice
        
        case $cluster_choice in
            0)
                echo "返回上一级菜单。"
                return 0
                ;;
            1) 
                cluster="Cluster_1"
                break
                ;;
            2) 
                cluster="Cluster_2"
                break
                ;;
            *) 
                echo_error "无效选择，请重新输入"
                echo ""
                ;;
        esac
    done
    
    while true; do
        # 选择要修改的服务器类型
        echo ""
        echo "请选择要修改的服务器："
        echo "1) 地面服务器 (Master)"
        echo "2) 洞穴服务器 (Caves)" 
        echo "0) 返回上一级"
        read -p "请输入选择 (0-2): " server_choice
        
        case $server_choice in
            0)
                echo "返回上一级菜单。"
                return 0
                ;;
            1|2)
                break
                ;;
            *)
                echo_error "无效选择，请重新输入"
                ;;
        esac
    done
    
    # 定义服务器配置文件路径
    master_file="$HOME/.klei/DoNotStarveTogether/${cluster}/Master/server.ini"
    caves_file="$HOME/.klei/DoNotStarveTogether/${cluster}/Caves/server.ini"
    
    # 根据选择的服务器类型获取对应的当前端口号
    current_port=""
    config_file=""
    
    case $server_choice in
        1)
            config_file="$master_file"
            server_type="地面服务器"
            ;;
        2)
            config_file="$caves_file" 
            server_type="洞穴服务器"
            ;;
    esac
    
    # 获取正确的当前端口号
    if [ -f "$config_file" ]; then
        current_port=$(grep "^server_port" "$config_file" 2>/dev/null | head -1 | awk -F'=' '{print $2}' | tr -d ' ')
        if [ -n "$current_port" ]; then
            echo "$server_type 当前端口号: $current_port"
        else
            echo "$server_type 当前未设置端口号"
        fi
    else
        echo_error "配置文件不存在: $config_file"
        echo "请先确保 $server_type 已正确配置。"
        return 1
    fi
    
    # 输入新的端口号
    echo ""
    read -p "请输入新的端口号 (输入0返回上一级): " new_port
    
    # 检查是否返回上一级
    if [ "$new_port" = "0" ]; then
        echo "返回上一级菜单。"
        return 0
    fi
    
    # 仅验证端口号是否为数字
    if ! [[ "$new_port" =~ ^[0-9]+$ ]]; then
        echo_error "端口号必须是数字"
        return 1
    fi
    
    # 根据选择修改相应的配置文件
    case $server_choice in
        1)
            modify_server_port "$master_file" "$new_port" "地面服务器"
            ;;
        2)
            modify_server_port "$caves_file" "$new_port" "洞穴服务器"
            ;;
        *)
            echo_error "无效选择"
            return 1
            ;;
    esac
    
    echo_success "端口修改完成！新端口号: $new_port"
    echo "请重启DST服务器使更改生效。"
}

# 辅助函数：修改单个服务器的端口
function modify_server_port() {
    local config_file="$1"
    local new_port="$2"
    local server_type="$3"
    
    echo ""
    echo "正在修改 $server_type 端口..."
    
    # 检查配置文件是否存在
    if [ ! -f "$config_file" ]; then
        echo_error "配置文件不存在: $config_file"
        echo "请先确保 $server_type 已正确配置。"
        return 1
    fi
    
    # 直接修改端口号
    if sed -i "2s/server_port = [0-9]*/server_port = $new_port/" "$config_file" 2>/dev/null; then
        echo_success "$server_type 端口修改成功"
    else
        echo_error "$server_type 端口修改失败"
        return 1
    fi
}

# 安装steam加速器
function install_steam302() {
    local download_urls=(
        "https://gh-proxy.net/github.com/xiaochency/dstsh/releases/download/1st/Steamcommunity_302.tar.gz"
        "https://github.dpik.top/github.com/xiaochency/dstsh/releases/download/1st/Steamcommunity_302.tar.gz"
        "https://ghfast.top/github.com/xiaochency/dstsh/releases/download/1st/Steamcommunity_302.tar.gz"
    )
    
    local mirror_names=(
        "镜像源1 (gh-proxy.net)"
        "镜像源2 (github.dpik.top)" 
        "镜像源3 (ghfast.top)"
    )
    
    echo "开始安装 steam302..."
    
    # 检查当前目录下是否已存在Steamcommunity_302文件
    if [ -e "Steamcommunity_302.tar.gz" ]; then
        echo_warning "检测到当前目录下已存在Steamcommunity_302文件，正在删除..."
        rm -f "Steamcommunity_302.tar.gz"
        echo_success "已删除现有Steamcommunity_302文件"
    fi
    if [ -d "Steamcommunity_302" ]; then
        echo_warning "检测到当前目录下已存在Steamcommunity_302文件夹，正在删除..."
        rm -rf "Steamcommunity_302"
        echo_success "已删除现有Steamcommunity_302文件夹"
    fi
    
    # 显示镜像源选择菜单
    echo "请选择下载镜像源："
    for i in "${!mirror_names[@]}"; do
        echo_success "$((i+1)). ${mirror_names[i]}"
    done
    
    local selected_mirror
    while true; do
        read -p "请输入选择 [1-3]: " selected_mirror
        
        case $selected_mirror in
            1|2|3)
                break
                ;;
            *)
                echo_error "无效选择，请输入 1-3 之间的数字"
                ;;
        esac
    done
    
    local download_success=false
    local output_file="Steamcommunity_302.tar.gz"
    
    # 使用选择的镜像源
    local mirror_index=$((selected_mirror-1))
    echo "使用镜像源：${mirror_names[mirror_index]}"
    echo "下载链接: ${download_urls[mirror_index]}"
    
    if download "${download_urls[mirror_index]}" 3 15 "$output_file"; then
        echo_success "镜像源 $selected_mirror 下载成功"
        
        # 文件验证步骤
        echo "验证下载的文件完整性..."
        
        # 1. 检查文件是否存在
        if [ ! -f "$output_file" ]; then
            echo_error "错误：下载的文件不存在"
            return 1
        fi
        
        # 2. 检查文件大小
        file_size=$(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file" 2>/dev/null || echo "0")
        if [ "$file_size" -lt 1000 ]; then
            echo_error "错误：下载的文件大小异常（$file_size 字节），可能下载失败"
            rm -f "$output_file"
            return 1
        fi
        
        # 3. 测试压缩包完整性
        if ! tar -tzf "$output_file" >/dev/null 2>&1; then
            echo_error "错误：压缩文件损坏或格式不正确"
            rm -f "$output_file"
            return 1
        fi
        
        echo_success "文件验证通过，开始解压..."
        if ! tar -zxvf "$output_file"; then
            echo_error "错误：解压失败，文件可能已损坏"
            rm -f "$output_file"
            return 1
        fi
        
        download_success=true
        
        echo_success "✅ Steamcommunity_302 安装完成！"
    else
        echo_error "镜像源 $selected_mirror 下载失败"
        return 1
    fi
}

# 启动Steamcommunity 302服务
function start_steam302() {
    local target_dir="Steamcommunity_302"
    local executable_file="./steamcommunity_302.cli"
    local screen_session_name="steam302"

    echo "正在启动Steamcommunity 302服务..."

    # 检查目标目录是否存在
    if [ ! -d "$target_dir" ]; then
        echo_error "错误：目录 '$target_dir' 不存在，请确认该目录已正确下载或创建。"
        return 1
    fi

    # 进入目标目录
    cd "$target_dir" || {
        echo_error "错误：无法进入目录 '$target_dir'。"
        return 1
    }

    echo_success "已成功进入目录: $(pwd)"

    # 检查可执行文件是否存在
    if [ ! -f "$executable_file" ]; then
        echo_error "错误：可执行文件 '$executable_file' 不存在，请确认该文件已正确下载或编译。"
        echo "提示：请确保已在当前目录下运行，并且文件具有可执行权限。"
        cd - > /dev/null  # 返回原目录
        return 1
    fi

    # 检查文件是否具有可执行权限
    if [ ! -x "$executable_file" ]; then
        echo_warning "警告：文件 '$executable_file' 没有可执行权限，正在尝试添加..."
        chmod +x "$executable_file"
        if [ $? -ne 0 ]; then
            echo_error "错误：无法为文件添加可执行权限。"
            cd - > /dev/null  # 返回原目录
            return 1
        fi
        echo_success "已成功添加可执行权限。"
    fi

    # 检查screen命令是否可用
    if ! command -v screen &> /dev/null; then
        echo_error "错误：系统未安装screen命令，无法创建后台会话。"
        echo "提示：您可以尝试安装screen：sudo apt install screen"
        cd - > /dev/null  # 返回原目录
        return 1
    fi

    # 检查是否已存在同名的screen会话
    if screen -list | grep -q "$screen_session_name"; then
        echo_warning "警告：已存在名为 '$screen_session_name' 的screen会话。"
        read -p "是否要重新启动该服务？[y/N] " restart_choice
        case $restart_choice in
            [Yy]*)
                echo "正在停止现有的screen会话..."
                screen -S "$screen_session_name" -X quit
                sleep 1
                ;;
            *)
                echo "已取消启动操作。"
                cd - > /dev/null  # 返回原目录
                return 0
                ;;
        esac
    fi

    # 使用screen创建后台会话并运行程序
    echo "正在创建screen会话 '$screen_session_name' 并启动程序..."
    screen -dmS "$screen_session_name" "$executable_file"

    if [ $? -eq 0 ]; then
        echo_success "✓ Steamcommunity 302服务已成功启动并运行在后台！"
        echo "提示："
        echo "  1. 要查看程序输出，请运行：screen -r $screen_session_name"
        echo "  2. 要退出查看模式但不停止程序，请按 Ctrl+A 然后按 D"
        echo "  3. Steamcommunity 302服务会占用80端口"
    else
        echo_error "错误：无法启动Steamcommunity 302服务，请检查screen配置。"
        cd - > /dev/null  # 返回原目录
        return 1
    fi

    # 返回原目录
    cd - > /dev/null
}

# 停止Steamcommunity 302服务
function stop_steam302() {
    local screen_session_name="steam302"
    
    echo "正在停止Steamcommunity 302服务..."
    
    # 检查是否存在指定的screen会话
    if screen -list | grep -q "$screen_session_name"; then
        echo_warning "正在停止screen会话: $screen_session_name"
        screen -S "$screen_session_name" -X quit
        echo_success "✓ Steamcommunity 302服务已停止。"
    else
        echo_success "✓ Steamcommunity 302服务未在运行。"
    fi
}

# Steam加速器管理菜单
function manage_steam302() {
    while true; do
        clear
        echo_success "================================================"
        echo_success "           Steam加速器管理"
        echo_success "================================================"
        echo "1. 安装Steamcommunity 302"
        echo "2. 启动Steamcommunity 302服务"
        echo "3. 停止Steamcommunity 302服务"
        echo "0. 返回上一级"
        echo_success "================================================"

        read -p "请输入选择 [0-3]: " steam302_choice

        case $steam302_choice in
            1)
                echo "执行: 安装Steamcommunity 302..."
                install_steam302
                ;;
            2)
                echo "执行: 启动Steamcommunity 302服务..."
                start_steam302
                ;;
            3)
                echo "执行: 停止Steamcommunity 302服务..."
                stop_steam302
                ;;
            0)
                echo_success "正在返回上一级菜单..."
                return 0
                ;;
            *)
                echo_error "无效选择，请输入 0-3 之间的数字。"
                ;;
        esac

        echo
        read -p "按回车键继续..."
    done
}

# 其他选项函数
others() {
    while true; do
        # 显示当前版本状态
        local current_version=$(get_current_version)
        echo "============================================"
        echo_info "其他选项"
        echo "1. 更新脚本"
        echo "2. 更新黑名单"
        echo "3. 删除所有MOD"
        echo "4. 删除DST服务器程序"
        echo "5. steam下载加速"
        echo "6. 切换32位/64位版本 [当前: ${current_version}位]"
        echo "7. 强制更新公网IP缓存"
        echo "8. 修改饥荒服务器端口"
        echo "0. 返回主菜单"
        read -p "输入选项: " option

        case $option in
            1)
                echo_info "正在更新脚本..."
                if [ -f "x.sh" ]; then
                    mv "x.sh" "x.sh.bak"
                    echo_warning "已将原有的 x.sh 文件重命名为 x.sh.bak"
                fi
                if download "https://ghfast.top/https://raw.githubusercontent.com/xiaochency/dstsh/refs/heads/main/x.sh" 5 10; then
                    chmod 755 x.sh
                    echo_success "已成功更新脚本，请重新执行脚本"
                else
                    echo_error "更新脚本失败，请检查网络连接或URL是否正确"
                fi
                exit 0
                ;;
            2)
                echo_info "正在更新黑名单..."
                if [ -f "blocklist.txt" ]; then
                    mv "blocklist.txt" "blocklist.txt.bak"
                    echo_warning "已将原有的 blocklist.txt 文件重命名为 blocklist.txt.bak"
                fi
                if download "https://ghfast.top/https://raw.githubusercontent.com/xiaochency/dstsh/refs/heads/main/blocklist.txt" 5 10; then
                    cp -f blocklist.txt $HOME/.klei/DoNotStarveTogether/Cluster_1
                    cp -f blocklist.txt $HOME/.klei/DoNotStarveTogether/Cluster_2
                    echo_success "已成功更新黑名单"
                else
                    echo_error "更新黑名单失败，请检查网络连接或URL是否正确"
                fi
                ;;
            3)
                read -p "您确定要删除所有MOD吗？(y/n): " confirm
                if [[ $confirm == "y" || $confirm == "Y" ]]; then
                    echo_info "正在删除所有MOD..."
                    rm -rf $HOME/dst/ugc_mods/Cluster_1/Master/content/322330/*
                    rm -rf $HOME/dst/ugc_mods/Cluster_2/Master/content/322330/*
                    rm -rf $HOME/dst/ugc_mods/Cluster_1/Caves/content/322330/*
                    rm -rf $HOME/dst/ugc_mods/Cluster_2/Caves/content/322330/*
                    echo_success "已成功删除所有MOD"
                else
                    echo_warning "取消删除所有MOD"
                fi
                ;;
            4)
                read -p "您确定要删除DST服务器程序吗？(y/n): " confirm
                if [[ $confirm == "y" || $confirm == "Y" ]]; then
                    echo_info "正在删除DST服务器程序..."
                    rm -rf "$install_dir"
                    rm -rf "$steamcmd_dir"
                    rm -rf "$steam_dir"
                    echo_success "已成功删除DST服务器程序"
                else
                    echo_warning "取消删除DST服务器程序"
                fi
                ;;
            5)
                #steam加速
                manage_steam302
                ;;
            6)
                # 显示当前版本并切换
                local current_version=$(get_current_version)
                echo_info "当前版本: ${current_version}位"
                
                # 检查64位版本是否存在
                local has_64bit=0
                if [ -f "$HOME/dst/bin64/dontstarve_dedicated_server_nullrenderer_x64" ]; then
                    has_64bit=1
                fi
                
                if [ "$current_version" = "32" ] && [ $has_64bit -eq 0 ]; then
                    echo_warning "⚠️  64位服务器程序未安装"
                    echo_info "请先通过选项9安装服务器程序！"
                    read -p "是否仍要切换到64位配置？(y/n): " confirm
                    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                        continue
                    fi
                fi
                
                toggle_version
                ;;
            7)
                force_update_public_ip  #强制更新公网ip
                break
                ;;
            8)
                change_dst_port
                break
                ;;
            0)
                echo_info "返回主菜单"
                break
                ;;
            *)
                echo_error "无效选项，请重试"
                ;;
        esac
    done
}

# 查看聊天日志函数
function view_chat_log() {
    local cluster_choice="$1"
    local chat_log_file=""
    
    case $cluster_choice in
        1)
            chat_log_file="$HOME/.klei/DoNotStarveTogether/Cluster_1/Master/server_chat_log.txt"
            echo_info "正在查看 Cluster_1 聊天日志..."
            ;;
        2)
            chat_log_file="$HOME/.klei/DoNotStarveTogether/Cluster_2/Master/server_chat_log.txt"
            echo_info "正在查看 Cluster_2 聊天日志..."
            ;;
        *)
            echo_error "无效的集群选择"
            return 1
            ;;
    esac
    
    # 检查聊天日志文件是否存在
    if [ ! -f "$chat_log_file" ]; then
        echo_warning "聊天日志文件不存在: $chat_log_file"
        echo_info "这可能是因为服务器尚未生成聊天日志，或者该集群未运行。"
        return 1
    fi
    
    # 检查文件是否为空
    if [ ! -s "$chat_log_file" ]; then
        echo_info "聊天日志文件为空，暂无聊天记录。"
        return 0
    fi
    
    # 显示最后50行聊天记录（可根据需要调整行数）
    echo "============================================"
    echo_success "📝 聊天日志内容 (最后50行):"
    echo "============================================"
    tail -50 "$chat_log_file"
    echo "============================================"
    
    # 提供更多选项
    echo ""
    echo_info "其他选项:"
    echo "1. 查看完整聊天日志"
    echo "2. 实时监控聊天日志（按Ctrl+C退出）"
    echo "0. 返回"
    
    read -p "输入您的选择 (0-2): " log_choice
    case $log_choice in
        1)
            echo "============================================"
            echo_success "📖 完整聊天日志:"
            echo "============================================"
            cat "$chat_log_file"
            echo "============================================"
            ;;
        2)
            echo_info "开始实时监控聊天日志（按Ctrl+C退出）..."
            echo "============================================"
            tail -f "$chat_log_file"
            ;;
        0)
            echo_info "返回上一级菜单..."
            ;;
        *)
            echo_error "无效选择，返回上一级菜单"
            ;;
    esac
}

# 主菜单
while true; do
    # 获取当前版本
    current_version=$(get_current_version)
    echo "-------------------------------------------------"
    echo -e "${GREEN}饥荒云服务器管理脚本1.5.5 By:xiaochency${NC}"
    echo -e "${CYAN}当前版本: ${current_version}位${NC}"
    echo "-------------------------------------------------"
    echo -e "${BLUE}请选择一个选项:${NC}"
    echo "-------------------------------------------------"
    echo -e "| ${CYAN}[1] 启动服务器${NC}          ${CYAN}[2] 更新服务器${NC}          |"
    echo "-------------------------------------------------"
    echo -e "| ${CYAN}[3] 查看服务器${NC}          ${CYAN}[4] 关闭服务器${NC}          |"
    echo "-------------------------------------------------"
    echo -e "| ${CYAN}[5] 查看玩家聊天${NC}        ${CYAN}[6] 监控服务器${NC}          |"
    echo "-------------------------------------------------"
    echo -e "| ${CYAN}[7] 存档管理${NC}            ${CYAN}[8] 服务器控制台${NC}        |"
    echo "-------------------------------------------------"
    echo -e "| ${CYAN}[9] 安装服务器${NC}          ${CYAN}[0] 更多${NC}                |"
    echo "-------------------------------------------------"

    read -p "输入您的选择 (0-9): " choice
    case $choice in
        1)
            while true; do
                echo "============================================"
                echo_info "当前版本: ${current_version}位"
                echo_info "请选择启动哪个服务器:"
                echo "1. 启动 Cluster_1Master"
                echo "2. 启动 Cluster_1Caves"
                echo "3. 启动 Cluster_1Master+Cluster_1Caves"
                echo "4. 启动 Cluster_2Master"
                echo "5. 启动 Cluster_2Caves"
                echo "6. 启动 Cluster_2Master+Cluster_2Caves"
                echo "0. 返回主菜单"

                read -p "输入您的选择 (0-6): " view_choice
                case $view_choice in
                    1)  
                        start_server "Cluster_1" "Master"
                        break
                        ;;
                    2)  
                        start_server "Cluster_1" "Caves"
                        break
                        ;;
                    3)  
                        start_server "Cluster_1" "Master"
                        start_server "Cluster_1" "Caves"
                        break
                        ;;
                    4)  
                        start_server "Cluster_2" "Master"
                        break
                        ;;
                    5)  
                        start_server "Cluster_2" "Caves"
                        break
                        ;;
                    6)  
                        start_server "Cluster_2" "Master"
                        start_server "Cluster_2" "Caves"
                        break
                        ;;
                    0)
                        break
                        ;;
                    *)
                        echo_error "无效选择. 请重试."
                        ;;
                esac
            done
            ;;
        2)
            Update_dst
            ;;
        3)  
            show_server_status
            echo "============================================"
            echo_info "当前运行的服务器如下："
            screen -ls
            while true; do
                echo_info "请选择一个选项:"
                echo "1. 查看 Cluster_1Master 运行日志"
                echo "2. 查看 Cluster_1Caves 运行日志"
                echo "3. 查看 Cluster_2Master 运行日志"
                echo "4. 查看 Cluster_2Caves 运行日志"
                echo "0. 返回主菜单"
                echo_warning "要退出 screen 会话, 请按 Ctrl+A+D."

                read -p "输入您的选择 (0-4): " view_choice
                case $view_choice in
                    1)
                        screen -r Cluster_1Master
                        ;;
                    2)
                        screen -r Cluster_1Caves
                        ;;
                    3)
                        screen -r Cluster_2Master
                        ;;
                    4)
                        screen -r Cluster_2Caves
                        ;;
                    0)
                        break
                        ;;
                    *)
                        echo_error "无效选择. 请重试."
                        ;;
                esac
            done
            ;;
        4)
            shutdown_server
            ;;
        5)
            while true; do
                echo "============================================"
                echo_info "请选择要查看哪个存档的聊天日志:"
                echo "1. 查看 Cluster_1 聊天日志"
                echo "2. 查看 Cluster_2 聊天日志"
                echo "0. 返回上一级"
                
                read -p "输入您的选择 (0-2): " chat_choice
                case $chat_choice in
                    1|2)
                        view_chat_log "$chat_choice"
                        ;;
                    0)
                        break
                        ;;
                    *)
                        echo_error "无效选择. 请重试."
                        ;;
                esac
            done
            ;;
        6)
            ms_servers
            ;;
        7)
            while true; do
                echo "============================================"
                echo_info "请选择一个选项:"
                echo "1. 备份存档"
                echo "2. 恢复存档"
                echo "3. 删除存档"
                echo "0. 返回主菜单"
                read -p "输入您的选择 (0-3): " view_choice

                case $view_choice in
                    1)
                        BackupSaves
                        ;;
                    2)
                        RestoreSaves
                        ;;
                    3)
                        DeleteSaves
                        ;;
                    0)
                        break
                        ;;    
                    *)
                        echo_error "无效选项，请重试"
                        ;;
                esac
            done
            ;;
        8)
            server_console
            ;;     
        9)
            Install_dst
            ;;
        0)
            others
            ;;
        *)
            echo_error "无效选择. 请重试."
            ;;
    esac
done

