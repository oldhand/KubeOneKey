#!/bin/bash

# 国内镜像源，可根据需要切换
REGISTRY="registry.cn-hangzhou.aliyuncs.com/google_containers"
# 对于Kube-OVN，使用专门的国内源
KUBE_OVN_REGISTRY="docker.m.daocloud.io/kubeovn"

# 定义需要拉取的镜像列表 (名称:版本)
IMAGES=(
    "coredns:v1.10.1"
    "etcd:3.5.9-0"
    "kube-apiserver:v1.29.3"
    "kube-controller-manager:v1.29.3"
    "kube-proxy:v1.29.3"
    "kube-scheduler:v1.29.3"
    "pause:3.9"
)

# 拉取并导出Kubernetes核心组件镜像
for image in "${IMAGES[@]}"; do
    full_image="${REGISTRY}/${image}"
    echo "正在拉取 ${full_image} ..."
    docker pull ${full_image}

    if [ $? -eq 0 ]; then
        echo "${full_image} 拉取成功"

        # 导出为tar文件，将冒号替换为连字符作为文件名
        tar_file="${image//:/-}.tar"
        echo "正在导出 ${full_image} 到 ${tar_file} ..."
        docker save -o ${tar_file} ${full_image}

        if [ $? -eq 0 ]; then
            echo "${full_image} 导出成功"
        else
            echo "${full_image} 导出失败"
        fi
    else
        echo "${full_image} 拉取失败，跳过导出"
    fi
    echo "-------------------------"
done

# 单独处理Kube-OVN镜像
KUBE_OVN_IMAGE="kube-ovn:v1.13.15"
full_kube_ovn_image="${KUBE_OVN_REGISTRY}/${KUBE_OVN_IMAGE}"
echo "正在拉取 ${full_kube_ovn_image} ..."
docker pull ${full_kube_ovn_image}

if [ $? -eq 0 ]; then
    echo "${full_kube_ovn_image} 拉取成功"

    # 导出为tar文件
    kube_ovn_tar_file="${KUBE_OVN_IMAGE//:/-}.tar"
    echo "正在导出 ${full_kube_ovn_image} 到 ${kube_ovn_tar_file} ..."
    docker save -o ${kube_ovn_tar_file} ${full_kube_ovn_image}

    if [ $? -eq 0 ]; then
        echo "${full_kube_ovn_image} 导出成功"
    else
        echo "${full_kube_ovn_image} 导出失败"
    fi
else
    echo "${full_kube_ovn_image} 拉取失败，跳过导出"
fi

echo "所有镜像拉取和导出操作完成"
