#!/bin/bash

install_dir="$HOME/dst"
steamcmd_dir="$HOME/steamcmd"

function fail() {
    echo "错误: $@" >&2
    exit 1
}

function check_for_file() {
    if [ ! -e "$1" ]; then
        return 1  # 返回 1 表示文件缺失
    fi
    return 0  # 返回 0 表示文件存在
}

#设置虚拟内存
settingSwap() {
# 创建一个2GB的交换文件
SWAPFILE=/swapfile
SWAPSIZE=2G

# 检查是否已经存在交换文件
if [ -f $SWAPFILE ]; then
    echo "交换文件已存在，跳过创建步骤。"
else
    echo "创建交换文件..."
    sudo fallocate -l $SWAPSIZE $SWAPFILE
    sudo chmod 600 $SWAPFILE
    sudo mkswap $SWAPFILE
    sudo swapon $SWAPFILE
    echo "交换文件创建并启用成功。"
fi

# 添加到 /etc/fstab 以便开机启动
if ! grep -q "$SWAPFILE" /etc/fstab; then
    echo "将交换文件添加到 /etc/fstab..."
    echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab
    echo "交换文件已添加到开机启动。"
else
    echo "交换文件已在 /etc/fstab 中，跳过添加步骤。"
fi
}

#安装服务器
Install_dst() {
    read -p "您确定要安装 Don't Starve Together 服务器吗？(y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "安装已取消."
        return
    fi

    echo "正在安装 Don't Starve Together 服务器..."
    sudo dpkg --add-architecture i386
    sudo apt-get update
    sudo apt-get install -y lib32gcc1
    sudo apt-get install -y libcurl4-gnutls-dev:i386
    sudo apt-get install -y screen

    settingSwap   #设置虚拟内存
    echo "设置虚拟内存2GB"
    mkdir ~/steamcmd
    cd ~/steamcmd

    wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
    tar -xvzf steamcmd_linux.tar.gz
    ./steamcmd.sh +login anonymous +force_install_dir "$install_dir" +app_update 343050 validate +quit

    cp ~/steamcmd/linux32/libstdc++.so.6 ~/dst/bin/lib32/
    cp ~/steamcmd/linux32/steamclient.so ~/dst/bin/lib32/

    mkdir -p ~/.klei/DoNotStarveTogether/Cluster_1/
    touch ~/.klei/DoNotStarveTogether/Cluster_1/cluster_token.txt
    touch ~/.klei/DoNotStarveTogether/Cluster_1/adminlist.txt
    touch ~/.klei/DoNotStarveTogether/Cluster_1/blocklist.txt
    touch ~/.klei/DoNotStarveTogether/Cluster_1/whitelist.txt
    mkdir -p ~/.klei/DoNotStarveTogether/Cluster_2/
    touch ~/.klei/DoNotStarveTogether/Cluster_2/cluster_token.txt
    touch ~/.klei/DoNotStarveTogether/Cluster_2/adminlist.txt
    touch ~/.klei/DoNotStarveTogether/Cluster_2/blocklist.txt
    touch ~/.klei/DoNotStarveTogether/Cluster_2/whitelist.txt

    echo "Don't Starve Together 服务器安装完成."
}


#更新服务器
Update_dst() {
    echo "正在更新 Don't Starve Together 服务器..."
    cd "$steamcmd_dir" || fail
    ./steamcmd.sh +login anonymous +force_install_dir "$install_dir" +app_update 343050 validate +quit
    cp ~/steamcmd/linux32/steamclient.so ~/dst/bin/lib32/
    echo "服务器更新完成,请重新执行脚本"
}


# 更新指定 Cluster 的模组
function AddAutoUpdateMod() {
    local cluster_choice="$1"
    local modTotal
    local modID

    # 定义文件路径
    local cluster_file
    if [[ "$cluster_choice" -eq 1 ]]; then
        cluster_file="$HOME/.klei/DoNotStarveTogether/Cluster_1/Master/modoverrides.lua"
    elif [[ "$cluster_choice" -eq 2 ]]; then
        cluster_file="$HOME/.klei/DoNotStarveTogether/Cluster_2/Master/modoverrides.lua"
    else
        echo "无效的集群选择."
        return
    fi

    local mods_file="$HOME/dst/mods/dedicated_server_mods_setup.lua"

    # 检查配置文件
    check_for_file "$cluster_file"

    # 计算模组总数
    modTotal=$(grep -c 'workshop-' "$cluster_file")

    if [[ $modTotal -eq 0 ]]; then
        echo "没有发现模组文件！"
        return
    fi

    # 循环添加模组到更新文件
    for item in $(seq "$modTotal"); do
        # 模组ID
        modID=$(grep 'workshop-' "$cluster_file" | cut -d '"' -f2 | sed 's#workshop-##g' | awk "NR==$item{print \$0}")

        # 添加ID 操作
        if [[ $(grep -c "$modID" "$mods_file") -eq 0 ]]; then
            echo "        ServerModSetup(\"$modID\")" >> "$mods_file"
            echo ""
            echo "$modID 模组添加完成！"
        else
            echo ""
            echo "这个 $modID 模组之前已被添加！"
        fi
    done
    
    sleep 3s
}

# 更新指定 Cluster 的模组
function UpdateMods() {
    local cluster_choice
    echo "请选择要更新的MOD配置:"
    echo "1. 更新 Cluster_1 模组配置文件"
    echo "2. 更新 Cluster_2 模组配置文件"
    echo "0. 返回主菜单"

    while true; do
        read -p "输入您的选择 (0-2): " cluster_choice
        if [[ "$cluster_choice" =~ ^[0-2]$ ]]; then
            break
        else
            echo "无效选择. 请重试."
        fi
    done

    case $cluster_choice in
        1)
            echo "正在更新 Cluster_1 模组配置文件..."
            AddAutoUpdateMod 1  # 传递参数 1 更新 Cluster_1
            echo "Cluster_1 模组配置文件更新完成."
            ;;
        2)
            echo "正在更新 Cluster_2 模组配置文件..."
            AddAutoUpdateMod 2  # 传递参数 2 更新 Cluster_2
            echo "Cluster_2 模组配置文件更新完成."
            ;;
        0)
            break
            ;;
    esac
}

# 启动服务器
function start_server() {
    local cluster=$1
    local shard=$2
    local screen_name="$cluster$shard"

    if screen -list | grep -q "$screen_name"; then
        echo "$screen_name 服务器已经在运行."
    else
        cd ~/dst/bin/ || fail
        screen -dmS "$screen_name" ./dontstarve_dedicated_server_nullrenderer -console -cluster "$cluster" -shard "$shard"
        echo "$screen_name 已启动!"
    fi
}

# 备份存档
BackupSaves() {
    local backup_choice
    local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")

    while true; do
        echo "请选择要备份的存档:"
        echo "1. 备份 Cluster_1 存档"
        echo "2. 备份 Cluster_2 存档"
        echo "0. 返回主菜单"

        read -p "输入您的选择 (0-2): " backup_choice

        case $backup_choice in
            1)
                echo "正在备份 Cluster_1 存档..."
                tar -czf "$HOME/.klei/DoNotStarveTogether/Cluster_1_backup_$timestamp.tar.gz" "$HOME/.klei/DoNotStarveTogether/Cluster_1"
                echo "Cluster_1 存档已备份至.klei/DoNotStarveTogether."
                ;;
            2)
                echo "正在备份 Cluster_2 存档..."
                tar -czf "$HOME/.klei/DoNotStarveTogether/Cluster_2_backup_$timestamp.tar.gz" "$HOME/.klei/DoNotStarveTogether/Cluster_2"
                echo "Cluster_2 存档已备份至.klei/DoNotStarveTogether."
                ;;
            0)
                break
                ;;
            *)
                echo "无效选择. 请重试."
                ;;
        esac
    done
}


# 删除存档
function DeleteSaves() {
    local cluster_choice
    while true; do
        echo "请选择要删除的存档:"
        echo "1. 删除 Cluster_1 存档"
        echo "2. 删除 Cluster_2 存档"
        echo "0. 返回上一级菜单"

        read -p "输入您的选择 (0-2): " cluster_choice
        if [[ "$cluster_choice" =~ ^[0-2]$ ]]; then
            if [[ "$cluster_choice" -eq 0 ]]; then
                return  # 返回上一级菜单
            fi

            case $cluster_choice in
                1)
                    echo "正在删除 Cluster_1 存档..."
                    rm -rf "$HOME/.klei/DoNotStarveTogether/Cluster_1/Master/save"/*
                    rm -rf "$HOME/.klei/DoNotStarveTogether/Cluster_1/Caves/save"/*
                    echo "Cluster_1 存档已删除."
                    ;;
                2)
                    echo "正在删除 Cluster_2 存档..."
                    rm -rf "$HOME/.klei/DoNotStarveTogether/Cluster_2/Master/save"/*
                    rm -rf "$HOME/.klei/DoNotStarveTogether/Cluster_2/Caves/save"/*
                    echo "Cluster_2 存档已删除."
                    ;;
            esac
        else
            echo "无效选择. 请重试."
        fi
    done
}


#定期检查
function run_monitoring() {
    local session_name=$1
    local master_func=$2
    local caves_func=$3

    screen -dmS "$session_name" bash -c "
        source ./ms.sh
        while true; do
            ${master_func}
            ${caves_func}
            sleep 180
        done
    "
}


# 监控崩溃重启
function ms_servers() {
    while true; do
        echo "请选择要执行的操作:"
        echo "1. 监控Cluster_1崩溃重启"
        echo "2. 监控Cluster_2崩溃重启"
        echo "3. 关闭监控脚本"
        echo "4. 设置服务器维护任务"
        echo "5. 关闭服务器维护任务"
        echo "0. 返回主菜单"

        read -p "请输入选项 (0/1/2/3/4/5): " choice

        case $choice in
            1)
                run_monitoring "111" "monitor_master1" "monitor_caves1"
                echo "已在后台启动 Cluster_1 监控脚本 (会话名: 111)"
                ;;
            2)
                run_monitoring "222" "monitor_master2" "monitor_caves2"
                echo "已在后台启动 Cluster_2 监控脚本 (会话名: 222)"
                ;;
            3)
                screen -list | grep -E '111|222' | cut -d. -f1 | awk '{print $1}' | xargs kill
                echo "已关闭监控脚本..."
                ;;
            4)
                # 设置服务器维护任务，每天早上 6 点执行命令
                (crontab -l; echo "0 6 * * * screen -X -S Cluster_1Master quit && screen -X -S Cluster_1Caves quit && screen -X -S Cluster_2Master quit && screen -X -S Cluster_2Caves quit && echo \"服务器维护成功!\"") | crontab -
                echo "已设置服务器维护任务，每天早上6点执行！"
                ;;
            5)
                # 删除 crontab 中的服务器维护任务
                (crontab -l | grep -v "screen -X -S Cluster_1Master quit" | grep -v "screen -X -S Cluster_1Caves quit" | grep -v "screen -X -S Cluster_2Master quit" | grep -v "screen -X -S Cluster_2Caves quit") | crontab -
                echo "已删除 crontab 中的服务器维护任务！"
                ;;
            0)
                echo "返回主菜单..."
                return
                ;;
            *)
                echo "无效的选项,请重试。"
                # 不使用递归，继续循环
                ;;
        esac
    done
}



#主菜单
while true; do
    echo 饥荒云服务器管理脚本1.1.3 By:xiaochency
    echo "请选择一个选项:"
    echo "1. 启动服务器"
    echo "2. 更新服务器"
    echo "3. 查看服务器"
    echo "4. 关闭服务器"
    echo "5. 更新服务器MOD配置"
    echo "6. 监控服务器崩溃重启"
    echo "7. 存档管理"
    echo "8. 服务器控制台"
    echo "9. 安装服务器"
    echo "0. 退出"

    read -p "输入您的选择 (0-9): " choice
    case $choice in
        1)
            while true; do
                echo "请选择启动哪个服务器:"
                echo "1. 启动 Cluster_1Master"
                echo "2. 启动 Cluster_1Caves"
                echo "3. 启动 Cluster_1Master+Cluster_1Caves"
                echo "4. 启动 Cluster_2Master"
                echo "5. 启动 Cluster_2Caves"
                echo "6. 启动 Cluster_2Master+Cluster_2Caves"
                echo "0. 返回主菜单"

                read -p "输入您的选择 (0-6): " view_choice
                case $view_choice in
                    1)  start_server "Cluster_1" "Master" ;;
                    2)  start_server "Cluster_1" "Caves" ;;
                    3)  start_server "Cluster_1" "Master"; start_server "Cluster_1" "Caves" ;;
                    4)  start_server "Cluster_2" "Master" ;;
                    5)  start_server "Cluster_2" "Caves" ;;
                    6)  start_server "Cluster_2" "Master"; start_server "Cluster_2" "Caves" ;;
                    0)
                        break
                        ;;
                    *)
                        echo "无效选择. 请重试."
                        ;;
                esac
            done
            ;;
        2)
            Update_dst # 更新服务器
            ;;
        3)
            echo "当前运行的服务器如下："
            screen -ls
            while true; do
                echo "请选择一个选项:"
                echo "1. 查看 Cluster_1Master 服务器"
                echo "2. 查看 Cluster_1Caves 服务"
                echo "3. 查看 Cluster_2Master 服务器"
                echo "4. 查看 Cluster_2Caves 服务"
                echo "0. 返回主菜单"
                echo "要退出 screen 会话, 请按 Ctrl+A+D."

                read -p "输入您的选择 (0-4): " view_choice
                case $view_choice in
                    1)
                        screen -r Cluster_1Master
                        ;;
                    2)
                        screen -r Cluster_1Caves
                        ;;
                    3)
                        screen -r Cluster_2Master
                        ;;
                    4)
                        screen -r Cluster_2Caves
                        ;;
                    0)
                        break
                        ;;
                    *)
                        echo "无效选择. 请重试."
                        ;;
                esac
            done
            ;;
        4)
            while true; do
                echo "请选择一个选项:"
                echo "1. 关闭存档1服务器"
                echo "2. 关闭存档2服务器"
                echo "0. 返回主菜单"
                echo "要退出 screen 会话, 请按 Ctrl+A+D."

                read -p "输入您的选择 (0-2): " view_choice
                case $view_choice in
                    1)
                        echo "正在关闭存档1服务器.."
                        screen -X -S Cluster_1Master quit
                        screen -X -S Cluster_1Caves quit
                        echo "存档1服务器已关闭."
                        ;;
                    2)
                        echo "正在关闭存档2服务器.."
                        screen -X -S Cluster_2Master quit
                        screen -X -S Cluster_2Caves quit
                        echo "存档2服务器已关闭."
                        ;;
                    0)
                        break
                        ;;
                    *)
                        echo "无效选择. 请重试."
                        ;;
                esac
            done
            ;;
        5)
            UpdateMods  # 调用更新模组的函数
            ;;
        6)
            # 检查 ms.sh 文件是否存在
			check_for_file "ms.sh"

			# 如果 ms.sh 不存在，则下载并设置权限
			if [ $? -ne 0 ]; then
				wget -q -O ms.sh https://gitee.com/xiaochency/dst/raw/master/ms.sh && chmod 755 ms.sh
				echo "已下载监测脚本，请重新执行命令"
				exit 0  # 下载后退出，提示用户重新执行
			fi

			# 如果 ms.sh 存在，则执行 ms_servers
			ms_servers
            ;;
        7)
            while true; do
                echo "请选择一个选项:"
                echo "1. 备份存档"
                echo "2. 删除存档"
                echo "3. 返回主菜单"

            read -p "输入您的选择 (1-3): " view_choice
            case $view_choice in
            1)
                BackupSaves
                ;;
            2)
                DeleteSaves
                ;;
            3)
                break
                ;;
            *)
                echo "无效选择. 请重试."
                ;;
            esac
            done
            ;;
        8)
            echo "功能还在做."
            ;;     
        9)
            Install_dst  # 安装服务器
            ;;
        0)
            echo "退出中..."
            exit 0
            ;;
        *)
            echo "无效选择. 请重试."
            ;;
    esac
done

