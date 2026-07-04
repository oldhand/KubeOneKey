#!/bin/bash

# ==========================================
# 变量配置区
# ==========================================
INTERFACE_NAME="k8s-dummy"
IP_ADDRESS="192.168.100.100"
SUBNET_MASK="/32"
# 新增：Kubernetes Service CIDR 网段，用于离线状态下的 ClusterIP 路由绑定
SERVICE_CIDR="172.23.0.0/17"

# ==========================================
# 1. 环境检查
# ==========================================
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误: 请使用 root 或 sudo 权限运行此脚本。"
  exit 1
fi

echo "🚀 开始配置虚拟网卡 (支持离线 k8s 路由优化版)..."

# ==========================================
# 2. 环境清理 (防冲突)
# ==========================================
echo "🧹 1/4 正在清理可能残留的失效 Netplan 配置..."
if [ -f "/etc/netplan/99-k8s-dummy.yaml" ]; then
    rm -f /etc/netplan/99-k8s-dummy.yaml
    netplan apply
fi

# ==========================================
# 3. 内核模块配置
# ==========================================
echo "📦 2/4 正在配置 dummy 内核模块开机加载..."
cat <<EOF > /etc/modules-load.d/k8s-dummy.conf
dummy
EOF
modprobe dummy

# ==========================================
# 4. 创建 Systemd 服务 (集成离线路由修复)
# ==========================================
echo "⚙️ 3/4 正在创建 systemd 自动化网络服务..."
cat <<EOF > /etc/systemd/system/${INTERFACE_NAME}.service
[Unit]
Description=Create K8s Dummy Interface and Assign Static IP
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes

# 1. 尝试创建虚拟网卡 (忽略已存在的报错)
ExecStartPre=-/sbin/ip link add dev ${INTERFACE_NAME} type dummy

# 2. 清空该网卡上可能残留的旧 IP
ExecStartPre=-/sbin/ip addr flush dev ${INTERFACE_NAME}

# 3. 强制分配指定的固定 IP
ExecStart=/sbin/ip addr add ${IP_ADDRESS}${SUBNET_MASK} dev ${INTERFACE_NAME}

# 4. 强制启动网卡
ExecStartPost=/sbin/ip link set dev ${INTERFACE_NAME} up

# 5. 添加 Service CIDR 路由，确保无网络时 ClusterIP (如 172.23.0.1) 能够正确路由并完成 iptables 转发
ExecStartPost=-/sbin/ip route add ${SERVICE_CIDR} dev ${INTERFACE_NAME}

# 停止服务时的清理动作
ExecStop=/sbin/ip link delete ${INTERFACE_NAME} type dummy

[Install]
WantedBy=multi-user.target
EOF

# ==========================================
# 5. 应用与启动
# ==========================================
echo "🔄 4/4 正在重载 systemd 并启动服务..."
systemctl daemon-reload
# 先停止可能正在运行的旧服务状态，确保全新启动
systemctl stop ${INTERFACE_NAME}.service >/dev/null 2>&1
systemctl enable --now ${INTERFACE_NAME}.service

# ==========================================
# 6. 验证结果
# ==========================================
echo -e "\n✅ 部署完成！网卡、IP 以及 Service 路由已成功挂载，且重启永久生效。"
echo "当前网络状态如下："
echo "----------------------------------------------------"
ip -4 addr show "${INTERFACE_NAME}"
echo "----------------------------------------------------"
echo "当前关联路由状态："
ip route show dev "${INTERFACE_NAME}"
echo "----------------------------------------------------"