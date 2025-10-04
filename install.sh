#!/bin/bash

# 获取操作系统名称
os_name=$(cat /etc/os-release | grep NAME | head -n1 | cut -d= -f2 | sed 's/"//g' | cut -d' ' -f1)

# 获取CPU架构
cpu_arch=$(uname -m)

# 输出结果
echo "操作系统: $os_name"
echo "CPU架构: $cpu_arch"

# 仅在 openEuler 系统上禁用 Swap
if [ "$os_name" = "openEuler" ]; then
    # 执行禁用 Swap
    swapoff -a
    sed -i '/swap/s/^/#/' /etc/fstab
    # 关闭防火墙
    systemctl stop firewalld
    systemctl disable firewalld
    # 关闭 SELinux 脚本
    setenforce 0
elif [ "$os_name" = "Ubuntu" ]; then
    swapoff -a
    sed -i '/swap/s/^/#/' /etc/fstab

    # 关闭ufw防火墙（Ubuntu默认防火墙）
    if systemctl is-active --quiet ufw; then
        systemctl stop ufw
        systemctl disable ufw
    fi
fi

ansible-playbook -i hosts.ini install_k8s.yml -k
