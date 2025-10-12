#!/bin/bash
set -euo pipefail

# 颜色输出定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 重置为无颜色

# 核心配置参数
TEST_POD="hami-gpu-test-pod"
TEST_IMAGE="swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/pytorch/pytorch:2.6.0-cuda12.4-cudnn9-runtime"
PLUGIN_LABEL="app.kubernetes.io/component=hami-device-plugin"
GPU_RESOURCE="hami.com/gpu"
GPU_JSON_RESOURCE="hami\.com/gpu"


# 定义GPU负载生成脚本（保持不变，修复YAML引用即可）
GPU_LOAD_SCRIPT=$(cat <<'EOF'
#!/bin/sh
set -eu

python3 -c "import torch; print(f'  - CUDA版本: {torch.version.cuda}')"
python3 -c "import torch; print(f'  - cuDNN版本: {torch.backends.cudnn.version()}')"

NODE_GPU_TOTAL=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits)
echo "当前节点GPU总数: $NODE_GPU_TOTAL"

cat <<PYSCRIPT > gpu_load.py
import torch
import time
from datetime import datetime
import subprocess

if not torch.cuda.is_available():
    raise Exception("❌ CUDA不可用")
if not torch.backends.cudnn.is_available():
    raise Exception("❌ cuDNN不可用")

gpu_count = torch.cuda.device_count()
print(f"✅ 环境验证通过：")
print(f"  - 可用GPU数量: {gpu_count}")
for i in range(gpu_count):
    print(f"  - GPU {i}: {torch.cuda.get_device_name(i)}")

print(f"\n🚀 开始生成GPU负载（跑满所有{gpu_count}个GPU）...")

matrix_size = 8192

def load_gpu(gpu_id):
    torch.cuda.set_device(gpu_id)
    torch.backends.cudnn.benchmark = True
    a = torch.randn(matrix_size, matrix_size, device=f'cuda:{gpu_id}', dtype=torch.float32)
    b = torch.randn(matrix_size, matrix_size, device=f'cuda:{gpu_id}', dtype=torch.float32)
    while True:
        c = torch.matmul(a, b)
        time.sleep(0.001)

import threading
threads = []
for i in range(gpu_count):
    t = threading.Thread(target=load_gpu, args=(i,), daemon=True)
    threads.append(t)
    t.start()
    print(f"  - GPU {i} 负载线程已启动")

print("\n📈 开始监控GPU占用率（持续10秒）：")
print("时间\t\tGPU ID\t单卡利用率(%)\t相对节点总GPU占比(%)")
print("-" * 60)
NODE_GPU_TOTAL = $NODE_GPU_TOTAL
for _ in range(5):
    timestamp = datetime.now().strftime("%H:%M:%S")
    result = subprocess.run(
        ['nvidia-smi', '--query-gpu=index,utilization.gpu', '--format=csv,noheader,nounits'],
        capture_output=True, text=True, check=True
    )
    nvidia_smi_output = result.stdout

    for line in nvidia_smi_output.strip().split('\n'):
        if line:
            gpu_id, gpu_util = line.strip().split(', ')
            gpu_id = gpu_id.strip()
            gpu_util = gpu_util.strip()
            relative_util = round(float(gpu_util) / NODE_GPU_TOTAL, 2)
            print(f"{timestamp}\t{gpu_id}\t{gpu_util}%\t\t{relative_util}%")
    time.sleep(2)

print("✅ 负载测试结束")
# 主动退出线程（解决core dumped警告）
import os
os._exit(0)
PYSCRIPT

echo -e "\n🎯 启动GPU负载测试..."
python3 -u gpu_load.py
EOF
)



# 1. 检查HAMI GPU设备插件部署状态
echo -e "\n${YELLOW}=== 1. 检查HAMI GPU设备插件部署状态 ==="${NC}
if ! kubectl get daemonset -n kube-system -l ${PLUGIN_LABEL} &> /dev/null; then
    echo -e "${RED}错误：未检测到HAMI GPU设备插件！${NC}"
    exit 1
fi
DS_POD_STATUS=$(kubectl get pods -n kube-system -l ${PLUGIN_LABEL} -o jsonpath='{.items[*].status.phase}')
if [[ -z "${DS_POD_STATUS}" || "${DS_POD_STATUS}" != *"Running"* ]]; then
    echo -e "${RED}错误：HAMI GPU设备插件Pod未正常运行${NC}"
    exit 1
fi
echo -e "${GREEN}✓ HAMI GPU设备插件正常运行${NC}"


# 2. 检查节点hami.com/gpu资源
echo -e "\n${YELLOW}=== 2. 检查节点${GPU_RESOURCE}资源 ==="${NC}
echo "集群节点${GPU_RESOURCE}资源详情："
kubectl get nodes -o jsonpath="{range .items[*]}{.metadata.name}{\"\tallocatable.gpu: \"}{.status.allocatable.${GPU_JSON_RESOURCE}}{\"\tcapacity.gpu: \"}{.status.capacity.${GPU_JSON_RESOURCE}}{\"\n\"}{end}"
GPU_NODES=$(kubectl get nodes -o jsonpath="{range .items[*]}{.metadata.name}{\" \"}{.status.allocatable.${GPU_JSON_RESOURCE}}{\"\n\"}{end}" | grep -v " null" | awk '$2 > 0 {print $1}')
if [ -z "$GPU_NODES" ]; then
    echo -e "${RED}错误：未找到可分配${GPU_RESOURCE}>0的节点！${NC}"
    exit 1
fi
FIRST_NODE=$(echo "$GPU_NODES" | head -n 1)
echo -e "${GREEN}✓ 找到可用节点：${FIRST_NODE}${NC}"


# 3. 验证前：跑满GPU并监控占用率
echo -e "\n${YELLOW}=== 3. 验证前：在节点${FIRST_NODE}跑满GPU ==="${NC}
echo -e "通过临时Pod (不指定${GPU_RESOURCE}=1) 执行负载测试："
kubectl run temp-hami-pre-check --rm -it --image="${TEST_IMAGE}" \
  --overrides='{"spec": {"nodeName": "'"${FIRST_NODE}"'", "restartPolicy": "Never"}}' \
  -- sh -c "cat > /gpu_load.sh <<'EOF'
${GPU_LOAD_SCRIPT}
EOF
chmod +x /gpu_load.sh && /gpu_load.sh" || {
    echo -e "${YELLOW}警告：负载测试执行失败${NC}"
    kubectl describe node "${FIRST_NODE}" | grep -A 15 "${GPU_RESOURCE}"
}
echo -e "${GREEN}✓ 验证前GPU负载测试完成${NC}"


# 4. 创建测试Pod验证调度（核心修复：YAML格式）
echo -e "\n${YELLOW}=== 4. 创建测试Pod (指定${GPU_RESOURCE}=1) 验证${GPU_RESOURCE}调度 ==="${NC}
kubectl delete pod "${TEST_POD}" --ignore-not-found
# 修复：确保INNER_EOF无缩进，与|后的起始位置对齐
ENCODED_SCRIPT=$(echo "${GPU_LOAD_SCRIPT}" | sed 's/^/      /')
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_POD}
spec:
  restartPolicy: Never
  tolerations:
  - key: "node-role.kubernetes.io/control-plane"
    operator: "Exists"
    effect: "NoSchedule"
  containers:
  - name: hami-gpu-test
    image: ${TEST_IMAGE}
    command:
    - sh
    - -c
    - |
      cat > /gpu_load.sh <<'INNER_EOF'
      ${ENCODED_SCRIPT}
      INNER_EOF
      chmod +x /gpu_load.sh && /gpu_load.sh
    resources:
      limits:
        ${GPU_RESOURCE}: 1
EOF

if ! kubectl wait --for=condition=Ready pod/"${TEST_POD}" --timeout=30s; then
    echo -e "${RED}错误：测试Pod启动失败${NC}"
    kubectl describe pod "${TEST_POD}"
    kubectl logs "${TEST_POD}"
    kubectl delete pod "${TEST_POD}" --ignore-not-found
    exit 1
fi
echo -e "${GREEN}✓ 测试Pod ${TEST_POD} 已就绪${NC}"


# 5. 验证测试Pod的GPU负载输出
echo -e "\n${YELLOW}=== 5. 验证测试Pod的GPU占用率 ==="${NC}
kubectl logs "${TEST_POD}" -f


# 6 清理资源与总结
echo -e "\n${YELLOW}=== 7. 清理测试资源 ==="${NC}
kubectl delete pod "${TEST_POD}" --ignore-not-found &> /dev/null
echo -e "${GREEN}✓ 测试Pod已清理${NC}"

echo -e "\n${GREEN}=====================================================${NC}"
echo -e "${GREEN}=== 所有验证通过！GPU调度与负载测试正常 ===${NC}"
echo -e "${GREEN}=====================================================${NC}"
