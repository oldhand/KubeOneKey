#!/bin/bash

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root权限运行此脚本 (sudo $0)"
    exit 1
fi

# 验证操作系统是否为OpenEuler 22.03
if ! grep -q "openEuler 22.03 LTS" /etc/os-release; then
    echo "此脚本专为 OpenEuler 22.03 LTS 设计，检测到不兼容的操作系统"
    exit 1
fi

# 检测网络接口（默认使用第一个活动接口）
INTERFACE=$(ip -br link show | awk '$1 !~ "lo" && $2 ~ "UP" {print $1; exit}')
if [ -z "$INTERFACE" ]; then
    echo "未找到活动的网络接口，请检查网络连接"
    exit 1
fi

echo "检测到活动网络接口: $INTERFACE"

# 获取当前DHCP分配的网络配置
IP_ADDRESS=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | cut -d '/' -f 1)
SUBNET_CIDR=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | cut -d '/' -f 2)
GATEWAY=$(ip route show default | grep -oP '(?<=via\s)\d+(\.\d+){3}')
DNS_SERVERS=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')

# 从CIDR计算子网掩码
calculate_netmask() {
    local cidr=$1
    local netmask=""
    local i=0
    while [ $i -lt 4 ]; do
        if [ $cidr -ge 8 ]; then
            netmask+="255."
            cidr=$((cidr - 8))
        else
            local bits=$(( (1 << 8) - (1 << (8 - cidr)) ))
            netmask+="$bits."
            cidr=0
        fi
        i=$((i + 1))
    done
    echo "${netmask%?}"  # 移除最后一个点
}

SUBNET_MASK=$(calculate_netmask $SUBNET_CIDR)

# 验证获取到的信息
if [ -z "$IP_ADDRESS" ] || [ -z "$SUBNET_MASK" ] || [ -z "$GATEWAY" ] || [ -z "$DNS_SERVERS" ]; then
    echo "无法获取完整的网络配置信息"
    echo "IP地址: $IP_ADDRESS"
    echo "子网掩码: $SUBNET_MASK"
    echo "网关: $GATEWAY"
    echo "DNS服务器: $DNS_SERVERS"
    exit 1
fi

# 显示获取到的配置信息
echo "当前网络配置:"
echo "IP地址: $IP_ADDRESS"
echo "子网掩码: $SUBNET_MASK (CIDR: /$SUBNET_CIDR)"
echo "网关: $GATEWAY"
echo "DNS服务器: $DNS_SERVERS"

# 确认是否继续
read -p "是否将以上配置设置为静态IP? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "脚本已取消"
    exit 1
fi

# 备份原有配置
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
NM_CONNECTION_FILE="/etc/sysconfig/network-scripts/ifcfg-$INTERFACE"

echo "备份原有网络配置到 ${NM_CONNECTION_FILE}.backup-${BACKUP_DATE}"
cp "$NM_CONNECTION_FILE" "${NM_CONNECTION_FILE}.backup-${BACKUP_DATE}"

# 配置静态IP
echo "配置静态IP..."

# 清除现有网络配置
sed -i '/^IPADDR=/d' "$NM_CONNECTION_FILE"
sed -i '/^NETMASK=/d' "$NM_CONNECTION_FILE"
sed -i '/^GATEWAY=/d' "$NM_CONNECTION_FILE"
sed -i '/^DNS1=/d' "$NM_CONNECTION_FILE"
sed -i '/^DNS2=/d' "$NM_CONNECTION_FILE"
sed -i '/^PREFIX=/d' "$NM_CONNECTION_FILE"
sed -i '/^BOOTPROTO=/d' "$NM_CONNECTION_FILE"

# 添加静态IP配置
echo "BOOTPROTO=static" >> "$NM_CONNECTION_FILE"
echo "IPADDR=$IP_ADDRESS" >> "$NM_CONNECTION_FILE"
echo "PREFIX=$SUBNET_CIDR" >> "$NM_CONNECTION_FILE"
echo "NETMASK=$SUBNET_MASK" >> "$NM_CONNECTION_FILE"
echo "GATEWAY=$GATEWAY" >> "$NM_CONNECTION_FILE"

# 添加DNS服务器
DNS_ARRAY=($DNS_SERVERS)
if [ ${#DNS_ARRAY[@]} -ge 1 ]; then
    echo "DNS1=${DNS_ARRAY[0]}" >> "$NM_CONNECTION_FILE"
fi
if [ ${#DNS_ARRAY[@]} -ge 2 ]; then
    echo "DNS2=${DNS_ARRAY[1]}" >> "$NM_CONNECTION_FILE"
fi

# 确保网络接口开机启动
sed -i "s/ONBOOT=no/ONBOOT=yes/" "$NM_CONNECTION_FILE"
if ! grep -q "ONBOOT=yes" "$NM_CONNECTION_FILE"; then
    echo "ONBOOT=yes" >> "$NM_CONNECTION_FILE"
fi

# 重启网络服务
echo "重启网络服务..."
systemctl restart NetworkManager

# 重新激活网络接口
nmcli connection down "$INTERFACE"
nmcli connection up "$INTERFACE"

echo "静态IP配置已完成。"
echo "配置的静态IP信息:"
echo "IP地址: $IP_ADDRESS"
echo "子网掩码: $SUBNET_MASK"
echo "网关: $GATEWAY"
echo "DNS服务器: $DNS_SERVERS"
echo "可以使用 'ip addr show $INTERFACE' 命令验证配置"
