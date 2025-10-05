#!/bin/bash

# 定义目标镜像名称
IMAGE="swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/nvidia/cuda:12.4.0-base-ubuntu22.04"

# 检查本地是否存在该镜像
if [ -z "$(sudo docker images -q $IMAGE)" ]; then
    echo "本地不存在镜像 $IMAGE，开始拉取..."
    # 拉取镜像
    sudo docker pull $IMAGE
    # 检查拉取是否成功
    if [ $? -ne 0 ]; then
        echo "镜像拉取失败，请检查网络或镜像地址是否正确"
        exit 1
    fi
else
    echo "本地已存在镜像 $IMAGE，直接运行容器..."
fi

# 运行容器（与原命令一致，自动删除容器并查看GPU信息）
sudo docker run --rm --gpus all $IMAGE nvidia-smi
