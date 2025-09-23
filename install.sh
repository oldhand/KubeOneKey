#!/bin/bash

# 获取操作系统名称
os_name=$(cat /etc/os-release | grep NAME | head -n1 | cut -d= -f2 | sed 's/"//g')

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

if [ "$cpu_arch" = "x86_64" ]; then
   if [ ! -f "images/x86_64/kube-apiserver-v1.29.3.tar" ]; then
     cat $PWD/images/x86_64/images.zip.001 $PWD/images/x86_64/images.zip.002 $PWD/images/x86_64/images.zip.003 $PWD/images/x86_64/images.zip.004 $PWD/images/x86_64/images.zip.005 > $PWD/images/x86_64/images.zip
     unzip $PWD/images/x86_64/images.zip -d $PWD/images/x86_64/
     rm -fr $PWD/images/x86_64/images.zip
   fi
elif [ "$cpu_arch" = "aarch64" ]; then
  if [ ! -f "images/aarch64/kube-apiserver-v1.29.3.tar" ]; then
     cat $PWD/images/aarch64/images.zip.001 $PWD/images/aarch64/images.zip.002 $PWD/images/aarch64/images.zip.003 $PWD/images/aarch64/images.zip.004 > $PWD/images/aarch64/images.zip
     unzip $PWD/images/aarch64/images.zip -d $PWD/images/aarch64/
     rm -fr $PWD/images/aarch64/images.zip
   fi
fi


ansible-playbook -i hosts.ini install_k8s.yml -k
