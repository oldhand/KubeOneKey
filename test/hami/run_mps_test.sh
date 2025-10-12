#!/bin/bash

echo "=== 启动MPS GPU测试任务 ==="
echo "开始时间: $(date)"

# 设置任务1：30%算力限制
echo "启动任务1 (30%算力限制)..."
export CUDA_MPS_ACTIVE_THREAD_PERCENTAGE=30
python3 high_intensity_gpu.py "Task1" 60 > task1_30_multi.log 2>&1 &
PID1=$!
echo "任务1启动完成，PID: $PID1"

# 设置任务2：70%算力限制  
echo "启动任务2 (70%算力限制)..."
export CUDA_MPS_ACTIVE_THREAD_PERCENTAGE=70
python3 high_intensity_gpu.py "Task2" 60 > task2_70_multi.log 2>&1 &
PID2=$!
echo "任务2启动完成，PID: $PID2"

echo "两个任务已在后台运行"
echo "任务1日志: task1_30_multi.log"
echo "任务2日志: task2_70_multi.log"
echo "可以使用以下命令监控任务状态:"
echo "  tail -f task1_30_multi.log"
echo "  tail -f task2_70_multi.log"
echo "  jobs -l"

# 等待任务完成（可选）
echo "等待任务完成（60秒）..."
sleep 60

echo "任务执行时间结束"
echo "结束时间: $(date)"
echo "=== 测试完成 ==="
