#!/bin/bash

# 获取操作系统名称
os_name=$(cat /etc/os-release | grep NAME | head -n1 | cut -d= -f2 | sed 's/"//g' | cut -d' ' -f1)

# 根据操作系统类型获取版本号（含小版本）
if [ "$os_name" = "CentOS" ] || [ "$os_name" = "RedHat" ] || [ "$os_name" = "Rocky" ] || [ "$os_name" = "AlmaLinux" ]; then
    # RHEL系（CentOS/Rocky等）从专门的release文件提取版本
    os_version=$(cat /etc/redhat-release | grep -oE '([0-9]+\.)+[0-9]+' | cut -d. -f1,2)
else
    # 其他发行版（Ubuntu/Debian等）从os-release的VERSION字段提取
    os_version=$(cat /etc/os-release | grep '^VERSION=' | head -n1 | cut -d= -f2 | sed 's/"//g' | grep -oE '[0-9]+\.[0-9]+')
fi

# 获取CPU架构
cpu_arch=$(uname -m)

# 输出结果
echo "操作系统: $os_name"
echo "操作系统版本: $os_version"
echo "CPU架构: $cpu_arch"

## 仅在 openEuler 系统上禁用 Swap
if [ "$os_name" = "openEuler" ]; then
   rpm -ivh $(pwd)/packages/$os_name/$cpu_arch/*.rpm --force --nodeps
elif [ "$os_name" = "CentOS" ]; then
   rpm -ivh $(pwd)/packages/$os_name/$cpu_arch/*.rpm --force --nodeps
elif [ "$os_name" = "Ubuntu" ]; then
   sudo dpkg -i ./packages/$os_name/$cpu_arch/*.deb
fi

ansible-galaxy collection install $(pwd)/kubernetes/kubernetes-core-6.1.0.tar.gz --force

if [ "$os_name" = "CentOS" ]; then
    pip3 install --no-index --find-links=$(pwd)/pip/$os_name/$os_version kubernetes PyYAML
else
  pip3 install --no-index --find-links=$(pwd)/pip/$os_name kubernetes PyYAML
fi
