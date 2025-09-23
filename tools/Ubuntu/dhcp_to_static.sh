#!/bin/bash

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root权限运行此脚本 (sudo $0)" >&2
    exit 1
fi

# 自动检测激活的网络接口（排除lo）
echo "正在检测激活的网络接口..."
ACTIVE_INTERFACES=($(ip -br link show | awk '$1 != "lo" && $2 == "UP" {print $1}'))

if [ ${#ACTIVE_INTERFACES[@]} -eq 0 ]; then
    echo "错误：未找到激活的网络接口" >&2
    exit 1
elif [ ${#ACTIVE_INTERFACES[@]} -eq 1 ]; then
    INTERFACE=${ACTIVE_INTERFACES[0]}
    echo "找到一个激活的网络接口：$INTERFACE"
else
    echo "找到多个激活的网络接口："
    for i in "${!ACTIVE_INTERFACES[@]}"; do
        echo "$((i+1)). ${ACTIVE_INTERFACES[$i]}"
    done
    read -p "请输入要配置的接口编号 (1-${#ACTIVE_INTERFACES[@]}): " SELECTION
    INTERFACE=${ACTIVE_INTERFACES[$((SELECTION-1))]}
    echo "已选择接口：$INTERFACE"
fi

# 确保systemd-networkd服务运行
echo "确保网络服务运行中..."
if ! systemctl is-active --quiet systemd-networkd; then
    echo "启动systemd-networkd服务..."
    systemctl start systemd-networkd
    systemctl enable systemd-networkd
fi

# 确保接口使用DHCP并获取当前IP信息
echo "确保接口 $INTERFACE 使用DHCP获取地址..."
NETPLAN_TEMP=$(mktemp)
cat > "$NETPLAN_TEMP" << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: yes
EOF

# 备份可能存在的同名临时文件
[ -f "/etc/netplan/00-temp-dhcp.yaml" ] && mv "/etc/netplan/00-temp-dhcp.yaml" "/etc/netplan/00-temp-dhcp.yaml.bak"
mv "$NETPLAN_TEMP" "/etc/netplan/00-temp-dhcp.yaml"
netplan apply

# 等待接口获取IP
echo "等待接口获取IP地址..."
IP_ADDR=""
for i in {1..15}; do
    # 提取IP地址
    IP_LINE=$(ip -4 addr show "$INTERFACE" | grep 'inet ' | head -n 1)
    if [ -n "$IP_LINE" ]; then
        IP_ADDR=$(echo "$IP_LINE" | awk '{print $2}' | cut -d'/' -f1)
        break
    fi
    echo "等待中... ($i/15)"
    sleep 2
done

if [ -z "$IP_ADDR" ]; then
    echo "错误：无法通过DHCP获取IP地址" >&2
    # 清理临时文件
    rm -f "/etc/netplan/00-temp-dhcp.yaml"
    [ -f "/etc/netplan/00-temp-dhcp.yaml.bak" ] && mv "/etc/netplan/00-temp-dhcp.yaml.bak" "/etc/netplan/00-temp-dhcp.yaml"
    netplan apply
    exit 1
fi

# 提取子网掩码
IP_LINE=$(ip -4 addr show "$INTERFACE" | grep 'inet ' | head -n 1)
SUBNET_MASK=$(echo "$IP_LINE" | awk '{print $2}' | cut -d'/' -f2)

if [ -z "$SUBNET_MASK" ] || [ "$SUBNET_MASK" -lt 0 ] || [ "$SUBNET_MASK" -gt 32 ]; then
    echo "警告：无法获取子网掩码，使用默认值24"
    SUBNET_MASK=24
fi

# 获取网关
GATEWAY=$(ip route show default | awk '/default/ {print $3}')

if [ -z "$GATEWAY" ]; then
    echo "错误：无法获取网关地址" >&2
    # 清理临时文件
    rm -f "/etc/netplan/00-temp-dhcp.yaml"
    [ -f "/etc/netplan/00-temp-dhcp.yaml.bak" ] && mv "/etc/netplan/00-temp-dhcp.yaml.bak" "/etc/netplan/00-temp-dhcp.yaml"
    netplan apply
    exit 1
fi

# 显示获取到的信息
echo "----------------------------------------"
echo "从DHCP获取到的网络信息："
echo "网络接口: $INTERFACE"
echo "IP地址: $IP_ADDR"
echo "子网掩码位数: $SUBNET_MASK"
echo "网关: $GATEWAY"
echo "DNS服务器: 8.8.8.8, 114.114.114.114"
echo "----------------------------------------"

# 查找并备份现有Netplan配置
NETPLAN_FILES=$(ls /etc/netplan/*.yaml 2>/dev/null | grep -v "00-temp-dhcp.yaml" | grep -v "\.bak$")
if [ -z "$NETPLAN_FILES" ]; then
    echo "未找到现有Netplan配置文件，创建新文件..."
    NETPLAN_FILE="/etc/netplan/01-static-ip.yaml"
else
    # 选择第一个非临时配置文件
    NETPLAN_FILE=$(echo "$NETPLAN_FILES" | head -n 1)
    echo "找到Netplan配置文件: $NETPLAN_FILE"
    echo "备份原始配置文件到 ${NETPLAN_FILE}.bak"
    cp "$NETPLAN_FILE" "${NETPLAN_FILE}.bak"
fi

# 生成静态IP配置（使用新的默认路由语法替代gateway4）
echo "生成静态IP配置..."
cat > "$NETPLAN_FILE" << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: no
      addresses: [$IP_ADDR/$SUBNET_MASK]
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [8.8.8.8, 114.114.114.114]
EOF

# 删除临时DHCP配置
rm -f "/etc/netplan/00-temp-dhcp.yaml"
# 恢复可能存在的备份临时文件
[ -f "/etc/netplan/00-temp-dhcp.yaml.bak" ] && mv "/etc/netplan/00-temp-dhcp.yaml.bak" "/etc/netplan/00-temp-dhcp.yaml"

# 应用配置
echo "应用静态IP配置..."
if ! netplan apply; then
    echo "配置应用失败，尝试修复..."
    netplan try --timeout 10
fi

# 重启网络服务确保配置生效
systemctl restart systemd-networkd
systemctl restart systemd-resolved

# 验证配置
echo "----------------------------------------"
echo "配置已应用，当前网络信息："
ip addr show "$INTERFACE" | grep inet
echo "----------------------------------------"
echo "当前路由信息："
ip route show | grep default
echo "----------------------------------------"
echo "DNS配置："
if command -v resolvectl &> /dev/null; then
    resolvectl status "$INTERFACE" | grep "DNS Servers" -A2
elif command -v systemd-resolve &> /dev/null; then
    systemd-resolve --status "$INTERFACE" | grep "DNS Servers" -A2
else
    cat /etc/resolv.conf | grep nameserver
fi

echo "静态IP配置完成！IP地址保持为DHCP获取的 $IP_ADDR"
