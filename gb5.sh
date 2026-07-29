#!/bin/bash

# 脚本发布版本
script_version="v2026-07-29"

# geekbench5发布版本
geekbench_version="5.5.1"
geekbench_tar_name="Geekbench-${geekbench_version}-Linux.tar.gz"
geekbench_tar_folder="Geekbench-${geekbench_version}-Linux"
geekbench_software_name="geekbench5"

# 测试工作目录
dir="./gb5-github-i-abc"

##### 配色 #####

red() {
    echo -e "\033[0;31;31m$1\033[0m"
}

yellow() {
    echo -e "\033[0;31;33m$1\033[0m"
}

blue() {
    echo -e "\033[0;31;36m$1\033[0m"
}

##### 横幅 #####
banner() {
    echo -e "# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #"
    echo -e "#            专用于服务器的GB5测试             #"
    echo -e "#                 $script_version                  #"
    echo -e "# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #"
    echo
}

##### 检测locale配置并覆盖为C语言环境 #####
check_locale() {
    if locale -a 2>/dev/null | grep -q "^C$"; then
        export LC_ALL=C
    fi
}

##### 检测某软件包是否安装，没安则自动安上，目前只支持RedHat、Debian系 #####
check_package() {
    yellow "正在检测所需的$1是否安装"
    # 检测软件包是否安装
    if ! command -v $1; then
        # 确认包管理器并安装软件包
        if command -v dnf; then
            sudo dnf -y install $2
        elif command -v yum; then
            sudo yum -y install $2
        elif command -v apt; then
            sudo apt -y install $2
        else
            blue "本机非RedHat、Debian系，暂不支持自动安装所需的软件包"
            exit
        fi
        # 再次检测软件包是否安装
        if ! command -v $1; then
            red "自动安装所需的$1失败"
            echo "请手动安装$1后再执行本脚本"
            exit
        fi
    fi
}

##### 创建目录
make_dir() {
    if [ ! -d "$dir" ]; then
        mkdir -p $dir
    fi
}

##### 检测IPv4网络（增强版） #####
check_ip() {
    # 1. 检查是否存在非内网 IPv4 地址
    local ipv4=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | grep -v '^169\.254' | head -1)
    if [ -z "$ipv4" ]; then
        echo -e "错误：未检测到有效的 IPv4 地址，本机可能为 IPv6 单栈。"
        echo -e "由于 Geekbench 结果上传需要 IPv4，测试无法继续。"
        exit 1
    fi
    blue "检测到 IPv4 地址：$ipv4"

    # 2. 使用 4.itdog.cn 验证 IPv4 网络连通性
    if curl -4 -s --connect-timeout 5 "https://4.itdog.cn" >/dev/null; then
        blue "IPv4 网络连通正常（通过 4.itdog.cn 验证）"
    else
        echo -e "警告：无法通过 4.itdog.cn 验证 IPv4 连通性，网络可能存在问题。"
        echo -e "但可尝试继续测试（结果上传可能失败）。"
        # 询问是否继续
        echo -e "是否强制继续测试？(y/N)：\c"
        read -r force_continue
        if [[ ! "$force_continue" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # 3. 尝试访问 Geekbench 浏览器站点（只警告，不退出）
    if ! curl -4 -s 'https://browser.geekbench.com' --connect-timeout 5 >/dev/null; then
        echo -e "提示：无法访问 browser.geekbench.com，这可能影响结果上传。"
        echo -e "若您确定网络可通，可忽略此提示。"
    fi
}

##### 判断IP所在地，选择相应下载源 #####
check_region() {
    echo "请选择一个下载源："
    echo "  1) ghfast.top 镜像源"
    echo "  2) github.dpik.top 镜像源"
    echo "  3) cdn.gh-proxy.org 镜像源"
    echo "  4) edgeone.gh-proxy.org 镜像源"
    echo -e "\n请输入选项编号 (1-4)：\c"
    read -r source_choice
    echo -e "\033[0m"

    case "$source_choice" in
        1)
            blue "已选择源 1: ghfast.top"
            geekbench_tar_url="https://ghfast.top/github.com/xiaochency/dstsh/releases/download/2nd/Geekbench-5.5.1-Linux.tar.gz"
            ;;
        2)
            blue "已选择源 2: github.dpik.top"
            geekbench_tar_url="https://github.dpik.top/github.com/xiaochency/dstsh/releases/download/2nd/Geekbench-5.5.1-Linux.tar.gz"
            ;;
        3)
            blue "已选择源 3: cdn.gh-proxy.org"
            geekbench_tar_url="https://cdn.gh-proxy.org/https://github.com/xiaochency/dstsh/releases/download/2nd/Geekbench-5.5.1-Linux.tar.gz"
            ;;
        4)
            blue "已选择源 4: edgeone.gh-proxy.org"
            geekbench_tar_url="https://edgeone.gh-proxy.org/https://github.com/xiaochency/dstsh/releases/download/2nd/Geekbench-5.5.1-Linux.tar.gz"
            ;;
        *)
            red "输入错误！请输入 1 到 4 之间的数字。"
            exit 1
            ;;
    esac
}

##### 下载Geekbench tar包 ######
download_geekbench() {
    yellow "测试软件下载中"
    axel -n 10 -o "$dir/${geekbench_tar_name}" "$geekbench_tar_url"
}

##### 解tar包 #####
unzip_tar() {
    tar -xf $dir/${geekbench_tar_name} -C ./$dir
}

##### 运行测试 #####
run_test() {
    yellow "测试中\n"

    # 计时开始
    run_start_time=$(date +"%s")

    $dir/${geekbench_tar_folder}/${geekbench_software_name} | tee $dir/result.txt
    
    # 计时结束
    run_end_time=$(date +"%s")

    # 计算测试运行时间
    run_time=$((run_end_time - run_start_time))
    run_time_minutes=$((run_time / 60))
    run_time_seconds=$((run_time % 60))
}

##### 输出结果 (含时间、参数、链接) #####
output_summary() {
    echo "当前时间：$(date +"%Y-%m-%d %H:%M:%S %Z")"
    echo -e "净测试时长：$run_time_minutes分$run_time_seconds秒\n"

    yellow "Geekbench 5 测试结果\n"
    awk '/System Information/,/Size/{sub("System Information", "系统信息"); sub("Processor Information", "处理器信息"); sub("Memory Information", "内存信息"); print}' $dir/result.txt

    echo
    # ---------- 链接输出 ----------
    awk '/https.*cpu\/[0-9]*$/{print "详细结果链接：" $1}' $dir/result.txt
    cpu=$(awk -F 'with an? | processor' '/Benchmark results for/{gsub(/ /,"%20",$2); print $2}' $dir/result.html 2>/dev/null)
    if [ -n "$cpu" ]; then
        echo "可供参考链接：https://browser.geekbench.com/search?k=v5_cpu&q=$cpu"
    fi
    echo
    awk '/https.*key=[0-9]*$/{print "个人保存链接：" $1}' $dir/result.txt
}

##### 查看已保存的结果 #####
view_saved_result() {
    if [ ! -f "$dir/result.txt" ]; then
        red "未找到测试结果文件，请先运行测试（选项1）。"
        return 1
    fi

    echo "当前时间：$(date +"%Y-%m-%d %H:%M:%S %Z")"
    echo -e "（显示上次保存的测试结果）\n"

    yellow "Geekbench 5 测试结果\n"
    awk '/System Information/,/Size/{sub("System Information", "系统信息"); sub("Processor Information", "处理器信息"); sub("Memory Information", "内存信息"); print}' $dir/result.txt
    echo

    # 链接输出
    awk '/https.*cpu\/[0-9]*$/{print "详细结果链接：" $1}' $dir/result.txt
    cpu=$(awk -F 'with an? | processor' '/Benchmark results for/{gsub(/ /,"%20",$2); print $2}' $dir/result.html 2>/dev/null)
    if [ -n "$cpu" ]; then
        echo "可供参考链接：https://browser.geekbench.com/search?k=v5_cpu&q=$cpu"
    fi
    echo
    awk '/https.*key=[0-9]*$/{print "个人保存链接：" $1}' $dir/result.txt
}

##### 安装 GB5（下载并解压） #####
install_gb5() {
    clear
    banner

    # 检查工作目录是否存在，若存在则删除
    if [ -d "$dir" ]; then
        yellow "检测到已存在的测试目录，将删除并重新安装。"
        rm -rf $dir
        blue "已删除旧目录。"
    fi

    check_locale
    check_ip
    check_package axel axel
    check_package curl curl
    check_package tar tar
    check_package perl perl
    make_dir

    # 下载压缩包
    check_region
    download_geekbench

    # 解压（目录为空，必然需要解压）
    unzip_tar
    blue "解压完成。"

    echo
    blue "GB5 安装完成。"
    echo
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

##### 运行 GB5 测试 #####
run_gb5_test() {
    clear
    banner
    check_locale
    check_package curl curl   # 测试时也需要curl下载结果页
    check_package perl perl
    make_dir

    # 检查可执行文件是否存在
    if [ ! -x "$dir/${geekbench_tar_folder}/${geekbench_software_name}" ]; then
        red "错误：未找到 Geekbench 可执行文件，请先执行安装（选项0）。"
        read -n 1 -s -r -p "按任意键返回主菜单..."
        return 1
    fi

    clear
    banner
    run_test
    clear
    echo
    banner
    output_summary
    echo
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

##### 主菜单 #####
main() {
    while true; do
        clear
        banner
        echo "主菜单"
        echo "  0) 安装 GB5（下载并解压）"
        echo "  1) 执行 GB5 测试"
        echo "  2) 查看上一次测试结果"
        echo "  3) 退出"
        echo
        yellow "请输入选项编号 (0-3)：\c"
        read -r choice
        echo -e "\033[0m"

        case "$choice" in
            0) install_gb5 ;;
            1) run_gb5_test ;;
            2) view_saved_result ; echo ; read -n 1 -s -r -p "按任意键返回主菜单..." ;;
            3) echo "退出脚本。" ; exit 0 ;;
            *) red "无效输入，请输入 0-3 之间的数字。" ; sleep 1 ;;
        esac
    done
}

# 启动主菜单
main