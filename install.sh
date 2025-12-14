#!/bin/bash

user_home=$HOME
original_dir=$(pwd)

echo "开始下载steamcmd 和 饥荒"

cd ~/steamcmd
./steamcmd.sh +login anonymous +force_install_dir ~/dst-dedicated-server +app_update 343050 validate +quit

mkdir -p ~/.klei/DoNotStarveTogether/MyDediServer

echo "Steamcmd installed at $HOME/steamcmd"
echo "Dst server installed at $HOME/dst-dedicated-server"

cd ~

mkdir $user_home/.klei/DoNotStarveTogether/backup
mkdir $user_home/.klei/DoNotStarveTogether/download_mod


# 切换到脚本所在目录
cd "$original_dir"

echo "steamcmd=$HOME/steamcmd" >> dst_config
echo "force_install_dir=$HOME/dst-dedicated-server" >> dst_config
echo "cluster=MyDediServer" >> dst_config
echo "backup=$user_home/.klei/DoNotStarveTogether/backup" >> dst_config
echo "mod_download_path=$user_home/.klei/DoNotStarveTogether/download_mod" >> dst_config

echo "安装完成"
