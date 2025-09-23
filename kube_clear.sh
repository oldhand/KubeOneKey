#!/bin/bash

# 适用于 openEuler 系统（Docker 作为容器运行时）的 Kubernetes + kube-ovn 清理脚本
# 警告：此操作会删除所有集群数据，执行前请确认！

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本需要以 root 权限运行，请使用 sudo 或切换至 root 用户执行"
    exit 1
fi

# 检查 Docker 是否安装
if ! command -v docker &>/dev/null; then
    echo "警告：未检测到 Docker 环境，将跳过 Docker 相关清理步骤"
    DOCKER_AVAILABLE=0
else
    DOCKER_AVAILABLE=1
fi

# 停止并禁用 openvswitch/ovn 相关服务（openEuler 适配）
echo "===== 停止并禁用 openvswitch/ovn 服务 ====="
systemctl stop openvswitch 2>/dev/null
systemctl disable openvswitch 2>/dev/null
systemctl stop ovn-central 2>/dev/null
systemctl stop ovn-controller 2>/dev/null
systemctl disable ovn-central 2>/dev/null
systemctl disable ovn-controller 2>/dev/null
systemctl daemon-reload

# 清理 kube-ovn 相关 CNI 配置
echo "===== 清理 CNI 配置文件 ====="
rm -rf /etc/cni/net.d/*kube-ovn*
rm -rf /opt/cni/net.d/*kube-ovn*

# 清理 ovn/ovs 数据目录与日志
echo "===== 清理 ovn/ovs 相关目录 ====="
rm -rf /var/run/openvswitch
rm -rf /var/run/ovn
rm -rf /var/log/openvswitch
rm -rf /var/log/ovn
rm -rf /etc/openvswitch
rm -rf /etc/ovn
rm -rf /etc/origin/openvswitch
rm -rf /etc/origin/ovn

# 执行 kubeadm reset 重置集群
echo "===== 执行 kubeadm reset 重置 Kubernetes 集群 ====="
kubeadm reset --force --ignore-preflight-errors=all

# 清理 Kubernetes 核心组件残留
echo "===== 清理 Kubernetes 核心目录 ====="
rm -rf /var/lib/kubelet
rm -rf /var/lib/etcd
rm -rf /etc/kubernetes
rm -rf /root/.kube/config
rm -rf /home/*/.kube/config

# 清理 Docker 容器（仅当 Docker 可用时）
if [ $DOCKER_AVAILABLE -eq 1 ]; then
    echo "===== 清理 Docker 容器 ====="
    # 停止并删除所有 Kubernetes 相关容器
    docker rm -f $(docker ps -aq --filter name=k8s_) 2>/dev/null
    # 清理 kube-ovn 相关容器
    docker rm -f $(docker ps -aq --filter name=kube-ovn) 2>/dev/null
    # 清理 ovn 相关容器
    docker rm -f $(docker ps -aq --filter name=ovn) 2>/dev/null
    # 清理 pause 容器
    docker rm -f $(docker ps -aq --filter name=pause) 2>/dev/null
fi

# 清理 Docker 镜像（仅当 Docker 可用时）
if [ $DOCKER_AVAILABLE -eq 1 ]; then
    echo "===== 清理 Docker 镜像 ====="
    # 清理 Kubernetes 基础镜像
    docker rmi $(docker images -q --filter reference='k8s.gcr.io/*') 2>/dev/null
    docker rmi $(docker images -q --filter reference='registry.aliyuncs.com/google_containers/*') 2>/dev/null
    # 清理 kube-ovn 镜像
    docker rmi $(docker images -q --filter reference='docker.io/kubeovn/*') 2>/dev/null
    docker rmi $(docker images -q --filter reference='docker.m.daocloud.io/kubeovn/*') 2>/dev/null
    # 清理 pause 镜像
    docker rmi $(docker images -q --filter reference='*pause:*') 2>/dev/null
    # 清理 dangling 镜像
    docker rmi $(docker images -q -f dangling=true) 2>/dev/null
fi

# 清理 openEuler 系统级残留
echo "===== 清理系统级残留 ====="
restorecon -R /etc/cni /var/lib/kubelet /var/lib/etcd 2>/dev/null

echo "===== 所有清理操作完成！ ====="
echo "提示：建议执行 'systemctl restart docker' 重启 Docker 服务，或直接重启系统以确保清理彻底"
