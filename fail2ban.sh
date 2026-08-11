#!/bin/bash
#======================================================================
# 🛡️  Fail2ban 智能管理脚本 (适用于 Debian 系，如 Ubuntu/Mint)
# ✅ 功能：安装、启动、停止、状态查看、日志查看、封禁记录
# ✅ 使用系统默认 apt 源，无换源逻辑
#======================================================================
set -euo pipefail

# --- 颜色与样式 ---
C_RESET="\033[0m"
C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_MAGENTA="\033[35m"
C_CYAN="\033[36m"
C_BOLD="\033[1m"

# --- 日志函数 ---
log()   { echo -e "${C_GREEN}【信息】 $* ${C_RESET}"; }
warn()  { echo -e "${C_YELLOW}【警告】 $* ${C_RESET}" >&2; }
error() { echo -e "${C_RED}【错误】 $* ${C_RESET}" >&2; exit 1; }
header(){ echo -e "\n${C_CYAN}${C_BOLD}═══════════  $* ═══════════${C_RESET}"; }

# --- 配置 sshd 防护 ---
configure_sshd_jail() {
    log "配置 SSH 防护策略..."
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
banaction = iptables-multiport

[sshd]
enabled = true
backend = systemd
maxretry = 3
findtime = 10m
bantime = 24h
EOF
    log "已写入 /etc/fail2ban/jail.local"
}

# --- 启动服务 ---
start_fail2ban() {
    log "启动 fail2ban 服务..."
    if ! command -v systemctl &>/dev/null; then
        error "未检测到 systemd，此脚本需要 systemd 支持。"
    fi
    systemctl enable fail2ban --now || error "启动 fail2ban 失败。"
    sleep 2
    if systemctl is-active --quiet fail2ban && fail2ban-client ping &>/dev/null; then
        log "✅ fail2ban 已启动并响应。"
    else
        error "fail2ban 启动后未响应，请检查日志。"
    fi
}

# --- 停止服务 ---
stop_fail2ban() {
    log "停止 fail2ban 服务..."
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        systemctl stop fail2ban
        log "✅ fail2ban 已停止。"
    else
        warn "fail2ban 当前未运行。"
    fi
}

# --- 查看状态 ---
status_fail2ban() {
    header "📊 Fail2ban 服务状态"
    systemctl status fail2ban --no-pager || true
    echo

    if ! fail2ban-client ping &>/dev/null; then
        warn "Fail2ban 服务未响应，请先启动。"
        return 1
    fi

    header "🛡️  SSH 防护状态 (jail 'sshd')"
    local status
    status=$(fail2ban-client status sshd 2>&1)
    if [[ "$status" == *"No such jail"* ]]; then
        warn "未找到 'sshd' 防护策略，请检查配置。"
        return
    fi

    local current_failed total_failed currently_banned total_banned banned_ips
    current_failed=$(echo "$status" | grep -o 'Currently failed:[^0-9]*[0-9]\+' | awk '{print $NF}')
    total_failed=$(echo "$status" | grep -o 'Total failed:[^0-9]*[0-9]\+' | awk '{print $NF}')
    currently_banned=$(echo "$status" | grep -o 'Currently banned:[^0-9]*[0-9]\+' | awk '{print $NF}')
    total_banned=$(echo "$status" | grep -o 'Total banned:[^0-9]*[0-9]\+' | awk '{print $NF}')
    banned_ips=$(echo "$status" | grep 'Banned IP list:' | sed 's/Banned IP list:[ \t]*//')

    echo -e "  ${C_BLUE}${C_BOLD}监控指标：${C_RESET}"
    printf "    %-20s : ${C_YELLOW}%s${C_RESET} 次 (findtime周期内)\n" "当前失败次数" "${current_failed:-0}"
    printf "    %-20s : ${C_CYAN}%s${C_RESET} 次\n" "历史失败总计" "${total_failed:-0}"
    printf "    %-20s : ${C_RED}${C_BOLD}%s${C_RESET} 个\n" "当前封禁IP数" "${currently_banned:-0}"
    printf "    %-20s : ${C_CYAN}%s${C_RESET} 个\n" "历史封禁总计" "${total_banned:-0}"

    echo -e "\n  ${C_BLUE}${C_BOLD}当前封禁 IP 列表：${C_RESET}"
    if [ -n "$banned_ips" ]; then
        echo "$banned_ips" | tr ' ' '\n' | while read -r ip; do
            [ -n "$ip" ] && echo -e "     ${C_MAGENTA}➔${C_RESET} $ip"
        done
    else
        echo -e "     ${C_GREEN}✅ 当前没有 IP 被封禁。${C_RESET}"
    fi
}

# --- 查看运行日志 ---
view_logs() {
    header "📜 Fail2ban 运行日志 (最近 50 行)"
    local log_file="/var/log/fail2ban.log"
    if [ ! -f "$log_file" ]; then
        warn "日志文件 $log_file 不存在，服务可能未启动或未产生日志。"
        return
    fi
    tail -n 50 "$log_file" | while read -r line; do
        echo -e "  ${C_CYAN}$line${C_RESET}"
    done
}

# --- 查看封禁记录 ---
view_bans() {
    header "🔒 封禁 / 解封 记录 (最近 30 条)"
    local log_file="/var/log/fail2ban.log"
    if [ ! -f "$log_file" ]; then
        warn "日志文件 $log_file 不存在。"
        return
    fi
    local records
    records=$(grep -E " Ban | Unban " "$log_file" | grep "sshd" | tail -n 30)
    if [ -z "$records" ]; then
        echo -e "  ${C_GREEN}未找到任何封禁或解封记录。${C_RESET}"
        return
    fi
    echo "$records" | while read -r line; do
        local timestamp action ip
        timestamp=$(echo "$line" | awk '{print $1 " " $2}')
        action=$(echo "$line" | grep -o -E "Ban|Unban" | head -1)
        ip=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [ -n "$ip" ]; then
            if [ "$action" == "Ban" ]; then
                echo -e "  [${C_YELLOW}${timestamp}${C_RESET}] ${C_RED}封禁${C_RESET} IP: ${C_MAGENTA}$ip${C_RESET}"
            else
                echo -e "  [${C_YELLOW}${timestamp}${C_RESET}] ${C_GREEN}解封${C_RESET} IP: ${C_MAGENTA}$ip${C_RESET}"
            fi
        fi
    done
}

# --- 安装 Fail2ban ---
install_fail2ban() {
    log "开始安装 Fail2ban..."
    if command -v fail2ban-server &>/dev/null; then
        warn "Fail2ban 已安装，如需重装请先卸载。"
        return 0
    fi

    log "更新软件包列表（使用系统默认源）..."
    apt-get clean
    apt-get update || error "apt-get update 失败。"

    log "安装 fail2ban ..."
    apt-get install -y fail2ban || error "安装失败。"

    configure_sshd_jail
    start_fail2ban
    log "✅ Fail2ban 安装并启动成功！"
}

# --- 主菜单 ---
display_menu() {
    clear
    echo -e "${C_CYAN}${C_BOLD}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║       Fail2ban 智能管理脚本 (Debian 系通用版)            ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${C_RESET}"
    echo "请选择操作："
    echo -e "  ${C_GREEN}0) 🚀  安装 Fail2ban${C_RESET}"
    echo -e "  ${C_GREEN}1) ▶️   启动 Fail2ban${C_RESET}"
    echo -e "  ${C_YELLOW}2) ⏹️   停止 Fail2ban${C_RESET}"
    echo -e "  ${C_BLUE}3) 📊  查看状态${C_RESET}"
    echo -e "  ${C_BLUE}4) 📜  查看运行日志${C_RESET}"
    echo -e "  ${C_BLUE}5) 🔒  查看封禁记录${C_RESET}"
    echo
}

# --- 主入口 ---
main() {
    if [ "$EUID" -ne 0 ]; then error "请以 root 用户运行此脚本。"; fi

    # 仅显示系统信息，不强制检查发行版
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log "当前系统：${PRETTY_NAME:-$ID $VERSION_ID}"
    else
        log "无法识别系统发行版，脚本将尝试使用 apt 和 systemd。"
    fi

    while true; do
        display_menu
        read -p "$(echo -e ${C_CYAN}${C_BOLD}"请输入选项 [0-5]："${C_RESET})" choice
        case "$choice" in
            0) install_fail2ban ;;
            1) start_fail2ban ;;
            2) stop_fail2ban ;;
            3) status_fail2ban ;;
            4) view_logs ;;
            5) view_bans ;;
            *) echo -e "${C_RED}无效输入，请重新选择。${C_RESET}"; continue ;;
        esac
        echo -e "\n${C_GREEN}按 Enter 键返回主菜单...${C_RESET}"
        read -r
    done
}

main