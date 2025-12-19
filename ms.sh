#!/bin/bash

# ms.sh - DST 服务器监控脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 输出函数
echo_error() { echo -e "${RED}错误: $@${NC}" >&2; }
echo_success() { echo -e "${GREEN}$@${NC}"; }
echo_warning() { echo -e "${YELLOW}$@${NC}"; }
echo_info() { echo -e "${BLUE}$@${NC}"; }

# 版本配置文件
VERSION_CONFIG_FILE="$HOME/.dst_version"
DEFAULT_VERSION="32"

# 读取版本配置
function read_version_config() {
    if [ -f "$VERSION_CONFIG_FILE" ]; then
        cat "$VERSION_CONFIG_FILE"
    else
        echo "$DEFAULT_VERSION"
    fi
}

# 启动服务器函数
function start_server_in_background() {
    local cluster_name="$1"
    local shard="$2"
    local version="$3"
    
    # 根据版本选择执行文件
    if [ "$version" = "64" ]; then
        local bin_dir="$HOME/dst/bin64/"
        local exec_file="./dontstarve_dedicated_server_nullrenderer_x64"
    else
        local bin_dir="$HOME/dst/bin/"
        local exec_file="./dontstarve_dedicated_server_nullrenderer"
    fi
    
    # 检查目录是否存在
    if [ ! -d "$bin_dir" ]; then
        echo_error "服务器目录不存在: $bin_dir"
        return 1
    fi
    
    # 检查执行文件是否存在
    if [ ! -f "$bin_dir/$(basename $exec_file)" ]; then
        echo_error "服务器可执行文件不存在: $bin_dir/$(basename $exec_file)"
        return 1
    fi
    
    # 启动服务器
    screen -dmS "${cluster_name}${shard}" bash -c "cd $bin_dir && $exec_file console_enabled -cluster $cluster_name -shard $shard"
    
    # 等待一会儿让进程启动
    sleep 2
    
    if screen -list | grep -q "${cluster_name}${shard}"; then
        echo_success "✅ ${cluster_name}${shard} 已启动 (${version}位)"
        return 0
    else
        echo_error "❌ ${cluster_name}${shard} 启动失败"
        return 1
    fi
}

# 监控函数
function monitor_cluster() {
    local cluster_num="$1"
    local cluster_name="Cluster_${cluster_num}"
    
    # 获取当前版本
    local monitor_version=$(read_version_config)
    local has_64bit=0
    
    if [ -f "$HOME/dst/bin64/dontstarve_dedicated_server_nullrenderer_x64" ]; then
        has_64bit=1
    fi
    
    # 如果配置为64位但程序不存在，自动降级
    if [ "$monitor_version" = "64" ] && [ $has_64bit -eq 0 ]; then
        echo_warning "⚠️  64位版本不存在，自动使用32位版本监控"
        monitor_version="32"
    fi
    
    echo_info "正在启动 ${cluster_name} 监控 (${monitor_version}位)..."
    
    # 创建监控会话
    screen -dmS "monitor_${cluster_name}" bash -c "
        # 导入颜色定义
        RED='\\033[0;31m'
        GREEN='\\033[0;32m'
        YELLOW='\\033[1;33m'
        BLUE='\\033[0;34m'
        NC='\\033[0m'
        
        # 输出函数
        echo_success() { echo -e \"\${GREEN}\$@\${NC}\"; }
        echo_warning() { echo -e \"\${YELLOW}\$@\${NC}\"; }
        echo_info() { echo -e \"\${BLUE}\$@\${NC}\"; }
        
        # 获取版本配置
        function get_version() {
            if [ -f '$VERSION_CONFIG_FILE' ]; then
                cat '$VERSION_CONFIG_FILE'
            else
                echo '32'
            fi
        }
        
        # 检查64位版本是否存在
        function check_64bit() {
            if [ -f '$HOME/dst/bin64/dontstarve_dedicated_server_nullrenderer_x64' ]; then
                echo '1'
            else
                echo '0'
            fi
        }
        
        # 启动服务器函数（在监控会话内）
        function start_server_in_monitor() {
            local cluster=\"\$1\"
            local shard=\"\$2\"
            
            local version=\$(get_version)
            local has_64bit=\$(check_64bit)
            
            # 如果配置为64位但程序不存在，自动降级
            if [ \"\$version\" = \"64\" ] && [ \"\$has_64bit\" = \"0\" ]; then
                version=\"32\"
                echo_warning \"⚠️  64位版本不存在，自动使用32位版本启动服务器\"
            fi
            
            # 根据版本选择执行文件
            if [ \"\$version\" = \"64\" ]; then
                local bin_dir=\"$HOME/dst/bin64/\"
                local exec_file=\"./dontstarve_dedicated_server_nullrenderer_x64\"
            else
                local bin_dir=\"$HOME/dst/bin/\"
                local exec_file=\"./dontstarve_dedicated_server_nullrenderer\"
            fi
            
            # 检查目录和文件
            if [ ! -d \"\$bin_dir\" ]; then
                echo_error \"服务器目录不存在: \$bin_dir\"
                return 1
            fi
            
            if [ ! -f \"\$bin_dir/\$(basename \$exec_file)\" ]; then
                echo_error \"服务器可执行文件不存在: \$bin_dir/\$(basename \$exec_file)\"
                return 1
            fi
            
            # 启动服务器
            screen -dmS \"\${cluster}\${shard}\" bash -c \"cd \$bin_dir && \$exec_file console_enabled -cluster \$cluster -shard \$shard\"
            
            # 等待一会儿让进程启动
            sleep 2
            
            if screen -list | grep -q \"\${cluster}\${shard}\"; then
                echo_success \"✅ \${cluster}\${shard} 已启动 (\${version}位)\"
                return 0
            else
                echo_error \"❌ \${cluster}\${shard} 启动失败\"
                return 1
            fi
        }
        
        # 监控循环
        while true; do
            echo_info \"[$(date '+%Y-%m-%d %H:%M:%S')] 检查 ${cluster_name} 服务器状态...\"
            
            # 监控 Master
            if ! screen -list | grep -q '${cluster_name}Master'; then
                echo_warning \"${cluster_name}Master 会话不存在，正在重新启动...\"
                start_server_in_monitor \"${cluster_name}\" \"Master\"
            else
                echo_success \"${cluster_name}Master 运行正常\"
            fi
            
            # 监控 Caves
            if ! screen -list | grep -q '${cluster_name}Caves'; then
                echo_warning \"${cluster_name}Caves 会话不存在，正在重新启动...\"
                start_server_in_monitor \"${cluster_name}\" \"Caves\"
            else
                echo_success \"${cluster_name}Caves 运行正常\"
            fi
            
            echo_info \"下一次检查将在 300 秒后...\"
            sleep 300
        done
    "
    
    # 等待一会儿让监控进程启动
    sleep 2
    
    if screen -list | grep -q "monitor_${cluster_name}"; then
        echo_success "✅ 已在后台启动 ${cluster_name} 监控脚本 (${monitor_version}位)"
        echo_info "监控将自动检查并重启崩溃的服务器，检查间隔：300秒"
        echo_info "监控会话名称: monitor_${cluster_name}"
    else
        echo_error "❌ ${cluster_name} 监控启动失败"
    fi
}

# 停止监控
function stop_monitor() {
    local cluster_name="$1"
    
    if [ -z "$cluster_name" ]; then
        echo_info "正在停止所有监控会话..."
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
    else
        echo_info "正在停止 ${cluster_name} 监控..."
        
        if screen -list | grep -q "monitor_${cluster_name}"; then
            screen -S "monitor_${cluster_name}" -X quit
            echo_success "✅ 已停止 ${cluster_name} 监控"
        else
            echo_warning "未找到 ${cluster_name} 监控会话"
        fi
    fi
}

# 主函数
main() {
    case "$1" in
        start)
            if [ -z "$2" ]; then
                echo_error "请选择要监控的Cluster"
                exit 1
            fi
            monitor_cluster "$2"
            ;;
        stop)
            stop_monitor "$2"
            ;;
        *)
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"