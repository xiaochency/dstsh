#!/bin/bash

#监控前置函数
function monitor_master1() {
    if ! screen -list | grep -q "Cluster_1Master"; then
        echo "Cluster_1Master 会话不存在，正在重新启动..."
        screen -dmS "Cluster_1Master" bash -c "cd ~/dst/bin/ && ./dontstarve_dedicated_server_nullrenderer -console -cluster Cluster_1 -shard Master"
    else
        echo "Cluster_1Master 会话已存在，无需重新启动。"
    fi
}

function monitor_master2() {
    if ! screen -list | grep -q "Cluster_2Master"; then
        echo "Cluster_2Master 会话不存在，正在重新启动..."
        screen -dmS "Cluster_2Master" bash -c "cd ~/dst/bin/ && ./dontstarve_dedicated_server_nullrenderer -console -cluster Cluster_2 -shard Master"
    else
        echo "Cluster_2Master 会话已存在，无需重新启动。"
    fi
}

function monitor_caves1() {
    if ! screen -list | grep -q "Cluster_1Caves"; then
        echo "Cluster_1Caves 会话不存在，正在重新启动..."
        screen -dmS "Cluster_1Caves" bash -c "cd ~/dst/bin/ && ./dontstarve_dedicated_server_nullrenderer -console -cluster Cluster_1 -shard Caves"
    else
        echo "Cluster_1Caves 会话已存在，无需重新启动。"
    fi
}

function monitor_caves2() {
    if ! screen -list | grep -q "Cluster_2Caves"; then
        echo "Cluster_2Caves 会话不存在，正在重新启动..."
        screen -dmS "Cluster_2Caves" bash -c "cd ~/dst/bin/ && ./dontstarve_dedicated_server_nullrenderer -console -cluster Cluster_2 -shard Caves"
    else
        echo "Cluster_2Caves 会话已存在，无需重新启动。"
    fi
}