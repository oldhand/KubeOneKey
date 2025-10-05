#!/bin/bash
set -euo pipefail

# 颜色输出定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 重置为无颜色

# 核心配置参数（适配hami.com/gpu资源标识）
TEST_POD="hami-gpu-test-pod"                          # 测试Pod名称
TEST_IMAGE="swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/nvidia/cuda:12.4.0-base-ubuntu22.04"      # 含nvidia-smi的基础镜像（适配RTX 4070）
PLUGIN_LABEL="app.kubernetes.io/component=hami-device-plugin" # HAMI GPU设备插件的DaemonSet标签（根据实际调整）
GPU_RESOURCE="hami.com/gpu"                           # 核心资源标识：hami.com/gpu
GPU_JSON_RESOURCE="hami\.com/gpu"                     # 核心资源标识：hami.com/gpu
GPU_CHECK_TOOL="nvidia-smi"                           # GPU状态检查工具（NVIDIA显卡通用）


# 1. 检查HAMI GPU设备插件部署状态
echo -e "\n${YELLOW}=== 1. 检查HAMI GPU设备插件部署状态 ==="${NC}
# 检查插件DaemonSet是否存在
if ! kubectl get daemonset -n kube-system -l ${PLUGIN_LABEL} &> /dev/null; then
    echo -e "${RED}错误：未检测到标签为 ${PLUGIN_LABEL} 的DaemonSet，请先安装HAMI GPU设备插件！${NC}"
    exit 1
fi

# 检查插件Pod是否正常运行
DS_POD_STATUS=$(kubectl get pods -n kube-system -l ${PLUGIN_LABEL} -o jsonpath='{.items[*].status.phase}')
if [[ -z "${DS_POD_STATUS}" || "${DS_POD_STATUS}" != *"Running"* ]]; then
    echo -e "${RED}错误：HAMI GPU设备插件Pod未正常运行，当前状态：${DS_POD_STATUS}${NC}"
    echo "当前插件Pod列表："
    kubectl get pods -n kube-system -l ${PLUGIN_LABEL}
    exit 1
fi
echo -e "${GREEN}✓ HAMI GPU设备插件DaemonSet及Pod均正常运行${NC}"


# 2. 检查节点hami.com/gpu资源（核心验证）
echo -e "\n${YELLOW}=== 2. 检查节点${GPU_RESOURCE}资源（核心验证） ==="${NC}
# 打印所有节点的hami.com/gpu容量与可分配资源
echo "集群所有节点${GPU_RESOURCE}资源详情（capacity=总容量，allocatable=可分配）："
kubectl get nodes -o jsonpath="{range .items[*]}{.metadata.name}{\"\tallocatable.gpu: \"}{.status.allocatable.${GPU_JSON_RESOURCE}}{\"\tcapacity.gpu: \"}{.status.capacity.${GPU_JSON_RESOURCE}}{\"\n\"}{end}"


# 筛选出“可分配hami.com/gpu>0”的节点
GPU_NODES=$(kubectl get nodes -o jsonpath="{range .items[*]}{.metadata.name}{\" \"}{.status.allocatable.${GPU_JSON_RESOURCE}}{\"\n\"}{end}" | grep -v " null" | awk '$2 > 0 {print $1}')
if [ -z "$GPU_NODES" ]; then
    echo -e "${RED}错误：未找到可分配${GPU_RESOURCE}>0的节点！需排查以下问题：${NC}"
    echo "  1. 节点是否安装NVIDIA驱动（适配RTX 4070需535+版本）：ssh <节点> ${GPU_CHECK_TOOL}"
    echo "  2. HAMI插件日志是否有错误：kubectl logs -n kube-system <插件Pod名> -c hami-gpu-plugin"
    echo "  3. 容器运行时是否支持GPU：需安装nvidia-container-runtime"
    exit 1
fi

# 选择第一个可用节点作为验证目标
FIRST_NODE=$(echo "$GPU_NODES" | head -n 1)
echo -e "${GREEN}✓ 找到可用${GPU_RESOURCE}节点：${FIRST_NODE}（allocatable.${GPU_RESOURCE} > 0）${NC}"


# 3. 验证前的GPU占用情况
echo -e "\n${YELLOW}=== 3. 验证前：查看节点${FIRST_NODE}的GPU实时状态 ==="${NC}
echo "通过临时Pod执行${GPU_CHECK_TOOL}（命令执行后自动清理Pod）："
kubectl run temp-hami-pre-check --rm -it --image="${TEST_IMAGE}" \
  --overrides='{"spec": {"nodeName": "'"${FIRST_NODE}"'", "restartPolicy": "Never"}}' \
  -- sh -c "${GPU_CHECK_TOOL}" || {
    echo -e "${YELLOW}警告：GPU检查命令执行失败，退而显示节点${GPU_RESOURCE}资源详情${NC}"
    kubectl describe node "${FIRST_NODE}" | grep -A 15 "${GPU_RESOURCE}"
}
echo -e "${GREEN}✓ 验证前GPU占用检查完成（临时Pod已自动清理）${NC}"


# 4. 创建测试Pod验证hami.com/gpu调度
echo -e "\n${YELLOW}=== 4. 创建测试Pod验证${GPU_RESOURCE}调度与访问 ==="${NC}
# 定义测试Pod的YAML（请求1单位hami.com/gpu）
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
    command: ["sh", "-c", "${GPU_CHECK_TOOL} && sleep 20"] # 执行GPU检查并保留Pod
    resources:
      limits:
        ${GPU_RESOURCE}: 1 # 请求1单位hami.com/gpu资源
EOF

# 等待Pod就绪（延长至120秒，适配镜像拉取）
echo "等待测试Pod ${TEST_POD} 就绪（最多等待120秒）..."
if ! kubectl wait --for=condition=Ready pod/"${TEST_POD}" --timeout=120s; then
    echo -e "${RED}错误：测试Pod启动失败，查看详细日志：${NC}"
    kubectl describe pod "${TEST_POD}"
    kubectl delete pod "${TEST_POD}" --ignore-not-found
    exit 1
fi
echo -e "${GREEN}✓ 测试Pod ${TEST_POD} 已成功就绪${NC}"


# 5. 验证测试Pod的GPU访问能力
echo -e "\n${YELLOW}=== 5. 验证测试Pod的GPU信息输出 ==="${NC}
echo "测试Pod ${TEST_POD} 的${GPU_CHECK_TOOL}输出："
kubectl logs "${TEST_POD}"

# 检查日志中是否包含NVIDIA-SMI（确认GPU被识别）
if ! kubectl logs "${TEST_POD}" | grep -q "NVIDIA-SMI"; then
    echo -e "${RED}错误：测试Pod未获取到GPU信息！${GPU_RESOURCE}资源访问异常${NC}"
    kubectl delete pod "${TEST_POD}" --ignore-not-found
    exit 1
fi
echo -e "${GREEN}✓ 测试Pod成功访问GPU！${GPU_CHECK_TOOL}信息正常输出${NC}"


# 6. 验证后的GPU占用情况
echo -e "\n${YELLOW}=== 6. 验证后：再次查看节点${FIRST_NODE}的GPU状态 ==="${NC}
echo "再次执行${GPU_CHECK_TOOL}（临时Pod自动清理）："
kubectl run temp-hami-post-check --rm -it --image="${TEST_IMAGE}" \
  --overrides='{"spec": {"nodeName": "'"${FIRST_NODE}"'", "restartPolicy": "Never"}}' \
  -- sh -c "${GPU_CHECK_TOOL}" || {
    echo -e "${YELLOW}警告：GPU检查命令执行失败，显示节点当前${GPU_RESOURCE}资源${NC}"
    kubectl describe node "${FIRST_NODE}" | grep -A 15 "${GPU_RESOURCE}"
}
echo -e "${GREEN}✓ 验证后GPU占用检查完成（临时Pod已自动清理）${NC}"


# 7. 清理测试资源与总结
echo -e "\n${YELLOW}=== 7. 清理测试资源 ==="${NC}
kubectl delete pod "${TEST_POD}" --ignore-not-found &> /dev/null
echo -e "${GREEN}✓ 测试Pod ${TEST_POD} 已清理完成${NC}"

# 最终验证结果总结
echo -e "\n${GREEN}=====================================================${NC}"
echo -e "${GREEN}=== 所有验证通过！${GPU_RESOURCE}资源工作正常 ===${NC}"
echo -e "${GREEN}=== 集群GPU可正常调度，Pod可正常访问GPU资源 ===${NC}"
echo -e "${GREEN}=====================================================${NC}"
