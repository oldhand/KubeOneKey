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
   rpm -ivh $(pwd)/packages/$os_name/$cpu_arch/*.rpm --force --nodeps
elif [ "$os_name" = "Ubuntu" ]; then
   sudo dpkg -i ./packages/$os_name/$cpu_arch/*.deb
fi

ansible-galaxy collection install $(pwd)/kubernetes/kubernetes-core-6.1.0.tar.gz --force

pip install --no-index --find-links=$(pwd)/pip kubernetes PyYAML