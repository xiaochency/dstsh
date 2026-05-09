#!/bin/bash

#======================================================================
# 🛠️  fail2ban 智能安装与查询脚本 v6.1 (寰宇分析版)
# ✅ 融合 binbas.txt 智能换源逻辑
# ✅ 支持：Debian, Ubuntu, CentOS, Alpine, Arch 等主流系统
# ✅ 优化：查询结果全汉化、格式化、彩色高亮，信息更直观
#
# 💡 更新日志 (v6.1):
#   - [BUG 修复] 修复了 v6.0 版本中因 else 分支为空导致的致命语法错误。
#   - [代码完善] 重新加入了对非 systemd 系统的传统日志文件 (/var/log/auth.log) 的解析逻辑。
#   - [UI 革新] 重新设计了启动菜单，采用更美观的字符画边框。
#   - [寰宇分析] 新增攻击来源地理位置分析！自动查询攻击频率最高的IP来源地 (国家/城市)。
#   - [视觉增强] 引入更多色彩和图标，优化了数据对齐，使报告更具可读性。
#
# 🔧 2026-01-18 修复：
#   - CentOS 8 使用 vault.centos.org 归档源（因 EOL）
#   - 移除 yum makecache 的 'fast' 参数（CentOS 8 不支持）
#======================================================================

set -euo pipefail

# --- 颜色与样式定义 ---
C_RESET="\033[0m"
C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_MAGENTA="\033[35m"
C_CYAN="\033[36m"
C_WHITE="\033[37m"
C_BOLD="\033[1m"

# --- 日志函数 ---
log() { echo -e "${C_GREEN}【信息】 $1 ${C_RESET}"; }
warn() { echo -e "${C_YELLOW}【警告】 $1 ${C_RESET}" >&2; }
error() { echo -e "${C_RED}【错误】 $1 ${C_RESET}" >&2; exit 1; }
header() { echo -e "\n${C_CYAN}${C_BOLD}═══════════  $1 ═══════════${C_RESET}"; }

#==================================================
# 🧩 全局变量及初始化
#==================================================
SYSTEM_ID=""
SYSTEM_VERSION_ID=""
SYSTEM_VERSION_ID_MAJOR=""
SYSTEM_VERSION_CODENAME=""
SYSTEM_PRETTY_NAME=""
SYSTEM_FACTIONS=""

Dir_YumRepos="/etc/yum.repos.d"
File_AlpineRepositories="/etc/apk/repositories"

#==================================================
# 🔍 智能检测与网络函数
#==================================================
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        SYSTEM_ID="${ID}"
        SYSTEM_VERSION_ID="${VERSION_ID}"
        SYSTEM_VERSION_ID_MAJOR="${VERSION_ID%%.*}"
        SYSTEM_VERSION_CODENAME="${VERSION_CODENAME:-}"
        SYSTEM_PRETTY_NAME="${PRETTY_NAME}"

        case "$ID" in
            debian|ubuntu|zorin|linuxmint) SYSTEM_FACTIONS="DEBIAN_FAMILY" ;;
            centos|rhel|rocky|almalinux|oracle|fedora|openeuler|opencloudos) SYSTEM_FACTIONS="REDHAT" ;;
            alpine) SYSTEM_FACTIONS="ALPINE" ;;
            arch|manjaro) SYSTEM_FACTIONS="ARCH" ;;
            *) error "无法识别的操作系统: $PRETTY_NAME" ;;
        esac
        
        if [ -z "$SYSTEM_VERSION_CODENAME" ] && command -v lsb_release >/dev/null; then
            SYSTEM_VERSION_CODENAME=$(lsb_release -cs)
        fi
    else
        error "关键文件 /etc/os-release 不存在，无法识别操作系统。"
    fi
    log "检测到系统: $SYSTEM_PRETTY_NAME"
}

get_country_code() {
    local code
    code=$(curl -fsSL --connect-timeout 5 --max-time 10 https://ipinfo.io/country) || echo "XX"
    if [[ "$code" =~ ^[A-Z]{2}$ ]]; then
        echo "$code"
    else
        echo "XX"
    fi
}

#==================================================
# 🌐 换源逻辑
#==================================================
change_mirrors_Debian_family() {
    local country_code="$1"; local source_file use_deb822_format=false; local components source_host sec_host main_path sec_path; local web_protocol="http"

    if [[ "$SYSTEM_ID" == "debian" ]]; then
        source_host="deb.debian.org"; sec_host="security.debian.org"; main_path="/debian"; sec_path="/debian-security"
        components="main contrib non-free"; source_file="/etc/apt/sources.list"
        case "$SYSTEM_VERSION_ID_MAJOR" in
            10|9|8) warn "检测到已归档的 Debian 版本 (${SYSTEM_VERSION_CODENAME})，强制使用官方归档源 archive.debian.org"; source_host="archive.debian.org"; sec_host="archive.debian.org" ;;
            *) if [[ "$country_code" == "CN" ]]; then log "IP所在地为中国，将主源和安全源均切换至腾讯云镜像..."; source_host="mirrors.tencent.com"; sec_host="mirrors.tencent.com"; fi ;;
        esac
        if dpkg --compare-versions "$SYSTEM_VERSION_ID" ge "12"; then use_deb822_format=true; source_file="/etc/apt/sources.list.d/debian.sources"; components="main contrib non-free non-free-firmware"; fi
    elif [[ "$SYSTEM_ID" == "ubuntu" ]]; then
        source_host="archive.ubuntu.com"; sec_host="security.ubuntu.com"; main_path="/ubuntu"; sec_path="/ubuntu"
        components="main restricted universe multiverse"; source_file="/etc/apt/sources.list"
        if [[ "$country_code" == "CN" ]]; then log "IP所在地为中国，使用腾讯云镜像源以加速。"; source_host="mirrors.tencent.com"; sec_host="mirrors.tencent.com"; fi
        if dpkg --compare-versions "$SYSTEM_VERSION_ID" ge "24.04"; then use_deb822_format=true; source_file="/etc/apt/sources.list.d/ubuntu.sources"; fi
    else
        error "不支持的 Debian 系发行版: $SYSTEM_ID"
    fi

    log "正在为 $SYSTEM_PRETTY_NAME 配置软件源..."; log "选择的主源: ${source_host}, 安全源: ${sec_host}"; log "正在清理旧的源配置文件..."
    [ -f /etc/apt/sources.list ] && mv /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%s)
    if [ -d /etc/apt/sources.list.d ]; then mv /etc/apt/sources.list.d /etc/apt/sources.list.d.bak.$(date +%s); fi
    mkdir -p /etc/apt/sources.list.d; touch /etc/apt/sources.list

    if [[ "$use_deb822_format" == "true" ]]; then
        cat > "$source_file" << EOF
Types: deb
URIs: ${web_protocol}://${source_host}${main_path}
Suites: ${SYSTEM_VERSION_CODENAME} ${SYSTEM_VERSION_CODENAME}-updates
Components: ${components}
Signed-By: /usr/share/keyrings/${SYSTEM_ID}-archive-keyring.gpg

Types: deb
URIs: ${web_protocol}://${sec_host}${sec_path}
Suites: ${SYSTEM_VERSION_CODENAME}-security
Components: ${components}
Signed-By: /usr/share/keyrings/${SYSTEM_ID}-archive-keyring.gpg
EOF
    else
        cat > "$source_file" << EOF
deb ${web_protocol}://${source_host}${main_path} ${SYSTEM_VERSION_CODENAME} ${components}
deb ${web_protocol}://${source_host}${main_path} ${SYSTEM_VERSION_CODENAME}-updates ${components}
deb ${web_protocol}://${sec_host}${sec_path} ${SYSTEM_VERSION_CODENAME}-security ${components}
EOF
    fi
}

change_mirrors_RedHat_and_EPEL() {
    local country_code="$1"
    log "正在配置基础源和 EPEL 源..."
    mkdir -p "$Dir_YumRepos/bak"
    mv $Dir_YumRepos/*.repo $Dir_YumRepos/bak/ 2>/dev/null || true

    if [[ "$SYSTEM_ID" == "centos" ]]; then
        if [ "$SYSTEM_VERSION_ID_MAJOR" -eq 7 ]; then
            curl -fsSL -o $Dir_YumRepos/CentOS-Base.repo https://mirrors.tencent.com/repo/centos7_base.repo
            curl -fsSL -o $Dir_YumRepos/epel.repo https://mirrors.tencent.com/repo/epel-7.repo
        elif [ "$SYSTEM_VERSION_ID_MAJOR" -eq 8 ]; then
            # CentOS 8 已 EOL，使用官方 vault 归档源（全球可访问）
            log "检测到 CentOS 8 (已 EOL)，使用官方 vault 归档源..."
            cat > "$Dir_YumRepos/CentOS-Base.repo" << 'EOF'
[base]
name=CentOS-$releasever - Base
baseurl=https://vault.centos.org/8.5.2111/BaseOS/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial

[appstream]
name=CentOS-$releasever - AppStream
baseurl=https://vault.centos.org/8.5.2111/AppStream/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial

[extras]
name=CentOS-$releasever - Extras
baseurl=https://vault.centos.org/8.5.2111/extras/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial

[centosplus]
name=CentOS-$releasever - Plus
baseurl=https://vault.centos.org/8.5.2111/centosplus/$basearch/os/
gpgcheck=1
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
EOF

            # EPEL for CentOS 8 from official archive
            cat > "$Dir_YumRepos/epel.repo" << 'EOF'
[epel]
name=Extra Packages for Enterprise Linux $releasever - $basearch
baseurl=https://dl.fedoraproject.org/pub/epel/8/Everything/$basearch
enabled=1
gpgcheck=1
gpgkey=https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-8
EOF
        fi
    else
        if [[ "$country_code" == "CN" ]]; then
            log "IP所在地为中国，配置 EPEL 使用腾讯云镜像..."
            sed -i -e 's|^metalink=|#metalink=|g' \
                   -e 's|^#baseurl=https://download.fedoraproject.org/pub|baseurl=https://mirrors.tencent.com|g' \
                   /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel-*.repo 2>/dev/null || true
        else
            log "IP所在地为海外，使用 EPEL 官方源。"
        fi
    fi
}

#==================================================
# 🚀 模式1 & 🔧 模式2
#==================================================
main_install() {
    log "正在根据IP所在地选择最佳软件源..."; local country_code; country_code=$(get_country_code)

    case "$SYSTEM_FACTIONS" in
        "DEBIAN_FAMILY")
            change_mirrors_Debian_family "$country_code"
            apt-get clean
            log "正在更新软件包列表..."
            if ! apt-get update; then error "'apt-get update' 失败。"; fi
            apt-get install -y fail2ban
            ;;
        "REDHAT")
            log "正在安装 EPEL 源..."
            yum install -y epel-release || error "安装 epel-release 失败。"
            change_mirrors_RedHat_and_EPEL "$country_code"
            log "正在创建缓存..."
            yum makecache  # ← 关键修复：移除 'fast'
            log "正在安装 fail2ban..."
            yum install -y fail2ban
            ;;
        "ALPINE")
            if [[ "$country_code" == "CN" ]]; then
                log "IP在中国，使用腾讯云镜像。"
                sed -i 's/dl-cdn.alpinelinux.org/mirrors.tencent.com/g' "$File_AlpineRepositories"
            fi
            apk update
            apk add fail2ban fail2ban-openrc
            ;;
        "ARCH")
            pacman -Sy --noconfirm fail2ban
            ;;
        *)
            error "不支持的系统: $SYSTEM_PRETTY_NAME"
            ;;
    esac

    log "正在配置 fail2ban (sshd)..."
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
banaction = iptables-multiport

[sshd]
enabled = true
backend = auto
maxretry = 3
findtime = 10m
bantime = 24h
EOF

    start_and_verify_fail2ban
}

main_repair() {
    log "开始执行检查与修复模式..."; if ! command -v fail2ban-server &> /dev/null; then error "Fail2ban 尚未安装，请选择模式1。"; fi

    if ! command -v iptables &> /dev/null; then
        log "核心依赖 'iptables' 未找到，正在尝试安装...";
        case "$SYSTEM_FACTIONS" in
            "DEBIAN_FAMILY") apt-get update && apt-get install -y iptables ;;
            "REDHAT") yum install -y iptables ;;
            *) warn "无法自动安装 iptables。";;
        esac
    fi

    if [ ! -f /etc/fail2ban/jail.local ]; then error "/etc/fail2ban/jail.local 不存在，无法修复。"; fi
    
    # 修复：正确使用 sed 正则捕获组，去除多余空格和错误字符
    if grep -q -E "^\s*banaction\s*=" /etc/fail2ban/jail.local; then
        log "检测到已存在的 banaction, 强制更新为 iptables-multiport..."
        sed -i "s/^\(\s*banaction\s*=\s*\).*/\1iptables-multiport/" /etc/fail2ban/jail.local
    else
        log "未找到 banaction, 正在 [DEFAULT] 段落中添加..."
        sed -i '/^\[DEFAULT\]$/a banaction = iptables-multiport' /etc/fail2ban/jail.local
    fi

    if command -v systemctl &> /dev/null; then
        log "检测到 systemd 系统，将优化配置以使用 systemd 日志..."
        # 修复：界定范围和替换的正则语法
        sed -i "/^\[sshd\]$/,/^\[/ s/^\(\s*backend\s*=\s*\).*/\1systemd/" /etc/fail2ban/jail.local
        log "已在 [sshd] 配置中强制设置 'backend = systemd'。"
    fi

    start_and_verify_fail2ban "修复后"
}

#==================================================
# 🔍 模式3：查询封禁信息 (核心优化部分)
#==================================================
query_ssh_bans() {
    log "开始查询 SSH 爆破封禁的详细信息..."

    if ! command -v fail2ban-client &> /dev/null; then
        error "Fail2ban 客户端 (fail2ban-client) 未找到。请先安装 Fail2ban (选项1)。"
        return 1
    fi

    local status
    status=$(fail2ban-client status sshd 2>&1)
    if [ $? -ne 0 ] || [[ "$status" == *"No such jail"* ]]; then
        warn "无法获取 'sshd' 防护策略(jail)的状态。可能原因："
        echo -e "${C_YELLOW}  1. Fail2ban 服务未运行。"
        echo -e "  2. 'sshd' 防护策略在配置文件中被禁用或不存在。"
        echo -e "  3. 配置文件存在语法错误。${C_RESET}"
        log "将尝试检查 Fail2ban 总体服务状态..."
        if command -v systemctl &> /dev/null; then systemctl status fail2ban --no-pager; elif command -v rc-service &> /dev/null; then rc-service fail2ban status; fi
        return 1
    fi
    
    # --- 1. SSH 防护状态概览 ---
    header "🛡️ [1/4] SSH 防护状态概览"
    local current_failed total_failed currently_banned total_banned banned_ips
    current_failed=$(echo "$status" | grep -o 'Currently failed:[^0-9]*[0-9]\+' | awk '{print $NF}')
    total_failed=$(echo "$status" | grep -o 'Total failed:[^0-9]*[0-9]\+' | awk '{print $NF}')
    currently_banned=$(echo "$status" | grep -o 'Currently banned:[^0-9]*[0-9]\+' | awk '{print $NF}')
    total_banned=$(echo "$status" | grep -o 'Total banned:[^0-9]*[0-9]\+' | awk '{print $NF}')
    banned_ips=$(echo "$status" | grep 'Banned IP list:' | sed 's/Banned IP list:[ \t]*//')

    echo -e "   ${C_BLUE}${C_BOLD}核心监控指标:${C_RESET}"
    printf "    %-20s :  ${C_YELLOW}%s${C_RESET} 次 (归零周期: findtime)\n" "当前失败次数" "${current_failed}"
    printf "    %-20s :  ${C_CYAN}%s${C_RESET} 次\n" "历史失败总计" "${total_failed}"
    printf "    %-20s :  ${C_RED}${C_BOLD}%s${C_RESET} 个\n" "当前封禁 IP 数" "${currently_banned}"
    printf "    %-20s :  ${C_CYAN}%s${C_RESET} 个\n" "历史封禁总计" "${total_banned}"
    
    echo -e "\n   ${C_BLUE}${C_BOLD}当前已封禁 IP 列表:${C_RESET}"
    if [ -n "$banned_ips" ]; then
        echo "$banned_ips" | xargs -n 5 | sed "s/^/     ${C_MAGENTA}➔${C_RESET} "
    else
        echo -e "     ${C_GREEN}太棒了！当前没有任何 IP 被封禁。${C_RESET}"
    fi

    # --- 2. 最近封禁动作日志 ---
    header "📜 [2/4] 最近 15 条封禁操作日志"
    local fail2ban_log="/var/log/fail2ban.log"
    if [ -f "$fail2ban_log" ] && grep -q "sshd" "$fail2ban_log"; then
        local ban_logs
        ban_logs=$(grep "Ban" "$fail2ban_log" | grep "sshd" | tail -n 15)
        if [ -n "$ban_logs" ]; then
            echo "$ban_logs" | awk '{print "  [⏰] 操作时间: " $1 " " $2 " | 动作: \033[1;31m封禁\033[0m | IP 地址: \033[33m" $NF "\033[0m"}'
        else
            echo -e "   ${C_GREEN}在日志中未找到近期的 'sshd' 封禁 (Ban) 记录。${C_RESET}"
        fi
    else
        warn "  未找到或无法读取 fail2ban 日志 ($fail2ban_log)，或日志中无 'sshd' 相关内容。"
    fi

    # --- 3. 系统日志中的攻击源头 ---
    header "💥 [3/4] 系统日志中最近 20 条 SSH 失败尝试"
    local attacker_ips="" found_logs=false
    if command -v journalctl &> /dev/null && journalctl -u sshd &> /dev/null; then
        log "  正在从 systemd journald 查询 (最近24小时)..."
        journalctl -u sshd --since "24 hours ago" -o short-iso | grep -E "Failed password|Connection closed by authenticating user" | tail -n 20 | while read -r line; do
            local timestamp ip user
            timestamp=$(echo "$line" | awk '{print $1" " substr($2,1,8)}')
            ip=$(echo "$line" | grep -oE 'from [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | awk '{print $2}')
            user=$(echo "$line" | grep -oE 'for (invalid user )?[a-zA-Z0-9_.-]+' | sed -e 's/for invalid user //' -e 's/for //')
            
            if [ -n "$ip" ]; then
                echo -e "  [${C_YELLOW}${timestamp}${C_RESET}] 尝试用户: ${C_CYAN}${user:-未知}${C_RESET} | ${C_RED}攻击源 IP: ${ip}${C_RESET}"
                attacker_ips+="$ip "
                found_logs=true
            fi
        done
        if [ "$found_logs" = false ]; then echo -e "   ${C_GREEN}在过去24小时的 journald 日志中未找到 SSH 登录失败记录。${C_RESET}"; fi
    else
        log "  未检测到 systemd, 尝试从传统日志文件查询..."
        local auth_log="/var/log/auth.log"
        local secure_log="/var/log/secure"
        local log_file=""
        if [ -f "$auth_log" ]; then log_file="$auth_log"; elif [ -f "$secure_log" ]; then log_file="$secure_log"; fi

        if [ -n "$log_file" ]; then
            grep -E "sshd.*(Failed password|Connection closed by authenticating user)" "$log_file" | tail -n 20 | while read -r line; do
                 local timestamp ip user
                 timestamp=$(echo "$line" | cut -d' ' -f1-3)
                 ip=$(echo "$line" | grep -oE 'from [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | awk '{print $2}')
                 user=$(echo "$line" | grep -oE 'for (invalid user )?[a-zA-Z0-9_.-]+' | sed -e 's/for invalid user //' -e 's/for //')

                 if [ -n "$ip" ]; then
                     echo -e "  [${C_YELLOW}${timestamp}${C_RESET}] 尝试用户: ${C_CYAN}${user:-未知}${C_RESET} | ${C_RED}攻击源 IP: ${ip}${C_RESET}"
                     attacker_ips+="$ip "
                     found_logs=true
                 fi
            done
            if [ "$found_logs" = false ]; then echo -e "   ${C_GREEN}在 $log_file 中未找到近期的 SSH 登录失败记录。${C_RESET}"; fi
        else
            warn "  未找到常见的 SSH 认证日志文件 (/var/log/auth.log 或 /var/log/secure)。"
        fi
    fi
    
    # --- 4. 攻击来源地理位置分析 ---
    header "🌍 [4/4] 攻击来源地理位置分析 (Top 5 攻击源)"
    if ! command -v curl &> /dev/null; then
        warn "  'curl' 命令未找到，无法进行 IP 地理位置查询。请先安装 curl。"
        return
    fi
    if [ -z "$attacker_ips" ]; then
        echo -e "   ${C_GREEN}最近24小时内无攻击记录，无需分析。${C_RESET}"
        return
    fi

    log "  正在分析攻击 IP 并查询地理位置，请稍候..."
    local top_attackers rank=0
    top_attackers=$(echo "$attacker_ips" | tr ' ' '\n' | grep . | sort | uniq -c | sort -rnb | head -n 5)
    
    echo "$top_attackers" | while read -r count ip; do
        ((rank++))
        local geo_info country city region
        geo_info=$(curl -fsSL --connect-timeout 3 "https://ipinfo.io/${ip}/json")
        if [ -n "$geo_info" ]; then
            country=$(echo "$geo_info" | grep '"country"' | awk -F'"' '{print $4}')
            city=$(echo "$geo_info" | grep '"city"' | awk -F'"' '{print $4}')
            region=$(echo "$geo_info" | grep '"region"' | awk -F'"' '{print $4}')
            printf "   ${C_BOLD}[#%d]${C_RESET} IP: ${C_YELLOW}%-15s${C_RESET} | 次数: ${C_RED}%-4s${C_RESET} | 地区: ${C_GREEN}%s, %s, %s${C_RESET}\n" "$rank" "$ip" "$count" "${country:-N/A}" "${region:-N/A}" "${city:-N/A}"
        else
            printf "   ${C_BOLD}[#%d]${C_RESET} IP: ${C_YELLOW}%-15s${C_RESET} | 次数: ${C_RED}%-4s${C_RESET} | ${C_YELLOW}地区: 查询失败或超时${C_RESET}\n" "$rank" "$ip" "$count"
        fi
        sleep 0.2 # 避免 API 请求过于频繁
    done

    log "查询完成。"
}

#==================================================
# ⚙️ 服务启动与验证
#==================================================
start_and_verify_fail2ban() {
    local action_prefix=${1:-""}; log "正在启动/重启 fail2ban 服务..."
    if command -v systemctl &> /dev/null; then
        systemctl enable fail2ban; systemctl restart fail2ban
        log "正在循环检测服务状态 (最多15秒)..."
        for i in {1..15}; do
            if systemctl is-active --quiet fail2ban && fail2ban-client ping >/dev/null 2>&1; then
                log "✅ ${action_prefix} fail2ban 已成功启动并响应！SSH 防护已开启！"; 
                fail2ban-client status sshd >/dev/null 2>&1 && fail2ban-client status sshd || true; 
                return 0
            fi; sleep 1; echo -n "."; done
        echo
        error "【严重】${action_prefix} fail2ban 启动失败或无响应。请检查详细错误日志：\n--- journalctl -u fail2ban -n 10 --no-pager --no-hostname --- \n$(journalctl -u fail2ban -n 10 --no-pager --no-hostname)"
    elif command -v rc-update &> /dev/null; then
        rc-update add fail2ban default; rc-service fail2ban restart; sleep 3
        if rc-service fail2ban status &> /dev/null; then log "✅ ${action_prefix} fail2ban 已成功启动。SSH 防护已开启！"; fail2ban-client status sshd || true;
        else error "${action_prefix} fail2ban 启动失败，请检查日志。"; fi
    else
        warn "⚠️ fail2ban 已安装，但未检测到 systemd 或 OpenRC, 请手动启动服务。"
    fi
}

#==================================================
# 🎬 主程序入口
#==================================================
display_menu() {
    clear
    echo -e "${C_CYAN}${C_BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║      Fail2ban 智能安装与查询脚本 v6.1 (智能分析版)         ║"
    echo "║                                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${C_RESET}"
    echo "请选择要执行的操作:"
    echo -e "   ${C_GREEN}1) 🚀  全新安装 Fail2ban (推荐)${C_RESET}"
    echo -e "   ${C_YELLOW}2) 🔧  检查与修复 Fail2ban (如已安装但不工作)${C_RESET}"
    echo -e "   ${C_BLUE}3) 📊  查询 SSH 爆破与封禁的详细分析报告${C_RESET}"
    echo
}

main() {
    if [ "$EUID" -ne 0 ]; then error "请以 root 用户运行此脚本。"; fi
    detect_system
    display_menu
    
    read -t 10 -p "$(echo -e ${C_CYAN}${C_BOLD}"请输入选项 [1-3]，10秒后将自动执行默认选项 [1]: "${C_RESET})" choice || choice=1
    
    case "$choice" in
        1) log "您选择了：1. 全新安装 Fail2ban"; main_install ;;
        2) log "您选择了：2. 检查与修复 Fail2ban"; main_repair ;;
        3) log "您选择了：3. 查询详细分析报告"; query_ssh_bans ;;
        *) log "无效输入，执行默认选项：1. 全新安装 Fail2ban"; main_install ;;
    esac
    log "🎉 脚本执行完毕！"
}

main