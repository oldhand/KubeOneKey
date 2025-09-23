#!/bin/bash

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本需要以root权限运行，请使用sudo执行"
    exit 1
fi

# 验证操作系统是否为OpenEuler 22.03 LTS
if ! grep -q "openEuler 22.03 LTS" /etc/os-release; then
    OS_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | sed 's/"//g')
    echo "此脚本专为 openEuler 22.03 LTS 设计，检测到不兼容的操作系统: $OS_NAME"
    exit 1
fi

echo "下载所有的依赖包..."


# OpenEuler使用dnf作为包管理器
# 第一组基础网络和工具包
sudo yumdownloader --resolve --destdir=$PWD/ \
    net-tools openssh-clients openssh-server sshpass curl wget git tar createrepo \
    telnet chrony ipset ipset-libs ipvsadm ca-certificates iptables iftop libselinux lvm2 nettle

# 第二组Ansible和Python相关包
sudo yumdownloader --resolve --destdir=$PWD/ ansible  openvswitch

# 第三组开发工具和库
sudo yumdownloader --resolve --destdir=$PWD/ \
    libasan libatomic libgcc libgfortran libgomp libitm liblsan libquadmath libstdc++ libtsan libubsan libssh2 \
    tk tk-devel zlib zlib-devel openssl openssl-devel curl curl-devel nmap


echo "所有包下载完成，存储在 ./packages 目录中"
