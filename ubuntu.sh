#!/bin/bash

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请以root用户运行此脚本。"
    exit 1
fi

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

# 显示主菜单
show_menu() {
    clear
    echo "==================================="
    echo "        系统配置工具"
    echo "==================================="
    echo "1. 设置root密码并启用SSH root登录"
    echo "2. 禁用Ubuntu自动更新"
    echo "3. 退出"
    echo "==================================="
    echo -n "请选择操作 [1-3]: "
}

# 主菜单处理函数
main_menu() {
    while true; do
        show_menu
        read choice
        
        case $choice in
            1)
                echo "您选择了: 设置root密码并启用SSH root登录"
                set_root_password
                ;;
            2)
                echo "您选择了: 禁用Ubuntu自动更新"
                disable_ubuntu_autoupdate
                ;;
            3)
                echo "退出系统配置工具。"
                exit 0
                ;;
            *)
                echo "无效选择，请重新输入。"
                ;;
        esac
        
        echo
        echo -n "按Enter键继续..."
        read
    done
}

# 主程序入口
echo "系统配置工具启动..."
main_menu
