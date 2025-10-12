import torch
import time
import sys

def high_intensity_gpu_task(task_id, duration=120):
    print(f"=== 高强度GPU任务 {task_id} 启动 ===")
    
    # 强制使用GPU 0 (Tesla T4)
    torch.cuda.set_device(0)
    device = torch.device('cuda:0')
    
    print(f"使用设备: {torch.cuda.get_device_name(device)}")
    
    # 创建非常大的矩阵来占用显存和计算资源
    # Tesla T4有16GB显存，我们可以使用更大的矩阵
    size = 12000  # 非常大的矩阵
    print(f"创建 {size}x{size} 矩阵...")
    
    try:
        # 创建多个大矩阵
        a = torch.randn(size, size, device=device)
        b = torch.randn(size, size, device=device)
        c = torch.randn(size, size, device=device)
        
        print("矩阵创建完成，开始高强度计算...")
    except RuntimeError as e:
        # 如果显存不足，使用小一点的矩阵
        print(f"显存不足，调整矩阵大小: {e}")
        size = 8000
        a = torch.randn(size, size, device=device)
        b = torch.randn(size, size, device=device)
        c = torch.randn(size, size, device=device)
    
    start_time = time.time()
    iteration = 0
    
    while time.time() - start_time < duration:
        iteration_start = time.time()
        
        # 连续多个矩阵乘法，增加计算密度
        result = a
        for _ in range(5):  # 连续5次矩阵乘法
            result = torch.matmul(result, b)
        
        # 额外的计算
        extra = torch.matmul(result, c)
        final_result = extra.sum().item()
        
        iteration_time = time.time() - iteration_start
        iteration += 1
        
        # 实时输出性能信息
        if iteration % 5 == 0:
            memory_used = torch.cuda.memory_allocated(device) / 1024**3
            memory_reserved = torch.cuda.memory_reserved(device) / 1024**3
            print(f"任务{task_id} - 迭代{iteration}: 耗时{iteration_time:.3f}s, 显存{memory_used:.1f}GB/{memory_reserved:.1f}GB")
        
        # 极短暂停，保持高负载
        time.sleep(0.01)
    
    print(f"任务 {task_id} 完成")

if __name__ == "__main__":
    task_id = sys.argv[1] if len(sys.argv) > 1 else "A"
    duration = int(sys.argv[2]) if len(sys.argv) > 2 else 120
    high_intensity_gpu_task(task_id, duration)
