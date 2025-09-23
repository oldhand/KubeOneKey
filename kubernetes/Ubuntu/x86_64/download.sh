#!/bin/bash

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本需要以root权限运行，请使用sudo执行"
    exit 1
fi

echo "deb [signed-by=/etc/apt/trusted.gpg.d/kubernetes-v1.29.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list


sudo apt update

sudo apt-get download -o Dir::Cache="./" -o Dir::Cache::archives="./"  kubeadm kubelet kubectl cri-tools conntrack kubernetes-cni ebtables socat

