#!/bin/bash

# =============================================================================
# 饥荒联机版云服务器管理脚本
# 作者: xiaochency
# =============================================================================

# --------------------------------------
# 颜色定义
# --------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# --------------------------------------
# 目录定义
# --------------------------------------
readonly INSTALL_DIR="$HOME/dst"
readonly STEAMCMD_DIR="$HOME/steamcmd"
readonly STEAM_DIR="$HOME/Steam"
readonly KLEI_BASE="$HOME/.klei/DoNotStarveTogether"
readonly BACKUP_DIR="$KLEI_BASE/backups"
readonly VERSION_CONFIG_FILE="$HOME/.dst_version"
readonly DEFAULT_VERSION="32"
readonly MS_SCRIPT="$HOME/ms.sh"

# --------------------------------------
# 全局变量（运行时可变）
# --------------------------------------
CURRENT_VERSION=""

# --------------------------------------
# 辅助函数：输出格式
# --------------------------------------
echo_error()   { echo -e "${RED}错误: $*${NC}" >&2; }
echo_success() { echo -e "${GREEN}$*${NC}"; }
echo_warning() { echo -e "${YELLOW}$*${NC}"; }
echo_info()    { echo -e "${BLUE}$*${NC}"; }
echo_debug()   { echo -e "${CYAN}$*${NC}"; }

fail() {
    echo_error "$@"
    exit 1
}

# --------------------------------------
# 版本管理
# --------------------------------------
read_version_config() {
    if [[ -f "$VERSION_CONFIG_FILE" ]]; then
        cat "$VERSION_CONFIG_FILE"
    else
        echo "$DEFAULT_VERSION"
    fi
}

save_version_config() {
    echo "$1" > "$VERSION_CONFIG_FILE"
}

get_current_version() {
    read_version_config
}

toggle_version() {
    local current=$(get_current_version)
    local new="32"
    if [[ "$current" == "32" ]]; then
        new="64"
        echo_info "正在切换到64位版本..."
    else
        new="32"
        echo_info "正在切换到32位版本..."
    fi
    save_version_config "$new"
    echo_success "已切换到${new}位版本"

    if [[ "$new" == "64" ]]; then
        if [[ ! -f "$HOME/dst/bin64/dontstarve_dedicated_server_nullrenderer_x64" ]]; then
            echo_warning "⚠️  64位服务器程序未安装，启动时将使用32位版本"
            echo_info "请通过更新服务器来安装64位版本"
        else
            echo_success "✅ 64位服务器程序已安装"
        fi
    fi
}

# --------------------------------------
# 通用工具函数
# --------------------------------------
check_for_file() { [[ -e "$1" ]]; }

download() {
    local url="$1"
    local tries="$2"
    local timeout="$3"
    wget -q --show-progress --tries="$tries" --timeout="$timeout" "$url"
}

# 创建必要目录（安装时使用）
create_klei_dirs() {
    local clusters=("Cluster_1" "Cluster_2")
    local files=("cluster_token.txt" "adminlist.txt" "blocklist.txt" "whitelist.txt")
    mkdir -p "$BACKUP_DIR"
    for cluster in "${clusters[@]}"; do
        mkdir -p "$KLEI_BASE/$cluster/Master" "$KLEI_BASE/$cluster/Caves"
        for file in "${files[@]}"; do
            touch "$KLEI_BASE/$cluster/$file"
        done
    done
}

# 设置虚拟内存
set_swap() {
    local swapfile="/swap.img"
    local swapsize="2G"

    # 检查是否已有 swap 设备或文件
	if [ -b /dev/dm-1 ] || [ -f $SWAPFILE ]; then
		echo_success "检测到已有 swap 设备 (/dev/dm-1) 或 swap 文件 ($SWAPFILE)，跳过创建步骤"
	else
		echo_info "未检测到 swap 设备或文件，正在创建 swap 文件..."
		sudo fallocate -l $SWAPSIZE $SWAPFILE
		sudo chmod 600 $SWAPFILE
		sudo mkswap $SWAPFILE
		sudo swapon $SWAPFILE
		echo_success "交换文件创建并启用成功"

		# 添加到 /etc/fstab 以便开机启动
		if ! grep -q "$SWAPFILE" /etc/fstab; then
			echo_info "将交换文件添加到 /etc/fstab "
			echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab
			echo_success "交换文件已添加到开机启动"
		else
			echo_success "交换文件已在 /etc/fstab 中，跳过添加步骤"
		fi
	fi

	# 更改swap配置并持久化（无论 swap 是否已存在都执行）
	sysctl -w vm.swappiness=20
	sysctl -w vm.min_free_kbytes=100000
	echo -e 'vm.swappiness = 20\nvm.min_free_kbytes = 100000\n' >/etc/sysctl.d/dmp_swap.conf

	echo_green "系统swap设置成功"
}

# 下载 steamcmd 并处理镜像源
download_steamcmd() {
    local urls=(
        "https://github.dpik.top/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://ghfast.top/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
        "https://cdn.gh-proxy.org/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://edgeone.gh-proxy.org/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
    )

    local output="steamcmd_linux.tar.gz"

    for url in "${urls[@]}"; do
        echo_info "尝试从 $url 下载（速度低于 100KB/s 持续 10 秒将自动切换）..."

        # 使用 curl 下载，设置低速限制：100KB/s，持续 10 秒则放弃
        curl -L --fail \
             --connect-timeout 10 \
             --speed-limit 100000 \
             --speed-time 10 \
             -o "$output" \
             "$url"

        if [[ $? -ne 0 ]]; then
            echo_warning "警告：从 $url 下载失败（速度过慢或网络错误），自动切换到下一个源..."
            rm -f "$output"
            continue
        fi

        # 验证文件大小（≥1MB）
        if [[ -s "$output" ]]; then
            local size
            size=$(stat -c%s "$output" 2>/dev/null || echo 0)
            if [[ $size -ge 1000000 ]]; then
                echo_info "下载成功并验证通过，来源：$url"
                tar -xzf "$output" && rm -f "$output" && return 0
            else
                echo_warning "警告：文件大小异常 ($size 字节)，可能为错误页面，继续尝试下一个源..."
            fi
        else
            echo_warning "警告：下载文件为空，继续尝试下一个源..."
        fi

        rm -f "$output"
    done

    echo_error "错误：所有镜像源均失败"
    return 1
}

# 修复MOD依赖
fix_mod_deps() {
    echo_info "正在执行MOD修复和依赖库"
    cp "$STEAMCMD_DIR/linux32/steamclient.so" "$INSTALL_DIR/bin/lib32/" 2>/dev/null
    cp "$STEAMCMD_DIR/linux64/steamclient.so" "$INSTALL_DIR/bin64/lib64/" 2>/dev/null
    cp "$STEAMCMD_DIR/linux32/libstdc++.so.6" "$INSTALL_DIR/bin/lib32/" 2>/dev/null
    echo_success "MOD更新bug已修复"
}

# 安装/更新核心（通用）
run_steamcmd_update() {
    cd "$STEAMCMD_DIR" || fail "无法进入 $STEAMCMD_DIR"
    ./steamcmd.sh +login anonymous +force_install_dir "$INSTALL_DIR" +app_update 343050 validate +quit
    fix_mod_deps
}

# --------------------------------------
# 核心功能：安装、更新、启动、备份、恢复等
# --------------------------------------
Install_dst() {
    read -p "您确定要安装 Don't Starve Together 服务器吗？(y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo_warning "安装已取消."; return; }

    echo_info "正在安装 Don't Starve Together 服务器..."
    dpkg --add-architecture i386
    apt-get update
    apt-get install -y screen unzip lib32gcc-s1 libcurl4-gnutls-dev:i386 libcurl4-gnutls-dev

    create_klei_dirs
    echo_success "饥荒初始文件夹创建完成"

    mkdir -p "$STEAMCMD_DIR"
    cd "$STEAMCMD_DIR" || fail

    # 下载 steamcmd
    if [[ -f "steamcmd_linux.tar.gz" ]]; then
        echo_warning "steamcmd_linux.tar.gz 存在，正在删除..."
        rm -f steamcmd_linux.tar.gz
    fi

    download_steamcmd || fail "无法下载 steamcmd，请检查网络连接后重试！"

    local install_success=false
    local retry_count=0
    local max_retries=3

    while [[ "$install_success" == false && $retry_count -lt $max_retries ]]; do
        echo_info "正在尝试安装 DST 服务器 (尝试 $((retry_count+1))/$max_retries)..."
        run_steamcmd_update

        if [[ -d "$INSTALL_DIR/bin" ]]; then
            echo_success "=================================================="
            echo_success "✅ 服务器安装验证通过！"
            echo_success "=================================================="
            fix_mod_deps
            echo_success "✅ Don't Starve Together 服务器安装完成！"
            install_success=true
        else
            echo_error "服务器安装验证失败，准备重试..."
            ((retry_count++))
            if [[ $retry_count -lt $max_retries ]]; then
                echo_warning "等待 6 秒后重试..."
                sleep 6
                cd "$STEAMCMD_DIR"
            else
                fail "服务器安装失败，请检查网络连接后重试！"
            fi
        fi
    done
    cd "$HOME"
}

Update_dst() {
    echo_info "正在更新 Don't Starve Together 服务器..."
    # 关闭所有相关 screen 会话
    local sessions=("Cluster_1Master" "Cluster_2Master" "Cluster_1Caves" "Cluster_2Caves" "monitor_Cluster_1" "monitor_Cluster_2")
    for session in "${sessions[@]}"; do
        if screen -list | grep -q "$session"; then
            echo_info "  关闭会话: $session"
            screen -X -S "$session" quit 2>/dev/null
        fi
    done
    sleep 2

    cd "$STEAMCMD_DIR" || fail
    run_steamcmd_update
    echo_success "服务器更新完成，请重新执行脚本"
}

# 自动更新所有集群的模组
AddAutoUpdateMod() {
    local clusters=("1" "2")
    local mods_file="$INSTALL_DIR/mods/dedicated_server_mods_setup.lua"
    echo_info "开始自动更新所有集群的模组配置..."
    echo "============================================"

    for cluster_choice in "${clusters[@]}"; do
        local cluster_file
        if [[ "$cluster_choice" == "1" ]]; then
            cluster_file="$KLEI_BASE/Cluster_1/Master/modoverrides.lua"
            echo_info "正在处理 Cluster_1 的模组配置..."
        else
            cluster_file="$KLEI_BASE/Cluster_2/Master/modoverrides.lua"
            echo_info "正在处理 Cluster_2 的模组配置..."
        fi

        if [[ ! -f "$cluster_file" ]]; then
            echo_warning "⚠️  模组配置文件不存在: $cluster_file"
            continue
        fi

        local modTotal=$(grep -c 'workshop-' "$cluster_file" 2>/dev/null || echo "0")
        if [[ $modTotal -eq 0 ]]; then
            echo_warning "  在 Cluster_$cluster_choice 中没有发现模组"
            continue
        fi

        echo_success "  发现 $modTotal 个模组"
        local added=0 skipped=0

        for ((item=1; item<=modTotal; item++)); do
            local modID=$(grep 'workshop-' "$cluster_file" | cut -d '"' -f2 | sed 's#workshop-##g' | awk "NR==$item")
            [[ -z "$modID" ]] && continue
            if ! grep -q "$modID" "$mods_file" 2>/dev/null; then
                echo "        ServerModSetup(\"$modID\")" >> "$mods_file"
                echo_success "  ✅ 添加模组: $modID"
                ((added++))
            else
                echo_warning "  ⚠️ 模组已存在: $modID"
                ((skipped++))
            fi
        done
        echo_success "  Cluster_$cluster_choice 处理完成: 新增 $added 个模组, 跳过 $skipped 个已存在模组"
        echo "--------------------------------------------"
    done

    echo "============================================"
    echo_success "✅ 模组配置更新完成!"
    echo_info "📁 模组配置文件位置: $mods_file"
    sleep 2
}

# 启动单个分片
start_server() {
    local cluster=$1
    local shard=$2
    local screen_name="${cluster}${shard}"
    local token_file="$KLEI_BASE/$cluster/cluster_token.txt"
    local cluster_dir="$KLEI_BASE/$cluster"

    local current=$(get_current_version)
    local has_64bit=0
    [[ -f "$INSTALL_DIR/bin64/dontstarve_dedicated_server_nullrenderer_x64" ]] && has_64bit=1

    local version="$current"
    if [[ "$version" == "64" && $has_64bit -eq 0 ]]; then
        echo_warning "⚠️  64位版本不存在，自动使用32位版本启动"
        version="32"
    fi

    local bin_dir=""
    local exec_file=""
    if [[ "$version" == "64" ]]; then
        bin_dir="$INSTALL_DIR/bin64/"
        exec_file="./dontstarve_dedicated_server_nullrenderer_x64"
        echo_info "使用64位版本启动服务器"
    else
        bin_dir="$INSTALL_DIR/bin/"
        exec_file="./dontstarve_dedicated_server_nullrenderer"
        echo_info "使用32位版本启动服务器"
    fi

    # 创建集群目录（如果缺失）
    if [[ ! -d "$cluster_dir" ]]; then
        echo_info "📁 集群目录不存在，正在创建: $cluster_dir"
        mkdir -p "$cluster_dir/Master" "$cluster_dir/Caves"
        echo_success "✔ 集群目录创建成功！"
    fi

    # 启动前更新模组配置
    AddAutoUpdateMod

    # 令牌文件处理
    if [[ ! -f "$token_file" ]] || [[ ! -s "$token_file" ]]; then
        echo_warning "⚠️ 令牌文件不存在或为空: $token_file"
        echo_info "📋 正在自动写入默认令牌..."
        echo "pds-g^KU_L2d_1Kio^qUZS9ifsEfTU9c5WBE/1J/ULPaTNAon4ZoViMJb8S5c=" > "$token_file"
        if [[ ! -s "$token_file" ]]; then
            echo_error "✘ 令牌文件仍然为空，无法启动服务器"
            return 1
        fi
        echo_success "✔ 令牌文件已创建并写入默认令牌！"
    fi

    # 检查是否已在运行
    if screen -list | grep -q "$screen_name"; then
        echo_warning "⚠️ $screen_name 服务器已经在运行."
        return 0
    fi

    # 启动
    cd "$bin_dir" || {
        echo_error "✘ 无法进入服务器目录: $bin_dir"
        return 1
    }
    echo_info "🚀 正在启动 $screen_name 服务器($version位)..."
    screen -dmS "$screen_name" $exec_file console_enabled -cluster "$cluster" -shard "$shard"
    sleep 2

    if screen -list | grep -q "$screen_name"; then
        echo_success "✔✔✔ $screen_name 服务器($version位)已成功启动!"
        return 0
    else
        echo_error "✘✘✘ $screen_name 服务器启动失败!"
        return 1
    fi
}

# 备份存档
BackupSaves() {
    local backup_dirs="$BACKUP_DIR"
    local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")

    mkdir -p "$backup_dirs" || { echo_error "无法创建备份目录"; return 1; }

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
                cd "$KLEI_BASE/Cluster_1" || continue
                local backup_file="$backup_dirs/Cluster_1_backup_$timestamp.tar.gz"
                tar -czf "$backup_file" . || { echo_error "备份出错"; continue; }
                echo_success "备份完成: $backup_file"
                ;;
            2)
                echo_info "正在备份 Cluster_2 存档..."
                cd "$KLEI_BASE/Cluster_2" || continue
                local backup_file="$backup_dirs/Cluster_2_backup_$timestamp.tar.gz"
                tar -czf "$backup_file" . || { echo_error "备份出错"; continue; }
                echo_success "备份完成: $backup_file"
                ;;
            0) break ;;
            *) echo_error "无效选择" ;;
        esac
    done
}

# 恢复存档
RestoreSaves() {
    local backup_dirs="$BACKUP_DIR"
    local backup_files=()
    if [[ -d "$backup_dirs" ]]; then
        while IFS= read -r -d $'\0' file; do
            backup_files+=("$file")
        done < <(find "$backup_dirs" -maxdepth 3 -type f \( -name "*.tar.gz" -o -name "*.zip" \) -print0 2>/dev/null)
    fi

    if [[ ${#backup_files[@]} -eq 0 ]]; then
        echo_error "未找到任何备份文件。"
        read -p "按回车键返回..."
        return
    fi

    # 检查 unzip
    if ! command -v unzip &>/dev/null; then
        echo_warning "未找到 unzip，尝试安装..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get update && sudo apt-get install -y unzip
        elif command -v yum &>/dev/null; then
            sudo yum install -y unzip
        else
            echo_error "无法安装 unzip，请手动安装"
        fi
    fi
    local unzip_installed=$(command -v unzip &>/dev/null && echo true || echo false)

    while true; do
        echo "============================================"
        echo_info "请选择要恢复的存档文件:"
        echo "0. 返回主菜单"
        local i=1
        for file in "${backup_files[@]}"; do
            local filename=$(basename "$file")
            local filesize=$(du -h "$file" | cut -f1)
            local filedate=$(date -r "$file" "+%Y-%m-%d %H:%M")
            if [[ "$filename" == *.zip ]] && [[ "$unzip_installed" == false ]]; then
                printf "%2d) %-45s %6s %s [需要 unzip]\n" "$i" "$filename" "$filesize" "$filedate"
            else
                printf "%2d) %-45s %6s %s\n" "$i" "$filename" "$filesize" "$filedate"
            fi
            ((i++))
        done

        read -p "输入文件编号 (0-${#backup_files[@]}): " file_choice
        if [[ "$file_choice" == "0" ]]; then return
        elif [[ "$file_choice" =~ ^[0-9]+$ ]] && (( file_choice >= 1 && file_choice <= ${#backup_files[@]} )); then
            local backup_path="${backup_files[$((file_choice-1))]}"
            if [[ "$backup_path" == *.zip ]] && [[ "$unzip_installed" == false ]]; then
                echo_error "无法解压 .zip 文件，缺少 unzip"
                continue
            fi

            local cluster_type=""
            if [[ "$backup_path" == *"Cluster_1"* ]]; then
                cluster_type="Cluster_1"
            elif [[ "$backup_path" == *"Cluster_2"* ]]; then
                cluster_type="Cluster_2"
            else
                echo "无法识别存档类型，请手动选择:"
                echo "1. Cluster_1"
                echo "2. Cluster_2"
                read -p "输入 (1-2): " cluster_choice
                case $cluster_choice in
                    1) cluster_type="Cluster_1" ;;
                    2) cluster_type="Cluster_2" ;;
                    *) echo_error "无效选择"; continue ;;
                esac
            fi

            local target_dir="$KLEI_BASE/$cluster_type"
            echo_warning "警告：这将覆盖 $target_dir 中的现有存档！"
            read -p "确认恢复？(y/n): " confirm
            [[ ! "$confirm" =~ ^[Yy]$ ]] && continue

            [[ -n "$target_dir" && -d "$target_dir/Master/save" ]] && rm -rf "$target_dir/Master/save"/*
            sleep 3
            mkdir -p "$target_dir"

            echo_info "正在恢复 $cluster_type 存档..."
            if [[ "$backup_path" == *.tar.gz ]]; then
                tar -xzf "$backup_path" -C "$target_dir"
            else
                unzip -o "$backup_path" -d "$target_dir"
            fi

            if [[ $? -eq 0 ]]; then
                echo_success "✔✔✔ 存档恢复成功！"
            else
                echo_error "✘✘✘ 恢复过程中出错！"
            fi
            read -p "按回车键继续..."
        else
            echo_error "无效选择"
        fi
    done
}

# 删除存档
DeleteSaves() {
    while true; do
        echo "============================================"
        echo_info "请选择要删除的存档:"
        echo "1. 删除 Cluster_1 存档"
        echo "2. 删除 Cluster_2 存档"
        echo "0. 返回上一级"
        read -p "输入 (0-2): " choice
        case $choice in
            1) rm -rf "$KLEI_BASE/Cluster_1/Master/save"/* "$KLEI_BASE/Cluster_1/Caves/save"/*; echo_success "Cluster_1 存档已删除" ;;
            2) rm -rf "$KLEI_BASE/Cluster_2/Master/save"/* "$KLEI_BASE/Cluster_2/Caves/save"/*; echo_success "Cluster_2 存档已删除" ;;
            0) return ;;
            *) echo_error "无效选择" ;;
        esac
    done
}

# =============================================================================
# 第二部分：剩余辅助函数 + 主菜单
# =============================================================================

# --------------------------------------
# 监控与维护任务
# --------------------------------------
ms_servers() {
    # 确保 ms.sh 存在
    while true; do
        if [[ -f "$MS_SCRIPT" && -x "$MS_SCRIPT" ]]; then
            break
        fi

        echo_warning "监控脚本 ms.sh 不存在，正在下载..."

        if curl -fsSL --connect-timeout 5 --max-time 10 \
            "https://ghfast.top/https://raw.githubusercontent.com/xiaochency/dstsh/refs/heads/main/ms.sh" \
            -o "$MS_SCRIPT"; then

            if head -n 1 "$MS_SCRIPT" | grep -q '^#!/bin/bash'; then
                chmod +x "$MS_SCRIPT"
                echo_success "已成功下载监控脚本 ms.sh"
                break
            fi
        fi

        echo_error "下载失败，文件异常"
        rm -f "$MS_SCRIPT"

        read -r -p "是否重试下载？(y/n): " retry
        [[ "$retry" != "y" ]] && return 1
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
            1) bash "$MS_SCRIPT" start 1 ;;
            2) bash "$MS_SCRIPT" start 2 ;;
            3)
                echo_info "正在关闭监控脚本..."
                local closed=0
                for session in $(screen -list | grep -E "monitor_Cluster" | cut -d. -f1); do
                    screen -S "$session" -X quit
                    echo_success "已关闭监控会话: $session"
                    ((closed++))
                done
                [[ $closed -eq 0 ]] && echo_warning "未找到运行中的监控会话" || echo_success "✅ 已关闭 $closed 个监控会话"
                ;;
            4) setup_maintenance_task ;;
            5) remove_maintenance_task ;;
            6) show_maintenance_status ;;
            0) return 0 ;;
            *) echo_error "无效选项" ;;
        esac
        read -p "按回车键继续..."
    done
}

setup_maintenance_task() {
    local hour
    local default_hour=$(date +%H)
    echo_info "🕒 设置服务器维护任务"
    echo "维护任务包括：维护前5分钟公告、前2分钟保存、整点关闭、后10分钟更新 SteamCMD"
    while true; do
        read -p "请输入维护时间的小时 (0-23) [默认: $default_hour]: " hour
        hour=${hour:-$default_hour}
        [[ "$hour" =~ ^[0-9]+$ && hour -ge 0 && hour -le 23 ]] && break
        echo_error "请输入0-23之间的有效数字"
    done
    local minute="00"
    local formatted_time=$(printf "%02d:%02d" "$hour" "$minute")
    local announce_minute="55"
    local save_minute="58"
    local announce_hour=$((hour - 1))
    local save_hour=$((hour - 1))
    local steamcmd_hour=$hour
    local steamcmd_minute="10"
    (( announce_hour < 0 )) && announce_hour=23
    (( save_hour < 0 )) && save_hour=23

    echo ""
    echo_success "📋 维护任务计划如下："
    echo_success "  ⏰ 维护时间: $formatted_time"
    echo_success "  📢 公告时间: $(printf "%02d:%02d" "$announce_hour" "$announce_minute")"
    echo_success "  💾 保存时间: $(printf "%02d:%02d" "$save_hour" "$save_minute")"
    echo_success "  🔄 SteamCMD更新: $(printf "%02d:%02d" "$steamcmd_hour" "$steamcmd_minute")"
    read -p "确认设置？(y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo_warning "已取消"; return; }

    remove_maintenance_task silent
    local temp_cron=$(mktemp)
    crontab -l 2>/dev/null > "$temp_cron"
    {
        echo "$announce_minute $announce_hour * * * if screen -list | grep -q 'Cluster_1Master'; then screen -S Cluster_1Master -p 0 -X stuff 'c_announce(\"服务器将于5分钟后维护重启\")\\n'; fi; if screen -list | grep -q 'Cluster_2Master'; then screen -S Cluster_2Master -p 0 -X stuff 'c_announce(\"服务器将于5分钟后维护重启\")\\n'; fi"
        echo "$save_minute $save_hour * * * if screen -list | grep -q 'Cluster_1Master'; then screen -S Cluster_1Master -p 0 -X stuff 'c_save()\\n'; fi; if screen -list | grep -q 'Cluster_2Master'; then screen -S Cluster_2Master -p 0 -X stuff 'c_save()\\n'; fi"
        echo "$minute $hour * * * for session in Cluster_1Master Cluster_1Caves Cluster_2Master Cluster_2Caves; do screen -X -S \"\$session\" quit 2>/dev/null; done"
        echo "$steamcmd_minute $steamcmd_hour * * * cd $STEAMCMD_DIR && ./steamcmd.sh +quit"
    } >> "$temp_cron"
    crontab "$temp_cron"
    rm -f "$temp_cron"
    echo_success "✅ 服务器维护任务已成功设置！"
    show_maintenance_status
}

show_maintenance_status() {
    echo_info "📋 当前维护任务状态:"
    local cron_list=$(crontab -l 2>/dev/null)
    if [[ -z "$cron_list" ]]; then
        echo_warning "  暂无维护任务"
        return
    fi
    local has=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        local cron_min=$(echo "$line" | awk '{print $1}')
        local cron_hour=$(echo "$line" | awk '{print $2}')
        if [[ "$line" =~ c_announce ]]; then
            echo_success "  📢 公告任务: $(printf "%02d:%02d" "${cron_hour:-0}" "${cron_min:-0}") 每天"
            has=1
        elif [[ "$line" =~ c_save ]]; then
            echo_success "  💾 保存任务: $(printf "%02d:%02d" "${cron_hour:-0}" "${cron_min:-0}") 每天"
            has=1
        elif [[ "$line" =~ screen.*quit ]]; then
            echo_success "  🛑 关闭任务: $(printf "%02d:%02d" "${cron_hour:-0}" "${cron_min:-0}") 每天"
            has=1
        elif [[ "$line" =~ steamcmd\.sh ]]; then
            echo_success "  🔄 SteamCMD更新: $(printf "%02d:%02d" "${cron_hour:-0}" "${cron_min:-0}") 每天"
            has=1
        fi
    done <<< "$cron_list"
    [[ $has -eq 0 ]] && echo_warning "  暂无维护任务"
}

remove_maintenance_task() {
    local silent="$1"
    [[ "$silent" != "silent" ]] && echo_info "正在删除服务器维护任务..."
    local temp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -v -E '(Cluster_1Master|Cluster_2Master|steamcmd\.sh)' > "$temp_cron" || true
    if [[ ! -s "$temp_cron" ]]; then
        crontab -r 2>/dev/null || true
    else
        crontab "$temp_cron"
    fi
    rm -f "$temp_cron"
    [[ "$silent" != "silent" ]] && { echo_success "✅ 所有服务器维护任务已删除"; show_maintenance_status; }
}

# --------------------------------------
# 服务器控制台命令
# --------------------------------------
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

regenerate_world() {
    local cluster_name="$1"
    local master_server="${cluster_name}Master"
    read -p "您确定要重置这个世界吗？(y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo_warning "已取消."; return; }
    if [[ "$master_server" == "Cluster_1Master" || "$master_server" == "Cluster_2Master" ]]; then
        echo_info "正在重置 $cluster_name 的世界..."
        screen -S "$master_server" -X stuff "c_regenerateworld()\n"
        echo_success "$cluster_name 的世界重置指令已发送。"
    else
        echo_error "无效的集群名称。"
    fi
}

ban_player() {
    local cluster_name="$1"
    read -p "请输入要拉黑的玩家 ID (userid): " userid
    [[ -z "$userid" ]] && { echo_error "玩家 ID 不能为空。"; return 1; }
    local master_server="${cluster_name}Master"
    if [[ "$master_server" == "Cluster_1Master" || "$master_server" == "Cluster_2Master" ]]; then
        echo_info "正在拉黑 $cluster_name 的 Master 服务器上的玩家 $userid..."
        screen -S "$master_server" -X stuff "TheNet:Ban(\"$userid\")\n"
        echo_success "已尝试在 $cluster_name 的 Master 服务器上拉黑玩家 $userid。"
    else
        echo_error "无效的集群名称。"
    fi
}

server_console() {
    while true; do
        echo "============================================"
        echo_info "服务器控制台"
        echo "1. 发送服务器公告"
        echo "2. 服务器回档"
        echo "3. 拉黑玩家"
        echo "4. 服务器重置世界"
        echo "0. 返回主菜单"
        read -p "输入选择 (0-4): " console_choice
        case $console_choice in
            1)
                while true; do
                    echo "请选择要发公告的服务器: 1. Cluster_1  2. Cluster_2  0. 返回"
                    read -p "输入 (0-2): " ac
                    case $ac in 1) send_announcement "Cluster_1" ;; 2) send_announcement "Cluster_2" ;; 0) break ;; *) echo_error "无效选择" ;; esac
                done
                ;;
            2)
                while true; do
                    echo "请选择要回档的服务器: 1. Cluster_1  2. Cluster_2  0. 返回"
                    read -p "输入 (0-2): " rc
                    case $rc in
                        1) read -p "请输入回档次数: " cnt; rollback_server "Cluster_1" "$cnt" ;;
                        2) read -p "请输入回档次数: " cnt; rollback_server "Cluster_2" "$cnt" ;;
                        0) break ;;
                        *) echo_error "无效选择" ;;
                    esac
                done
                ;;
            3)
                while true; do
                    echo "请选择要拉黑玩家的服务器: 1. Cluster_1  2. Cluster_2  0. 返回"
                    read -p "输入 (0-2): " bc
                    case $bc in 1) ban_player "Cluster_1" ;; 2) ban_player "Cluster_2" ;; 0) break ;; *) echo_error "无效选择" ;; esac
                done
                ;;
            4)
                while true; do
                    echo "请选择要重置世界的服务器: 1. Cluster_1  2. Cluster_2  0. 返回"
                    read -p "输入 (0-2): " rg
                    case $rg in 1) regenerate_world "Cluster_1" ;; 2) regenerate_world "Cluster_2" ;; 0) break ;; *) echo_error "无效选择" ;; esac
                done
                ;;
            0) break ;;
            *) echo_error "无效选择" ;;
        esac
    done
}

shutdown_server() {
    while true; do
        echo "============================================"
        echo_info "请选择一个选项:"
        echo "1. 关闭Cluster_1服务器"
        echo "2. 关闭Cluster_2服务器"
        echo "0. 返回主菜单"
        echo_warning "在关闭服务器前会自动保存！"
        read -p "输入 (0-2): " view_choice
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
            0) break ;;
            *) echo_error "无效选择" ;;
        esac
    done
}

# --------------------------------------
# 公网IP相关
# --------------------------------------
get_public_ip() {
    local ip_file="$HOME/.dst_public_ip"
    if [[ -f "$ip_file" && -s "$ip_file" ]]; then
        local ip=$(cat "$ip_file" | head -n1 | tr -d '\n\r')
        echo_info "从缓存读取公网IP: $ip"
        echo "$ip"
        return 0
    fi
    echo_info "正在获取本机公网IP..."
    local sources=("https://checkip.amazonaws.com" "https://v4.ident.me")
    for src in "${sources[@]}"; do
        local ip=$(curl -s --connect-timeout 5 "$src" 2>/dev/null | tr -d '\n\r')
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo_success "成功获取公网IP: $ip"
            echo "$ip" > "$ip_file"
            chmod 600 "$ip_file" 2>/dev/null
            echo "$ip"
            return 0
        fi
        sleep 1
    done
    echo_warning "无法获取公网IP，请检查网络连接"
    echo "未知" > "$ip_file"
    echo "未知"
    return 1
}

force_update_public_ip() {
    rm -f "$HOME/.dst_public_ip" 2>/dev/null
    echo_info "已清除IP缓存，下次将重新获取公网IP"
}

show_server_status() {
    echo "=== 当前服务器状态 ==="
    local clusters=("Cluster_1" "Cluster_2")
    local shards=("Master" "Caves")
    local cluster1_running=0 cluster2_running=0

    for cluster in "${clusters[@]}"; do
        for shard in "${shards[@]}"; do
            if screen -list | grep -q "${cluster}${shard}"; then
                echo "✅ ${cluster}.${shard} - 运行中"
                [[ "$cluster" == "Cluster_1" ]] && cluster1_running=1 || cluster2_running=1
            else
                echo "❌ ${cluster}.${shard} - 未运行"
            fi
        done
    done
    echo "===================="

    if [[ $cluster1_running -eq 0 && $cluster2_running -eq 0 ]]; then
        echo_warning "没有检测到运行中的服务器，跳过直连信息显示"
        return
    fi

    local public_ip=$(get_public_ip)
    if [[ "$public_ip" == "未知" ]]; then
        echo_warning "无法获取公网IP，请检查网络连接"
        echo_info "提示：可以尝试在'其他选项'中强制更新IP缓存"
    else
        echo_success "本机公网IP: $public_ip (缓存)"
    fi

    echo
    echo "=== 存档直连信息 ==="
    local clean_ip=$(echo "$public_ip" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    [[ -z "$clean_ip" ]] && clean_ip="$public_ip"

    local port1="10999" port2="10999"
    local ini1="$KLEI_BASE/Cluster_1/Master/server.ini"
    local ini2="$KLEI_BASE/Cluster_2/Master/server.ini"
    if [[ -f "$ini1" ]]; then
        local p=$(grep -E '^server_port\s*=' "$ini1" | head -1 | sed 's/.*=\s*//' | tr -d ' ')
        [[ -n "$p" ]] && port1="$p"
    fi
    if [[ -f "$ini2" ]]; then
        local p=$(grep -E '^server_port\s*=' "$ini2" | head -1 | sed 's/.*=\s*//' | tr -d ' ')
        [[ -n "$p" ]] && port2="$p"
    fi
    port1=$(echo "$port1" | tr -cd '0-9'); port2=$(echo "$port2" | tr -cd '0-9')
    [[ -z "$port1" ]] && port1="10999"
    [[ -z "$port2" ]] && port2="10999"

    if [[ "$clean_ip" != "未知" ]]; then
        echo_success "════════════════════════════════════════════"
        [[ $cluster1_running -eq 1 ]] && echo_success "📡 Cluster_1 [🟢 运行中]" || echo_warning "📡 Cluster_1 [🔴 未运行]"
        echo "c_connect(\"$clean_ip\", $port1)"
        echo
        [[ $cluster2_running -eq 1 ]] && echo_success "📡 Cluster_2 [🟢 运行中]" || echo_warning "📡 Cluster_2 [🔴 未运行]"
        echo "c_connect(\"$clean_ip\", $port2)"
        echo_success "════════════════════════════════════════════"
        echo_info "💡 在游戏大厅按 ~ 键打开控制台，输入以上命令直连"
    fi
}

# --------------------------------------
# 端口修改
# --------------------------------------
modify_server_port() {
    local config_file="$1"
    local new_port="$2"
    local server_type="$3"
    if [[ ! -f "$config_file" ]]; then
        echo_error "配置文件不存在: $config_file"
        return 1
    fi
    sed -i "2s/server_port = [0-9]*/server_port = $new_port/" "$config_file" 2>/dev/null && \
        echo_success "$server_type 端口修改成功" || { echo_error "修改失败"; return 1; }
}

change_dst_port() {
    while true; do
        echo "=== DST服务器端口修改工具 ==="
        echo "1) Cluster_1   2) Cluster_2   0) 返回"
        read -p "请选择存档: " cluster_choice
        case $cluster_choice in
            0) return 0 ;;
            1) cluster="Cluster_1"; break ;;
            2) cluster="Cluster_2"; break ;;
            *) echo_error "无效选择" ;;
        esac
    done
    while true; do
        echo "请选择服务器: 1) 地面(Master)  2) 洞穴(Caves)  0) 返回"
        read -p "输入 (0-2): " server_choice
        case $server_choice in
            0) return ;;
            1|2) break ;;
            *) echo_error "无效选择" ;;
        esac
    done
    local master_file="$KLEI_BASE/${cluster}/Master/server.ini"
    local caves_file="$KLEI_BASE/${cluster}/Caves/server.ini"
    local config_file=""
    local server_type=""
    case $server_choice in
        1) config_file="$master_file"; server_type="地面服务器" ;;
        2) config_file="$caves_file"; server_type="洞穴服务器" ;;
    esac
    if [[ -f "$config_file" ]]; then
        local current=$(grep "^server_port" "$config_file" | head -1 | awk -F'=' '{print $2}' | tr -d ' ')
        echo "$server_type 当前端口: ${current:-未设置}"
    else
        echo_error "配置文件不存在: $config_file"
        return 1
    fi
    read -p "请输入新的端口号 (输入0返回): " new_port
    [[ "$new_port" == "0" ]] && return
    [[ "$new_port" =~ ^[0-9]+$ ]] || { echo_error "端口号必须是数字"; return 1; }
    modify_server_port "$config_file" "$new_port" "$server_type"
    echo_success "端口修改完成！新端口: $new_port，请重启服务器生效。"
}

# --------------------------------------
# Steam 加速器管理
# --------------------------------------
install_steam302() {
    local urls=(
        "https://cdn.gh-proxy.org/github.com/xiaochency/dstsh/releases/download/1st/Steamcommunity_302.tar.gz"
        "https://github.dpik.top/github.com/xiaochency/dstsh/releases/download/1st/Steamcommunity_302.tar.gz"
        "https://ghfast.top/github.com/xiaochency/dstsh/releases/download/1st/Steamcommunity_302.tar.gz"
    )
    local names=("镜像源1 (cdn.gh-proxy.org)" "镜像源2 (github.dpik.top)" "镜像源3 (ghfast.top)")
    echo "开始安装 steam302..."
    rm -f Steamcommunity_302.tar.gz
    rm -rf Steamcommunity_302
    echo "请选择下载镜像源："
    for i in "${!names[@]}"; do echo_success "$((i+1)). ${names[i]}"; done
    local choice
    while true; do
        read -p "请输入选择 [1-3]: " choice
        [[ "$choice" =~ ^[1-3]$ ]] && break
        echo_error "无效选择"
    done
    local url="${urls[$((choice-1))]}"
    echo "使用镜像源：${names[$((choice-1))]}"
    if download "$url" 3 15; then
        if [[ -f "Steamcommunity_302.tar.gz" ]]; then
            local size=$(stat -c%s "Steamcommunity_302.tar.gz" 2>/dev/null || echo "0")
            if [[ $size -lt 1000 ]]; then
                echo_error "文件大小异常，删除"
                rm -f Steamcommunity_302.tar.gz
                return 1
            fi
            if tar -tzf Steamcommunity_302.tar.gz >/dev/null 2>&1; then
                tar -zxvf Steamcommunity_302.tar.gz
                echo_success "✅ Steamcommunity_302 安装完成！"
            else
                echo_error "压缩包损坏"
                rm -f Steamcommunity_302.tar.gz
                return 1
            fi
        else
            echo_error "文件未找到"
            return 1
        fi
    else
        echo_error "下载失败"
        return 1
    fi
}

start_steam302() {
    local target_dir="Steamcommunity_302"
    local executable="./steamcommunity_302.cli"
    local session="steam302"
    if [[ ! -d "$target_dir" ]]; then
        echo_error "目录 $target_dir 不存在，请先安装"
        return 1
    fi
    cd "$target_dir" || return 1
    chmod +x Steamcommunity_302 steamcommunity_302.caddy steamcommunity_302.cli
    if screen -list | grep -q "$session"; then
        echo_warning "已存在会话 $session，是否重启？[y/N]"
        read -p "" restart
        [[ "$restart" =~ ^[Yy]$ ]] && screen -S "$session" -X quit || { cd - >/dev/null; return; }
    fi
    screen -dmS "$session" "$executable"
    if [[ $? -eq 0 ]]; then
        echo_success "✓ Steamcommunity 302 服务已启动 (占用80端口)"
    else
        echo_error "启动失败"
        cd - >/dev/null
        return 1
    fi
    cd - >/dev/null
}

stop_steam302() {
    local session="steam302"
    if screen -list | grep -q "$session"; then
        screen -S "$session" -X quit
        echo_success "✓ Steamcommunity 302 服务已停止"
    else
        echo_success "服务未在运行"
    fi
}

manage_steam302() {
    while true; do
        clear
        echo_success "================================================"
        echo_success "           Steam加速器管理"
        echo_success "================================================"
        echo "1. 安装Steamcommunity 302"
        echo "2. 启动Steamcommunity 302服务"
        echo "3. 停止Steamcommunity 302服务"
        echo "0. 返回上一级"
        read -p "请输入选择 [0-3]: " choice
        case $choice in
            1) install_steam302 ;;
            2) start_steam302 ;;
            3) stop_steam302 ;;
            0) return 0 ;;
            *) echo_error "无效选择" ;;
        esac
        read -p "按回车键继续..."
    done
}

# --------------------------------------
# 查看聊天日志
# --------------------------------------
view_chat_log() {
    local cluster_choice=$1
    local chat_log=""
    case $cluster_choice in
        1) chat_log="$KLEI_BASE/Cluster_1/Master/server_chat_log.txt"; echo_info "查看 Cluster_1 聊天日志..." ;;
        2) chat_log="$KLEI_BASE/Cluster_2/Master/server_chat_log.txt"; echo_info "查看 Cluster_2 聊天日志..." ;;
        *) echo_error "无效选择"; return 1 ;;
    esac
    if [[ ! -f "$chat_log" ]]; then
        echo_warning "聊天日志文件不存在: $chat_log"
        return 1
    fi
    if [[ ! -s "$chat_log" ]]; then
        echo_info "聊天日志为空"
        return
    fi
    echo "============================================"
    echo_success "📝 聊天日志内容 (最后50行):"
    tail -50 "$chat_log"
    echo "============================================"
    echo ""
    echo_info "其他选项: 1.查看完整日志  2.实时监控  0.返回"
    read -p "输入 (0-2): " opt
    case $opt in
        1) cat "$chat_log" ;;
        2) tail -f "$chat_log" ;;
        *) ;;
    esac
}

# --------------------------------------
# 其他选项菜单
# --------------------------------------
others() {
    while true; do
        local cur_ver=$(get_current_version)
        echo "============================================"
        echo_info "其他选项"
        echo "1. 更新脚本"
        echo "2. 更新黑名单"
        echo "3. 删除所有MOD"
        echo "4. 删除DST服务器程序"
        echo "5. steam下载加速"
        echo "6. 切换32位/64位版本 [当前: ${cur_ver}位]"
        echo "7. 强制更新公网IP缓存"
        echo "8. 修改饥荒服务器端口"
        echo "9. 设置虚拟内存"
        echo "0. 返回主菜单"
        read -p "输入选项: " option
        case $option in
            1)
                echo_info "正在更新脚本..."
                [[ -f "x.sh" ]] && mv "x.sh" "x.sh.bak"
                if download "https://ghfast.top/https://raw.githubusercontent.com/xiaochency/dstsh/refs/heads/main/x.sh" 5 10; then
                    chmod 755 x.sh
                    echo_success "脚本更新成功，请重新执行"
                else
                    echo_error "更新失败"
                fi
                exit 0
                ;;
            2)
                echo_info "正在更新黑名单..."
                [[ -f "blocklist.txt" ]] && mv "blocklist.txt" "blocklist.txt.bak"
                if download "https://ghfast.top/https://raw.githubusercontent.com/xiaochency/dstsh/refs/heads/main/blocklist.txt" 5 10; then
                    cp -f blocklist.txt "$KLEI_BASE/Cluster_1/" "$KLEI_BASE/Cluster_2/"
                    echo_success "黑名单更新成功"
                else
                    echo_error "更新失败"
                fi
                ;;
            3)
                read -p "确认删除所有MOD？(y/n): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    rm -rf "$INSTALL_DIR/ugc_mods"/Cluster_{1,2}/{Master,Caves}/content/322330/*
                    echo_success "MOD已删除"
                else
                    echo_warning "取消"
                fi
                ;;
            4)
                read -p "确认删除DST服务器程序？(y/n): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    rm -rf "$INSTALL_DIR" "$STEAMCMD_DIR" "$STEAM_DIR"
                    echo_success "服务器程序已删除"
                else
                    echo_warning "取消"
                fi
                ;;
            5) manage_steam302 ;;
            6) toggle_version ;;
            7) force_update_public_ip ;;
            8) change_dst_port ;;
            9) set_swap ;;
            0) break ;;
            *) echo_error "无效选项" ;;
        esac
    done
}

# --------------------------------------
# 主菜单循环
# --------------------------------------
CURRENT_VERSION=$(get_current_version)
while true; do
    echo "-------------------------------------------------"
    echo -e "${GREEN}饥荒云服务器管理脚本1.5.9 By:xiaochency${NC}"
    echo -e "${CYAN}当前版本: ${CURRENT_VERSION}位${NC}"
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
                echo_info "当前版本: ${CURRENT_VERSION}位"
                echo "1. 启动 Cluster_1Master"
                echo "2. 启动 Cluster_1Caves"
                echo "3. 启动 Cluster_1Master+Cluster_1Caves"
                echo "4. 启动 Cluster_2Master"
                echo "5. 启动 Cluster_2Caves"
                echo "6. 启动 Cluster_2Master+Cluster_2Caves"
                echo "0. 返回主菜单"
                read -p "输入 (0-6): " sub
                case $sub in
                    1) start_server "Cluster_1" "Master"; break ;;
                    2) start_server "Cluster_1" "Caves"; break ;;
                    3) start_server "Cluster_1" "Master"; start_server "Cluster_1" "Caves"; break ;;
                    4) start_server "Cluster_2" "Master"; break ;;
                    5) start_server "Cluster_2" "Caves"; break ;;
                    6) start_server "Cluster_2" "Master"; start_server "Cluster_2" "Caves"; break ;;
                    0) break ;;
                    *) echo_error "无效选择" ;;
                esac
            done
            ;;
        2) Update_dst ;;
        3)
            show_server_status
            echo "============================================"
            echo_info "当前运行的服务器如下："
            screen -ls
            while true; do
                echo "1. 查看 Cluster_1Master 日志"
                echo "2. 查看 Cluster_1Caves 日志"
                echo "3. 查看 Cluster_2Master 日志"
                echo "4. 查看 Cluster_2Caves 日志"
                echo "0. 返回"
                echo_warning "退出 screen 请按 Ctrl+A+D"
                read -p "输入 (0-4): " vc
                case $vc in
                    1) screen -r Cluster_1Master ;;
                    2) screen -r Cluster_1Caves ;;
                    3) screen -r Cluster_2Master ;;
                    4) screen -r Cluster_2Caves ;;
                    0) break ;;
                    *) echo_error "无效选择" ;;
                esac
            done
            ;;
        4) shutdown_server ;;
        5)
            while true; do
                echo "1. 查看 Cluster_1 聊天日志"
                echo "2. 查看 Cluster_2 聊天日志"
                echo "0. 返回"
                read -p "输入 (0-2): " cc
                case $cc in
                    1|2) view_chat_log "$cc" ;;
                    0) break ;;
                    *) echo_error "无效选择" ;;
                esac
            done
            ;;
        6) ms_servers ;;
        7)
            while true; do
                echo "1. 备份存档"
                echo "2. 恢复存档"
                echo "3. 删除存档"
                echo "0. 返回"
                read -p "输入 (0-3): " sm
                case $sm in
                    1) BackupSaves ;;
                    2) RestoreSaves ;;
                    3) DeleteSaves ;;
                    0) break ;;
                    *) echo_error "无效选择" ;;
                esac
            done
            ;;
        8) server_console ;;
        9) Install_dst ;;
        0) others ;;
        *) echo_error "无效选择" ;;
    esac
done