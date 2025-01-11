#!/bin/bash

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请以root用户运行此脚本。"
    exit 1
fi

# 设置root密码
echo "请输入新的root密码："
passwd root

# 备份SSH配置文件
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# 修改sshd_config文件以允许root登录
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# 重启SSH服务以应用更改
systemctl restart ssh

echo "远程root登录已启用，root密码已设置。"