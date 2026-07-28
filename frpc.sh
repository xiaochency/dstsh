#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# 颜色定义
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

# 全局变量
WORK_PATH=$(dirname $(readlink -f $0))
FRP_NAME=frpc
FRP_VERSION=0.70.0
FRP_PATH=/usr/local/frp
# 镜像列表
PROXY_URLS=(
    "https://github.dpik.top"
    "https://ghfast.top"
    "https://ghproxy.net"
)
SERVICE_NAME="${FRP_NAME}.service"
CONFIG_FILE="${FRP_PATH}/${FRP_NAME}.toml"
BIN_FILE="${FRP_PATH}/${FRP_NAME}"

# 检查是否已安装（二进制、配置、服务）
is_installed() {
    [ -f "${BIN_FILE}" ] && [ -f "${CONFIG_FILE}" ] && [ -f "/lib/systemd/system/${SERVICE_NAME}" ]
}

# 打印帮助信息
print_menu() {
    echo -e "\n${Green}========== FRPC 管理脚本 ==========${Font}"
    echo -e " ${Green}0.${Font} 安装 frpc"
    echo -e " ${Green}1.${Font} 启动 frpc"
    echo -e " ${Green}2.${Font} 停止 frpc"
    echo -e " ${Green}3.${Font} 查看 frpc 状态"
    echo -e " ${Green}4.${Font} 查看 frpc 日志"
    echo -e " ${Green}5.${Font} 编辑 frpc.toml"
    echo -e " ${Green}6.${Font} 管理 frpc 开机自启"
    echo -e " ${Green}7.${Font} 退出"
    echo -e "${Green}====================================${Font}"
}

# 检查必要工具（仅安装时使用）
check_pkg() {
    if ! type curl >/dev/null 2>&1 ; then
        apt-get install curl -y
    fi
}

# 安装 frpc
install_frpc() {
    if is_installed; then
        echo -e "${Red}检测到已安装 frpc，是否覆盖安装？(y/n)${Font}"
        read -r choice
        if [[ ! "$choice" =~ ^[Yy]$ ]]; then
            echo -e "${Yellow}取消安装。${Font}"
            return
        fi
        # 停止并卸载旧服务
        systemctl stop ${FRP_NAME} 2>/dev/null
        systemctl disable ${FRP_NAME} 2>/dev/null
        rm -rf /lib/systemd/system/${SERVICE_NAME}
        rm -rf ${FRP_PATH}
        systemctl daemon-reload
    fi

    # 杀死所有 frpc 进程
    while ! test -z "$(ps -A | grep -w ${FRP_NAME})"; do
        FRPCPID=$(ps -A | grep -w ${FRP_NAME} | awk 'NR==1 {print $1}')
        kill -9 $FRPCPID
    done

    # 安装依赖工具
    check_pkg

    # 选择镜像
    echo -e "${Green}请选择下载镜像：${Font}"
    for i in "${!PROXY_URLS[@]}"; do
        echo -e " ${Green}$((i+1)).${Font} ${PROXY_URLS[$i]}"
    done
    read -p "请输入序号 (1-${#PROXY_URLS[@]}): " mirror_choice
    # 验证输入
    if ! [[ "$mirror_choice" =~ ^[0-9]+$ ]] || [ "$mirror_choice" -lt 1 ] || [ "$mirror_choice" -gt ${#PROXY_URLS[@]} ]; then
        echo -e "${Red}无效输入，将使用第一个镜像。${Font}"
        mirror_choice=1
    fi
    PROXY_URL="${PROXY_URLS[$((mirror_choice-1))]}"
    echo -e "${Green}使用镜像: ${PROXY_URL}${Font}"

    # 检测架构
    if [ $(uname -m) = "x86_64" ]; then
        PLATFORM=amd64
    elif [ $(uname -m) = "aarch64" ]; then
        PLATFORM=arm64
    elif [ $(uname -m) = "armv7" ] || [ $(uname -m) = "armv7l" ] || [ $(uname -m) = "armhf" ]; then
        PLATFORM=arm
    else
        echo -e "${Red}不支持的架构: $(uname -m)${Font}"
        return 1
    fi

    FILE_NAME=frp_${FRP_VERSION}_linux_${PLATFORM}

    # 从镜像下载
    echo -e "${Green}开始从 ${PROXY_URL} 下载 frp ${FRP_VERSION} ...${Font}"
    wget -P ${WORK_PATH} ${PROXY_URL}/https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILE_NAME}.tar.gz -O ${FILE_NAME}.tar.gz

    if [ $? -ne 0 ]; then
        echo -e "${Red}下载失败，请检查网络或更换镜像。${Font}"
        return 1
    fi

    tar -zxvf ${FILE_NAME}.tar.gz
    mkdir -p ${FRP_PATH}
    mv ${FILE_NAME}/${FRP_NAME} ${FRP_PATH}

    # 生成随机名称
    RADOM_NAME=$(cat /dev/urandom | head -n 10 | md5sum | head -c 8)

    # 写入默认配置（用户可随后修改）
    cat >${CONFIG_FILE}<<EOF
serverAddr = "frp.freefrp.net"
serverPort = 7000
auth.method = "token"
auth.token = "freefrp.net"

[[proxies]]
name = "web1_${RADOM_NAME}"
type = "http"
localIP = "192.168.1.2"
localPort = 5000
customDomains = ["nas.yourdomain.com"]

[[proxies]]
name = "web2_${RADOM_NAME}"
type = "https"
localIP = "192.168.1.2"
localPort = 5001
customDomains = ["nas.yourdomain.com"]

[[proxies]]
name = "tcp1_${RADOM_NAME}"
type = "tcp"
localIP = "192.168.1.3"
localPort = 22
remotePort = 22222
EOF

    # 配置 systemd 服务
    cat >/lib/systemd/system/${SERVICE_NAME} <<EOF
[Unit]
Description=Frp Client Service
After=network.target syslog.target
Wants=network.target

[Service]
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=${BIN_FILE} -c ${CONFIG_FILE}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl start ${FRP_NAME}
    systemctl enable ${FRP_NAME}

    # 清理临时文件
    rm -rf ${WORK_PATH}/${FILE_NAME}.tar.gz ${WORK_PATH}/${FILE_NAME}

    echo -e "${Green}====================================================================${Font}"
    echo -e "${Green}安装成功！请先编辑 ${CONFIG_FILE} 确保配置正确。${Font}"
    echo -e "${Green}====================================================================${Font}"
}

# 启动
start_frpc() {
    if ! is_installed; then
        echo -e "${Red}frpc 未安装，请先执行安装 (选项 0)。${Font}"
        return
    fi
    systemctl start ${FRP_NAME}
    echo -e "${Green}启动命令已执行，可通过选项 3 查看状态。${Font}"
}

# 停止
stop_frpc() {
    if ! is_installed; then
        echo -e "${Red}frpc 未安装。${Font}"
        return
    fi
    systemctl stop ${FRP_NAME}
    echo -e "${Green}停止命令已执行。${Font}"
}

# 状态
status_frpc() {
    if ! is_installed; then
        echo -e "${Red}frpc 未安装。${Font}"
        return
    fi
    systemctl status ${FRP_NAME} --no-pager
}

# 日志
show_logs() {
    if ! is_installed; then
        echo -e "${Red}frpc 未安装。${Font}"
        return
    fi
    journalctl -u ${FRP_NAME} -n 100 --no-pager
}

# 编辑配置
edit_config() {
    if ! is_installed; then
        echo -e "${Red}frpc 未安装。${Font}"
        return
    fi
    EDITOR=${EDITOR:-vi}
    ${EDITOR} ${CONFIG_FILE}
    echo -e "${Green}配置已编辑，请重启frpc服务${Font}"
}

# 管理开机自启
manage_autostart() {
    if ! is_installed; then
        echo -e "${Red}frpc 未安装。${Font}"
        return
    fi
    enabled=$(systemctl is-enabled ${FRP_NAME} 2>/dev/null)
    echo -e "${Yellow}当前开机自启状态: ${enabled}${Font}"
    echo -e "是否切换自启状态？(y: 启用, n: 禁用, q: 返回)"
    read -r choice
    case "$choice" in
        [Yy])
            systemctl enable ${FRP_NAME}
            echo -e "${Green}已启用开机自启。${Font}"
            ;;
        [Nn])
            systemctl disable ${FRP_NAME}
            echo -e "${Green}已禁用开机自启。${Font}"
            ;;
        [Qq])
            return
            ;;
        *)
            echo -e "${Red}无效输入。${Font}"
            ;;
    esac
}

# 主程序
main() {
    while true; do
        print_menu
        read -p "请输入选项编号: " option
        case "$option" in
            0)
                install_frpc
                ;;
            1)
                start_frpc
                ;;
            2)
                stop_frpc
                ;;
            3)
                status_frpc
                ;;
            4)
                show_logs
                ;;
            5)
                edit_config
                ;;
            6)
                manage_autostart
                ;;
            7)
                echo -e "${Green}退出。${Font}"
                exit 0
                ;;
            *)
                echo -e "${Red}无效选项，请重新输入。${Font}"
                ;;
        esac
        echo -e "\n按任意键继续..."
        read -n 1
    done
}

# 检查是否以 root 运行（多数操作需要）
if [ $(id -u) -ne 0 ]; then
    echo -e "${Red}本脚本大部分功能需要 root 权限，请使用 sudo 运行。${Font}"
    exit 1
fi

main