#!/bin/bash
# MTU永久配置脚本 - Systemd版本（已修复变量BUG）
# 使用方法：sudo bash mtu.sh

set -e

SERVICE_NAME="set-mtu-eth0"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SCRIPT_PATH="/usr/local/bin/set_mtu_eth0.sh"

echo "=== Ubuntu永久设置MTU脚本 ==="

# 1. 创建实际执行MTU设置的脚本
echo "创建MTU设置脚本..."
cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/bash
# 等待网络接口就绪
sleep 2

# 检查eth0是否存在
if ip link show eth0 > /dev/null 2>&1; then
    ip link set dev eth0 mtu 1400

    CURRENT_MTU=$(ip link show eth0 | grep -oP 'mtu \K\d+')
    echo "$(date): eth0 MTU已设置为 $CURRENT_MTU" >> /var/log/mtu_setup.log
else
    echo "$(date): 警告 - eth0接口不存在" >> /var/log/mtu_setup.log
fi
EOF

chmod +x "$SCRIPT_PATH"

# 2. 创建systemd服务文件
echo "创建systemd服务..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Set MTU for eth0 to 1400
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${SCRIPT_PATH}
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 3. 启用并启动服务
echo "启用systemd服务..."
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service
systemctl start ${SERVICE_NAME}.service

# 4. 立即应用设置
echo "立即应用MTU设置..."
$SCRIPT_PATH

# 5. 验证结果
echo ""
echo "=== 验证结果 ==="
ip link show eth0 | grep mtu
echo ""
echo "服务状态:"
systemctl status ${SERVICE_NAME}.service --no-pager -l

echo ""
echo "=== 完成 ==="
echo "MTU设置已永久生效，重启后会自动应用。"
echo "日志文件: /var/log/mtu_setup.log"
echo "如需卸载，请执行:"
echo "  sudo systemctl disable ${SERVICE_NAME}.service"
echo "  sudo rm ${SERVICE_FILE} ${SCRIPT_PATH}"
