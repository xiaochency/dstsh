#!/bin/bash
# ------------------------------------------------------------------
# 文件名: cpu_benchmark.sh
# 描述: 通过 sysbench 测试 CPU 单核/多核性能，带彩色菜单
# 适用系统: Ubuntu 22.04
# ------------------------------------------------------------------

set -e

# ---------- 颜色定义 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ---------- 辅助函数 ----------
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_title() {
    echo -e "${BOLD}${CYAN}$1${NC}"
}

print_menu_item() {
    echo -e "${BOLD}${BLUE}$1${NC})${NC} $2"
}

# ---------- 检查并安装 sysbench ----------
check_and_install_sysbench() {
    if ! command -v sysbench &> /dev/null; then
        print_warn "sysbench 未安装，正在自动安装（需要 sudo 权限）..."
        sudo apt update -qq
        sudo apt install -y sysbench
        if [ $? -eq 0 ]; then
            print_info "sysbench 安装成功！"
        else
            print_error "sysbench 安装失败，请手动安装后再运行脚本。"
            exit 1
        fi
    else
        print_info "sysbench 已安装，版本: $(sysbench --version)"
    fi
}

# ---------- CPU 测试函数 ----------
run_cpu_test() {
    local threads=$1
    local test_name=$2

    echo ""
    print_title "========== 开始 ${test_name} CPU 测试 (线程数: ${threads}) =========="
    echo ""

    # 运行 sysbench CPU 测试（默认 prime 计算，时间 10 秒可调整）
    # 使用 --time=10 快速测试，也可改为 30 或 60 获取更稳定结果
    sysbench cpu --threads=${threads} --time=30 run

    echo ""
    print_info "${test_name} CPU 测试完成。"
    echo ""
}

# ---------- 菜单显示 ----------
show_menu() {
    clear
    print_title "==========================================="
    print_title "          CPU 性能测试工具 (sysbench)       "
    print_title "==========================================="
    echo ""
    print_menu_item "1" "运行 单核 CPU 测试"
    print_menu_item "2" "运行 多核 CPU 测试 (使用所有核心)"
    print_menu_item "3" "运行 单核 + 多核 CPU 测试 (连续)"
    print_menu_item "0" "退出"
    echo ""
    echo -n "请输入您的选择 [0-3]: "
}

# ---------- 主流程 ----------
main() {
    # 检查并安装 sysbench
    check_and_install_sysbench

    while true; do
        show_menu
        read -r choice
        case $choice in
            1)
                run_cpu_test 1 "单核"
                read -p "按回车键继续..."
                ;;
            2)
                local total_cores=$(nproc)
                run_cpu_test ${total_cores} "多核 (${total_cores} 核)"
                read -p "按回车键继续..."
                ;;
            3)
                run_cpu_test 1 "单核"
                local total_cores=$(nproc)
                run_cpu_test ${total_cores} "多核 (${total_cores} 核)"
                read -p "全部测试完成，按回车键继续..."
                ;;
            0)
                print_info "感谢使用，再见！"
                exit 0
                ;;
            *)
                print_error "无效选项，请重新选择。"
                sleep 1
                ;;
        esac
    done
}

# 捕获 Ctrl+C 等中断信号，优雅退出
trap 'echo ""; print_warn "用户中断执行"; exit 1' INT TERM

# 执行主函数
main
