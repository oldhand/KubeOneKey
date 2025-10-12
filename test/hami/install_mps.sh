#!/bin/bash

echo "=== 配置MPS环境 ==="

# 停止可能运行的MPS服务
echo "停止现有MPS服务..."
echo quit | nvidia-cuda-mps-control 2>/dev/null || true

# 设置GPU为独占模式
echo "设置GPU独占模式..."
sudo nvidia-smi -i 0 -c EXCLUSIVE_PROCESS

# 设置环境变量
export CUDA_VISIBLE_DEVICES=0

# 启动MPS服务
echo "启动MPS服务..."
nvidia-cuda-mps-control -d

# 验证MPS状态
echo "验证MPS状态..."
ps -ef | grep mps
echo "status" | nvidia-cuda-mps-control

echo "=== MPS配置完成 ==="
