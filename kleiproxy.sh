#!/bin/bash
# ======================================================
# 饥荒大厅反代脚本 (基于 OpenResty + Lua)
# 功能：安装配置、启动、查看日志、停止
# ======================================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 全局变量
FRP_IP=""
FRP_PORT=""
OPENRESTY_INSTALLED=false
CONFIG_DIR="/etc/nginx"
SSL_DIR="${CONFIG_DIR}/ssl"
LOG_DIR="/var/log/openresty"

# 检测系统类型
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        echo -e "${RED}无法识别操作系统${NC}"
        exit 1
    fi
}

# 安装 OpenResty
install_openresty() {
    echo -e "${YELLOW}正在安装 OpenResty...${NC}"
    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y wget gnupg lsb-release
            wget -O - https://openresty.org/package/pubkey.gpg | apt-key add -
            echo "deb https://openresty.org/package/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/openresty.list
            apt-get update
            apt-get install -y openresty openresty-opm
            ;;
        centos|rhel|fedora)
            yum install -y yum-utils
            yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo
            yum install -y openresty openresty-opm
            ;;
        *)
            echo -e "${RED}不支持的操作系统${NC}"
            exit 1
            ;;
    esac
    # 创建软链接，方便使用 nginx 命令
    ln -sf /usr/local/openresty/nginx/sbin/nginx /usr/bin/nginx 2>/dev/null || true
    OPENRESTY_INSTALLED=true
    echo -e "${GREEN}OpenResty 安装完成${NC}"
}

# 生成自签名 SSL 证书（用于 HTTPS 代理）
generate_ssl_cert() {
    mkdir -p ${SSL_DIR}
    cd ${SSL_DIR}
    if [[ ! -f server.crt || ! -f server.key ]]; then
        echo -e "${YELLOW}生成自签名 SSL 证书...${NC}"
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout server.key -out server.crt \
            -subj "/C=CN/ST=Beijing/L=Beijing/O=Klei/CN=lobby-v2.klei.com"
        chmod 600 server.key
        echo -e "${GREEN}证书已生成至 ${SSL_DIR}${NC}"
    else
        echo -e "${GREEN}证书已存在，跳过生成${NC}"
    fi
}

# 创建 Nginx 配置文件
create_nginx_config() {
    local ip=$1
    local port=$2
    mkdir -p ${CONFIG_DIR}/conf.d
    cat > ${CONFIG_DIR}/conf.d/lobby-proxy.conf <<EOF
server {
    listen 443 ssl;
    server_name lobby-v2.klei.com;

    ssl_certificate     ${SSL_DIR}/server.crt;
    ssl_certificate_key ${SSL_DIR}/server.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    resolver 8.8.8.8 114.114.114.114 valid=300s;
    resolver_timeout 5s;

    location / {
        # 代理到真实的科雷大厅（HTTPS）
        proxy_pass https://lobby-v2.klei.com;
        proxy_ssl_verify off;
        proxy_ssl_server_name on;
        proxy_set_header Host lobby-v2.klei.com;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

        # 使用 Lua 修改请求体中的 IP 和端口
        set \$target_ip "${ip}";
        set \$target_port "${port}";

        access_by_lua_block {
            ngx.req.read_body()
            local data = ngx.req.get_body_data()
            if data and #data > 0 then
                local cjson = require("cjson.safe")
                local obj, err = cjson.decode(data)
                if obj then
                    -- 根据实际请求格式修改字段名（常见为 "ip" 和 "port"）
                    if obj.ip then obj.ip = ngx.var.target_ip end
                    if obj.port then obj.port = tonumber(ngx.var.target_port) end
                    if obj.address then obj.address = ngx.var.target_ip end   -- 备选字段
                    local new_data = cjson.encode(obj)
                    ngx.req.set_body_data(new_data)
                else
                    ngx.log(ngx.ERR, "JSON decode failed: ", err)
                end
            end
        }

        # 记录请求日志（方便调试）
        access_log ${LOG_DIR}/lobby_access.log;
        error_log  ${LOG_DIR}/lobby_error.log;
    }
}
EOF
    mkdir -p ${LOG_DIR}
    echo -e "${GREEN}Nginx 配置已生成: ${CONFIG_DIR}/conf.d/lobby-proxy.conf${NC}"
}

# 修改 nginx.conf 引入自定义配置
patch_main_conf() {
    local main_conf="${CONFIG_DIR}/nginx.conf"
    if [[ -f ${main_conf} ]]; then
        # 检查是否已包含 conf.d
        if ! grep -q "include /etc/nginx/conf.d/\*.conf" ${main_conf}; then
            sed -i '/http {/a \    include /etc/nginx/conf.d/*.conf;' ${main_conf}
        fi
    else
        # 如果主配置不存在，创建最小配置
        cat > ${main_conf} <<EOF
user root;
worker_processes auto;
error_log /var/log/openresty/error.log;
pid /run/openresty.pid;

events {
    worker_connections 1024;
}

http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;
    include /etc/nginx/conf.d/*.conf;
}
EOF
    fi
}

# 安装并配置（选项 1）
install_and_config() {
    read -p "请输入 FRP 转发后的公网 IP（例如 2.2.2.2）: " FRP_IP
    read -p "请输入 FRP 转发后的端口（例如 20999）: " FRP_PORT
    if [[ -z "$FRP_IP" || -z "$FRP_PORT" ]]; then
        echo -e "${RED}IP 和端口不能为空${NC}"
        exit 1
    fi
    detect_os
    install_openresty
    generate_ssl_cert
    create_nginx_config $FRP_IP $FRP_PORT
    patch_main_conf
    # 测试配置
    nginx -t && echo -e "${GREEN}配置测试通过${NC}" || { echo -e "${RED}配置错误，请检查${NC}"; exit 1; }
    echo -e "${GREEN}安装与配置完成！${NC}"
    echo -e "${YELLOW}请手动执行以下操作：${NC}"
    echo "1. 在本地电脑 hosts 文件中添加: 腾讯云ip lobby-v2.klei.com"
    echo "2. 将自签名证书 ${SSL_DIR}/server.crt 导入本地信任区（如果本地服务器验证证书）"
    echo "3. 然后使用选项 2 启动服务"
}

# 启动服务（选项 2）
start_service() {
    if [[ ! -f /usr/bin/nginx ]]; then
        echo -e "${RED}未安装 OpenResty，请先执行选项 1${NC}"
        exit 1
    fi
    nginx -t || { echo -e "${RED}配置检查失败，请修复${NC}"; exit 1; }
    systemctl restart openresty 2>/dev/null || nginx -s reload 2>/dev/null || nginx
    echo -e "${GREEN}服务已启动${NC}"
    echo "日志位置: ${LOG_DIR}/lobby_access.log"
}

# 查看日志（选项 3）
view_logs() {
    if [[ -f ${LOG_DIR}/lobby_access.log ]]; then
        tail -f ${LOG_DIR}/lobby_access.log ${LOG_DIR}/lobby_error.log
    else
        echo -e "${RED}日志文件不存在，请先启动服务${NC}"
    fi
}

# 停止服务（选项 4）
stop_service() {
    systemctl stop openresty 2>/dev/null || nginx -s stop 2>/dev/null || killall nginx 2>/dev/null
    echo -e "${GREEN}服务已停止${NC}"
}

# 主菜单
show_menu() {
    echo "========================================"
    echo "   饥荒大厅反代管理脚本"
    echo "========================================"
    echo "1) 安装并配置（首次运行）"
    echo "2) 启动服务"
    echo "3) 查看日志"
    echo "4) 停止服务"
    echo "5) 退出"
    echo "========================================"
    read -p "请输入选项 [1-5]: " choice
    case $choice in
        1) install_and_config ;;
        2) start_service ;;
        3) view_logs ;;
        4) stop_service ;;
        5) exit 0 ;;
        *) echo -e "${RED}无效选项${NC}" ;;
    esac
}

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}请使用 root 用户执行此脚本${NC}"
    exit 1
fi

while true; do
    show_menu
done