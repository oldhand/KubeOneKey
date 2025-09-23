#!/bin/bash

# 显示警告信息
echo "警告：此脚本将清理Docker中的所有容器、镜像、网络和卷！"
echo "这是一个不可逆的操作，请确保你知道自己在做什么。"
read -p "是否继续？(y/N) " -n 1 -r
echo    # 换行

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "操作已取消。"
    exit 1
fi

# 停止所有正在运行的容器
echo "正在停止所有运行中的容器..."
docker stop $(docker ps -aq) 2>/dev/null

# 删除所有容器
echo "正在删除所有容器..."
docker rm $(docker ps -aq) 2>/dev/null

# 删除所有镜像
echo "正在删除所有镜像..."
docker rmi -f $(docker images -aq) 2>/dev/null

# 清理所有未使用的网络
echo "正在清理网络..."
docker network prune -f 2>/dev/null

# 清理所有卷
echo "正在清理卷..."
docker volume prune -f 2>/dev/null

# 执行系统级清理
echo "正在执行系统级Docker清理..."
docker system prune -a --volumes -f 2>/dev/null

echo "清理完成！"
