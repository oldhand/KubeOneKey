#!/bin/bash
set -euo pipefail

# 颜色输出定义（便于区分日志类型）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 重置为无颜色

# 核心配置参数（可根据集群实际情况调整）
TEST_POD="nvidia-gpu-test-pod"                          # 测试Pod名称
TEST_IMAGE="swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/nvidia/cuda:12.4.0-base-ubuntu22.04" # GPU测试镜像（含nvidia-smi）
PLUGIN_LABEL="app.kubernetes.io/name=nvidia-device-plugin" # nvidia-device-plugin的DaemonSet标签


# 1. 检查nvidia-device-plugin部署状态（确保插件已安装且运行）
echo -e "\n${YELLOW}=== 1. 检查nvidia-device-plugin部署状态 ==="${NC}
# 先检查DaemonSet是否存在
if ! kubectl get daemonset -n kube-system -l ${PLUGIN_LABEL} &> /dev/null; then
    echo -e "${RED}错误：未检测到标签为 ${PLUGIN_LABEL} 的DaemonSet，请先安装NVIDIA设备插件！${NC}"
    echo "参考安装命令：kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.4/nvidia-device-plugin.yml"
    exit 1
fi

# 检查插件Pod是否处于Running状态
DS_POD_STATUS=$(kubectl get pods -n kube-system -l ${PLUGIN_LABEL} -o jsonpath='{.items[*].status.phase}')
if [[ -z "${DS_POD_STATUS}" || "${DS_POD_STATUS}" != *"Running"* ]]; then
    echo -e "${RED}错误：nvidia-device-plugin Pod未正常运行，当前状态：${DS_POD_STATUS}${NC}"
    echo "当前插件Pod列表："
    kubectl get pods -n kube-system -l ${PLUGIN_LABEL}
    exit 1
fi
echo -e "${GREEN}✓ 插件DaemonSet及Pod均正常运行${NC}"


# 2. 检查节点GPU资源（关键步骤：确保有可用GPU节点）
echo -e "\n${YELLOW}=== 2. 检查节点GPU资源（核心验证） ==="${NC}
# 打印所有节点的GPU容量与可分配资源（直观查看资源情况）
echo "集群所有节点GPU资源详情（capacity=总容量，allocatable=可分配）："
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\tallocatable.gpu: "}{.status.allocatable.nvidia\.com/gpu}{"\tcapacity.gpu: "}{.status.capacity.nvidia\.com/gpu}{"\n"}{end}'

# 筛选出“可分配GPU>0”的节点（排除无GPU或GPU不可用的节点）
GPU_NODES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' | grep -v " null" | awk '$2 > 0 {print $1}')
if [ -z "$GPU_NODES" ]; then
    echo -e "${RED}错误：未找到可分配GPU>0的节点！需先排查以下问题：${NC}"
    echo "  1. 节点是否安装NVIDIA驱动？执行：ssh <节点名> nvidia-smi（需正常输出驱动信息）"
    echo "  2. 插件日志是否有错误？执行：kubectl logs -n kube-system <插件Pod名> -c nvidia-device-plugin-ctr"
    echo "  3. 容器运行时是否支持GPU？需安装nvidia-container-runtime（Docker/Containerd）"
    exit 1
fi

# 选择第一个可用GPU节点作为后续验证目标
FIRST_NODE=$(echo "$GPU_NODES" | head -n 1)
echo -e "${GREEN}✓ 找到可用GPU节点：${FIRST_NODE}（allocatable.gpu > 0）${NC}"


# 3. 验证前的GPU占用情况（使用kubectl run替代debug，支持自动清理）
echo -e "\n${YELLOW}=== 3. 验证前：查看节点${FIRST_NODE}的GPU实时占用 ==="${NC}
echo "通过临时调试Pod执行nvidia-smi（命令执行后自动清理Pod）："
# 使用kubectl run创建临时Pod，指定运行节点并自动清理
kubectl run temp-gpu-pre-check --rm -it --image="${TEST_IMAGE}" \
  --overrides='{"spec": {"nodeName": "'"${FIRST_NODE}"'", "restartPolicy": "Never"}}' \
  -- sh -c "nvidia-smi" || {
    echo -e "${YELLOW}警告：调试命令执行失败，退而显示节点GPU资源详情${NC}"
    # 若命令失败，通过describe node查看GPU资源分配情况
    kubectl describe node "${FIRST_NODE}" | grep -A 15 "nvidia.com/gpu"
}
echo -e "${GREEN}✓ 验证前GPU占用检查完成（临时Pod已自动清理）${NC}"


# 4. 创建测试Pod验证GPU调度（带控制平面容忍+延长超时，适配多场景）
echo -e "\n${YELLOW}=== 4. 创建测试Pod验证GPU调度与访问 ==="${NC}
# 定义测试Pod的YAML（请求1块GPU，执行nvidia-smi后休眠20秒确保日志可查）
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_POD}
spec:
  restartPolicy: Never # 失败后不重启，避免重复调度
  tolerations:
  - key: "node-role.kubernetes.io/control-plane" # 容忍控制平面污点（若GPU节点是控制平面）
    operator: "Exists"
    effect: "NoSchedule"
  containers:
  - name: gpu-test
    image: ${TEST_IMAGE}
    command: ["sh", "-c", "nvidia-smi && sleep 20"] # 执行nvidia-smi并保留Pod20秒
    resources:
      limits:
        nvidia.com/gpu: 1 # 显式请求1块GPU（触发调度器分配GPU）
EOF

# 等待Pod就绪（延长至90秒，应对镜像拉取耗时较长的场景）
echo "等待测试Pod ${TEST_POD} 就绪（最多等待90秒）..."
if ! kubectl wait --for=condition=Ready pod/"${TEST_POD}" --timeout=90s; then
    echo -e "${RED}错误：测试Pod启动失败，查看详细错误日志：${NC}"
    kubectl describe pod "${TEST_POD}" # 打印Pod事件，定位启动失败原因
    kubectl delete pod "${TEST_POD}" --ignore-not-found # 清理失败的Pod
    exit 1
fi
echo -e "${GREEN}✓ 测试Pod ${TEST_POD} 已成功就绪${NC}"


# 5. 验证测试Pod的GPU访问能力（核心结果验证）
echo -e "\n${YELLOW}=== 5. 验证测试Pod的GPU信息输出 ==="${NC}
echo "测试Pod ${TEST_POD} 的nvidia-smi输出："
kubectl logs "${TEST_POD}"

# 检查日志中是否包含NVIDIA-SMI（确认GPU已被Pod识别）
if ! kubectl logs "${TEST_POD}" | grep -q "NVIDIA-SMI"; then
    echo -e "${RED}错误：测试Pod未获取到GPU信息！nvidia-device-plugin功能异常${NC}"
    kubectl delete pod "${TEST_POD}" --ignore-not-found
    exit 1
fi
echo -e "${GREEN}✓ 测试Pod成功访问GPU！NVIDIA-SMI信息正常输出${NC}"


# 6. 验证后的GPU占用情况（确认GPU资源已正确释放/分配）
echo -e "\n${YELLOW}=== 6. 验证后：再次查看节点${FIRST_NODE}的GPU占用 ==="${NC}
echo "再次执行nvidia-smi（临时Pod自动清理）："
# 使用kubectl run创建临时Pod，指定运行节点并自动清理
kubectl run temp-gpu-post-check --rm -it --image="${TEST_IMAGE}" \
  --overrides='{"spec": {"nodeName": "'"${FIRST_NODE}"'", "restartPolicy": "Never"}}' \
  -- sh -c "nvidia-smi" || {
    echo -e "${YELLOW}警告：调试命令执行失败，显示节点当前GPU资源${NC}"
    kubectl describe node "${FIRST_NODE}" | grep -A 15 "nvidia.com/gpu"
}
echo -e "${GREEN}✓ 验证后GPU占用检查完成（临时Pod已自动清理）${NC}"


# 7. 清理测试资源与总结（避免残留资源）
echo -e "\n${YELLOW}=== 7. 清理测试资源 ==="${NC}
# 删除测试Pod（无论成功与否，确保资源不残留）
kubectl delete pod "${TEST_POD}" --ignore-not-found &> /dev/null
echo -e "${GREEN}✓ 测试Pod ${TEST_POD} 已清理完成${NC}"

# 最终验证结果总结
echo -e "\n${GREEN}=====================================================${NC}"
echo -e "${GREEN}=== 所有验证通过！nvidia-device-plugin工作正常 ===${NC}"
echo -e "${GREEN}=== 集群GPU可正常调度，Pod可正常访问GPU资源 ===${NC}"
echo -e "${GREEN}=====================================================${NC}"
