#!/bin/bash

###########################################
# 用户自定义设置请修改下方变量，其他变量请不要修改 #
###########################################

# --------------- ↓可修改↓ --------------- #
# dmp暴露端口，即网页打开时所用的端口
PORT=80

# 数据库文件所在目录，例如：./config
CONFIG_DIR="./data"

# 日志等级，例如：debug info warn error
LEVEL="info"

# --------------- ↑可修改↑ --------------- #

###########################################
#     下方变量请不要修改，否则可能会出现异常     #
###########################################

USER=$(whoami)
ExeFile="$HOME/dmp"
install_dir="$HOME/dst"
steamcmd_dir="$HOME/steamcmd"

ACCELERATED_URL=""

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

function echo_red_blink() {
	echo -e "\033[5;31m$*\033[0m"
}

# 检查用户，只能使用root执行
if [[ "${USER}" != "root" ]]; then
	echo_red "请使用root用户执行此脚本"
	exit 1
fi

function check_curl() {
	echo_cyan "正在检查curl命令"
	if ! curl --version >/dev/null 2>&1; then
		OS=$(grep -P "^ID=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g")
		if [[ ${OS} == "ubuntu" ]]; then
			apt install -y curl
		else
			if grep -P "^ID_LIKE=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g" | grep rhel; then
				yum install -y curl
			fi
		fi
	fi
}

function check_strings() {
	echo_cyan "正在检查strings命令"
	if ! strings --version >/dev/null 2>&1; then
		OS=$(grep -P "^ID=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g")
		if [[ ${OS} == "ubuntu" ]]; then
			apt install -y binutils
		else
			if grep -P "^ID_LIKE=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g" | grep rhel; then
				yum install -y binutils
			fi
		fi
	fi

}

# Ubuntu检查GLIBC, rhel需要下载文件手动安装
function check_glibc() {
	check_strings
	echo_cyan "正在检查GLIBC版本"
	OS=$(grep -P "^ID=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g")
	if [[ ${OS} == "ubuntu" ]]; then
		if ! strings /lib/x86_64-linux-gnu/libc.so.6 | grep GLIBC_2.34 >/dev/null 2>&1; then
			apt update
			apt install -y libc6
		fi
	else
		echo_red "非Ubuntu系统，如GLIBC小于2.34，请手动升级"
	fi
}

# 检查下载 sqlite3
function check_sqlite3() {
    if ! command -v sqlite3 &> /dev/null; then
        echo_yellow "检测到未安装 sqlite3，正在安装..."
        
        OS=$(grep -P "^ID=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g")
        
        case $OS in
            ubuntu|debian)
                if apt-get update && apt-get install -y sqlite3; then
                    echo_green "sqlite3 安装成功"
                else
                    echo_red "sqlite3 安装失败，请手动安装"
                    return 1
                fi
                ;;
            centos|rhel|fedora|rocky|alma)
                if yum install -y sqlite3; then
                    echo_green "sqlite3 安装成功"
                else
                    echo_red "sqlite3 安装失败，请手动安装"
                    return 1
                fi
                ;;
            alpine)
                if apk add sqlite; then
                    echo_green "sqlite3 安装成功"
                else
                    echo_red "sqlite3 安装失败，请手动安装"
                    return 1
                fi
                ;;
            *)
                echo_red "不支持的操作系统: $OS，请手动安装 sqlite3"
                echo_yellow "安装命令参考:"
                echo_yellow "  Ubuntu/Debian: sudo apt-get install sqlite3"
                echo_yellow "  CentOS/RHEL: sudo yum install sqlite3"
                echo_yellow "  Alpine: sudo apk add sqlite"
                return 1
                ;;
        esac
    fi
    
    return 0
}


# 下载函数:下载链接,尝试次数,超时时间(s)
function download() {
	# 显示详细进度
	local url="$1"
	local output="$2"
	local timeout="$3"
	curl -L --connect-timeout "${timeout}" --progress-bar -o "${output}" "${url}" 2>&1

	local curl_exit_code=$?

	if [ $curl_exit_code -eq 0 ]; then
		echo_green "下载完成: $output"
	else
		echo_red "下载失败 (退出码: $curl_exit_code)"
	fi

	return $curl_exit_code
}

# 安装主程序
function install_dmp() {
    check_curl

    dmp_urls=(
        "https://github.dpik.top/github.com/miracleEverywhere/dst-management-platform-api/releases/download/v3.1.2/dmp.tgz"
        "https://cdn.gh-proxy.org/github.com/miracleEverywhere/dst-management-platform-api/releases/download/v3.1.2/dmp.tgz"
        "https://gh.927223.xyz/github.com/miracleEverywhere/dst-management-platform-api/releases/download/v3.1.2/dmp.tgz"
        "https://edgeone.gh-proxy.org/github.com/miracleEverywhere/dst-management-platform-api/releases/download/v3.1.2/dmp.tgz"
        "https://gh.llkk.cc/github.com/miracleEverywhere/dst-management-platform-api/releases/download/v3.1.2/dmp.tgz"
    )

    # 显示下载地址选择菜单
    echo_cyan "请选择 dmp 下载地址："
    echo_green "1. 镜像源1 (github.dpik.top)"
    echo_green "2. 镜像源2 (cdn.gh-proxy.org)" 
    echo_green "3. 镜像源3 (gh.927223.xyz)" 
    echo_green "4. 镜像源4 (edgeone.gh-proxy.org)" 
    echo_green "5. 镜像源5 (gh.llkk.cc)"
    
    local download_choice
    while true; do
        read -p "请输入选择 [1-5]: " download_choice
        
        case $download_choice in
            1|2|3|4|5)
                break
                ;;
            *)
                echo_red "无效选择，请输入 1-5 之间的数字"
                ;;
        esac
    done

    # 根据用户选择获取 URL
    local url_index=$((download_choice-1))
    local selected_url="${dmp_urls[$url_index]}"
    
    case $download_choice in
        1) echo_cyan "使用镜像源1: $selected_url" ;;
        2) echo_cyan "使用镜像源2: $selected_url" ;;
        3) echo_cyan "使用镜像源3: $selected_url" ;;
        4) echo_cyan "使用镜像源4: $selected_url" ;;
        5) echo_cyan "使用镜像源5: $selected_url" ;;
    esac
    
    # 开始下载
    echo_cyan "正在下载 dmp.tgz..."
    download "$selected_url" "dmp.tgz" 10

    # 验证下载的文件
    if [ ! -f "dmp.tgz" ]; then
        echo_red "下载失败：文件不存在"
        return 1
    fi

    # 检查文件大小是否为0
    if [ ! -s "dmp.tgz" ]; then
        echo_red "下载失败：文件为空"
        rm -f dmp.tgz
        return 1
    fi

    if ! tar -tzf dmp.tgz >/dev/null 2>&1; then
        echo_red "无法读取压缩包内容"
        rm -f dmp.tgz
        return 1
    fi

    # 解压
    echo_cyan "解压 dmp.tgz..."
    tar zxvf dmp.tgz >/dev/null
    rm -f dmp.tgz
    chmod +x "$ExeFile"
	echo_green "安装 dmp 成功"
}

# 检查进程状态
function check_dmp() {
	sleep 1
	if pgrep dmp >/dev/null; then
		echo_green "启动成功"
	else
		echo_red "启动失败"
		exit 1
	fi
}

# 启动主程序
function start_dmp() {
	# 检查端口是否被占用,如果被占用则退出
	port=$(ss -ltnp | awk -v port=${PORT} '$4 ~ ":"port"$" {print $4}')

	if [ -n "$port" ]; then
		echo_red "端口 $PORT 已被占用: $port", 修改 run.sh 中的 PORT 变量后重新运行
		exit 1
	fi

	check_glibc

	if [ -e "$ExeFile" ]; then
		nohup "$ExeFile" -bind ${PORT} -dbpath ${CONFIG_DIR} -level ${LEVEL} >/dev/null 2>&1 &
	else
		install_dmp
		nohup "$ExeFile" -bind ${PORT} -dbpath ${CONFIG_DIR} -level ${LEVEL} >/dev/null 2>&1 &
	fi
}

# 关闭主程序
function stop_dmp() {
	pkill -9 dmp
	echo_green "关闭成功"
	sleep 1
}

# 删除主程序、请求日志、运行日志、遗漏的压缩包
function clear_dmp() {
	echo_cyan "正在执行清理"
	rm -f dmp dmp.tgz logs/*
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
	echo -e 'vm.swappiness = 20\nvm.min_free_kbytes = 100000\n' >/etc/sysctl.d/dmp_swap.conf

	echo_green "系统swap设置成功"
}

# 设置开机自启
function auto_start_dmp() {
	CRON_JOB="@reboot /bin/bash -c 'source /etc/profile && cd /root && echo 1 | /root/run.sh'"

	# 检查 crontab 中是否已存在该命令
	if crontab -l 2>/dev/null | grep -Fq "$CRON_JOB"; then
		echo_yellow "已发现开机自启配置，请勿重复添加"
	else
		# 如果不存在，则添加到 crontab
		(
			crontab -l 2>/dev/null
			echo "$CRON_JOB"
		) | crontab -
		echo_green "已成功设置开机自启"
	fi
}

# 查看所有用户名
function list_users() {
    if [[ ! -f "${CONFIG_DIR}/dmp.db" ]]; then
        echo_red "数据库文件 ${CONFIG_DIR}/dmp.db 不存在！"
        return 1
    fi
    
    echo_cyan "当前平台注册的用户名如下："
    echo "--------------------------------"
    sqlite3 "${CONFIG_DIR}/dmp.db" "SELECT username FROM users;" | while read -r user; do
        echo_green "  - $user"
    done
    [[ $? -ne 0 ]] && echo_yellow "（暂无用户或查询失败）"
    echo "--------------------------------"
}

# 修改密码（交互式）
function change_password() {
    if [[ ! -f "${CONFIG_DIR}/dmp.db" ]]; then
        echo_red "数据库文件 ${CONFIG_DIR}/dmp.db 不存在！"
        return 1
    fi

    echo_yellow "=== 修改用户密码 ==="
    read -r -p "请输入要修改的用户名: " USERNAME
    
    # 检查用户是否存在
    exists=$(sqlite3 "${CONFIG_DIR}/dmp.db" "SELECT COUNT(*) FROM users WHERE username='$USERNAME';")
    if [[ "$exists" -eq 0 ]]; then
        echo_red "用户 '$USERNAME' 不存在！"
        return 1
    fi

    read -s -r -p "请输入新密码: " PASSWORD
    echo
    read -s -r -p "请再次输入新密码: " PASSWORD2
    echo

    if [[ "$PASSWORD" != "$PASSWORD2" ]]; then
        echo_red "两次输入的密码不一致！"
        return 1
    fi

    if [[ -z "$PASSWORD" ]]; then
        echo_red "密码不能为空！"
        return 1
    fi

    # 生成 SHA512 加密密码（和平台一致）
    db_password=$(echo -n "$PASSWORD" | sha512sum | awk '{print $1}')

    # 执行更新
    sqlite3 "${CONFIG_DIR}/dmp.db" "UPDATE users SET password='$db_password' WHERE username='$USERNAME';"
    
    if [[ $? -eq 0 ]]; then
        echo_green "用户 '$USERNAME' 的密码修改成功！"
    else
        echo_red "密码修改失败，请检查数据库权限或SQLite是否正常"
    fi
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
        "https://gh.927223.xyz/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://cdn.gh-proxy.org/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://edgeone.gh-proxy.org/github.com/xiaochency/SteamCmdLinuxFile/releases/download/steamcmd-latest/steamcmd_linux.tar.gz"
        "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
    )

    # 显示下载地址选择菜单
    echo_cyan "请选择steamcmd下载地址："
    echo_green "1. 镜像源1 (github.dpik.top)"
    echo_green "2. 镜像源2 (gh.927223.xyz)" 
    echo_green "3. 镜像源3 (cdn.gh-proxy.org)" 
    echo_green "4. 镜像源4 (edgeone.gh-proxy.org)" 
    echo_green "5. 官方源  (steamcdn-a.akamaihd.net)"
    
    local download_choice
    while true; do
        read -p "请输入选择 [1-5]: " download_choice
        
        case $download_choice in
            1|2|3|4|5)
                break
                ;;
            *)
                echo_red "无效选择，请输入 1-5 之间的数字"
                ;;
        esac
    done

    # 手动选择模式：使用指定地址
    local url_index=$((download_choice-1))
    local selected_url="${steamcmd_urls[$url_index]}"
    
    case $download_choice in
        1) echo_cyan "使用镜像源1: $selected_url" ;;
        2) echo_cyan "使用镜像源2: $selected_url" ;;
        3) echo_cyan "使用镜像源3: $selected_url" ;;
        4) echo_cyan "使用镜像源4: $selected_url" ;;
        3) echo_cyan "使用官方源5: $selected_url" ;;
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
                        2) echo_green "$((i+1)). 镜像源2 (gh.927223.xyz)" ;;
                        3) echo_green "$((i+1)). 镜像源3 (cdn.gh-proxy.org)" ;;
                        4) echo_green "$((i+1)). 镜像源4 (edgeone.gh-proxy.org)" ;;
                        3) echo_green "$((i+1)). 官方源5 (steamcdn-a.akamaihd.net)" ;;
                    esac
                fi
            done
            
            local new_choice
            while true; do
                read -p "请输入选择: " new_choice
                if [[ "$new_choice" =~ ^[1-5]$ ]] && [ "$new_choice" -ne "$download_choice" ]; then
                    download_choice=$new_choice
                    url_index=$((download_choice-1))
                    selected_url="${steamcmd_urls[$url_index]}"
                    break
                elif [ "$new_choice" -eq "$download_choice" ]; then
                    echo_red "不能选择已尝试的地址，请选择其他地址"
                else
                    echo_red "无效选择，请输入 1-5 之间的数字"
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

# 设置root密码的函数
set_root_password() {
    echo "正在设置root密码..."
    echo "请输入新的root密码："
    passwd root
    
    # 备份SSH配置文件
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # 修改sshd_config文件以允许root登录
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
    
    # 重启SSH服务以应用更改
    systemctl restart ssh
    
    echo "远程root登录已启用，root密码已设置。"
}

# 禁用Ubuntu自动更新的函数
disable_ubuntu_autoupdate() {
    echo "正在禁用Ubuntu自动更新..."
    
    # 停止并禁用自动更新服务
    systemctl stop unattended-upgrades
    systemctl disable unattended-upgrades
    
    # 停止并禁用定时器
    systemctl stop apt-daily.timer
    systemctl disable apt-daily.timer
    systemctl stop apt-daily-upgrade.timer
    systemctl disable apt-daily-upgrade.timer
    
    # 修改20auto-upgrades配置文件
    AUTO_UPGRADE_FILE="/etc/apt/apt.conf.d/20auto-upgrades"
    if [ -f "$AUTO_UPGRADE_FILE" ]; then
        echo "正在修改自动更新配置文件..."
        # 备份原文件
        cp "$AUTO_UPGRADE_FILE" "$AUTO_UPGRADE_FILE.bak"
        
        # 检查并替换配置项
        if grep -q 'APT::Periodic::Update-Package-Lists "1";' "$AUTO_UPGRADE_FILE"; then
            sed -i 's/APT::Periodic::Update-Package-Lists "1";/APT::Periodic::Update-Package-Lists "0";/' "$AUTO_UPGRADE_FILE"
            echo "已禁用自动更新包列表"
        fi
        
        if grep -q 'APT::Periodic::Unattended-Upgrade "1";' "$AUTO_UPGRADE_FILE"; then
            sed -i 's/APT::Periodic::Unattended-Upgrade "1";/APT::Periodic::Unattended-Upgrade "0";/' "$AUTO_UPGRADE_FILE"
            echo "已禁用无人值守升级"
        fi
        
        # 如果文件不存在相关配置，则添加禁用配置
        if ! grep -q 'APT::Periodic::Update-Package-Lists' "$AUTO_UPGRADE_FILE"; then
            echo 'APT::Periodic::Update-Package-Lists "0";' >> "$AUTO_UPGRADE_FILE"
        fi
        
        if ! grep -q 'APT::Periodic::Unattended-Upgrade' "$AUTO_UPGRADE_FILE"; then
            echo 'APT::Periodic::Unattended-Upgrade "0";' >> "$AUTO_UPGRADE_FILE"
        fi
    else
        # 如果文件不存在，创建并添加禁用配置
        echo "创建自动更新配置文件并设置为禁用状态"
        echo 'APT::Periodic::Update-Package-Lists "0";' > "$AUTO_UPGRADE_FILE"
        echo 'APT::Periodic::Unattended-Upgrade "0";' >> "$AUTO_UPGRADE_FILE"
    fi
    
    echo "Ubuntu自动更新已禁用。"
}

# 菜单
function prompt_user() {
	clear
	echo_green "饥荒管理平台(DMP)"
	echo_yellow "————————————————————————————————————————————————————————————"
	echo_green "[0]: 下载并启动饥荒管理平台"
	echo_yellow "————————————————————————————————————————————————————————————"
	echo_green "[1]: 启动饥荒管理平台"
	echo_green "[2]: 关闭饥荒管理平台"
	echo_green "[3]: 设置开机自启"
	echo_yellow "————————————————————————————————————————————————————————————"
	echo_green "[4]: 下载DST程序"
	echo_green "[5]: 更新DST程序"
	echo_green "[6]: steamcmd自动更新"
	echo_yellow "————————————————————————————————————————————————————————————"
	echo_green "[7]: 修改root密码"
	echo_green "[8]: 停止vps自动更新"
	echo_green "[9]: 查看DMP所有用户名"
	echo_green "[10]: 修改DMP用户密码"
	echo_yellow "————————————————————————————————————————————————————————————"
	echo_green "[q]: 退出脚本"
	echo_yellow "————————————————————————————————————————————————————————————"
	echo_yellow "请输入要执行的操作 [0-10] 或输入 q 退出脚本: "
}

# 使用无限循环让用户输入命令
while true; do
	# 提示用户输入
	prompt_user
	# 读取用户输入
	read -r command
	# 使用 case 语句判断输入的命令
	case $command in
	0)
		clear_dmp
		install_dmp
		start_dmp
		check_dmp
		break
		;;
	1)  
		start_dmp
		check_dmp
		break
		;;
	2)
		stop_dmp
		break
		;;
	3)
		auto_start_dmp
		break
		;;
	4)
		install_dst
		break
		;;
	5)
		update_dst
		break
		;;
	6)
		manage_crontab
		break
		;;
	7)
		set_root_password
		break
		;;
	8)
		disable_ubuntu_autoupdate
		break
		;;
	9)
		check_sqlite3
        list_users
        echo
        echo_yellow "按回车返回主菜单..."
        read -r
        ;;
	10)
		check_sqlite3
		change_password
		echo_red "修改后需要重启DMP生效！"
		echo_red "修改后需要重启DMP生效！"
		echo_yellow "按回车返回主菜单..."
		read -r
        ;;

	q|Q)
		exit 0
		;;
	*)
		echo_red "请输入正确的数字 [0-9]"
		continue
		;;
	esac
done
